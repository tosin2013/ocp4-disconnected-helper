# Execution Environment Delegation Strategy

**Date**: 2026-06-17  
**Status**: Active  
**Upstream EE Repository**: https://github.com/tosin2013/ocp4-aap-execution-environment

---

## Overview

As of v1.3.0, this project **fully delegates** Ansible Execution Environment (EE) management to the upstream `ocp4-aap-execution-environment` repository. We consume pre-built images from Quay rather than building custom EEs locally.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│ ocp4-aap-execution-environment (UPSTREAM)   │
│  - files/requirements.yml (collection deps) │
│  - Containerfile (image build)              │
│  - GitHub Actions (build + publish)         │
│  - Quay.io registry (public images)         │
└──────────────┬──────────────────────────────┘
               │ publishes to
               ↓
┌─────────────────────────────────────────────┐
│ quay.io/takinosh/                           │
│   ocp4-aap-execution-environment:vX.Y.Z     │
└──────────────┬──────────────────────────────┘
               │ pulls from
     ┌─────────┴──────────┐
     ↓                    ↓
┌──────────────┐  ┌────────────────────────┐
│ AAP Runtime  │  │ GitHub Actions CI/CD   │
│ (Job Exec)   │  │ (Syntax Validation)    │
└──────────────┘  └────────────────────────┘
```

---

## What We Removed

**Deprecated Files** (removed in v1.3.0):
- ❌ `playbooks/build-custom-ee.yml` — EE build playbook
- ❌ `.github/workflows/build-ee.yml` — EE build CI workflow  
- ❌ `execution-environment.yml` — Local EE definition
- ❌ `files/requirements.yml` — Collection dependencies

**Reason**: Maintaining duplicate EE build logic creates:
- Version drift between this repo and upstream
- CI build time overhead (5-10 minutes per run)
- Duplicate dependency management
- Stale documentation

---

## What We Consume

**Upstream EE Image**:
```yaml
registry: quay.io
image: takinosh/ocp4-aap-execution-environment
tag: vX.Y.Z (version pinned, never :latest)
```

**Included Collections** (as of v1.2.2):
- `ansible.controller 4.8.2` — AAP job templates, workflows
- `ansible.hub 1.0.6` — AAP configuration management
- `infra.aap_utilities 3.4.0` — AAP setup/installation
- `community.libvirt 2.2.0` — KVM/libvirt VM provisioning (NEW in v1.2.2)
- `containers.podman 1.20.2` — Podman container management (NEW in v1.2.2)
- `ansible.posix 2.2.0` — Firewall, selinux, mount utilities
- `kubernetes.core 6.4.0` — OpenShift/K8s resource management
- `community.general 13.1.0` — General-purpose modules
- `ansible.utils 6.0.3` — Network/data utilities
- `amazon.aws 11.3.0` — AWS cloud resources
- `azure.azcollection 3.19.0` — Azure cloud resources

**Total**: 11 collections (comprehensive coverage for disconnected OpenShift deployments)

---

## How We Use It

### 1. GitHub Actions CI/CD

**Workflow**: `.github/workflows/ansible-sanity.yml`

```yaml
- name: Pull Custom AAP Execution Environment
  run: |
    # Pull upstream EE for syntax validation
    podman pull quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2

