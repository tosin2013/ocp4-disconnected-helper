"""
OCP Registry Sync DAG - Mirror and Push OpenShift Images to Registries
ADR Reference: ADR 0003 (oc-mirror v2), ADR 0012 (Airflow DAGs call playbooks)

This DAG orchestrates the synchronization of OpenShift images to local registries
by calling Ansible playbooks - NOT inline oc-mirror commands.

Workflow:
1. Pre-flight validation
2. Resolve versions (query OpenShift API for latest patch versions)
3. Download images to TAR (via download-to-tar.yml playbook)
4. Push TAR to registry (via push-tar-to-registry.yml playbook)
5. Generate sync report

SMART VERSION RESOLUTION:
- Uses versions_check.sh logic to query OpenShift upgrade graph API
- Sets minVersion = maxVersion to download ONLY specific versions (not ranges)
- Prevents downloading entire version ranges (saves 100s of GB)

Target: OpenShift 4.17-4.20
Designed to run on qubinode_navigator's Airflow instance.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.utils.trigger_rule import TriggerRule
from airflow.models.param import Param

# =============================================================================
# Configuration
# =============================================================================
PLAYBOOKS_PATH = '/root/ocp4-disconnected-helper/playbooks'
EXTRA_VARS_PATH = '/root/ocp4-disconnected-helper/extra_vars'

default_args = {
    'owner': 'ocp4-disconnected-helper',
    'depends_on_past': False,
    'start_date': datetime(2025, 11, 28),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# =============================================================================
# Define the DAG
# =============================================================================
dag = DAG(
    'ocp_registry_sync',
    default_args=default_args,
    description='Sync OCP images to registries via Ansible playbooks (ADR 0012)',
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=['ocp4-disconnected-helper', 'openshift', 'registry', 'sync'],
    params={
        'source_version': Param(
            default='4.19',
            type='string',
            enum=['4.17', '4.18', '4.19', '4.20'],
            description='Source OCP version (current cluster version)',
        ),
        'target_version': Param(
            default='4.20',
            type='string',
            enum=['4.17', '4.18', '4.19', '4.20'],
            description='Target OCP version (upgrade destination)',
        ),
        'upgrade_type': Param(
            default='major',
            type='string',
            enum=['major', 'patch'],
            description='Upgrade type: major (4.19->4.20) or patch (4.20.4->4.20.5)',
        ),
        'target_registry': Param(
            default='quay',
            type='string',
            enum=['quay', 'harbor', 'jfrog'],
            description='Target registry type',
        ),
        'skip_download': Param(
            default=False,
            type='boolean',
            description='Skip download, only push existing content',
        ),
        'clean_mirror': Param(
            default=False,
            type='boolean',
            description='Full mirror (true) or incremental (false)',
        ),
        'auto_resolve_versions': Param(
            default=True,
            type='boolean',
            description='Auto-resolve latest patch versions from OpenShift API',
        ),
    },
    doc_md=__doc__,
)

# =============================================================================
# Task 1: Pre-flight Checks (SSH to host per ADR-0046)
# =============================================================================
preflight_checks = BashOperator(
    task_id='preflight_checks',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

echo "===================================================================="
echo "[INFO] OCP Registry Sync - Pre-flight Checks"
echo "===================================================================="
echo ""
echo "Source Version: {{ params.source_version }}"
echo "Target Version: {{ params.target_version }}"
echo "Upgrade Type: {{ params.upgrade_type }}"
echo "Auto Resolve: {{ params.auto_resolve_versions }}"
echo "Target Registry: {{ params.target_registry }}"
echo "Skip Download: {{ params.skip_download }}"
echo "Clean Mirror: {{ params.clean_mirror }}"
echo "Timestamp: $(date -Iseconds)"
echo ""

ERRORS=0

# Check required binaries
echo "[INFO] Checking required binaries..."
for cmd in ansible-playbook oc oc-mirror curl jq podman; do
    if command -v $cmd &> /dev/null; then
        echo "  [OK] $cmd: $(which $cmd)"
    else
        echo "  [ERROR] $cmd NOT FOUND"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check playbooks exist
echo ""
echo "[INFO] Checking Ansible playbooks..."
PLAYBOOKS_PATH="/root/ocp4-disconnected-helper/playbooks"
for playbook in download-to-tar.yml push-tar-to-registry.yml; do
    if [ -f "$PLAYBOOKS_PATH/$playbook" ]; then
        echo "  [OK] $playbook exists"
    else
        echo "  [ERROR] $playbook NOT FOUND at $PLAYBOOKS_PATH"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check extra_vars files
echo ""
echo "[INFO] Checking extra_vars files..."
EXTRA_VARS_PATH="/root/ocp4-disconnected-helper/extra_vars"
for varsfile in download-to-tar-vars.yml push-tar-to-registry-vars.yml; do
    if [ -f "$EXTRA_VARS_PATH/$varsfile" ]; then
        echo "  [OK] $varsfile exists"
    else
        echo "  [WARN] $varsfile not found (will use defaults)"
    fi
done

# Check pull secret
echo ""
echo "[INFO] Checking pull secret..."
if [ -f /root/pull-secret.json ]; then
    echo "  [OK] /root/pull-secret.json exists"
elif [ -f /root/rh-pull-secret ]; then
    echo "  [OK] /root/rh-pull-secret exists"
else
    echo "  [ERROR] No pull secret found"
    ERRORS=$((ERRORS + 1))
fi

# Check disk space
echo ""
echo "[INFO] Checking disk space..."
MIRROR_PATH="/opt/images"
mkdir -p "$MIRROR_PATH" 2>/dev/null || true
AVAIL=$(df -BG "$MIRROR_PATH" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$AVAIL" -gt 50 ]; then
    echo "  [OK] Available space: ${AVAIL}GB"
else
    echo "  [WARN] Low disk space: ${AVAIL}GB (50GB+ recommended)"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "[ERROR] Pre-flight checks FAILED with $ERRORS error(s)"
    exit 1
else
    echo "[OK] Pre-flight checks PASSED"
fi
REMOTE_SCRIPT
    """,
    dag=dag,
)

