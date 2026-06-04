# ADR 0026: Use RHEL 9 Base Image for AAP VM

**Status:** Accepted  
**Date:** 2026-06-04  
**Deciders:** Platform Team  
**Related:** ADR 0021 - Deprecate Airflow and Adopt AAP

## Context

Ansible Automation Platform (AAP) 2.5 is a Red Hat enterprise product requiring a supported operating system. The initial AAP VM provisioning playbook (`playbooks/provision-aap-vm.yml`) used CentOS Stream 9 as the base image, which is not officially supported for AAP deployments.

## Decision

Use **Red Hat Enterprise Linux (RHEL) 9.2+** as the base operating system for AAP VM deployments.

### Official Requirements

Per [Red Hat AAP 2.5 System Requirements](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/rpm_installation/platform-system-requirements):

| Component | Requirement |
|-----------|-------------|
| **Operating System** | RHEL 9.2+ (preferred) or RHEL 8.8+ |
| **Architecture** | x86_64, ppc64le, s390x, aarch64 |
| **Ansible Core** | 2.16+ |
| **Installation Method** | Containerized (primary), RPM (deprecated) |

### Why RHEL 9.2+?

1. **Official Support**: AAP 2.5 is tested and supported on RHEL 9.2+
2. **Lifecycle Alignment**: RHEL 9 has longer support lifecycle than RHEL 8
3. **Containerized Installation**: AAP 2.5 containerized requires modern systemd and Podman (better on RHEL 9)
4. **Future-Proof**: RPM installation deprecated in AAP 2.5, removed in AAP 2.6

## Implementation

### RHEL Cloud Image Source

**Download Location**: [Red Hat Customer Portal](https://access.redhat.com/downloads/content/rhel)

**Requirements**:
- Valid Red Hat subscription
- Access to Red Hat Customer Portal downloads
- RHEL 9 KVM Guest Image (qcow2 format)

**Image Characteristics** (per [Red Hat Documentation](https://access.redhat.com/solutions/641193)):
- Cloud-init enabled
- Root account locked
- `cloud-user` account with sudo access
- EC2-compatible metadata service configured

### Playbook Changes

**File**: `playbooks/provision-aap-vm.yml`

```yaml
# Updated base image configuration
base_image_url: "{{ rhel9_kvm_guest_image_url }}"  # From inventory or vault
base_image_path: "/var/lib/libvirt/images/rhel9-kvm-guest.qcow2"
```

**Inventory Configuration** (`inventory/ibm-cloud.yml`):

```yaml
all:
  vars:
    # RHEL 9 KVM Guest Image (requires Red Hat subscription)
    rhel9_kvm_guest_image_url: "{{ lookup('env', 'RHEL9_IMAGE_URL') }}"
    # Or use pre-downloaded image path
    rhel9_base_image_path: "/var/lib/libvirt/images/rhel9-kvm-guest.qcow2"
```

### Alternative: Pre-Download RHEL Image

For disconnected/air-gapped environments:

```bash
# On connected workstation with Red Hat subscription
curl -u '<username>:<password>' \
  -o rhel-9-kvm-guest.qcow2 \
  'https://access.redhat.com/downloads/content/.../rhel-9.2-x86_64-kvm.qcow2'

# Transfer to hypervisor
scp rhel-9-kvm-guest.qcow2 vpcuser@hypervisor:/var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

## Consequences

### Positive

- **Official Support**: AAP deployments fully supported by Red Hat
- **Subscription Clarity**: Clear RHEL subscription requirement
- **Security Updates**: Access to RHEL security patches via subscription
- **Compliance**: Meets enterprise compliance for Red Hat products
- **Stability**: Production-grade OS for mission-critical automation

### Negative

- **Subscription Required**: Cannot use freely available CentOS Stream
- **Download Complexity**: Requires Red Hat Customer Portal authentication
- **Cost**: Additional RHEL subscription cost (beyond AAP subscription)

### Migration Path

**For Existing CentOS Stream 9 AAP VMs**:
1. Provision new RHEL 9 AAP VM
2. Export AAP configuration from CentOS VM
3. Import configuration to RHEL 9 VM
4. Validate automation workflows
5. Decommission CentOS VM

**For New Deployments**:
- Use updated `playbooks/provision-aap-vm.yml` with RHEL 9 base image
- Ensure RHEL subscription available before provisioning

## References

- [AAP 2.5 System Requirements](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/rpm_installation/platform-system-requirements)
- [RHEL KVM Guest Images](https://access.redhat.com/downloads/content/rhel)
- [AAP Containerized Installation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/containerized_installation)
- [RHEL Cloud Image Configuration](https://access.redhat.com/solutions/641193)

## Related ADRs

- ADR 0021: Deprecate Airflow and Adopt AAP (decision to use AAP 2.5)
- ADR 0023: Pure Ansible with community.libvirt (VM provisioning method)

## Notes

**Cloud-Init User Setup**:
- Default user: `cloud-user` (not `root`)
- Root password: Must be set post-deployment for console access
- SSH: Key-based authentication via cloud-init

**Subscription Attachment**:
```bash
# After VM boot
ssh cloud-user@<aap-vm-ip>
sudo subscription-manager register --username <rh-username> --password <rh-password>
sudo subscription-manager attach --pool=<pool-id>
sudo subscription-manager repos --enable=ansible-automation-platform-2.5-for-rhel-9-x86_64-rpms
```
