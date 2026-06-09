# Podman Environment Setup

## XDG_RUNTIME_DIR Requirement

Podman running in **rootless mode** requires the `XDG_RUNTIME_DIR` environment variable to be set. This is critical for:

- Building container images with `podman build`
- Running `ansible-builder` (which uses podman internally)
- All podman operations (login, push, pull, run)

### Local Development Setup

Add to `~/.bashrc` (automatically done during initial setup):

```bash
# Set XDG_RUNTIME_DIR for podman (required for rootless containers)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
```

**Apply changes**:
```bash
source ~/.bashrc
```

**Verify**:
```bash
echo $XDG_RUNTIME_DIR
# Expected output: /run/user/1001 (or your UID)

podman --version
# Expected: podman version 5.8.2
```

---

## GitHub Actions Setup

Set `XDG_RUNTIME_DIR` as a workflow environment variable:

```yaml
env:
  XDG_RUNTIME_DIR: /run/user/${{ github.actor_id || 1001 }}
```

**Example** (see `.github/workflows/build-custom-ee.yml`):

```yaml
name: Build Custom EE

on:
  push:
    branches: [main]

env:
  XDG_RUNTIME_DIR: /run/user/${{ github.actor_id || 1001 }}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Build with podman
        run: |
          ansible-builder build --container-runtime podman ...
```

---

## AAP (Ansible Automation Platform) Setup

When running playbooks via AAP, ensure the execution environment or job template sets:

```bash
XDG_RUNTIME_DIR=/run/user/$(id -u)
```

**Option 1: Custom Execution Environment** (recommended):
Add to your EE's Dockerfile/Containerfile:
```dockerfile
ENV XDG_RUNTIME_DIR=/run/user/0
```

**Option 2: Job Template Extra Vars**:
```yaml
extra_vars:
  ansible_env:
    XDG_RUNTIME_DIR: "/run/user/{{ ansible_user_uid }}"
```

---

## Troubleshooting

### Error: "Failed to obtain podman configuration"

**Symptom**:
```
Failed to obtain podman configuration: lstat /home/vpcuser/.run/containers: no such file or directory
```

**Cause**: `XDG_RUNTIME_DIR` not set or incorrectly set.

**Fix**:
```bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
podman --version  # Test
```

---

### Error: "/run/user/0 does not exist"

**Symptom**:
```
Error: "/run/user/0" directory set by $XDG_RUNTIME_DIR does not exist
```

**Cause**: Variable resolving to root's UID (0) instead of actual user's UID.

**Fix**:
```bash
# Check current value
echo $XDG_RUNTIME_DIR

# Should be /run/user/1001 (your UID), NOT /run/user/0

# Re-export correctly
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
```

---

## Why This Matters

Podman's **rootless architecture** (ADR 0030 - to be created) stores runtime data in user-specific directories:

- **Session sockets**: `/run/user/$(id -u)/podman/podman.sock`
- **Container state**: `/run/user/$(id -u)/containers/`
- **Lock files**: `/run/user/$(id -u)/libpod/`

Without `XDG_RUNTIME_DIR`, podman doesn't know where to create these files, causing failures.

---

## References

- [Podman Rootless Tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- ADR 0029: Custom Execution Environment for AAP Registry Authentication
- ADR 0030: Podman Rootless Architecture (planned)
