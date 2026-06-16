# Molecule Test Scenarios for common_vm Role

This directory contains Molecule test scenarios for validating the common_vm role behavior across different configuration modes and error conditions.

## Available Scenarios

### 1. default (Basic Functionality)
**Location**: `molecule/default/`  
**Purpose**: Smoke test for basic Molecule infrastructure  
**Duration**: ~6 seconds

**Tests**:
- ✓ Container creation with rootful Podman
- ✓ Basic Ansible execution inside container
- ✓ Systemd running correctly

**Run**:
```bash
molecule test  # Runs default scenario
```

---

### 2. static-ip (Static IP Configuration)
**Location**: `molecule/static-ip/`  
**Purpose**: Validate cloud-init network-config v2 generation with static IP  
**Duration**: ~8 seconds

**Tests**:
- ✓ Network-config v2 format validation
- ✓ Static IP address configuration (192.168.10.50/24)
- ✓ DHCP4 explicitly disabled
- ✓ Gateway4 configuration (CentOS Stream 9 compatible)
- ✓ DNS nameserver configuration
- ✓ YAML syntax validation
- ✓ User-data file generation

**Key Validation Points**:
- Uses `gateway4` instead of `routes` (resolves CentOS Stream 9 cloud-init bug)
- DNS servers formatted as proper JSON list
- Static IP with `/24` CIDR notation

**Run**:
```bash
molecule test -s static-ip
```

**Sample Output**:
```
========================================
Static IP Configuration Tests: PASSED
========================================
✓ Network-config v2 format valid
✓ Static IP: 192.168.10.50/24
✓ DHCP4 disabled
✓ Gateway4: 192.168.10.1 (CentOS Stream 9 compatible)
✓ DNS servers: 192.168.10.1, 8.8.8.8
✓ YAML syntax valid
✓ User-data generated
```

---

### 3. dhcp (DHCP Configuration)
**Location**: `molecule/dhcp/`  
**Purpose**: Validate cloud-init network-config v2 with DHCP enabled  
**Duration**: ~7 seconds

**Tests**:
- ✓ Network-config v2 format validation
- ✓ DHCP4 enabled
- ✓ No static addresses configured
- ✓ No static gateway configured
- ✓ DNS from DHCP server (no manual override)
- ✓ YAML syntax validation
- ✓ Minimal configuration (clean)

**Key Validation Points**:
- Ensures `addresses` field is absent (not set to empty list)
- Verifies `gateway4` is not configured (DHCP provides routing)
- Confirms minimal config (only `dhcp4: true` parameter)

**Run**:
```bash
molecule test -s dhcp
```

**Sample Output**:
```
=====================================
DHCP Configuration Tests: PASSED
=====================================
✓ Network-config v2 format valid
✓ DHCP4 enabled
✓ No static addresses configured
✓ No static gateway configured
✓ DNS from DHCP server
✓ YAML syntax valid
✓ Minimal configuration (clean)
```

---

### 4. error-handling (Error Conditions)
**Location**: `molecule/error-handling/`  
**Purpose**: Validate graceful failure and defensive programming  
**Duration**: ~9 seconds

**Tests**:
1. **Missing Static IP**: Template falls back to DHCP (defensive programming)
2. **Invalid IP Format**: Template accepts (validation deferred to role logic)
3. **Missing DNS Servers**: Template handles empty list gracefully
4. **Special Characters in Hostname**: YAML syntax validation catches issues
5. **Static IP Without Gateway**: Template handles missing gateway

**Key Findings**:
- ✅ **Graceful Degradation**: Template uses DHCP fallback instead of failing
- ⚠️ **Validation Gap**: IP address format validation should be in role tasks
- ⚠️ **Hostname Validation**: Special characters need RFC 1123 compliance check

**Recommendations**:
- Add IP address format validation in role tasks (regex or ipaddr filter)
- Add hostname validation (RFC 1123: alphanumeric + hyphens only)
- Require gateway when static IP is enabled (fail if missing)
- Add DNS server validation (at least one required for static IP)

**Run**:
```bash
molecule test -s error-handling
```

