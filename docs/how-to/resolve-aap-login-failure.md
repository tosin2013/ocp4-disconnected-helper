# How to Resolve: AAP Login Failure

Fix "Invalid username or password" error when logging into AAP Web UI.

---

## Problem

You enter the correct username and password in the AAP Web UI at `https://aap.sandbox3377.opentlc.com`, but get:

```
Invalid username or password
```

However, API authentication with the same credentials works:

```bash
curl -u admin:<password> https://aap.sandbox3377.opentlc.com/api/controller/v2/ping/
# ✅ Returns 200 OK
```

---

## Root Cause

**AAP 2.6 multi-node architecture uses TWO separate admin passwords**:

1. **`automationgateway_admin_password`** - For **Web UI login** (Gateway component)
2. **`admin_password`** - For **Controller API authentication** (Controller component)

You are using the **Controller password** (`admin_password`) for the **Web UI**, which requires the **Gateway password** (`automationgateway_admin_password`).

See [ADR-0028: AAP 2.6 Multi-Node Password Architecture](../adrs/0028-aap-multi-node-password-architecture.md) for complete details.

---

## Solution

### Step 1: Identify the Correct Password

Check your secrets file:

```bash
ansible-vault view extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass | grep -E "(automationgateway_admin_password|admin_password)"
```

Output:
```yaml
admin_password: 'ControllerAPIPassword123!'
automationgateway_admin_password: 'GatewayWebUIPassword456!'
```

### Step 2: Use the Gateway Password for Web UI

**Web UI Login**:
- URL: `https://aap.sandbox3377.opentlc.com`
- Username: `admin`
- Password: `GatewayWebUIPassword456!` ← **Use this one**

**API Authentication**:
```bash
curl -u admin:ControllerAPIPassword123! \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/ping/
```

---

## Verification

### Test Web UI Access

1. Open browser: `https://aap.sandbox3377.opentlc.com`
2. Login with:
   - Username: `admin`
   - Password: `<automationgateway_admin_password>`
3. You should see the AAP dashboard

### Test API Access

```bash
# Controller API (uses admin_password)
curl -sk -u admin:"$ADMIN_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/ping/" | jq .version

# Expected: "4.7.12"
```

---

## Prevention

### Validate Passwords Before Deployment

Run the validation playbook before deploying AAP:

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/validate-aap-passwords.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

This ensures:
- ✅ Both passwords are set
- ✅ Passwords are different (security best practice)
- ✅ No accidental password reuse

### Use Different Passwords

**Bad** (security risk):
```yaml
admin_password: 'SamePassword123!'
automationgateway_admin_password: 'SamePassword123!'
```

**Good** (separate passwords):
```yaml
admin_password: 'ControllerAPISecret789!'
automationgateway_admin_password: 'GatewayUISecret456!'
```

---

## Why This Matters

**Security Separation**: Gateway and Controller are separate components with different attack surfaces. Using different passwords limits credential exposure.

**Component Isolation**: If one password is compromised, the other component remains secure.

**Operational Clarity**: Explicit password separation prevents confusion in automation scripts (API calls vs Web UI automation).

---

## Related Documentation

- [ADR-0028: AAP 2.6 Multi-Node Password Architecture](../adrs/0028-aap-multi-node-password-architecture.md)
- [Hardening Report: AAP Multi-Node Password (v1.0)](../hardening/aap-multi-node-password-v1.0-2026-06-05.md)
- [AAP Deployment Guide](../AAP_DEPLOYMENT_GUIDE.md#installation-configuration)
