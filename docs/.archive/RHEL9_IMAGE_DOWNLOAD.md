# RHEL 9 KVM Guest Image Download Guide

**Target**: `/var/lib/libvirt/images/rhel9-kvm-guest.qcow2`  
**Required**: Active Red Hat subscription  
**File Size**: ~1.2-1.5 GB

---

## Step 1: Download from Red Hat Customer Portal

### Web UI Method (Recommended)

1. **Navigate to Red Hat Downloads**:
   ```
   https://access.redhat.com/downloads/content/rhel
   ```

2. **Login** with your Red Hat credentials

3. **Select Product**:
   - Product: **Red Hat Enterprise Linux 9**
   - Version: **9.4** (or latest 9.x)
   - Architecture: **x86_64**

4. **Find KVM Guest Image**:
   - Look for: **"Red Hat Enterprise Linux 9.X KVM Guest Image"**
   - File format: `.qcow2`
   - Size: ~1.2 GB

5. **Download** the qcow2 file

---

## Step 2: Transfer to Hypervisor

### If Downloaded on Different Machine

```bash
# From your workstation/laptop
scp ~/Downloads/rhel-9.*-x86_64-kvm.qcow2 vpcuser@10.241.64.9:/tmp/

# On hypervisor
sudo mv /tmp/rhel-9.*-x86_64-kvm.qcow2 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chown qemu:qemu /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chmod 644 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

### If Downloading Directly on Hypervisor

**Note**: Command-line download requires authentication token. Easier to use Web UI.

If you have `curl` with Red Hat token:

```bash
# This requires a valid Red Hat API token
# Get token from: https://access.redhat.com/management/api

sudo curl -o /var/lib/libvirt/images/rhel9-kvm-guest.qcow2 \
  -H "Authorization: Bearer YOUR_RH_API_TOKEN" \
  'https://access.redhat.com/downloads/content/...'

# Set permissions
sudo chown qemu:qemu /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chmod 644 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

---

## Step 3: Verify Download

```bash
# Check file exists and size
ls -lh /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Expected output:
# -rw-r--r-- 1 qemu qemu 1.2G Jun 04 17:00 rhel9-kvm-guest.qcow2

# Verify qcow2 format
sudo qemu-img info /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Expected output:
# image: rhel9-kvm-guest.qcow2
# file format: qcow2
# virtual size: 10 GiB (10737418240 bytes)
# disk size: 1.2 GiB
# ...
```

---

## Step 4: Provision AAP VM

Once the image is in place, run the AAP VM provisioning playbook:

```bash
cd /home/vpcuser/ocp4-disconnected-helper

# Provision AAP VM (will use rhel9-kvm-guest.qcow2)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml

# Expected VM configuration:
# - Name: aap-vm
# - IP: 192.168.122.30
# - Memory: 16 GB
# - CPUs: 4
# - Disk: 60 GB
```

---

## Troubleshooting

### Issue: File Not Found After Download

```bash
# Find the downloaded file
find /tmp /home/$USER/Downloads -name "*rhel*kvm*.qcow2" -type f 2>/dev/null

# Move to correct location
sudo mv /path/to/downloaded/file.qcow2 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

### Issue: Permission Denied

```bash
# Fix ownership and permissions
sudo chown qemu:qemu /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chmod 644 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

### Issue: Disk Space Insufficient

```bash
# Check available space
df -h /var/lib/libvirt/images/

# Need at least 2 GB free for:
# - Base image: 1.2 GB
# - VM disk: Will expand to 60 GB
```

---

## Alternative: Use Existing CentOS Stream 9 (Development Only)

**⚠️ NOT RECOMMENDED FOR AAP PRODUCTION**

If you need to test VM provisioning workflow only:

```bash
# Temporarily use CentOS Stream 9 for development
ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml \
  -e base_image_path=/var/lib/libvirt/images/centos-stream-9-base.qcow2

# WARNING: AAP 2.6 is NOT officially supported on CentOS Stream
# See ADR 0026 for RHEL requirement justification
```

---

## Next Steps

After RHEL 9 image is downloaded and AAP VM is provisioned:

1. **SSH to AAP VM**: `ssh cloud-user@192.168.122.30`
2. **Register RHEL**: `sudo subscription-manager register`
3. **Install AAP 2.6**: Follow `docs/AAP_DEPLOYMENT_GUIDE.md`

---

## References

- [Red Hat Downloads Portal](https://access.redhat.com/downloads/content/rhel)
- [RHEL 9 KVM Guest Image Documentation](https://access.redhat.com/solutions/641193)
- [AAP Deployment Guide](./AAP_DEPLOYMENT_GUIDE.md)
- [ADR 0026: RHEL 9 Base Image for AAP](./adrs/0026-rhel-base-for-aap.md)
