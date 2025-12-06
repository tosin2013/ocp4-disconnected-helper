"""
OCP Harbor Registry DAG - Deploy and Manage Harbor Container Registry
ADR Reference: ADR 0004 (Dual Registry Support), ADR 0012 (DAGs call playbooks)

This DAG deploys Harbor container registry for disconnected OpenShift environments.
Harbor provides enterprise-grade features like vulnerability scanning, replication, etc.

Target Host: disconn-harbor.d70.kemo.labs (192.168.71.240)
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
    'start_date': datetime(2025, 12, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# =============================================================================
# Define the DAG
# =============================================================================
dag = DAG(
    'ocp_harbor_registry',
    default_args=default_args,
    description='Deploy Harbor Container Registry for disconnected OCP',
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=['ocp4-disconnected-helper', 'harbor', 'registry', 'infrastructure'],
    params={
        'harbor_hostname': Param(
            default='disconn-harbor.d70.kemo.labs',
            type='string',
            description='Harbor registry hostname',
        ),
        'harbor_ip': Param(
            default='192.168.71.240',
            type='string',
            description='Harbor host IP address',
        ),
        'harbor_version': Param(
            default='v2.7.3',
            type='string',
            description='Harbor version to deploy',
        ),
        'data_volume_path': Param(
            default='/data',
            type='string',
            description='Path for Harbor data volume (needs lots of space)',
        ),
    },
    doc_md=__doc__,
)

# =============================================================================
# Task 1: Pre-flight Checks
# =============================================================================
preflight_checks = BashOperator(
    task_id='preflight_checks',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

HARBOR_HOSTNAME="{{ params.harbor_hostname }}"
HARBOR_IP="{{ params.harbor_ip }}"

echo "===================================================================="
echo "[INFO] Harbor Registry Deployment - Pre-flight Checks"
echo "===================================================================="
echo ""
echo "Harbor Hostname: $HARBOR_HOSTNAME"
echo "Harbor IP: $HARBOR_IP"
echo "Harbor Version: {{ params.harbor_version }}"
echo "Data Volume: {{ params.data_volume_path }}"
echo "Timestamp: $(date -Iseconds)"
echo ""

ERRORS=0

# Check if Harbor host is reachable
echo "[INFO] Checking Harbor host connectivity..."
if ping -c 2 -W 3 "$HARBOR_IP" > /dev/null 2>&1; then
    echo "  [OK] Harbor host $HARBOR_IP is reachable"
else
    echo "  [ERROR] Cannot reach Harbor host $HARBOR_IP"
    ERRORS=$((ERRORS + 1))
fi

# Check SSH access to Harbor host
echo ""
echo "[INFO] Checking SSH access to Harbor host..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR root@$HARBOR_IP "echo 'SSH OK'" 2>/dev/null; then
    echo "  [OK] SSH access to Harbor host works"
else
    echo "  [ERROR] Cannot SSH to Harbor host"
    echo "  Hint: Ensure SSH keys are set up for root@$HARBOR_IP"
    ERRORS=$((ERRORS + 1))
fi

# Check if playbook exists
echo ""
echo "[INFO] Checking playbook..."
if [ -f /root/ocp4-disconnected-helper/playbooks/setup-harbor-registry.yml ]; then
    echo "  [OK] setup-harbor-registry.yml exists"
else
    echo "  [ERROR] setup-harbor-registry.yml not found"
    ERRORS=$((ERRORS + 1))
fi

# Check if extra_vars exists
echo ""
echo "[INFO] Checking extra_vars..."
if [ -f /root/ocp4-disconnected-helper/extra_vars/setup-harbor-registry-vars.yml ]; then
    echo "  [OK] setup-harbor-registry-vars.yml exists"
else
    echo "  [ERROR] setup-harbor-registry-vars.yml not found"
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
# Task 2: Deploy Harbor via Ansible Playbook
# =============================================================================
deploy_harbor = BashOperator(
    task_id='deploy_harbor',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

HARBOR_HOSTNAME="{{ params.harbor_hostname }}"

echo "===================================================================="
echo "[INFO] Deploying Harbor Registry: $HARBOR_HOSTNAME"
echo "===================================================================="
echo ""
echo "Per ADR 0012: Using setup-harbor-registry.yml playbook"
echo ""

cd /root/ocp4-disconnected-helper/playbooks

# Unset vault password file env var if no vault is used
unset ANSIBLE_VAULT_PASSWORD_FILE 2>/dev/null || true

# Run the Harbor setup playbook
echo "[INFO] Running: ansible-playbook -i inventory setup-harbor-registry.yml -e @../extra_vars/setup-harbor-registry-vars.yml"
echo ""

ansible-playbook -i inventory setup-harbor-registry.yml \
    -e @../extra_vars/setup-harbor-registry-vars.yml \
    -v

echo ""
echo "[OK] Harbor deployment playbook completed"
REMOTE_SCRIPT
    """,
    dag=dag,
    execution_timeout=timedelta(hours=1),
)

