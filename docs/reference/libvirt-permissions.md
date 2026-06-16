---
layout: default
title: Libvirt Permissions
parent: Reference
nav_order: 3
---


## Problem
By default, `vpcuser` cannot run `virsh` commands without `sudo`, which breaks Ansible automation.

## Solution

### 1. Add user to libvirt group
```bash
sudo usermod -a -G libvirt vpcuser
```

### 2. Configure polkit access
```bash
cat > /tmp/libvirt-vpcuser.rules << 'RULES'
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.user == "vpcuser") {
            return polkit.Result.YES;
    }
});
RULES
sudo cp /tmp/libvirt-vpcuser.rules /etc/polkit-1/rules.d/80-libvirt-vpcuser.rules
sudo systemctl restart polkit
```

### 3. Set default libvirt URI
Add to `~/.bashrc`:
```bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
```

Apply immediately:
```bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
source ~/.bashrc
```

### 4. Verify
```bash
virsh net-list --all    # Should show networks without sudo
virsh list --all        # Should show VMs without sudo
```

## SSH Key Injection

VMs automatically get the SSH public key from `~/.ssh/id_rsa.pub` via cloud-init.

**Variable**: `vm_ssh_public_key` in `roles/common_vm/defaults/main.yml`

**Location in cloud-init**: `roles/common_vm/templates/cloud-init/user-data.yml.j2`
- Injected for `admin` user (configured via `vm_user`)
- Injected for `root` user
- Both users can SSH with `~/.ssh/id_rsa` private key

## Troubleshooting

**Issue**: `virsh` still requires sudo
- Check: `groups` - should include `libvirt`
- Check: `echo $LIBVIRT_DEFAULT_URI` - should be `qemu:///system`
- Try: `virsh -c qemu:///system net-list` explicitly

**Issue**: SSH to VM fails
- Check cloud-init logs on VM: `sudo virsh console <vm-name>`
- Verify key in `~/.ssh/id_rsa.pub` matches what's in inventory
- Test: `ssh -i ~/.ssh/id_rsa admin@<vm-ip>`
