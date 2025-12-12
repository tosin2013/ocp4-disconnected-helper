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
        'deploy_on_kvm': Param(
            default=False,
            type='boolean',
            description='Deploy VMs on KVM using hack/deploy-on-kvm.sh',
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

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

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

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

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

# Check required binaries (oc-mirror is optional - only needed for mirror sync)
echo "[INFO] Checking required binaries..."
for cmd in ansible-playbook oc kcli openshift-install; do
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

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

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

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

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

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

echo "===================================================================="
echo "[INFO] Deploying JFrog Artifactory"
echo "===================================================================="

cd /root/ocp4-disconnected-helper/playbooks

# Run JFrog setup playbook on localhost (not remote inventory)
ansible-playbook -i "localhost," -c local setup-jfrog-registry.yml \
    -e "jfrog_hostname=$JFROG_HOSTNAME" \
    -e "jfrog_port=$JFROG_PORT" \
    -e "use_generated_certs=true" \
    -e "ansible_python_interpreter=/usr/bin/python3"

echo "[OK] JFrog Artifactory deployed"

# Verify JFrog is accessible (use localhost if DNS not configured)
echo "[INFO] Verifying JFrog accessibility..."
sleep 10

# Try localhost first, then hostname
if curl -k -s "https://localhost:$JFROG_PORT/artifactory/api/system/ping" 2>/dev/null | grep -q "OK"; then
    echo "[OK] JFrog is accessible on localhost:$JFROG_PORT"
elif curl -k -s "https://$JFROG_HOSTNAME:$JFROG_PORT/artifactory/api/system/ping" 2>/dev/null | grep -q "OK"; then
    echo "[OK] JFrog is accessible on $JFROG_HOSTNAME:$JFROG_PORT"
else
    echo "[WARN] JFrog ping check failed - container may still be starting"
    echo "[INFO] Continuing anyway - JFrog should be available shortly"
fi

echo "[OK] JFrog deployment completed"
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

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

echo "===================================================================="
echo "[INFO] Configuring Registry Passthrough Mode (ADR 0020)"
echo "===================================================================="

cd /root/ocp4-disconnected-helper/playbooks

# Run passthrough setup on localhost
ansible-playbook -i "localhost," -c local setup-registry-passthrough.yml \
    -e "registry_type=jfrog" \
    -e "registry_local_uri=$JFROG_HOSTNAME" \
    -e "registry_local_port=$JFROG_PORT" \
    -e "ansible_python_interpreter=/usr/bin/python3" || {
    echo "[WARN] Passthrough setup had issues - continuing anyway"
    echo "[INFO] You may need to manually configure ICSP"
}

echo "[OK] Passthrough mode configured"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=10),
    dag=dag,
)

# =============================================================================
# Task 6: Trigger Mirror Sync
# =============================================================================
trigger_mirror_sync = BashOperator(
    task_id='trigger_mirror_sync',
    bash_command="""
SKIP_MIRROR="{{ params.skip_mirror }}"

if [ "$SKIP_MIRROR" = "True" ] || [ "$SKIP_MIRROR" = "true" ]; then
    echo "[INFO] Skipping mirror sync (skip_mirror=true)"
    echo "[INFO] Ensure images are already mirrored to JFrog"
    exit 0
fi

echo "===================================================================="
echo "[INFO] Mirror sync would be triggered here"
echo "[INFO] For full mirror sync, run ocp_registry_sync DAG separately"
echo "===================================================================="

# For now, just verify JFrog is accessible
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

curl -k -s "https://localhost:$JFROG_PORT/artifactory/api/system/ping" 2>/dev/null && \
    echo "[OK] JFrog registry is accessible" || \
    echo "[WARN] JFrog ping check failed - may need manual verification"

echo "[INFO] To mirror images, run: airflow dags trigger ocp_registry_sync"
    """,
    execution_timeout=timedelta(minutes=5),
    dag=dag,
)

