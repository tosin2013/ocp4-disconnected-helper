# ADR-0031: AAP 2.6 Installer Registry Credential Configuration

## Date
2026-06-09

## Status
Accepted

## Context

Ansible Automation Platform (AAP) 2.6 containerized deployment requires authentication to `registry.redhat.io` to pull base container images for the Control Plane Execution Environment and other system components. The Control Plane EE is a **system-managed resource** used by AAP for internal operations including:

- Project syncs from Git repositories (SCM updates)
- Collection installation from Ansible Galaxy or Automation Hub
- Internal AAP platform operations

**Problem Discovered (June 9, 2026):**

When AAP 2.6 was deployed without registry credentials in the installer inventory, all project syncs failed with:
```
Error: unable to retrieve auth token: invalid username/password: unauthorized
```

Attempted post-deployment fixes via Web UI and API all failed because the Control Plane Execution Environment is **read-only** after installation. API attempts to modify it return HTTP 403 Forbidden.

**Root Cause:**

Registry credentials must be embedded in the installer inventory file **before running `setup.sh`** during initial deployment. They cannot be added retroactively via Web UI or API.

## Decision

**Mandatory Requirement:** All AAP 2.6 deployments MUST configure Red Hat registry credentials in the installer inventory file before running `setup.sh`.

### Implementation

**1. Obtain Red Hat Service Account Credentials**

Generate a service account at: https://access.redhat.com/terms-based-registry/

- Service Account Name: `ansible-execution-environment` (or similar)
- Purpose: AAP 2.6 Container Registry Authentication
- Save credentials:
  - Username: `<org-id>|<service-account-name>`
  - Token: Long JWT token string

**2. Configure Installer Inventory**

Edit `/opt/ansible-automation-platform/installer/inventory` and add to `[all:vars]` section:

```ini
[all:vars]
# Red Hat Registry Credentials (MANDATORY for AAP 2.6)
registry_url='registry.redhat.io'
registry_username='<YOUR-ORG-ID>|<YOUR-SERVICE-ACCOUNT-NAME>'
registry_password='<YOUR-SERVICE-ACCOUNT-TOKEN>'

# ... other variables ...
```

**3. Run Setup Script**

```bash
cd /opt/ansible-automation-platform/installer
./setup.sh -i inventory
```

This applies registry credentials to:
- Control Plane Execution Environment
- All AAP platform containers (Gateway, Controller, Database nodes)
- Podman authentication on all nodes

### Post-Deployment Verification

```bash
# Check Control Plane EE configuration
curl -sk -u admin:<password> \
  "https://aap.example.com/api/controller/v2/execution_environments/3/" | \
  jq -r '.image'

# Expected: registry.redhat.io/ansible-automation-platform-26/ee-supported-rhel9:latest

# Test podman authentication on AAP nodes
ssh ansible@<aap-gateway-ip> "sudo podman login registry.redhat.io --get-login"
# Expected: <service-account-username>
```

### Credential Rotation

When service account credentials expire or need rotation:

1. Update credentials in installer inventory file
2. Re-run `./setup.sh -i inventory`
3. All AAP containers reconfigure automatically (5-10 minute process)
4. Verify project syncs work after reconfiguration

## Consequences

### Positive

1. **Prevents Deployment Failures:** Ensures Control Plane EE can pull images from `registry.redhat.io` from day one
2. **Follows Red Hat Best Practices:** Aligns with official AAP 2.6 installation guide (Option 1: Configure During Installation)
3. **Single Source of Truth:** Installer inventory is the authoritative configuration for registry credentials
4. **Atomic Reconfiguration:** Changes applied via `setup.sh` are tested and validated by Red Hat's installer
5. **Multi-Node Support:** Works correctly across Gateway, Controller, and Database nodes in multi-node topologies

### Negative

1. **Requires Re-run on Updates:** Credential rotation requires re-running `setup.sh` (5-10 minute downtime)
2. **Plaintext in Inventory:** Credentials stored in plaintext in inventory file (mitigate with file permissions `chmod 600`)
3. **Manual Process:** No automated credential refresh mechanism (requires administrator intervention)

### Security Considerations

**Credential Storage:**
- Inventory file should be `chmod 600` (owner read/write only)
- Inventory file should NOT be committed to Git (add to `.gitignore`)
- Use Ansible Vault or HashiCorp Vault to encrypt inventory file at rest

**Credential Lifecycle:**
- Service account tokens should be rotated every 90-180 days per security policy
- Document rotation schedule in `docs/SECURITY.md`
- Test credential rotation in staging environment before production

