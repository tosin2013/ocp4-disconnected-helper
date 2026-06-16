---
layout: default
title: AAP Job Templates
parent: Reference
nav_order: 1
---


**Prerequisites**: VyOS router deployed and configured (ADR 0025)

This guide defines AAP job templates for the core disconnected OpenShift deployment workflow.

---

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────┐
│  VyOS Router (PREREQUISITE - Assumed Deployed)              │
│  ├─ VLAN 1924 (Management): 192.168.10.0/24                │
│  ├─ VLAN 1925 (OpenShift): 192.168.20.0/24                 │
│  └─ VLAN 1927 (Storage): 192.168.30.0/24                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Job Template 1: Deploy Registry VM                         │
│  ├─ Provision VM on VLAN 1924                              │
│  ├─ Install Quay mirror-registry                           │
│  ├─ Configure certificates (Let's Encrypt or self-signed)  │
│  └─ Set up authentication (auth.json)                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Job Template 2: Mirror OpenShift Images                    │
│  ├─ Download images with oc-mirror (internet → disk)       │
│  ├─ Package as TAR file                                    │
│  ├─ Transfer to disconnected environment                   │
│  └─ Push TAR to registry                                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
        [ Ready for OpenShift Cluster Deployment ]
```

---

## Job Template 1: Deploy Registry VM

### Purpose
Deploy containerized Quay mirror-registry on a dedicated VM for OpenShift image mirroring.

### Inventory
- **Host**: `localhost` (KVM hypervisor)
- **Connection**: `local`

### Project
- **Name**: `ocp4-disconnected-helper`
- **SCM Type**: Git
- **SCM URL**: `https://github.com/tosin2013/ocp4-disconnected-helper.git`
- **SCM Branch**: `main`

### Playbook
```
playbooks/deploy-registry.yml
```

### Execution Environment
- **Default EE** or **Custom EE with kubernetes.core** (if using k8s resources)

### Variables (Extra Vars)
```yaml
---
# Registry Configuration
registry_type: mirror-registry
registry_hostname: registry.sandbox3377.opentlc.com
registry_version: latest

# Network Configuration (VLAN 1924 - Management)
vm_static_ip: 192.168.10.10
vm_gateway: 192.168.10.1
vm_netmask: 255.255.255.0
vm_dns_servers:
  - 192.168.10.1
  - 1.1.1.1

# VM Resources
vm_name: registry
vm_memory_mb: 16384
vm_vcpus: 4
vm_disk_size: 500G

# Certificate Configuration
ssl_cert_provider: letsencrypt  # or "selfsigned" for disconnected
external_domain: sandbox3377.opentlc.com

# Storage
mirror_data_dir: /opt/mirror-registry
```

### Credentials Required
1. **Machine Credential**: SSH key for VM access
2. **Vault Credential**: For encrypted registry credentials in `extra_vars/rhel-subscription-secrets.yml`

### Tags
```
registry,provision,certificates
```

### Expected Duration
- **First run**: 15-20 minutes (VM provisioning + mirror-registry install)
- **Subsequent runs**: 5-10 minutes (idempotent, configuration updates only)

### Success Criteria
- ✅ VM created with static IP 192.168.10.10
- ✅ mirror-registry container running: `podman ps | grep quay-app`
- ✅ Health check responds: `curl -k https://192.168.10.10:8443/health/instance`
- ✅ Authentication configured: `~/.config/containers/auth.json` exists

### Troubleshooting
- **VM fails to get IP**: Check VyOS DHCP reservation on VLAN 1924
- **Registry health fails**: Check `journalctl -u quay-pod`
- **Certificate errors**: Verify DNS records for Let's Encrypt (if using)

---

## Job Template 2: Mirror OpenShift Images

### Purpose
Download OpenShift container images and push to disconnected registry using oc-mirror v2.

### Inventory
- **Host**: `localhost` (bastion with internet access) OR `dmz-mirror` (DMZ host)
- **Connection**: `local`

### Project
- **Name**: `ocp4-disconnected-helper`
- **SCM Type**: Git
- **SCM URL**: `https://github.com/tosin2013/ocp4-disconnected-helper.git`
- **SCM Branch**: `main`

### Playbook
```
playbooks/push-to-registry-v2.yml
```

### Execution Environment
- **Custom EE** with `oc`, `oc-mirror`, `kubectl` binaries (ADR 0029)

### Variables (Extra Vars)
```yaml
---
# oc-mirror Configuration
mirror_mode: to-registry  # or "to-disk" for DMZ workflow
mirror_config_file: extra_vars/mirror-v2-example.yml

# Registry Target
target_registry: registry.sandbox3377.opentlc.com:8443
registry_namespace: ocp4/openshift4

# OpenShift Version
ocp_version: 4.21.18
ocp_channel: stable-4.21

# Operators (optional)
mirror_operators: true
operator_packages:
  - local-storage-operator
  - ocs-operator
  - metallb-operator
  - kubernetes-nmstate-operator

# Pull Secret (from Ansible Vault)
pull_secret_file: /root/pull-secret.json

# Workflow Mode
workflow: full  # "download-only", "push-only", or "full"
```

### Credentials Required
1. **Machine Credential**: SSH key for bastion/DMZ host
2. **Vault Credential**: For Red Hat pull secret
3. **Container Registry Credential**: For target registry authentication

### Tags
```
mirror,download,push
```

### Expected Duration
- **Full workflow** (download + push):
  - OCP 4.21 base: ~45 minutes (35GB compressed)
  - + Operators (4 packages): +20 minutes per operator
  - Total: ~2-3 hours for complete mirror
- **Push-only** (TAR already downloaded): 30-45 minutes

### Success Criteria
- ✅ oc-mirror completes without errors
- ✅ TAR file created (if `to-disk` mode): `/data/ocp-mirror/mirror_*.tar`
- ✅ Images visible in registry: `curl -k https://registry.../v2/_catalog | jq`
- ✅ ImageContentSourcePolicy generated: `oc-mirror-workspace/results-*/imageContentSourcePolicy.yaml`

### Workflow Options

#### Option A: Direct to Registry (Connected Environment)
**When**: Bastion has internet + registry access
```yaml
mirror_mode: to-registry
target_registry: registry.sandbox3377.opentlc.com:8443
```

#### Option B: Two-Phase via TAR (Disconnected DMZ)
**Phase 1 - DMZ (Internet Access)**:
```yaml
mirror_mode: to-disk
workflow: download-only
```
→ Produces: `/data/ocp-mirror/mirror_seq1_000000.tar`

**Transfer TAR** to disconnected environment via physical media/jump host

**Phase 2 - Disconnected (No Internet)**:
```yaml
mirror_mode: from-disk
workflow: push-only
tar_file: /data/ocp-mirror/mirror_seq1_000000.tar
target_registry: registry.sandbox3377.opentlc.com:8443
```

### Troubleshooting
- **"unable to retrieve auth token"**: Check pull secret at `/root/pull-secret.json`
- **Timeout during download**: Increase async timeout in playbook (default: 7200s)
- **Registry push fails**: Verify registry credentials in `~/.config/containers/auth.json`
- **Disk space**: Ensure `/data/ocp-mirror/` has 200GB+ free

---

## AAP Configuration Steps

### Step 1: Create Inventory

**Name**: `Disconnected Infrastructure`

**Hosts**:
```yaml
localhost:
  ansible_connection: local
  ansible_python_interpreter: /usr/bin/python3
  
# Optional: DMZ host for two-phase mirror
dmz-mirror:
  ansible_host: 10.0.1.50
  ansible_user: mirror
```

---

### Step 2: Create Credentials

#### 2a. Machine Credential (SSH)
- **Name**: `KVM Hypervisor SSH Key`
- **Type**: Machine
- **Username**: `vpcuser`
- **SSH Private Key**: (paste your SSH key)

#### 2b. Vault Credential
- **Name**: `Ansible Vault Password`
- **Type**: Vault
- **Vault Password**: (your vault password)

#### 2c. Container Registry Credential
- **Name**: `Quay Mirror Registry`
- **Type**: Container Registry
- **Registry URL**: `registry.sandbox3377.opentlc.com:8443`
- **Username**: `init`
- **Password**: (from `/opt/mirror-registry/credentials.txt` on registry VM)

---

### Step 3: Create Job Templates

#### Template 1: Deploy Registry VM

**Name**: `Deploy Registry VM`  
**Job Type**: Run  
**Inventory**: Disconnected Infrastructure  
**Project**: ocp4-disconnected-helper  
**Playbook**: `playbooks/deploy-registry.yml`  
**Credentials**:
- KVM Hypervisor SSH Key
- Ansible Vault Password

**Variables** (copy from "Variables (Extra Vars)" section above)

**Options**:
- ✅ Enable Privilege Escalation
- ✅ Enable Fact Storage
- ⬜ Allow Simultaneous (only one registry deployment at a time)

---

#### Template 2: Mirror OpenShift Images

**Name**: `Mirror OpenShift Images to Registry`  
**Job Type**: Run  
**Inventory**: Disconnected Infrastructure  
**Project**: ocp4-disconnected-helper  
**Playbook**: `playbooks/push-to-registry-v2.yml`  
**Credentials**:
- KVM Hypervisor SSH Key
- Ansible Vault Password
- Quay Mirror Registry

**Variables** (copy from "Variables (Extra Vars)" section above)

**Options**:
- ✅ Enable Privilege Escalation
- ✅ Enable Fact Storage
- ⬜ Allow Simultaneous (prevent concurrent mirror operations)

**Job Tags** (optional):
- Run with `download` tag only: Download images but don't push
- Run with `push` tag only: Push existing TAR to registry

---

### Step 4: Create Workflow Template (Optional)

**Name**: `Deploy Disconnected OpenShift Infrastructure`

**Workflow**:
```
[START]
   ↓
[Deploy Registry VM]
   ↓ (on success)
[Mirror OpenShift Images]
   ↓ (on success)
[Deploy OpenShift Cluster] ← (Future: ADR 0019)
   ↓
[END]
```

**Convergence**: `all` (wait for each step to complete before next)

**Options**:
- ✅ Enable Webhooks (trigger via Git push)
- ✅ Enable Notifications (Slack/email on failure)

---

## Verification Commands

After successful job execution, verify from AAP GUI or CLI:

### Registry VM Health
```bash
# SSH to registry VM
ssh admin@192.168.10.10

# Check mirror-registry pod
podman ps | grep quay-app

# Health endpoint
curl -k https://localhost:8443/health/instance

# List repositories
curl -k -u init:<password> \
  https://localhost:8443/v2/_catalog | jq
```

### Registry Contents
```bash
# From bastion/hypervisor
export REGISTRY=registry.sandbox3377.opentlc.com:8443

# List catalogs
curl -k https://$REGISTRY/v2/_catalog | jq

# Check OpenShift images
curl -k https://$REGISTRY/v2/ocp4/openshift4/release/tags/list | jq
```

### oc-mirror Artifacts
```bash
# ImageContentSourcePolicy for cluster install
cat /data/ocp-mirror/oc-mirror-workspace/results-*/imageContentSourcePolicy.yaml

# CatalogSource for operators
cat /data/ocp-mirror/oc-mirror-workspace/results-*/catalogSource-*.yaml
```

---

## Related Documentation

- [ADR 0003: oc-mirror v2 for Image Mirroring](../adrs/0003-oc-mirror-image-mirroring.md)
- [ADR 0017: Quay Mirror Registry](../adrs/0017-quay-mirror-registry.md)
- [ADR 0021: Adopt AAP](../adrs/0021-deprecate-airflow-adopt-aap.md)
- [ADR 0024: Roles Architecture](../adrs/0024-ansible-roles-collections-architecture.md)
- [ADR 0025: VyOS Router Prerequisite](../adrs/0025-vyos-router-network-prerequisite.md)
- [AAP Post-Installation Guide](AAP_POST_INSTALLATION.md)

---

## Next Steps

After successful registry deployment and image mirroring:

1. **Verify ImageContentSourcePolicy**: Generated by oc-mirror for cluster install
2. **Prepare cluster install-config.yaml**: Reference disconnected registry
3. **Deploy OpenShift cluster**: Using Agent-based installer (ADR 0019)
4. **Apply ICSP and CatalogSources**: Enable disconnected operator installation

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-09  
**Author**: Platform Team