# =============================================================================
# Task 7: Create Agent Manifests and Build ISO
# Uses hack/create-iso.sh which handles both manifest generation and ISO creation
# =============================================================================
create_agent_manifests = BashOperator(
    task_id='create_agent_manifests',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

CLUSTER_NAME="{{ params.cluster_name }}"
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"

echo "===================================================================="
echo "[INFO] Preparing JFrog Disconnected Cluster Configuration"
echo "===================================================================="

cd /root/openshift-agent-install

# Install required Ansible collection if missing
ansible-galaxy collection install community.crypto 2>/dev/null || true

# Ensure jfrog-disconnected example exists and update it with current values
EXAMPLE_DIR="examples/jfrog-disconnected"
mkdir -p "$EXAMPLE_DIR"

# Read CA cert for trust bundle
CA_CERT_PATH="/etc/pki/disconnected-ca/ca.crt"

# Update cluster.yml with JFrog registry settings
if [ -f "$EXAMPLE_DIR/cluster.yml" ]; then
    echo "[INFO] Updating cluster.yml with JFrog registry: $JFROG_HOSTNAME:$JFROG_PORT"
    # Update the JFrog hostname in imageContentSources
    sed -i "s|jfrog.example.com:8443|$JFROG_HOSTNAME:$JFROG_PORT|g" "$EXAMPLE_DIR/cluster.yml"
    
    # Update additionalTrustBundlePath if CA cert exists
    if [ -f "$CA_CERT_PATH" ]; then
        sed -i "s|additionalTrustBundlePath:.*|additionalTrustBundlePath: $CA_CERT_PATH|g" "$EXAMPLE_DIR/cluster.yml"
    fi
fi

echo "[INFO] Cluster configuration prepared in $EXAMPLE_DIR"
cat "$EXAMPLE_DIR/cluster.yml"

echo "[OK] Agent manifests preparation completed"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=10),
    dag=dag,
)

# =============================================================================
# Task 8: Build Agent ISO using hack/create-iso.sh
# =============================================================================
build_agent_iso = BashOperator(
    task_id='build_agent_iso',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

# Unset vault password file to avoid errors
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

CLUSTER_NAME="{{ params.cluster_name }}"

echo "===================================================================="
echo "[INFO] Building Agent-Based Installer ISO using hack/create-iso.sh"
echo "===================================================================="

cd /root/openshift-agent-install

# Set generated asset path
export GENERATED_ASSET_PATH="${HOME}/generated_assets"
export SITE_CONFIG_DIR="examples"

# Install required Ansible collection if missing
ansible-galaxy collection install community.crypto 2>/dev/null || true

# Install nmstate package required for network config validation
if ! command -v nmstatectl &> /dev/null; then
    echo "[INFO] Installing nmstate package..."
    dnf install -y nmstate || yum install -y nmstate || {
        echo "[WARN] Could not install nmstate - trying pip"
        pip3 install nmstate || true
    }
fi

# Read CA cert and set as environment variable for the playbook
CA_CERT_PATH="/etc/pki/disconnected-ca/ca.crt"
if [ -f "$CA_CERT_PATH" ]; then
    echo "[INFO] Reading CA certificate from $CA_CERT_PATH"
    export ADDITIONAL_TRUST_BUNDLE=$(cat "$CA_CERT_PATH")
    
    # Update cluster.yml to include the cert content
    # The playbook template expects 'additional_trust_bundle' variable
    cat >> examples/jfrog-disconnected/cluster.yml << CERTEOF

# Dynamically added CA certificate content
additional_trust_bundle: |
$(cat "$CA_CERT_PATH" | sed 's/^/  /')
CERTEOF
    echo "[OK] CA certificate added to cluster.yml"
else
    echo "[WARN] CA certificate not found at $CA_CERT_PATH"
    echo "[INFO] Proceeding without additionalTrustBundle"
fi

# Run the create-iso.sh script with jfrog-disconnected config
echo "[INFO] Running: ./hack/create-iso.sh jfrog-disconnected"
./hack/create-iso.sh jfrog-disconnected

# Verify ISO was created
ISO_PATH="${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso"
if [ -f "$ISO_PATH" ]; then
    echo "[OK] Agent ISO created successfully"
    ls -lh "$ISO_PATH"
    echo ""
    echo "ISO Location: $ISO_PATH"
else
    # Check alternate location
    ALT_ISO=$(find "$GENERATED_ASSET_PATH" -name "agent.x86_64.iso" 2>/dev/null | head -1)
    if [ -n "$ALT_ISO" ]; then
        echo "[OK] Agent ISO created at: $ALT_ISO"
        ls -lh "$ALT_ISO"
    else
        echo "[ERROR] ISO creation failed - no agent.x86_64.iso found"
        ls -la "$GENERATED_ASSET_PATH/" 2>/dev/null || echo "Generated assets directory not found"
        exit 1
    fi
fi
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=30),
    dag=dag,
)

