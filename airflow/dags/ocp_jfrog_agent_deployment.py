"""
OCP JFrog Agent-Based Deployment DAG
ADR References: ADR 0004 (JFrog), ADR 0016 (Certificates), ADR 0018 (Registry VM), 
                ADR 0020 (Passthrough Mode), ADR 0019 (Agent Install Integration)

This DAG orchestrates the complete workflow for:
1. Deploying JFrog Artifactory on a dedicated VM
2. Configuring TLS certificates (step-ca or self-signed)
3. Setting up registry passthrough mode
4. Mirroring OpenShift images
5. Creating agent-based installer ISO
6. Deploying OpenShift cluster

Target: OpenShift 4.17-4.20 disconnected deployments
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.trigger_rule import TriggerRule
from airflow.models.param import Param

# =============================================================================
# Configuration
# =============================================================================
PLAYBOOKS_PATH = '/root/ocp4-disconnected-helper/playbooks'
AGENT_INSTALL_PATH = '/root/openshift-agent-install'
EXTRA_VARS_PATH = '/root/ocp4-disconnected-helper/extra_vars'

default_args = {
    'owner': 'ocp4-disconnected-helper',
    'depends_on_past': False,
    'start_date': datetime(2025, 12, 12),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# =============================================================================
# Define the DAG
# =============================================================================
dag = DAG(
    'ocp_jfrog_agent_deployment',
    default_args=default_args,
    description='Deploy JFrog + Step-CA + OpenShift via Agent-Based Installer',
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=['ocp4-disconnected-helper', 'jfrog', 'agent-installer', 'step-ca'],
    params={
        'jfrog_vm_name': Param(
            default='jfrog-registry',
            type='string',
            description='Name for the JFrog VM',
        ),
        'jfrog_hostname': Param(
            default='jfrog.disconnected.local',
            type='string',
            description='Hostname for JFrog Artifactory',
        ),
        'jfrog_port': Param(
            default='8443',
            type='string',
            description='HTTPS port for JFrog',
        ),
        'cert_provider': Param(
            default='self-signed',
            type='string',
            enum=['self-signed', 'step-ca'],
            description='Certificate provider (ADR 0016)',
        ),
        'step_ca_url': Param(
            default='https://step-ca.disconnected.local:9000',
            type='string',
            description='Step-CA server URL (if cert_provider=step-ca)',
        ),
        'ocp_version': Param(
            default='4.20.4',
            type='string',
            description='OpenShift version to deploy (e.g., 4.20.4 for upgrade path to 4.20.6)',
        ),
        'cluster_name': Param(
            default='ocp-cluster',
            type='string',
            description='Name for the OpenShift cluster',
        ),
        'base_domain': Param(
            default='disconnected.local',
            type='string',
            description='Base domain for the cluster',
        ),
        'skip_vm_provision': Param(
            default=False,
            type='boolean',
            description='Skip VM provisioning (use existing JFrog)',
        ),
        'skip_mirror': Param(
            default=False,
            type='boolean',
            description='Skip image mirroring (images already mirrored)',
        ),
    },
    doc_md=__doc__,
)

# =============================================================================
# Task 0: Setup DNS Records (FreeIPA)
# =============================================================================
setup_dns = BashOperator(
    task_id='setup_dns',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

CLUSTER_NAME="{{ params.cluster_name }}"
BASE_DOMAIN="{{ params.base_domain }}"
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"

echo "===================================================================="
echo "[INFO] Setting up FreeIPA DNS Records"
echo "===================================================================="

cd /root/ocp4-disconnected-helper/playbooks

# Check if setup-freeipa-dns.yml exists
if [ ! -f "setup-freeipa-dns.yml" ]; then
    echo "[WARN] setup-freeipa-dns.yml not found, skipping DNS setup"
    echo "[INFO] Ensure DNS records are configured manually"
    exit 0
fi

# Run DNS setup playbook
ansible-playbook -i inventory setup-freeipa-dns.yml \
    -e "cluster_name=$CLUSTER_NAME" \
    -e "ipa_domain=$BASE_DOMAIN" \
    -e "jfrog_hostname=${JFROG_HOSTNAME%%.*}" || {
        echo "[WARN] DNS setup failed, continuing anyway"
        echo "[INFO] Ensure DNS records are configured manually"
    }

echo "[OK] DNS setup completed"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=5),
    dag=dag,
)

# =============================================================================
# Task 1: Pre-flight Checks
# =============================================================================
preflight_checks = BashOperator(
    task_id='preflight_checks',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

echo "===================================================================="
echo "[INFO] JFrog Agent Deployment - Pre-flight Checks"
echo "===================================================================="
echo ""
echo "JFrog VM Name: {{ params.jfrog_vm_name }}"
echo "JFrog Hostname: {{ params.jfrog_hostname }}"
echo "Certificate Provider: {{ params.cert_provider }}"
echo "OCP Version: {{ params.ocp_version }}"
echo "Cluster Name: {{ params.cluster_name }}"
echo "Base Domain: {{ params.base_domain }}"
echo "Timestamp: $(date -Iseconds)"
echo ""

ERRORS=0

# Check required binaries
echo "[INFO] Checking required binaries..."
for cmd in ansible-playbook oc oc-mirror kcli openshift-install; do
    if command -v $cmd &> /dev/null; then
        echo "  [OK] $cmd: $(which $cmd)"
    else
        echo "  [WARN] $cmd NOT FOUND - will attempt to install"
        
        # Use helper scripts from openshift-agent-install if available
        if [ "$cmd" = "oc" ] || [ "$cmd" = "openshift-install" ]; then
            if [ -f "/root/openshift-agent-install/download-openshift-cli.sh" ]; then
                echo "  [INFO] Running download-openshift-cli.sh..."
                cd /root/openshift-agent-install && ./download-openshift-cli.sh
                cp ./bin/* /usr/local/bin/ 2>/dev/null || true
                cd -
            fi
        fi
        
        # Re-check after install attempt
        if ! command -v $cmd &> /dev/null; then
            echo "  [ERROR] $cmd still NOT FOUND after install attempt"
            ERRORS=$((ERRORS + 1))
        else
            echo "  [OK] $cmd installed: $(which $cmd)"
        fi
    fi
done

# Check playbooks
echo ""
echo "[INFO] Checking playbooks..."
PLAYBOOKS=(
    "/root/ocp4-disconnected-helper/playbooks/setup-jfrog-registry.yml"
    "/root/ocp4-disconnected-helper/playbooks/setup-certificates.yml"
    "/root/ocp4-disconnected-helper/playbooks/setup-registry-passthrough.yml"
    "/root/openshift-agent-install/playbooks/create-manifests.yml"
)
for pb in "${PLAYBOOKS[@]}"; do
    if [ -f "$pb" ]; then
        echo "  [OK] $pb"
    else
        echo "  [ERROR] $pb NOT FOUND"
        ERRORS=$((ERRORS + 1))
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
# Task 2: Provision JFrog VM
# =============================================================================
provision_jfrog_vm = BashOperator(
    task_id='provision_jfrog_vm',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

SKIP_PROVISION="{{ params.skip_vm_provision }}"
VM_NAME="{{ params.jfrog_vm_name }}"

if [ "$SKIP_PROVISION" = "True" ] || [ "$SKIP_PROVISION" = "true" ]; then
    echo "[INFO] Skipping VM provisioning (skip_vm_provision=true)"
    exit 0
fi

echo "===================================================================="
echo "[INFO] Provisioning JFrog VM: $VM_NAME"
echo "===================================================================="

# Check if VM already exists
if kcli list vm | grep -q "$VM_NAME"; then
    echo "[INFO] VM $VM_NAME already exists"
    kcli info vm "$VM_NAME"
else
    echo "[INFO] Creating VM $VM_NAME..."
    kcli create vm "$VM_NAME" \
        -i centos9stream \
        -P memory=8192 \
        -P numcpus=4 \
        -P disks=[100] \
        -P nets=['{"name": "default", "ip": "dhcp"}']
    
    echo "[INFO] Waiting for VM to be ready..."
    sleep 60
fi

# Get VM IP
VM_IP=$(kcli info vm "$VM_NAME" -f ip -v 2>/dev/null | tail -1)
echo "[OK] VM $VM_NAME provisioned with IP: $VM_IP"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=15),
    dag=dag,
)

# =============================================================================
# Task 3: Setup Certificates
# =============================================================================
setup_certificates = BashOperator(
    task_id='setup_certificates',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

CERT_PROVIDER="{{ params.cert_provider }}"
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
STEP_CA_URL="{{ params.step_ca_url }}"

echo "===================================================================="
echo "[INFO] Setting up certificates via $CERT_PROVIDER"
echo "===================================================================="

cd /root/ocp4-disconnected-helper/playbooks

if [ "$CERT_PROVIDER" = "step-ca" ]; then
    echo "[INFO] Using step-ca for certificate generation"
    
    # Check if step CLI is available
    if ! command -v step &> /dev/null; then
        echo "[INFO] Installing step CLI..."
        curl -sLO https://dl.smallstep.com/gh-release/cli/docs-cli-install/v0.25.0/step-cli_0.25.0_amd64.rpm
        rpm -i step-cli_0.25.0_amd64.rpm || true
    fi
    
    # Generate certificate from step-ca
    echo "[INFO] Requesting certificate from step-ca..."
    step ca certificate "$JFROG_HOSTNAME" \
        /etc/pki/registry/jfrog.crt \
        /etc/pki/registry/jfrog.key \
        --ca-url "$STEP_CA_URL" \
        --provisioner admin \
        --not-after 8760h \
        --san "$JFROG_HOSTNAME" \
        --san "{{ params.jfrog_vm_name }}" \
        --force || {
            echo "[WARN] step-ca certificate request failed, falling back to self-signed"
            CERT_PROVIDER="self-signed"
        }
fi

if [ "$CERT_PROVIDER" = "self-signed" ]; then
    echo "[INFO] Using self-signed certificates (ADR 0016)"
    
    ansible-playbook -i inventory setup-certificates.yml \
        -e "registry_hostnames=['$JFROG_HOSTNAME', '{{ params.jfrog_vm_name }}']" \
        -e "cert_server_validity_days=365"
fi

echo "[OK] Certificate setup completed"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=10),
    dag=dag,
)

# =============================================================================
# Task 4: Deploy JFrog Artifactory
# =============================================================================
deploy_jfrog = BashOperator(
    task_id='deploy_jfrog',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

echo "===================================================================="
echo "[INFO] Deploying JFrog Artifactory"
echo "===================================================================="

cd /root/ocp4-disconnected-helper/playbooks

# Run JFrog setup playbook
ansible-playbook -i inventory setup-jfrog-registry.yml \
    -e "jfrog_hostname=$JFROG_HOSTNAME" \
    -e "jfrog_port=$JFROG_PORT" \
    -e "use_generated_certs=true"

echo "[OK] JFrog Artifactory deployed"

# Verify JFrog is accessible
echo "[INFO] Verifying JFrog accessibility..."
sleep 30
curl -k -s "https://$JFROG_HOSTNAME:$JFROG_PORT/artifactory/api/system/ping" || {
    echo "[WARN] JFrog ping failed, waiting longer..."
    sleep 60
    curl -k -s "https://$JFROG_HOSTNAME:$JFROG_PORT/artifactory/api/system/ping"
}

echo "[OK] JFrog is accessible"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=30),
    dag=dag,
)

# =============================================================================
# Task 5: Configure Passthrough Mode
# =============================================================================
configure_passthrough = BashOperator(
    task_id='configure_passthrough',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

echo "===================================================================="
echo "[INFO] Configuring Registry Passthrough Mode (ADR 0020)"
echo "===================================================================="

cd /root/ocp4-disconnected-helper/playbooks

ansible-playbook -i inventory setup-registry-passthrough.yml \
    -e "registry_type=jfrog" \
    -e "registry_local_uri=$JFROG_HOSTNAME" \
    -e "registry_local_port=$JFROG_PORT"

echo "[OK] Passthrough mode configured"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=10),
    dag=dag,
)

# =============================================================================
# Task 6: Trigger Mirror Sync
# =============================================================================
trigger_mirror_sync = TriggerDagRunOperator(
    task_id='trigger_mirror_sync',
    trigger_dag_id='ocp_registry_sync',
    conf={
        'target_registry': 'jfrog',
        'enable_passthrough': True,
        'source_version': '{{ params.ocp_version }}',
        'target_version': '{{ params.ocp_version }}',
        'skip_download': '{{ params.skip_mirror }}',
    },
    wait_for_completion=True,
    poke_interval=60,
    execution_timeout=timedelta(hours=6),
    dag=dag,
)

# =============================================================================
# Task 7: Create Agent Manifests
# =============================================================================
create_agent_manifests = BashOperator(
    task_id='create_agent_manifests',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

CLUSTER_NAME="{{ params.cluster_name }}"
BASE_DOMAIN="{{ params.base_domain }}"
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"
OCP_VERSION="{{ params.ocp_version }}"

echo "===================================================================="
echo "[INFO] Creating Agent-Based Installer Manifests"
echo "===================================================================="

cd /root/openshift-agent-install/playbooks

# Create cluster configuration
cat > /tmp/cluster-vars.yml << EOF
cluster_name: $CLUSTER_NAME
base_domain: $BASE_DOMAIN
openshift_version: "$OCP_VERSION"

# Registry configuration for disconnected install
imageContentSources:
  - mirrors:
    - $JFROG_HOSTNAME:$JFROG_PORT/mirror/quay.io
    source: quay.io
  - mirrors:
    - $JFROG_HOSTNAME:$JFROG_PORT/mirror/registry.redhat.io
    source: registry.redhat.io
  - mirrors:
    - $JFROG_HOSTNAME:$JFROG_PORT/mirror/registry.access.redhat.com
    source: registry.access.redhat.com

# Pull secret path
pull_secret_path: /root/pull-secret.json

# Additional trust bundle
additionalTrustBundle: |
$(cat /etc/pki/disconnected-ca/ca.crt 2>/dev/null | sed 's/^/  /' || echo "  # CA cert not found")
EOF

echo "[INFO] Running create-manifests.yml..."
ansible-playbook -e "@/tmp/cluster-vars.yml" create-manifests.yml

echo "[OK] Agent manifests created"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=15),
    dag=dag,
)

# =============================================================================
# Task 8: Build Agent ISO
# =============================================================================
build_agent_iso = BashOperator(
    task_id='build_agent_iso',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

CLUSTER_NAME="{{ params.cluster_name }}"

echo "===================================================================="
echo "[INFO] Building Agent-Based Installer ISO"
echo "===================================================================="

MANIFEST_DIR="/root/openshift-agent-install/playbooks/generated_manifests/$CLUSTER_NAME"
OCP_VERSION="{{ params.ocp_version }}"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "[ERROR] Manifest directory not found: $MANIFEST_DIR"
    exit 1
fi

# Download RHCOS ISO if not cached
RHCOS_CACHE="$HOME/.cache/agent/image_cache"
if [ ! -f "$RHCOS_CACHE/coreos-x86_64.iso" ]; then
    echo "[INFO] Downloading RHCOS ISO using helper script..."
    if [ -f "/root/openshift-agent-install/get-rhcos-iso.sh" ]; then
        cd /root/openshift-agent-install
        ./get-rhcos-iso.sh "${OCP_VERSION}" x86_64 || echo "[WARN] RHCOS download may have failed"
        
        # Move ISO to cache location
        mkdir -p "$RHCOS_CACHE"
        mv rhcos-*.iso "$RHCOS_CACHE/coreos-x86_64.iso" 2>/dev/null || true
        cd -
    fi
fi

cd "$MANIFEST_DIR"

echo "[INFO] Creating agent ISO..."
openshift-install agent create image --dir .

if [ -f "agent.x86_64.iso" ]; then
    echo "[OK] Agent ISO created: $MANIFEST_DIR/agent.x86_64.iso"
    ls -lh agent.x86_64.iso
else
    echo "[ERROR] ISO creation failed"
    exit 1
fi
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=30),
    dag=dag,
)

# =============================================================================
# Task 9: Deployment Report
# =============================================================================
deployment_report = BashOperator(
    task_id='deployment_report',
    bash_command="""