# =============================================================================
# Task 3: Verify Harbor Deployment
# =============================================================================
verify_harbor = BashOperator(
    task_id='verify_harbor',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

HARBOR_HOSTNAME="{{ params.harbor_hostname }}"
HARBOR_IP="{{ params.harbor_ip }}"

echo "===================================================================="
echo "[INFO] Verifying Harbor Deployment"
echo "===================================================================="
echo ""

ERRORS=0

# Wait a bit for Harbor to start
echo "[INFO] Waiting for Harbor to initialize..."
sleep 30

# Check Harbor API health
echo ""
echo "[INFO] Checking Harbor health endpoint..."
HEALTH_STATUS=$(curl -sk --connect-timeout 10 "https://${HARBOR_IP}/api/v2.0/health" 2>/dev/null || echo "FAILED")

if echo "$HEALTH_STATUS" | grep -q "healthy"; then
    echo "  [OK] Harbor API is healthy"
else
    echo "  [WARN] Harbor health check returned: $HEALTH_STATUS"
    echo "  Trying alternative endpoint..."
    
    # Try the v2 endpoint
    V2_STATUS=$(curl -sk --connect-timeout 10 "https://${HARBOR_IP}/v2/" 2>/dev/null || echo "FAILED")
    if [ "$V2_STATUS" = "{}" ]; then
        echo "  [OK] Harbor v2 registry endpoint is responding"
    else
        echo "  [ERROR] Harbor is not responding correctly"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check if we can list projects
echo ""
echo "[INFO] Checking Harbor API access..."
PROJECTS=$(curl -sk -u admin:notHarbor12345 "https://${HARBOR_IP}/api/v2.0/projects" 2>/dev/null || echo "FAILED")
if echo "$PROJECTS" | grep -q "name"; then
    echo "  [OK] Harbor API authentication works"
    echo "  Projects: $(echo $PROJECTS | jq -r '.[].name' 2>/dev/null | tr '\n' ' ')"
else
    echo "  [WARN] Could not list Harbor projects"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "[ERROR] Harbor verification FAILED"
    exit 1
else
    echo "===================================================================="
    echo "[OK] Harbor Registry Deployed Successfully!"
    echo "===================================================================="
    echo ""
    echo "Harbor URL: https://$HARBOR_HOSTNAME"
    echo "Harbor IP:  https://$HARBOR_IP"
    echo "Username:   admin"
    echo "Password:   (see extra_vars/setup-harbor-registry-vars.yml)"
    echo ""
    echo "Next: Run ocp_registry_sync DAG to push images to Harbor"
fi
REMOTE_SCRIPT
    """,
    dag=dag,
)

# =============================================================================
# Task 4: Add DNS Entry (if using local DNS)
# =============================================================================
configure_dns = BashOperator(
    task_id='configure_dns',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
set -euo pipefail

HARBOR_HOSTNAME="{{ params.harbor_hostname }}"
HARBOR_IP="{{ params.harbor_ip }}"

echo "===================================================================="
echo "[INFO] DNS Configuration for Harbor"
echo "===================================================================="
echo ""

# Check if hostname resolves
if host "$HARBOR_HOSTNAME" > /dev/null 2>&1; then
    RESOLVED_IP=$(host "$HARBOR_HOSTNAME" | grep -oP '(\d+\.){3}\d+' | head -1)
    echo "[OK] $HARBOR_HOSTNAME resolves to $RESOLVED_IP"
else
    echo "[WARN] $HARBOR_HOSTNAME does not resolve via DNS"
    echo ""
    echo "Options to fix:"
    echo "  1. Add DNS record for $HARBOR_HOSTNAME -> $HARBOR_IP"
    echo "  2. Add to /etc/hosts: $HARBOR_IP $HARBOR_HOSTNAME"
    echo ""
    
    # Add to local /etc/hosts as fallback
    if ! grep -q "$HARBOR_HOSTNAME" /etc/hosts; then
        echo "[INFO] Adding $HARBOR_HOSTNAME to /etc/hosts"
        echo "$HARBOR_IP $HARBOR_HOSTNAME" >> /etc/hosts
        echo "[OK] Added to /etc/hosts"
    else
        echo "[OK] Entry already exists in /etc/hosts"
    fi
fi

echo ""
echo "[OK] DNS configuration complete"
REMOTE_SCRIPT
    """,
    dag=dag,
)

# =============================================================================
# Task: Cleanup on Failure
# =============================================================================
cleanup_on_failure = BashOperator(
    task_id='cleanup_on_failure',
    bash_command="""
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@localhost << 'REMOTE_SCRIPT'
echo "===================================================================="
echo "[WARN] Harbor Deployment Failed - Cleanup"
echo "===================================================================="
echo ""
echo "Check the logs for errors and retry after fixing issues."
echo ""
echo "Common issues:"
echo "  - SSH access to Harbor host not configured"
echo "  - Insufficient disk space on Harbor host"
echo "  - SSL certificate issues"
echo "  - Port 443/80 already in use"
REMOTE_SCRIPT
    """,
    dag=dag,
    trigger_rule=TriggerRule.ONE_FAILED,
)

# =============================================================================
# Task Dependencies
# =============================================================================
preflight_checks >> deploy_harbor >> verify_harbor >> configure_dns

# Cleanup runs on any failure
[preflight_checks, deploy_harbor, verify_harbor] >> cleanup_on_failure

