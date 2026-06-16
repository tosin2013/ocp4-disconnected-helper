# oc-mirror v2 Workflow - Ansible Automation

**The Right Way**: Use Ansible playbooks, not raw commands

---

## ❌ What We Did (Wrong Approach)

```bash
# Phase 1: Raw oc-mirror command
oc-mirror --config imageset-config-v2-test.yml \
  file:///home/vpcuser/.oc-mirror \
  --authfile ~/pull-secret.json \
  --v2

# Phase 2: Raw oc-mirror command
oc-mirror --config imageset-config-v2-test.yml \
  --workspace file:///home/vpcuser/.oc-mirror \
  docker://registry.ocp4.sandbox3377.opentlc.com:8443/openshift4 \
  --authfile ~/pull-secret-combined.json \
  --dest-tls-verify=false \
  --v2
```

**Problems**:
- Not idempotent (can't safely re-run)
- No error handling
- No validation
- Manual configuration
- Not reproducible across environments

---

## ✅ What We Should Have Done (Ansible Playbooks)

### Phase 1: Download to Disk (mirrorToDisk)

```bash
# Use the playbook we created
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-v2-example.yml

# With dry-run validation first
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-v2-example.yml \
  -e "dry_run=true"
```

**What the playbook does**:
- ✅ Validates prerequisites (oc-mirror installed, pull-secret exists)
- ✅ Checks disk space
- ✅ Generates ImageSetConfiguration v2alpha1 dynamically
- ✅ Supports dry-run mode
- ✅ Comprehensive error handling
- ✅ Summary report at the end
- ✅ Idempotent (can run multiple times)

### Phase 2: Push to Registry (mirrorToMirror)

```bash
# Setup authentication first
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/setup-registry-authentication.yml

# Push to registry
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/push-to-registry-v2.yml \
  -e "workspace_path=/home/vpcuser/.oc-mirror"

# With dry-run validation
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/push-to-registry-v2.yml \
  -e "workspace_path=/home/vpcuser/.oc-mirror" \
  -e "dry_run=true"
```

**What the playbook does**:
- ✅ Validates workspace exists
- ✅ Tests registry connectivity
- ✅ Tests authentication with `podman login`
- ✅ Uses combined pull-secret automatically
- ✅ Supports dry-run mode
- ✅ Post-push verification (catalog check)
- ✅ Proper error messages and troubleshooting hints

---

## Complete Workflow Example

### Setup (One-time)

```bash
# 1. Create extra_vars for your environment
cat > extra_vars/my-environment.yml <<EOF
---
# Storage Configuration
target_mirror_path: "/data/ocp-mirror"
clean_mirror_path: false

# OpenShift Releases
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0

architectures:
  - amd64

# Performance Tuning
parallel_images: 4
parallel_layers: 5
max_retries: 5
EOF

# 2. Update inventory with your registry details
vi inventory/ibm-cloud.yml
# Set:
#   quay_vm_ip: "192.168.122.26"
#   quay_vm_port: 8443
#   quay_url: "registry.ocp4.sandbox3377.opentlc.com"
```

### Execute Full Workflow

```bash
# Step 1: Download images (Phase 1)
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/my-environment.yml

# Expected output:
# ✅ Prerequisites validated
# ✅ ImageSetConfiguration generated
# ✅ 194 images downloaded
# ✅ Workspace: /data/ocp-mirror/oc-mirror-workspace
# ⏱️  Duration: ~10 minutes

# Step 2: Setup registry authentication
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/setup-registry-authentication.yml

# Expected output:
# ✅ Mirror-registry credentials retrieved
# ✅ Combined pull-secret created: ~/pull-secret-combined.json

# Step 3: Push to registry (Phase 2)
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/push-to-registry-v2.yml \
  -e "workspace_path=/data/ocp-mirror/oc-mirror-workspace"

# Expected output:
# ✅ Registry connectivity validated
# ✅ Authentication successful
# ✅ 194 images pushed
# ✅ Registry catalog verified
# ⏱️  Duration: ~10-15 minutes
```

---

## Playbook Features

### download-to-disk-v2.yml

**Variables** (from extra_vars or CLI):
```yaml
target_mirror_path: "/data/ocp-mirror"      # Where to store workspace
oc_mirror_version: "latest"                 # or specific version
dry_run: false                              # true for validation only
clean_mirror_path: false                    # true to clean before run
parallel_images: 4                          # Concurrent image downloads
parallel_layers: 5                          # Concurrent layer downloads
max_retries: 5                              # Retry failed downloads

openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
    shortestPath: false

architectures:
  - amd64

operators: []                               # Optional operator catalogs
additional_images: []                       # Optional additional images
```

**Key Tasks**:
1. Install prerequisites (oc, oc-mirror, base packages)
2. Validate pull-secret.json
3. Check disk space (warns if < 100GB)
4. Generate ImageSetConfiguration v2alpha1
5. Dry-run validation (if requested)
6. Execute oc-mirror mirrorToDisk
7. Display workspace summary

### push-to-registry-v2.yml

**Variables** (from inventory or CLI):
```yaml
workspace_path: "/data/ocp-mirror/oc-mirror-workspace"
target_registry: "{{ quay_url }}:{{ quay_vm_port }}"
target_namespace: "openshift4"
combined_pull_secret: "~/pull-secret-combined.json"
imageset_config: "{{ workspace_path | dirname }}/imageset-config-v2.yml"
skip_tls_verify: false                      # true for self-signed certs
dry_run: false                              # true for validation only
parallel_images: 4
parallel_layers: 5
max_retries: 5
```

**Key Tasks**:
1. Validate oc-mirror installed
2. Check workspace exists
3. Validate ImageSetConfiguration exists
4. Check combined pull-secret exists
5. Test registry connectivity (HTTP/HTTPS)
6. Test authentication (`podman login`)
7. Dry-run validation (if requested)
8. Execute oc-mirror push
9. Verify images in registry catalog

---

## Why Ansible Matters

### Idempotency Example

**Raw Command** (Not idempotent):
```bash
# Run twice = potential duplicate work, no validation
oc-mirror --config config.yml file:///workspace --v2
oc-mirror --config config.yml file:///workspace --v2  # Re-downloads everything!
```

**Ansible Playbook** (Idempotent):
```yaml
- name: Check if workspace already exists
  ansible.builtin.stat:
    path: "{{ target_mirror_path }}/oc-mirror-workspace"
  register: workspace_stat

- name: Skip if workspace exists
  ansible.builtin.debug:
    msg: "Workspace already exists, skipping download"
  when: workspace_stat.stat.exists

- name: Run oc-mirror (only if workspace doesn't exist)
  ansible.builtin.command: ...
  when: not workspace_stat.stat.exists
```

### Error Handling Example

**Raw Command**:
```bash
oc-mirror ... || echo "Failed!" && exit 1  # Useless error message
```

**Ansible Playbook**:
```yaml
- name: Run oc-mirror
  ansible.builtin.command: ...
  register: mirror_output
  failed_when: mirror_output.rc != 0

- name: Handle failure
  when: mirror_output.rc != 0
  block:
    - name: Display detailed error
      ansible.builtin.debug:
        msg:
          - "❌ oc-mirror failed with exit code {{ mirror_output.rc }}"
          - "Error: {{ mirror_output.stderr }}"
          - ""
          - "Troubleshooting:"
          - "1. Check pull-secret validity: jq . ~/pull-secret.json"
          - "2. Check disk space: df -h {{ target_mirror_path }}"
          - "3. Test Red Hat registry access: podman login registry.redhat.io"
    
    - name: Fail with clear message
      ansible.builtin.fail:
        msg: "See troubleshooting steps above"
```

### Environment Portability

**Raw Commands** (Hardcoded):
```bash
# Development
oc-mirror ... docker://192.168.122.26:8443/openshift4 ...

# Production (different registry!)
oc-mirror ... docker://registry.prod.example.com:8443/openshift4 ...
# Have to remember to change this manually!
```

**Ansible Playbooks** (Inventory-based):
```yaml
# inventory/dev.yml
quay_url: "192.168.122.26"
quay_vm_port: 8443

# inventory/prod.yml
quay_url: "registry.prod.example.com"
quay_vm_port: 8443

# Same playbook works for both!
ansible-playbook -i inventory/dev.yml playbooks/push-to-registry-v2.yml
ansible-playbook -i inventory/prod.yml playbooks/push-to-registry-v2.yml
```

---

## Testing Strategy

### 1. Syntax Validation

```bash
# Validate playbook syntax
ansible-playbook --syntax-check playbooks/download-to-disk-v2.yml
ansible-playbook --syntax-check playbooks/push-to-registry-v2.yml
```

### 2. Dry-Run Validation

```bash
# Test download without actually downloading
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/my-environment.yml \
  -e "dry_run=true"

# Test push without actually pushing
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/push-to-registry-v2.yml \
  -e "workspace_path=/data/ocp-mirror/oc-mirror-workspace" \
  -e "dry_run=true"
```

### 3. Idempotency Testing

```bash
# Run twice - second run should skip or show no changes
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/my-environment.yml

# Run again
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/my-environment.yml
# Should detect existing workspace and skip
```

---

## Best Practices

### DO ✅

```bash
# Use playbooks for automation
ansible-playbook playbooks/download-to-disk-v2.yml -e @extra_vars/config.yml

# Use inventory for environment-specific settings
ansible-playbook -i inventory/prod.yml playbooks/push-to-registry-v2.yml

# Test with dry-run first
ansible-playbook playbooks/download-to-disk-v2.yml -e "dry_run=true"

# Use verbose mode for troubleshooting
ansible-playbook playbooks/push-to-registry-v2.yml -vvv
```

### DON'T ❌

```bash
# Don't run raw oc-mirror commands
oc-mirror --config config.yml file:///workspace --v2

# Don't hardcode values in commands
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e "target_registry=192.168.122.26:8443"  # Use inventory instead!

# Don't skip validation
ansible-playbook playbooks/download-to-disk-v2.yml --skip-tags validate

# Don't ignore errors
ansible-playbook playbooks/push-to-registry-v2.yml || true  # Bad!
```

---

## Troubleshooting Playbook Issues

### Issue: Playbook hangs during download

```bash
# Check oc-mirror process
ps aux | grep oc-mirror

# Check network connectivity to Red Hat
curl -I https://registry.redhat.io/v2/

# Run with verbose output
ansible-playbook playbooks/download-to-disk-v2.yml -vvv
```

### Issue: Authentication failed

```bash
# Validate pull-secret format
jq . ~/pull-secret.json

# Test Red Hat login
podman login registry.redhat.io --authfile ~/pull-secret.json

# Test mirror registry login
podman login registry.ocp4.sandbox3377.opentlc.com:8443 \
  --authfile ~/pull-secret-combined.json

# Re-run setup-registry-authentication.yml
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/setup-registry-authentication.yml
```

### Issue: Workspace not found

```bash
# Check workspace location
ls -lh /data/ocp-mirror/oc-mirror-workspace

# Verify workspace_path variable matches
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/push-to-registry-v2.yml \
  -e "workspace_path=/data/ocp-mirror/oc-mirror-workspace" \
  -vvv
```

---

## Comparison: Raw vs Ansible

| Feature | Raw Commands | Ansible Playbooks |
|---------|-------------|-------------------|
| Idempotent | ❌ No | ✅ Yes |
| Error Handling | ❌ Basic | ✅ Comprehensive |
| Validation | ❌ Manual | ✅ Automated |
| Dry-Run | ❌ Limited | ✅ Full support |
| Env Portability | ❌ Hardcoded | ✅ Inventory-based |
| Prerequisites | ❌ Manual | ✅ Auto-installed |
| Documentation | ❌ Tribal knowledge | ✅ Self-documenting |
| Reproducibility | ❌ Hard | ✅ Easy |
| Rollback | ❌ Manual | ✅ Playbook-based |
| Team Collaboration | ❌ Difficult | ✅ Version-controlled |

---

## Execution: Ansible Playbook (Recommended)

**ALWAYS use the Ansible playbook** for oc-mirror downloads. The playbook has a 4-hour async timeout and handles large downloads properly:

```bash
# Production execution (recommended)
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-v2-test.yml

# The playbook runs in background automatically
# Duration: 15-60 minutes depending on image count
# Timeout: 4 hours (14400 seconds)
```

**Playbook features**:
- ✅ 4-hour async timeout (handles large downloads)
- ✅ Polling every 30 seconds for progress updates
- ✅ Resumes from existing workspace (idempotent)
- ✅ Proper error handling and validation
- ✅ Post-download verification

---

## Manual Execution in tmux (ONLY for debugging)

**Use manual tmux ONLY for**:
- Debugging playbook issues
- Testing new oc-mirror flags
- One-off experiments

**NOT for production workflows** - the playbook is designed for this.

```bash
# Debugging only - NOT recommended for production
tmux new -s oc-mirror-download
oc-mirror --config /data/ocp-mirror-test/imageset-config.yaml \
  file:///data/ocp-mirror-test \
  --v2 \
  --dest-skip-tls=false
```

---

## Lessons Learned

### What We Did Wrong

1. **Bypassed our own automation**: Created comprehensive playbooks but then ran raw commands
2. **Lost idempotency**: Raw commands don't check for existing work
3. **No validation**: Didn't use dry-run mode before production execution
4. **Hardcoded values**: Used specific paths instead of inventory variables
5. **Manual workflow**: Forced manual intervention instead of automated workflow

### What We Should Do

1. **Always use playbooks**: They exist for a reason - use them!
2. **Test with dry-run**: Always validate before production execution
3. **Use inventory**: Environment-specific values belong in inventory files
4. **Follow the pattern**: If there's a playbook for it, use it
5. **Document deviations**: If you must use raw commands, document why in ADR

---

## Key Takeaway

> **"We need to remember Ansible should be doing this"**  
> — User feedback (2026-06-03)

The project is **Ansible-first by design** (ADR 0022, ADR 0023). Raw commands should only be used for:
- Quick debugging
- One-off troubleshooting
- Developing new playbooks (before automation exists)

For all production and development workflows:
1. Check if playbook exists
2. Use the playbook
3. Report issues with playbook
4. Improve playbook if needed

**DO NOT bypass automation for convenience.** The short-term convenience creates long-term maintenance burden.

---

**Last Updated**: 2026-06-03  
**Lesson Source**: Session feedback  
**Action Item**: Update developer onboarding to emphasize Ansible-first approach