- name: Check playbook syntax (in custom EE container)
  run: |
    for playbook in playbooks/*.yml; do
      podman run --rm \
        -v $PWD:/workspace:Z \
        -w /workspace \
        quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2 \
        ansible-playbook --syntax-check "$playbook" \
        -i inventory/ibm-cloud.yml
    done
```

**Benefits**:
- Zero build time (pull takes 30-60s vs 5-10min build)
- Exact parity with AAP runtime environment
- Automatic collection updates on upstream releases

---

### 2. AAP Job Template Execution

**Configuration**: `playbooks/configure-custom-ee-in-aap.yml`

```yaml
- name: Configure Custom Execution Environment in AAP
  ansible.controller.execution_environment:
    name: "Custom OCP4 EE"
    image: "quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2"
    pull: "always"
    organization: "Default"
```

**Runtime**: All AAP job templates execute inside this EE container

---

### 3. Local Development (ansible-navigator)

**Configuration**: `ansible-navigator.yml` (user-specific, not in repo)

```yaml
execution-environment:
  enabled: true
  image: quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2
  pull:
    policy: always
```

**Usage**:
```bash
ansible-navigator run playbooks/site.yml \
  --execution-environment-image quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2 \
  --mode stdout
```

---

## Version Pinning Strategy

**❌ NEVER use `:latest`** in production workflows:
```yaml
# BAD - cache issues, non-deterministic
image: quay.io/takinosh/ocp4-aap-execution-environment:latest
```

**✅ ALWAYS use specific version tags**:
```yaml
# GOOD - reproducible, explicit upgrades
image: quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2
```

**Rationale** (ADR-0029):
- Avoids stale registry caches
- Forces intentional upgrades with testing
- Clear rollback path if issues found
- Reproducible builds across time

---

## Upgrade Process

When upstream releases a new EE version (e.g., v1.2.3):

### Step 1: Review Release Notes
```bash
# Check what changed
gh release view v1.2.3 --repo tosin2013/ocp4-aap-execution-environment
```

### Step 2: Test Locally
```bash
# Pull new version
podman pull quay.io/takinosh/ocp4-aap-execution-environment:v1.2.3

# Verify collections
podman run --rm quay.io/takinosh/ocp4-aap-execution-environment:v1.2.3 \
  ansible-galaxy collection list

# Run syntax check
for playbook in playbooks/*.yml; do
  podman run --rm \
    -v $PWD:/workspace:Z \
    -w /workspace \
    quay.io/takinosh/ocp4-aap-execution-environment:v1.2.3 \
    ansible-playbook --syntax-check "$playbook" \
    -i inventory/ibm-cloud.yml || echo "FAILED: $playbook"
done
```

### Step 3: Update Workflow Files
```bash
# Update GitHub Actions workflow
sed -i 's/v1\.2\.2/v1.2.3/g' .github/workflows/ansible-sanity.yml

# Update ADR documentation
vim docs/adrs/0029-custom-execution-environment-for-aap-registry-authentication.md
```

### Step 4: Commit and Test
```bash
git add .github/workflows/ansible-sanity.yml docs/adrs/0029-custom-execution-environment-for-aap-registry-authentication.md
git commit -m "chore(ci): Upgrade EE to v1.2.3"
git push
```

### Step 5: Monitor CI
```bash
gh run watch
```

### Step 6: Update AAP Configuration (if needed)
```bash
# Update AAP organization default EE
ansible-playbook playbooks/configure-custom-ee-in-aap.yml \
  -e ee_image_tag=v1.2.3
```

---

## Collaboration Model

### Upstream Responsibilities (ocp4-aap-execution-environment)
- Maintain comprehensive collection set
- Build and publish EE images to Quay
- Version tagging and release management
- GitHub Actions CI for build validation

### Downstream Responsibilities (this repo)
- Consume pre-built images from Quay
- Report missing collections via GitHub issues
- Test new versions before upgrading
- Document version-specific requirements

---

## Requesting New Collections

If a playbook requires a collection not in the upstream EE:

### Step 1: Create GitHub Issue
```markdown
Title: [Collection Request] community.docker for container orchestration

## Use Case
Playbooks `setup-docker-registry.yml` requires `community.docker.docker_container` module.

## Failed Playbooks
- playbooks/setup-docker-registry.yml

## Error Message
ERROR! couldn't resolve module/action 'community.docker.docker_container'.

## Collection Details
- Name: community.docker
- Galaxy URL: https://galaxy.ansible.com/ui/repo/published/community/docker/
- Latest Version: 3.8.0

## Impact
1 playbook fails (2% failure rate) - Medium priority

## Verification Command
podman run --rm quay.io/takinosh/ocp4-aap-execution-environment:vX.Y.Z \
  ansible-doc community.docker.docker_container
```

### Step 2: Submit PR (Optional - Faster)
If you have write access, submit a PR directly:

```bash
cd ~/ocp4-aap-execution-environment
vim files/requirements.yml  # Add collection
git add files/requirements.yml
git commit -m "feat: Add community.docker collection"
git push origin add-docker-collection
gh pr create
```

---

## Troubleshooting

### Issue: Playbook fails with "module not found"

**Diagnosis**:
```bash
# Check if collection is in EE
podman run --rm quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2 \
  ansible-galaxy collection list | grep <collection-name>
```

**Solution**:
- If collection missing: Request via GitHub issue (see above)
- If collection present but module missing: May be wrong module name or version mismatch

---

### Issue: CI pulls wrong image version

**Diagnosis**:
```bash
# Check workflow file
grep "ocp4-aap-execution-environment" .github/workflows/ansible-sanity.yml
```

**Solution**:
```bash
# Ensure specific version tag, not :latest
sed -i 's/:latest/:v1.2.2/g' .github/workflows/ansible-sanity.yml
```

---

### Issue: Local build still exists from old workflow

**Cleanup**:
```bash
# Remove old local build
podman rmi localhost/ocp4-aap-execution-environment:latest

# Pull upstream image
podman pull quay.io/takinosh/ocp4-aap-execution-environment:v1.2.2
```

---

## Related Documentation

- **ADR-0029**: Custom Execution Environment for AAP Registry Authentication
- **Upstream Repository**: https://github.com/tosin2013/ocp4-aap-execution-environment
- **Quay Registry**: https://quay.io/repository/takinosh/ocp4-aap-execution-environment
- **Release Notes**: https://github.com/tosin2013/ocp4-aap-execution-environment/releases

---

## Changelog

### v1.3.0 (2026-06-17)
- ✅ Removed local EE build playbooks and workflows
- ✅ Delegated to upstream ocp4-aap-execution-environment repository
- ✅ Updated GitHub Actions to pull from Quay
- ✅ Documented collaboration model (this file)

### v1.2.2 (2026-06-17 - upstream)
- ✅ Added `community.libvirt` collection (critical for VM provisioning)
- ✅ Added `containers.podman` collection (JFrog registry support)
- ✅ Documented missing collections report

### v1.2.1 (2026-06-17 - upstream)
- ✅ Added `infra.aap_utilities` collection (AAP deployment workflows)

### v1.2.0 (2026-06-17 - upstream)
- ✅ Added `ansible.controller` collection (AAP job templates)