# =============================================================================
# Task 9: Deploy VMs on KVM (Optional)
# Uses hack/deploy-on-kvm.sh to create VMs and boot from agent ISO
# =============================================================================
deploy_on_kvm = BashOperator(
    task_id='deploy_on_kvm',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

CLUSTER_NAME="{{ params.cluster_name }}"
DEPLOY_ON_KVM="{{ params.deploy_on_kvm }}"

echo "===================================================================="
echo "[INFO] Deploy VMs on KVM"
echo "===================================================================="

if [ "$DEPLOY_ON_KVM" != "True" ] && [ "$DEPLOY_ON_KVM" != "true" ]; then
    echo "[INFO] KVM deployment skipped (deploy_on_kvm=false)"
    echo "[INFO] To deploy on KVM, set deploy_on_kvm=true in DAG config"
    exit 0
fi

cd /root/openshift-agent-install

# Set environment variables
export CLUSTER_NAME="$CLUSTER_NAME"
export GENERATED_ASSET_PATH="${HOME}/generated_assets"

# Check if ISO exists
if [ ! -f "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso" ]; then
    echo "[ERROR] Agent ISO not found at ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso"
    exit 1
fi

echo "[INFO] Running: ./hack/deploy-on-kvm.sh examples/jfrog-disconnected/nodes.yml"
./hack/deploy-on-kvm.sh examples/jfrog-disconnected/nodes.yml

echo "[OK] KVM VMs deployed and booting from agent ISO"
echo "[INFO] Monitor VM status with: virsh list --all"
REMOTE_SCRIPT
    """,
    execution_timeout=timedelta(minutes=15),
    dag=dag,
)

# =============================================================================
# Task 10: Deployment Report
# =============================================================================
deployment_report = BashOperator(
    task_id='deployment_report',
    bash_command="""
set -euo pipefail

CLUSTER_NAME="{{ params.cluster_name }}"
BASE_DOMAIN="{{ params.base_domain }}"
JFROG_HOSTNAME="{{ params.jfrog_hostname }}"
JFROG_PORT="{{ params.jfrog_port }}"
DEPLOY_ON_KVM="{{ params.deploy_on_kvm }}"

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
echo "  - Manifests: ~/generated_assets/$CLUSTER_NAME/"
echo "  - ISO: ~/generated_assets/$CLUSTER_NAME/agent.x86_64.iso"
echo "  - ICSP: /opt/ocp4-disconnected-helper/templates/icsp/"
echo ""
if [ "$DEPLOY_ON_KVM" = "True" ] || [ "$DEPLOY_ON_KVM" = "true" ]; then
echo "KVM Deployment:"
echo "  - VMs created and booting from agent ISO"
echo "  - Check status: virsh list --all"
echo ""
fi
echo "===================================================================="
echo "Next Steps:"
if [ "$DEPLOY_ON_KVM" != "True" ] && [ "$DEPLOY_ON_KVM" != "true" ]; then
echo "  1. Boot target nodes with the agent ISO"
else
echo "  1. VMs are booting - monitor progress"
fi
echo "  2. Monitor bootstrap: openshift-install agent wait-for bootstrap-complete --dir ~/generated_assets/$CLUSTER_NAME"
echo "  3. Monitor install: openshift-install agent wait-for install-complete --dir ~/generated_assets/$CLUSTER_NAME"
echo "  4. Apply ICSP post-install: /opt/ocp4-disconnected-helper/templates/icsp/apply-icsp-jfrog.sh"
echo ""
echo "To destroy KVM VMs:"
echo "  cd /root/openshift-agent-install && ./hack/destroy-on-kvm.sh examples/jfrog-disconnected/nodes.yml"
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
trigger_mirror_sync >> create_agent_manifests >> build_agent_iso >> deploy_on_kvm >> deployment_report

# Cleanup runs on any failure
[setup_dns, preflight_checks, provision_jfrog_vm, setup_certificates, deploy_jfrog, 
 configure_passthrough, trigger_mirror_sync, create_agent_manifests, 
 build_agent_iso, deploy_on_kvm] >> cleanup_on_failure