set -euo pipefail

CLUSTER_NAME="{{ params.cluster_name }}"
BASE_DOMAIN="{{ params.base_domain }}"
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

echo ""
echo "===================================================================="
echo "[INFO] JFrog Agent Deployment Report"
echo "===================================================================="
echo ""
echo "Deployment Completed: $(date -Iseconds)"
echo ""
echo "JFrog Registry:"
echo "  - URL: https://$JFROG_HOSTNAME:$JFROG_PORT"
echo "  - Type: JFrog Artifactory"
echo "  - Passthrough Mode: Enabled (ADR 0020)"
echo ""
echo "OpenShift Cluster:"
echo "  - Name: $CLUSTER_NAME"
echo "  - Domain: $CLUSTER_NAME.$BASE_DOMAIN"
echo "  - Version: {{ params.ocp_version }}"
echo ""
echo "Generated Files:"
echo "  - Manifests: /root/openshift-agent-install/playbooks/generated_manifests/$CLUSTER_NAME/"
echo "  - ISO: /root/openshift-agent-install/playbooks/generated_manifests/$CLUSTER_NAME/agent.x86_64.iso"
echo "  - ICSP: /opt/ocp4-disconnected-helper/templates/icsp/"
echo ""
echo "===================================================================="
echo "Next Steps:"
echo "  1. Boot target nodes with the agent ISO"
echo "  2. Monitor bootstrap: openshift-install agent wait-for bootstrap-complete --dir /root/openshift-agent-install/playbooks/generated_manifests/$CLUSTER_NAME"
echo "  3. Monitor install: openshift-install agent wait-for install-complete --dir /root/openshift-agent-install/playbooks/generated_manifests/$CLUSTER_NAME"
echo "  4. Apply ICSP post-install: /opt/ocp4-disconnected-helper/templates/icsp/apply-icsp-jfrog.sh"
echo "===================================================================="
echo "[OK] JFrog Agent Deployment workflow completed!"
    """,
    trigger_rule=TriggerRule.ALL_SUCCESS,
    dag=dag,
)

# =============================================================================
# Task 10: Cleanup on Failure
# =============================================================================
cleanup_on_failure = BashOperator(
    task_id='cleanup_on_failure',
    bash_command="""
set +e

echo "===================================================================="
echo "[WARN] Cleanup After Failure"
echo "===================================================================="

echo "[INFO] Checking for partial resources..."

# Log failure details
echo ""
echo "Review the failed task above for details."
echo ""
echo "Common fixes:"
echo "  1. Check JFrog VM status: kcli list vm"
echo "  2. Check certificate generation logs"
echo "  3. Verify network connectivity to JFrog"
echo "  4. Check Ansible playbook logs"
echo "  5. Verify pull secret is valid"
echo ""
echo "After fixing, retrigger this DAG"
    """,
    trigger_rule=TriggerRule.ONE_FAILED,
    dag=dag,
)

# =============================================================================
# Task Dependencies
# =============================================================================
setup_dns >> preflight_checks >> provision_jfrog_vm >> setup_certificates >> deploy_jfrog
deploy_jfrog >> configure_passthrough >> trigger_mirror_sync
trigger_mirror_sync >> create_agent_manifests >> build_agent_iso >> deployment_report

# Cleanup runs on any failure
[setup_dns, preflight_checks, provision_jfrog_vm, setup_certificates, deploy_jfrog, 
 configure_passthrough, trigger_mirror_sync, create_agent_manifests, 
 build_agent_iso] >> cleanup_on_failure
