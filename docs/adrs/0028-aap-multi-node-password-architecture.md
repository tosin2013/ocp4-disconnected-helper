# ADR 0028: AAP 2.6 Multi-Node Password Architecture

**Status:** Accepted  
**Date:** 2026-06-05  
**Deciders:** Platform Team  
**Related:** ADR 0021 - Deprecate Airflow and Adopt AAP  
**Incident Reference:** PMB ULID `0019e9806e6c4_72f49a83` - AAP Multi-Node Login Failure

## Context

Ansible Automation Platform (AAP) 2.6 multi-node deployment architecture separates components into distinct roles:
- **Automation Gateway**: User-facing web UI and API gateway (port 443)
- **Automation Controller**: Workflow execution engine (internal API)
- **Database**: PostgreSQL backend for both Gateway and Controller

This architectural separation introduces **dual authentication contexts** that were not present in AAP 2.5 all-in-one deployments.

### Incident Background (2026-06-05)

During AAP 2.6 multi-node deployment testing, user authentication failed with:
- **Symptom**: Web UI login at https://aap.sandbox3377.opentlc.com returned "Invalid username or password"
- **User Action**: Entered credentials `admin` / `YourSecureControllerPassword123!`
- **Root Cause**: User attempted Gateway login with Controller password
- **Discovery**: API authentication (`curl -u admin:YourSecureControllerPassword123! /api/controller/v2/ping/`) succeeded, confirming Controller password was correct
- **Resolution**: Login with Gateway password (`automationgateway_admin_password: YourSecureGatewayPassword123!`)

## Decision

**Document and enforce AAP 2.6 multi-node password separation architecture** to prevent authentication confusion.

### Password Taxonomy

AAP 2.6 multi-node requires **five distinct passwords**:

| Password Variable | Component | Purpose | Access Method |
|-------------------|-----------|---------|---------------|
| `automationgateway_admin_password` | Gateway | **Web UI login** | HTTPS /login page |
| `admin_password` | Controller | API authentication | Basic auth to `/api/controller/*` |
| `automationgateway_pg_password` | Gateway DB | Gateway → Database connection | Internal (not user-facing) |
| `pg_password` | Controller DB | Controller → Database connection | Internal (not user-facing) |
| `postgresql_admin_password` | Database | PostgreSQL admin | Internal (not user-facing) |

### Critical Distinction

