# How to Resolve: oc-mirror Async Cache Error

Fix "port 55000 already bound" error that returns immediately (<5 seconds).

---

## Problem

Running `ansible-playbook playbooks/download-to-disk-v2.yml` fails instantly with:

```
FAILED! => {
    "msg": "[ERROR] [Executor] 55000 is already bound and cannot be used"
}
```

**Indicators this is async cache (not real port conflict)**:
- Playbook fails in **<5 seconds** (real oc-mirror takes 1-60 minutes)
- Same job ID appears in multiple runs (e.g., `j571283734101.416643`)
- Port 55000 is actually **free**: `ss -tlnp | grep 55000` returns nothing

---

## Root Cause

Stale Ansible async cache at `/root/.ansible_async/` returning cached failure from a previous playbook run.

The playbook does **NOT actually execute** - it returns the cached result immediately with the original error.

See [Hardening Report: oc-mirror Async Cache (v1.0)](../hardening/oc-mirror-async-cache-v1.0-2026-06-04.md) for complete incident analysis.

---

## Solution

### Clear Async Cache

```bash
sudo rm -rf /root/.ansible_async/*
```

Or use the cleanup script:

```bash
sudo ./scripts/clear-async-cache.sh
```

### Re-run Playbook

```bash
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

**Expected behavior**: Playbook should now take >30 seconds to start (installing prerequisites).

---

## Verification

### Detect Cached vs Real Failure

**Cached failure** (async cache):
- ✅ Fails in **<5 seconds**
- ✅ Port 55000 is **free**: `sudo ss -tlnp | grep 55000` returns nothing
- ✅ Same job ID across multiple runs
- ✅ Error message references old execution

**Real failure** (actual port conflict):
- ❌ Fails after **30+ seconds** (after prerequisites installed)
- ❌ Port 55000 is **bound**: `sudo ss -tlnp | grep 55000` shows process
- ❌ Different job ID each run
- ❌ oc-mirror process actually running: `ps aux | grep oc-mirror`

### Confirm Playbook Execution

After clearing cache, verify playbook actually runs:

```bash
# Should take 30+ seconds to reach oc-mirror execution
time ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

Watch for:
```
TASK [Install oc-mirror prerequisites] ****************************************
...
TASK [Download OpenShift images with oc-mirror] *******************************
...
[INFO] Mirroring 1234 images...
```

---

## Prevention

### Preflight Warning (v1.1+)

Newer versions of `download-to-disk-v2.yml` warn about stale async cache:

```
TASK [Check for stale async cache] ********************************************
[WARNING]: Stale async cache detected at /root/.ansible_async/
[WARNING]: Clear with: sudo rm -rf /root/.ansible_async/*
```

**Heed this warning** and clear cache before proceeding.

### Manual Cleanup After Failures

After any failed oc-mirror run:

```bash
sudo rm -rf /root/.ansible_async/*
```

This prevents future playbook runs from returning cached failures.

---

## Advanced: Verify Port is Actually Free

If unsure whether port conflict is real or cached:

```bash
# Check if port 55000 is listening
sudo ss -tlnp | grep 55000

# Check if oc-mirror is running
ps aux | grep oc-mirror

# Check recent async jobs
ls -lt /root/.ansible_async/ | head -5
```

**If all three return nothing**, it's async cache, not a real conflict.

---

## Related Issues

### oc-mirror Fails with Different Error

If oc-mirror fails with a different error (not port 55000):
1. **Do NOT clear async cache** (you'll lose the error details)
2. Debug the actual error first
3. Only clear cache after resolving root cause

### Playbook Hangs After Cache Clear

If playbook starts but hangs:
- Check disk space: `df -h /data`
- Check network connectivity: `ping registry.redhat.io`
- Monitor oc-mirror progress: `tail -f /data/logs/oc-mirror.log`

---

## Related Documentation

- [Hardening Report: oc-mirror Async Cache (v1.0)](../hardening/oc-mirror-async-cache-v1.0-2026-06-04.md)
- [ADR-0003: oc-mirror v2 for Image Mirroring](../adrs/0003-oc-mirror-image-mirroring.md)
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