**Sample Output**:
```
=========================================
Error Handling Tests Summary
=========================================
Total Tests: 5
Tests Reviewed: 5

Key Findings:
✓ Missing static IP: Falls back to DHCP
✓ Invalid IP format: Template accepts (validation needed in role)
✓ Missing DNS: Handled
✓ Special chars: Needs validation
✓ No gateway: Handled

Recommendations:
- Add IP address format validation in role tasks
- Add hostname validation (RFC 1123 compliance)
- Require gateway when static IP is enabled
- Add DNS server validation (at least one required)
```

---

## Running All Scenarios

**Sequential**:
```bash
molecule test -s default
molecule test -s static-ip
molecule test -s dhcp
molecule test -s error-handling
```

**Parallel** (if supported):
```bash
for scenario in default static-ip dhcp error-handling; do
  molecule test -s $scenario &
done
wait
```

---

## Test Coverage Summary

| Scenario | Lines of Code | Assertions | Coverage Area |
|----------|---------------|------------|---------------|
| default | ~30 | 1 | Container lifecycle |
| static-ip | ~120 | 8 | Static IP config |
| dhcp | ~90 | 8 | DHCP config |
| error-handling | ~150 | 5 | Error conditions |
| **TOTAL** | **~390** | **22** | **100% network modes** |

---

## Key Architectural Decisions Tested

### ADR Validation

**ADR-0036 (Molecule Framework)**:
- ✅ Rootful Podman workaround (CentOS Stream 10 UID mapping)
- ✅ Fast feedback cycle (<10 seconds per scenario)
- ✅ No actual VM provisioning (template-level testing)

**Cloud-init Best Practices**:
- ✅ Uses `gateway4` instead of `routes` (CentOS Stream 9 compatibility)
- ✅ Network-config v2 format (modern cloud-init)
- ✅ Explicit `dhcp4: false` for static IP (prevents race conditions)

**Defensive Programming**:
- ✅ DHCP fallback when static IP misconfigured
- ✅ Graceful handling of missing parameters
- ⚠️ Validation gaps documented as recommendations

---

## Test Artifacts

**Generated Files** (per scenario):
- `/tmp/molecule-test-{scenario}/user-data` — Cloud-init user-data
- `/tmp/molecule-test-{scenario}/network-config` — Cloud-init network-config v2
- `/tmp/molecule-test-errors/test-results.yml` — Error handling results

**Cleanup**:
Test artifacts are automatically cleaned up by Molecule's destroy phase.

---

## Troubleshooting

### Container Creation Fails
**Error**: `newuidmap: Permission denied`  
**Solution**: Verify Molecule playbooks use `sudo podman` (rootful) due to CentOS Stream 10 UID mapping limitation. See ADR-0036.

### Template Not Found
**Error**: `Could not find or access '../../templates/cloud-init/...`  
**Solution**: Run Molecule from role directory: `cd roles/common_vm && molecule test -s <scenario>`

### YAML Syntax Errors
**Error**: `yaml.safe_load() failed`  
**Solution**: Check template output in `/tmp/molecule-test-*/` and validate manually:
```bash
python3 -c 'import yaml; yaml.safe_load(open("/tmp/molecule-test-images/network-config"))'
```

---

## Next Steps

**Future Test Scenarios** (Planned):
1. **VyOS Integration**: Test VyOS-managed network configuration
2. **Multi-NIC**: Test multiple network interfaces
3. **IPv6**: Test dual-stack IPv4/IPv6 configuration
4. **Performance**: Test template rendering performance at scale
5. **Idempotence**: Test repeated role execution (should be no changes)

**Integration Testing** (Outside Molecule Scope):
- Actual VM provisioning with libvirt (slow, CI-unfriendly)
- Network connectivity validation (requires nested KVM)
- SSH access verification (requires running VMs)

These belong in E2E workflow testing (ADR-0033), not Molecule unit tests.

---

## References

- **Molecule Documentation**: https://molecule.readthedocs.io/
- **Cloud-init Network Config v2**: https://cloudinit.readthedocs.io/en/latest/reference/network-config-format-v2.html
- **ADR-0036**: Adopt Molecule Framework for Infrastructure Automation Testing
- **docs/TESTING.md**: Comprehensive testing guide for this project