**Web UI vs API Authentication**:
- **Web UI** (https://aap.sandbox3377.opentlc.com) → Uses `automationgateway_admin_password`
- **Controller API** (`/api/controller/*`) → Uses `admin_password`
- **Gateway API** (`/api/gateway/*`) → Uses `automationgateway_admin_password`

### Why Two Admin Passwords?

Per [AAP 2.6 Containerized Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index):

> "The automation gateway serves as the unified entry point for all user interactions, while the automation controller handles workflow execution. Each component maintains independent authentication contexts to support role-based access control (RBAC) and service isolation."

**Design Rationale**:
1. **Service Isolation**: Gateway authentication separate from Controller automation credentials
2. **RBAC Granularity**: Different permissions for UI users vs. automation service accounts
3. **Security Boundary**: Gateway can validate user credentials without full Controller access
4. **Migration Path**: Allows independent scaling/migration of Gateway vs. Controller

## Implementation

### Inventory Template (`templates/aap/inventory-multi-node.j2`)

**Current Implementation** (CORRECT):
```jinja2
[all:vars]
# Red Hat Registry Credentials
registry_url='registry.redhat.io'
registry_username='{{ registry_username }}'
registry_password='{{ registry_password }}'

# AAP Gateway Configuration
automationgateway_admin_password='{{ automationgateway_admin_password }}'
automationgateway_pg_password='{{ automationgateway_pg_password }}'

# AAP Controller Configuration
admin_password='{{ admin_password }}'
pg_password='{{ pg_password }}'

# PostgreSQL Admin Password
postgresql_admin_password='{{ postgresql_admin_password }}'
```

### Secrets File (`extra_vars/rhel-subscription-secrets.yml.example`)

**Required Documentation** (ADDED):
```yaml
# ==============================================================================
# AAP 2.6 Multi-Node Password Architecture
# ==============================================================================
# CRITICAL: AAP 2.6 multi-node uses TWO separate admin passwords:
#
#   1. automationgateway_admin_password - For WEB UI login (https://aap.example.com)
#   2. admin_password - For CONTROLLER API authentication (/api/controller/*)
#
# Do NOT use the same password for both - they authenticate to different components.
# ==============================================================================

# AAP Gateway Admin Password (Web UI Login)
# Used for: https://aap.sandbox3377.opentlc.com login page
automationgateway_admin_password: "YourSecureGatewayPassword123!"

# AAP Controller Admin Password (API Authentication)
# Used for: curl -u admin:password https://aap.../api/controller/v2/ping/
admin_password: "YourSecureControllerPassword123!"

# Database Passwords (Internal - Not User-Facing)
automationgateway_pg_password: "YourSecureGatewayPgPassword123!"
pg_password: "YourSecureControllerPgPassword123!"
postgresql_admin_password: "YourSecurePostgresAdminPassword123!"
```

### Deployment Playbook Documentation

**File**: `playbooks/deploy-aap-multi-node.yml`

Add documentation block at top of file:
```yaml
---
# Deploy AAP 2.6 Multi-Node across Gateway, Controller, Database VMs
# ADR Reference: ADR 0028 - AAP 2.6 Multi-Node Password Architecture
#
# AUTHENTICATION ARCHITECTURE:
#   - Web UI (https://aap.example.com): Uses automationgateway_admin_password
#   - Controller API (/api/controller/*): Uses admin_password
#   - Gateway API (/api/gateway/*): Uses automationgateway_admin_password
#
# VERIFICATION:
#   Web UI:  Open https://aap.example.com → Login with automationgateway_admin_password
#   API:     curl -u admin:admin_password https://aap.../api/controller/v2/ping/
```

### User Guidance in Deployment Summary

Update deployment summary task to display:
```yaml
- name: Display AAP access information
  ansible.builtin.debug:
    msg:
      - "✅ AAP 2.6 Multi-Node Deployment Complete"
      - ""
      - "🌐 WEB UI ACCESS:"
      - "   URL: https://{{ aap_url }}"
      - "   Username: admin"
      - "   Password: <automationgateway_admin_password from secrets file>"
      - "   (This is the GATEWAY password, NOT the Controller password)"
      - ""
      - "🔧 API ACCESS (Controller):"
      - "   URL: https://{{ aap_url }}/api/controller/"
      - "   Auth: Basic (admin:<admin_password from secrets file>)"
      - ""
      - "📚 Password Reference: See ADR 0028 - Multi-Node Password Architecture"
```

## Consequences

### Positive

- **Clear Authentication Model**: Explicit documentation prevents password confusion
- **Security Best Practice**: Separate passwords for UI and API enforces least-privilege principle
- **Troubleshooting Efficiency**: Future users can quickly identify which password to use
- **Compliance**: Audit trail clearly shows different authentication contexts

### Negative

- **Increased Complexity**: Users must manage 5 passwords instead of 1 (all-in-one model)
- **Documentation Overhead**: Must maintain password taxonomy in multiple locations
- **Migration Friction**: Users migrating from AAP 2.5 all-in-one may be confused

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Password confusion | HIGH | Clear documentation in secrets file example + deployment summary |
| Insecure password reuse | MEDIUM | Enforce different passwords via validation playbook |
| Forgotten passwords | LOW | Document in Ansible Vault + external password manager |

## Validation

### Preflight Check (New Playbook Required)

Create `playbooks/validate-aap-passwords.yml`:
```yaml
---
- name: Validate AAP Password Configuration
  hosts: localhost
  gather_facts: no
  vars_files:
    - ../extra_vars/rhel-subscription-secrets.yml
  
  tasks:
    - name: Check all 5 AAP passwords are defined
      ansible.builtin.assert:
        that:
          - automationgateway_admin_password is defined
          - admin_password is defined
          - automationgateway_pg_password is defined
          - pg_password is defined
          - postgresql_admin_password is defined
        fail_msg: "Missing AAP password variables. See ADR 0028 for required passwords."
    
    - name: Verify Gateway and Controller passwords are different
      ansible.builtin.assert:
        that:
          - automationgateway_admin_password != admin_password
        fail_msg: |
          SECURITY WARNING: automationgateway_admin_password and admin_password are identical.
          AAP 2.6 multi-node requires separate passwords for Gateway (Web UI) and Controller (API).
          See ADR 0028 for password architecture.
    
    - name: Display password configuration status
      ansible.builtin.debug:
        msg:
          - "✅ All 5 AAP passwords configured"
          - "✅ Gateway and Controller passwords are distinct"
          - "📚 Password usage: See ADR 0028"
```

### Post-Deployment Verification

Update `playbooks/deploy-aap-multi-node.yml` to include:
```yaml
- name: Verify AAP Authentication
  hosts: aap-gateway
  gather_facts: no
  become: yes
  
  tasks:
    - name: Test Controller API with admin_password
      ansible.builtin.uri:
        url: "https://{{ hostvars['aap-gateway'].vm_static_ip }}/api/controller/v2/ping/"
        method: GET
        user: admin
        password: "{{ admin_password }}"
        force_basic_auth: yes
        validate_certs: no
      register: controller_api_check
      failed_when: controller_api_check.status != 200
    
    - name: Test Gateway API with automationgateway_admin_password
      ansible.builtin.uri:
        url: "https://{{ hostvars['aap-gateway'].vm_static_ip }}/api/gateway/"
        method: GET
        user: admin
        password: "{{ automationgateway_admin_password }}"
        force_basic_auth: yes
        validate_certs: no
      register: gateway_api_check
      failed_when: gateway_api_check.status != 200
    
    - name: Display authentication verification results
      ansible.builtin.debug:
        msg:
          - "✅ Controller API authentication: SUCCESS (admin_password)"
          - "✅ Gateway API authentication: SUCCESS (automationgateway_admin_password)"
          - "✅ Multi-node authentication validated"
```

## References

- [AAP 2.6 Containerized Installation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- [AAP 2.6 Architecture Overview](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/red_hat_ansible_automation_platform_architecture/index)
- Incident Record: PMB tag `hardening, v1.0` - ULID `0019e9806e6c4_72f49a83`

## Related ADRs

- ADR 0021: Deprecate Airflow and Adopt AAP (decision to adopt AAP 2.6)
- ADR 0026: Use RHEL 9 Base Image for AAP VM (deployment requirements)
- ADR 0009: Secrets Management Strategy (password storage via Ansible Vault)