# =============================================================================
# Task 2: Resolve Versions (Query OpenShift API for latest patch versions)
# Uses scripts/resolve-ocp-versions.sh to avoid downloading entire version ranges
# =============================================================================
resolve_versions = BashOperator(
    task_id='resolve_versions',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

SOURCE_VERSION="{{ params.source_version }}"
TARGET_VERSION="{{ params.target_version }}"
UPGRADE_TYPE="{{ params.upgrade_type }}"
AUTO_RESOLVE="{{ params.auto_resolve_versions }}"

if [ "$AUTO_RESOLVE" != "True" ] && [ "$AUTO_RESOLVE" != "true" ]; then
    echo "===================================================================="
    echo "[INFO] Auto-resolve disabled, using static versions from extra_vars"
    echo "===================================================================="
    yq eval '.openshift_releases' /root/ocp4-disconnected-helper/extra_vars/download-to-tar-vars.yml
    exit 0
fi

# Call the version resolution script
/root/ocp4-disconnected-helper/scripts/resolve-ocp-versions.sh \
    "$SOURCE_VERSION" \
    "$TARGET_VERSION" \
    "$UPGRADE_TYPE" \
    "/root/ocp4-disconnected-helper/extra_vars/download-to-tar-vars.yml"
REMOTE_SCRIPT
    """,
    dag=dag,
)

# =============================================================================
# Task 3: Download Images via Ansible Playbook (ADR 0012 compliant)
# =============================================================================
download_images = BashOperator(
    task_id='download_images',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

SKIP_DOWNLOAD="{{ params.skip_download }}"
CLEAN_MIRROR="{{ params.clean_mirror }}"
SOURCE_VERSION="{{ params.source_version }}"
TARGET_VERSION="{{ params.target_version }}"

if [ "$SKIP_DOWNLOAD" = "True" ] || [ "$SKIP_DOWNLOAD" = "true" ]; then
    echo "===================================================================="
    echo "[INFO] Skipping Download (skip_download=true)"
    echo "===================================================================="
    
    MIRROR_PATH="/opt/images"
    if ls "$MIRROR_PATH"/*.tar 1>/dev/null 2>&1; then
        echo "[OK] Using existing TAR files:"
        ls -lh "$MIRROR_PATH"/*.tar
    else
        echo "[ERROR] No TAR files found at $MIRROR_PATH"
        echo "Set skip_download=false to download images"
        exit 1
    fi
    exit 0
fi

echo "===================================================================="
echo "[INFO] Downloading OCP ${SOURCE_VERSION}→${TARGET_VERSION} Images via Ansible Playbook"
echo "===================================================================="
echo ""
echo "Per ADR 0012: Using download-to-tar.yml playbook"
echo ""

cd /root/ocp4-disconnected-helper/playbooks

# Build extra vars for this run
EXTRA_VARS=""
EXTRA_VARS="$EXTRA_VARS -e clean_mirror_path=$CLEAN_MIRROR"

# Check if custom vars file exists
if [ -f ../extra_vars/download-to-tar-vars.yml ]; then
    echo "[INFO] Using extra_vars/download-to-tar-vars.yml"
    EXTRA_VARS="$EXTRA_VARS -e @../extra_vars/download-to-tar-vars.yml"
fi

echo "[INFO] Running: ansible-playbook -i inventory download-to-tar.yml $EXTRA_VARS"
echo ""

# Unset vault password file env var if no vault is used
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

ansible-playbook -i inventory download-to-tar.yml $EXTRA_VARS

echo ""
echo "[OK] Download playbook completed"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(hours=4),
    dag=dag,
)

# =============================================================================
# Task 3: Push to Registry via Ansible Playbook (ADR 0012 compliant)
# =============================================================================
push_to_registry = BashOperator(
    task_id='push_to_registry',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

TARGET_REGISTRY="{{ params.target_registry }}"

echo "===================================================================="
echo "[INFO] Pushing Images to $TARGET_REGISTRY Registry via Ansible Playbook"
echo "===================================================================="
echo ""
echo "Per ADR 0012: Using push-tar-to-registry.yml playbook"
echo ""

cd /root/ocp4-disconnected-helper/playbooks

# Build extra vars for this run
EXTRA_VARS=""

# Check if custom vars file exists
if [ -f ../extra_vars/push-tar-to-registry-vars.yml ]; then
    echo "[INFO] Using extra_vars/push-tar-to-registry-vars.yml"
    EXTRA_VARS="$EXTRA_VARS -e @../extra_vars/push-tar-to-registry-vars.yml"
else
    echo "[ERROR] Missing extra_vars/push-tar-to-registry-vars.yml"
    echo "This file is required to configure the target registry"
    exit 1
fi

echo "[INFO] Running: ansible-playbook -i inventory push-tar-to-registry.yml $EXTRA_VARS"
echo ""

# Unset vault password file env var if no vault is used
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

ansible-playbook -i inventory push-tar-to-registry.yml $EXTRA_VARS

echo ""
echo "[OK] Push playbook completed"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(hours=2),
    dag=dag,
)

# =============================================================================
# Task 4: Generate Sync Report
# =============================================================================
sync_report = BashOperator(
    task_id='sync_report',
    bash_command="""
set -euo pipefail

echo ""
echo "===================================================================="
echo "[INFO] Registry Sync Report"
echo "===================================================================="
echo ""
echo "Sync Completed: $(date -Iseconds)"
echo "Source Version: {{ params.source_version }}"
echo "Target Version: {{ params.target_version }}"
echo "Upgrade Type:   {{ params.upgrade_type }}"
echo "Registry:       {{ params.target_registry }}"
echo "Skip Download:  {{ params.skip_download }}"
echo "Clean Mirror:   {{ params.clean_mirror }}"
echo ""

# Show mirror path contents
MIRROR_PATH="/opt/images"
echo "Mirror Path Contents:"
ls -lh "$MIRROR_PATH"/*.tar 2>/dev/null | head -5 || echo "  No TAR files (may have been pushed directly)"

# Show oc-mirror workspace
if [ -d "$MIRROR_PATH/oc-mirror-workspace" ]; then
    LATEST_RESULTS=$(ls -td "$MIRROR_PATH/oc-mirror-workspace"/results-* 2>/dev/null | head -1)
    if [ -d "$LATEST_RESULTS" ]; then
        echo ""
        echo "Generated Manifests: $LATEST_RESULTS"
        ls "$LATEST_RESULTS" 2>/dev/null | head -10
    fi
fi

echo ""
echo "===================================================================="
echo "Next Steps:"
echo "  1. Apply ICSP/IDMS manifests to cluster"
echo "  2. Verify images: skopeo list-tags docker://<registry>/<repo>"
echo "  3. Deploy cluster: airflow dags trigger ocp_agent_deployment"
echo "===================================================================="
echo "[OK] OCP Registry Sync completed successfully!"
    """,
    trigger_rule=TriggerRule.ALL_SUCCESS,
    dag=dag,
)

# =============================================================================
# Task 5: Cleanup on Failure
# =============================================================================
cleanup_on_failure = BashOperator(
    task_id='cleanup_on_failure',
    bash_command="""
set +e  # Don't exit on error during cleanup

echo "===================================================================="
echo "[WARN] Cleanup After Failure"
echo "===================================================================="
echo ""

# Clean up partial oc-mirror workspace
MIRROR_PATH="/opt/images"
if [ -d "$MIRROR_PATH/oc-mirror-workspace" ]; then
    echo "[INFO] Cleaning partial working directories..."
    find "$MIRROR_PATH/oc-mirror-workspace" -type d -name "working-*" -exec rm -rf {} + 2>/dev/null || true
fi

echo "[OK] Cleanup complete"
echo ""
echo "===================================================================="
echo "SYNC FAILED - Review errors above"
echo "===================================================================="
echo ""
echo "Common fixes:"
echo "  1. Check Ansible playbook logs for detailed errors"
echo "  2. Verify extra_vars files are configured correctly"
echo "  3. Ensure pull secret is valid and not expired"
echo "  4. Check disk space: df -h /opt/images"
echo "  5. Check registry connectivity"
echo ""
echo "After fixing, retrigger this DAG"
    """,
    trigger_rule=TriggerRule.ONE_FAILED,
    dag=dag,
)

# =============================================================================
# Task Dependencies
# =============================================================================
preflight_checks >> resolve_versions >> download_images >> push_to_registry >> sync_report

# Cleanup runs on any failure
[preflight_checks, resolve_versions, download_images, push_to_registry] >> cleanup_on_failure