**Service Account Permissions:**
- Service account only needs `registry.redhat.io` pull permissions
- Should NOT have broader Red Hat customer portal access
- Create dedicated service accounts per environment (dev, staging, prod)

## Alternatives Considered

### 1. Configure Credentials via Web UI Post-Deployment
**Status:** Rejected  
**Reason:** Control Plane EE is system-managed and cannot be modified via Web UI. This approach works for **custom execution environments** but not for the Control Plane EE.

### 2. Configure Credentials via ansible.controller API
**Status:** Rejected  
**Reason:** API returns HTTP 403 Forbidden when attempting to modify Control Plane EE. This is by design - it's a protected system resource.

### 3. Build Custom EE with Embedded Credentials
**Status:** Rejected for Control Plane EE (Valid for Job Templates)  
**Reason:** Does not solve the root problem. Control Plane EE is still used for project syncs and needs its own authentication. Custom EEs are a **supplement** for job template execution, not a replacement for proper Control Plane EE configuration.

### 4. Use Insecure Registry Configuration
**Status:** Rejected  
**Reason:** Security violation. Would disable TLS verification and allow unauthenticated image pulls.

## Validation

### Preflight Check (Before Deployment)

Create `scripts/preflight-aap-registry-check.sh`:
```bash
#!/bin/bash
# Preflight validation for AAP installer registry credentials

INVENTORY_FILE="/opt/ansible-automation-platform/installer/inventory"

if [ ! -f "$INVENTORY_FILE" ]; then
  echo "❌ FAIL: Inventory file not found at $INVENTORY_FILE"
  exit 1
fi

# Check for required variables
REQUIRED_VARS=("registry_url" "registry_username" "registry_password")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
  if ! grep -q "^${var}=" "$INVENTORY_FILE"; then
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "❌ FAIL: Missing required registry credentials in inventory:"
  printf '  - %s\n' "${MISSING_VARS[@]}"
  echo ""
  echo "Add to [all:vars] section:"
  echo "  registry_url='registry.redhat.io'"
  echo "  registry_username='<org-id>|<service-account>'"
  echo "  registry_password='<token>'"
  exit 1
fi

echo "✅ PASS: Registry credentials present in inventory"

# Validate registry_url
REGISTRY_URL=$(grep "^registry_url=" "$INVENTORY_FILE" | cut -d"'" -f2)
if [ "$REGISTRY_URL" != "registry.redhat.io" ]; then
  echo "⚠️  WARNING: registry_url is '$REGISTRY_URL' (expected 'registry.redhat.io')"
fi

# Validate username format (should contain pipe |)
REGISTRY_USERNAME=$(grep "^registry_username=" "$INVENTORY_FILE" | cut -d"'" -f2)
if [[ ! "$REGISTRY_USERNAME" =~ \| ]]; then
  echo "⚠️  WARNING: registry_username should be '<org-id>|<service-account>' format"
fi

echo "✅ Preflight check complete"
exit 0
```

### Post-Deployment Verification

Run after `setup.sh` completes:
```bash
# Test project sync
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-aap-project-sync.yml
```

Expected: Project sync succeeds without registry authentication errors.

## Related ADRs

- **ADR 0021**: Deprecate Airflow and Adopt AAP 2.5 - Establishes AAP as automation platform
- **ADR 0028**: AAP 2.6 Multi-Node Password Architecture - Documents credential taxonomy
- **ADR 0029**: Custom Execution Environment for AAP Registry Authentication - Documents custom EE use cases (complements this ADR)
- **ADR 0009**: Secrets Management - Future: Encrypt installer inventory with HashiCorp Vault

## Implementation Checklist

For every AAP 2.6 deployment:

- [ ] Generate Red Hat service account for registry access
- [ ] Add credentials to installer inventory `[all:vars]`
- [ ] Run preflight check: `scripts/preflight-aap-registry-check.sh`
- [ ] Execute `./setup.sh -i inventory`
- [ ] Verify project sync succeeds
- [ ] Document credential rotation schedule
- [ ] Set calendar reminder for credential rotation (90 days)

## References

- [Creating and using execution environments - AAP 2.6](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/creating_and_using_execution_environments/index)
- [Red Hat Terms-Based Registry](https://access.redhat.com/terms-based-registry/)
- [AAP 2.6 Containerized Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- [How To Change Control Plane Execution Environment Settings](https://www.jazakallah.info/post/how-to-change-control-plane-execution-environment-settings)

## Approval

**Approved By**: Project Architecture Team  
**Date**: 2026-06-09  
**Implementation Status**: Applied retroactively to existing AAP 2.6 deployment
