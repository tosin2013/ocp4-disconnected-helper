---
layout: default
title: Download RHEL9 ISO
parent: How-To Guides
nav_order: 9
---


**Goal**: Download RHEL 9 KVM guest image directly to hypervisor (no SCP)  
**Target**: `/var/lib/libvirt/images/rhel9-kvm-guest.qcow2`

---

## Method 1: Web UI + curl (Recommended - Easiest)

### Automated Script (Recommended)

```bash
cd /home/vpcuser/ocp4-disconnected-helper
sudo scripts/rhel9-download/download-rhel9-curl.sh
```

**Features**:
- Interactive prompts for download URL
- Automatic disk space check
- Resume interrupted downloads
- File size validation
- qcow2 format verification
- Automatic permission setting

See: `scripts/rhel9-download/README.md` for full script documentation

---

### Manual Method

### Step 1: Get Download URL from Red Hat Customer Portal

**On your workstation browser**:

1. Navigate to: https://access.redhat.com/downloads/content/rhel
2. **Login** with Red Hat subscription
3. Select:
   - **Product**: Red Hat Enterprise Linux 9
   - **Version**: 9.4 (or latest)
   - **Architecture**: x86_64
4. Find: **"Red Hat Enterprise Linux 9.X KVM Guest Image"**
5. **Right-click** the download button → **Copy Link Address**

   The URL will look like:
   ```
   https://access.cdn.redhat.com/content/origin/files/sha256/XX/XXXXX.../rhel-9.4-x86_64-kvm.qcow2?...auth_token=XXXXXX
   ```

### Step 2: Download Directly on Hypervisor

**On this hypervisor** (paste the copied URL):

```bash
# Download directly to libvirt images directory
sudo curl -o /var/lib/libvirt/images/rhel9-kvm-guest.qcow2 \
  'https://access.cdn.redhat.com/content/origin/files/sha256/.../rhel-9.4-x86_64-kvm.qcow2?...auth_token=XXXXX'

# Set proper permissions
sudo chown qemu:qemu /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chmod 644 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

**Notes**:
- The URL contains a temporary authentication token (valid for ~1 hour)
- curl can resume interrupted downloads with `-C -` flag
- Download size: ~1.2 GB, time: ~2-5 minutes on fast connection

**References**:
- [How to download RHEL ISOs using curl](https://access.redhat.com/solutions/29815)
- [Download RHEL directly to server](https://levelupla.io/download-red-hat-isos-and-tarballs-directly-to-your-server/)

---

## Method 2: Red Hat API with Offline Token (Advanced - Fully Automated)

This method uses Red Hat's API for programmatic access. Best for automation and scripting.

### Step 1: Generate Red Hat API Offline Token

1. Navigate to: https://access.redhat.com/management/api
2. **Login** with Red Hat subscription
3. Click **"Generate Token"**
4. **Copy** the offline token (long string starting with `eyJh...`)
5. **Save securely** - this token doesn't expire

### Step 2: Get Access Token

```bash
# Set your offline token
export RH_OFFLINE_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCIgO..."

# Exchange for access token (valid 15 minutes)
ACCESS_TOKEN=$(curl -s -d grant_type=refresh_token \
  -d client_id=rhsm-api \
  -d refresh_token=$RH_OFFLINE_TOKEN \
  https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token \
  | jq -r '.access_token')

echo "Access Token: $ACCESS_TOKEN"
```

### Step 3: Find RHEL 9 KVM Image via API

**Note**: As of 2026, Red Hat doesn't expose a direct "list downloadable images" API endpoint. The API is primarily for subscription management, not content downloads.

**Workaround**: Use the Web UI method (Method 1) to get the download URL, then use the access token if needed.

### Alternative: rhsm-cli Tool

Install the community RHSM API client:

```bash
# Download rhsm-cli
git clone https://github.com/antonioromito/rhsm-api-client.git
cd rhsm-api-client

# Use with your offline token
export RHSM_API_TOKEN=$RH_OFFLINE_TOKEN

# List available images (if supported)
./rhsm-cli images --checksum <CHECKSUM>
```

**Limitations**: This tool is community-maintained and may not support RHEL 9 KVM image downloads directly.

**References**:
- [Getting Started with Red Hat APIs](https://access.redhat.com/articles/3626371)
- [Red Hat Customer Portal Integration Guide](https://docs.redhat.com/en/documentation/red_hat_customer_portal/1/html-single/customer_portal_integration_guide/index)
- [rhsm-api-client GitHub](https://github.com/antonioromito/rhsm-api-client)

---

## Method 3: Red Hat Image Builder (Build Custom Image)

If you have RHEL 9 already installed and registered, you can **build** a custom KVM guest image locally.

### Prerequisites

```bash
# Requires RHEL 9 system with active subscription
sudo subscription-manager register
sudo subscription-manager attach

