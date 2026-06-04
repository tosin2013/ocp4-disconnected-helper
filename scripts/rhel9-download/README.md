# RHEL 9 KVM Guest Image Download Scripts

Automated scripts for downloading RHEL 9 KVM guest image using three different methods.

**Target**: `/var/lib/libvirt/images/rhel9-kvm-guest.qcow2`

---

## Scripts Overview

| Script | Method | Time | Complexity | Recommended |
|--------|--------|------|------------|-------------|
| `download-rhel9-curl.sh` | Web UI + curl | 2-5 min | Easy | ✅ Yes |
| `download-rhel9-api.sh` | Red Hat API | N/A | Advanced | For automation |
| `build-rhel9-image.sh` | Image Builder | 10-20 min | Medium | Alternative |

---

## Method 1: Web UI + curl (Recommended)

### Usage

```bash
sudo ./download-rhel9-curl.sh
```

### Interactive Prompts

1. **Get Download URL**:
   - Navigate to https://access.redhat.com/downloads/content/rhel
   - Login with Red Hat subscription
   - Right-click "Red Hat Enterprise Linux 9.X KVM Guest Image" → Copy Link
   - Paste URL when prompted

2. **If File Exists**:
   - Option 1: Delete and re-download
   - Option 2: Resume download (if interrupted)
   - Option 3: Keep existing and exit

3. **Auto-Verification**:
   - Checks file size (should be ~1.2 GB)
   - Verifies qcow2 format with `qemu-img info`
   - Sets proper permissions (qemu:qemu, 644)

### Non-Interactive Usage

```bash
# Paste URL directly
sudo ./download-rhel9-curl.sh 'https://access.cdn.redhat.com/content/...'
```

### Features

- ✅ Resume interrupted downloads
- ✅ Disk space check before download
- ✅ File size validation
- ✅ qcow2 format verification
- ✅ Automatic permission setting
- ✅ Color-coded output

---

## Method 2: Red Hat API (Advanced)

### Usage

```bash
# Option 1: Set environment variable
export RH_OFFLINE_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCIgO..."
sudo -E ./download-rhel9-api.sh

# Option 2: Interactive (prompts for token)
sudo ./download-rhel9-api.sh
```

### Get Offline Token

1. Navigate to: https://access.redhat.com/management/api
2. Login with Red Hat account
3. Click "Generate Token"
4. Copy the offline token (starts with `eyJh...`)
5. Store securely (doesn't expire)

### Current Limitation

Red Hat Customer Portal API doesn't provide direct endpoints for listing/downloading RHEL KVM images. This script:

1. Exchanges offline token for access token (15 min validity)
2. Saves access token for potential API calls
3. Provides guidance to use Web UI method for actual download

**Use Case**: Automation where you manage tokens centrally and need API authentication.

---

## Method 3: Image Builder (Alternative)

### Prerequisites

- RHEL 9 system with active subscription
- System registered: `subscription-manager register`

### Usage

```bash
sudo ./build-rhel9-image.sh
```

### What It Does

1. **Checks subscription** status
2. **Installs Image Builder** (if not present):
   - osbuild-composer
   - composer-cli
   - cockpit-composer
3. **Creates blueprint** with:
   - cloud-init
   - podman
   - firewalld
   - python3
   - cloud-user account
4. **Builds qcow2 image** (10-20 minutes)
5. **Monitors progress** (shows build status)
6. **Downloads** and **moves** to target location
7. **Verifies** image format

### Features

- ✅ Fully customizable image
- ✅ Real-time build monitoring
- ✅ Automatic cleanup
- ✅ Pre-configured for AAP deployment

---

## Installation

### Make Scripts Executable

```bash
cd scripts/rhel9-download
chmod +x *.sh
```

### Install Dependencies

```bash
# For all methods
sudo dnf install -y curl

# For Method 2 (API)
sudo dnf install -y jq

# For Method 3 (Image Builder)
sudo dnf install -y osbuild-composer composer-cli
```

---

## Verification

After any method:

```bash
# Check file exists
ls -lh /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Verify qcow2 format
sudo qemu-img info /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Check permissions
ls -l /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
# Expected: -rw-r--r-- 1 qemu qemu ...
```

---

## Next Steps

Once image is downloaded:

```bash
cd /home/vpcuser/ocp4-disconnected-helper
ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml
```

---

## Troubleshooting

### Script: download-rhel9-curl.sh

**Issue**: "File size is suspiciously small"

```bash
# URL token expired - get fresh URL
# Navigate to Red Hat Portal and copy new link
sudo ./download-rhel9-curl.sh 'https://access.cdn.redhat.com/...'
```

**Issue**: "Download failed"

```bash
# Resume interrupted download
sudo ./download-rhel9-curl.sh
# Select option 2 (Resume)
```

### Script: download-rhel9-api.sh

**Issue**: "Failed to get access token"

```bash
# Regenerate offline token
# Go to https://access.redhat.com/management/api
# Generate new token and try again
```

### Script: build-rhel9-image.sh

**Issue**: "System is not registered"

```bash
# Register RHEL system
sudo subscription-manager register --username <user> --password <pass>
sudo subscription-manager attach --pool=<pool-id>
```

**Issue**: "Build failed"

```bash
# Check build logs
composer-cli compose log <UUID>

# Check service status
systemctl status osbuild-composer
```

---

## Security Notes

- **Offline Tokens**: Store securely (Ansible Vault, HashiCorp Vault)
- **Download URLs**: Contain temporary auth tokens (valid ~1 hour)
- **Scripts run as root**: Review before execution
- **File permissions**: Automatically set to qemu:qemu, 644

---

## References

- [Red Hat Customer Portal Downloads](https://access.redhat.com/downloads/content/rhel)
- [Red Hat API Documentation](https://access.redhat.com/articles/3626371)
- [RHEL Image Builder Guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/composing_a_customized_rhel_system_image/preparing-and-deploying-kvm-guest-images-with-image-builder_composing-a-customized-rhel-system-image)

---

## Related Documentation

- `../../docs/RHEL9_DIRECT_DOWNLOAD.md` - Full documentation
- `../../docs/RHEL9_IMAGE_DOWNLOAD.md` - Alternative methods
- `../../docs/AAP_DEPLOYMENT_GUIDE.md` - AAP 2.6 deployment