# Install Image Builder
sudo dnf install -y osbuild-composer composer-cli cockpit-composer
sudo systemctl enable --now osbuild-composer.socket
```

### Build RHEL 9 KVM Guest Image

```bash
# Create blueprint
cat > rhel9-kvm.toml << 'EOF'
name = "rhel9-kvm-guest"
description = "RHEL 9 KVM Guest Image"
version = "1.0.0"
modules = []
groups = []

[[packages]]
name = "cloud-init"
version = "*"

[[customizations.user]]
name = "cloud-user"
groups = ["wheel"]
EOF

# Push blueprint
composer-cli blueprints push rhel9-kvm.toml

# Start image build (qcow2 format)
composer-cli compose start rhel9-kvm-guest qcow2

# Monitor build status
composer-cli compose status

# Download finished image (once completed)
composer-cli compose image <UUID>

# Move to libvirt directory
sudo mv <UUID>-disk.qcow2 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chown qemu:qemu /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

**Build Time**: ~10-20 minutes

**References**:
- [Preparing KVM Guest Images with RHEL Image Builder](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/composing_a_customized_rhel_system_image/preparing-and-deploying-kvm-guest-images-with-image-builder_composing-a-customized-rhel-system-image)
- [Using Hosted Image Builder via API](https://www.redhat.com/en/blog/using-hosted-image-builder-its-api)

---

## Verification (All Methods)

After download/build, verify the image:

```bash
# Check file exists and size
ls -lh /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Expected output:
# -rw-r--r-- 1 qemu qemu 1.2G ... rhel9-kvm-guest.qcow2

# Verify qcow2 format
sudo qemu-img info /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Expected output:
# image: rhel9-kvm-guest.qcow2
# file format: qcow2
# virtual size: 10 GiB (10737418240 bytes)
# disk size: 1.2 GiB
```

---

## Recommended Approach

**For quickest results**: Use **Method 1** (Web UI + curl)

1. Copy download URL from Red Hat Customer Portal (30 seconds)
2. Paste into curl command on hypervisor (1 command)
3. Download completes in ~2-5 minutes
4. No SCP, no file transfer, direct to target location

**Advantages**:
- ✅ No workstation→hypervisor file transfer
- ✅ No temporary disk space wasted
- ✅ Resumes interrupted downloads
- ✅ Single command execution

---

## Troubleshooting

### Issue: "URL has expired"

**Cause**: Download URL token expired (valid ~1 hour)

**Solution**:
```bash
# Get a fresh URL from Red Hat Customer Portal
# Copy new link address and retry curl command
```

### Issue: "Connection timeout"

**Cause**: Slow/unstable network

**Solution**:
```bash
# Use curl with resume capability
sudo curl -C - -o /var/lib/libvirt/images/rhel9-kvm-guest.qcow2 \
  'https://access.cdn.redhat.com/...'
```

### Issue: "No space left on device"

**Cause**: Insufficient disk space

**Solution**:
```bash
# Check available space
df -h /var/lib/libvirt/images/

# Clean up old images if needed
sudo rm -f /var/lib/libvirt/images/centos*.qcow2
```

---

## Next Steps

Once RHEL 9 image is in place:

```bash
# Verify image
ls -lh /var/lib/libvirt/images/rhel9-kvm-guest.qcow2

# Provision AAP VM
cd /home/vpcuser/ocp4-disconnected-helper
ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml
```

---

## Security Notes

- **Offline tokens** never expire - store securely (e.g., Ansible Vault, HashiCorp Vault)
- **Access tokens** expire after 15 minutes - regenerate as needed
- **Download URLs** are time-limited and single-use
- Never commit tokens to git repositories

---

## Alternative: Free Red Hat Developer Subscription

If you don't have a paid subscription:

1. Sign up at: https://developers.redhat.com/
2. **No-cost Red Hat Developer Subscription** included
3. Access to RHEL downloads (same as paid)
4. **Limit**: 16 systems for development use

**References**:
- [No-cost RHEL Developer Subscription FAQs](https://developers.redhat.com/articles/faqs-no-cost-red-hat-enterprise-linux)
- [How to Use Free Red Hat Developer Subscription](https://www.linuxtechi.com/use-redhat-developer-subscription-rhel/)
