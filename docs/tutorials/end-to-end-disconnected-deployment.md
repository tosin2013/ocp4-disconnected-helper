---
layout: default
title: End-to-End Disconnected Deployment
parent: Tutorials
nav_order: 3
---

# End-to-End Disconnected OpenShift Deployment

Complete tutorial from bare hypervisor to working disconnected OpenShift cluster.

**Time**: 4-6 hours  
**Level**: Intermediate to Advanced  
**Prerequisites**: RHEL/Ansible experience, Red Hat account with pull secret

---

## What You'll Build

By the end of this tutorial:

- ✅ Bootstrap layer (VyOS, DNS, AAP)
- ✅ Container registry with mirrored images
- ✅ Disconnected OpenShift 4.21 cluster (3 masters, 2 workers)
- ✅ Operator catalog (storage, networking, observability)
- ✅ Production-ready certificate management

**Architecture**:
```
IBM Cloud VSI (48 vCPU, 188 GB RAM)
  ├─ VyOS Router (network routing, NAT, DHCP, DNS)
  ├─ Quay Registry (mirrored OpenShift images)
  ├─ AAP 2.6 (workflow orchestration)
  └─ OpenShift 4.21 Cluster
      ├─ 3 Master Nodes (8 vCPU, 16 GB RAM each)
      └─ 2 Worker Nodes (8 vCPU, 32 GB RAM each)
```

---

## Part 1: Environment Setup (30 minutes)

### Step 1: Provision IBM Cloud VSI

**Spec**:
- OS: CentOS Stream 10
- vCPU: 48 cores
- RAM: 188 GB
- Disk: 500 GB SSD
- Network: Public IP

**Alternative**: Use existing RHEL/CentOS host with nested KVM enabled

### Step 2: Clone Repository

```bash
git clone https://github.com/tosin2013/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper
```

### Step 3: Install Dependencies

```bash
# Install Ansible and collections
sudo dnf install -y ansible-core
ansible-galaxy collection install -r requirements.yml

# Install KVM/libvirt
sudo dnf install -y @virtualization
sudo systemctl enable --now libvirtd

# Configure libvirt permissions
export LIBVIRT_DEFAULT_URI="qemu:///system"
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
```

### Step 4: Configure Credentials

**Create vault password file**:
```bash
echo "YourVaultPassword123!" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

**Create secrets file**:
```bash
cp extra_vars/rhel-subscription-secrets.yml.example \
   extra_vars/rhel-subscription-secrets.yml

ansible-vault edit extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Required secrets**:
```yaml
# RHEL Subscription
rh_username: your-rh-username
rh_password: your-rh-password

# Red Hat Registry (get from https://access.redhat.com/terms-based-registry/)
rh_registry_username: '<YOUR-ORG-ID>|<YOUR-SERVICE-ACCOUNT>'
rh_registry_password: 'eyJhbGciOiJSUzUxMi...'

# Registry passwords
registry_admin_password: 'SecureRegistryPassword123!'
quay_admin_password: 'SecureQuayPassword456!'

# AAP passwords (must be different - ADR-0028)
admin_password: 'ControllerAPIPassword789!'
automationgateway_admin_password: 'GatewayWebUIPassword012!'
pg_password: 'PostgreSQLPassword345!'

# AWS (optional - for Let's Encrypt)
# aws_access_key_id: '<YOUR-AWS-ACCESS-KEY-ID>'
# aws_secret_access_key: 'wJalrXUtnFEMI/K7MDENG...'
```

### Step 5: Download Red Hat Pull Secret

```bash
# Download from https://console.redhat.com/openshift/install/pull-secret
# Save to /root/rh-pull-secret.json

curl -o ~/rh-pull-secret.json \
  'https://console.redhat.com/openshift/install/pull-secret'

sudo cp ~/rh-pull-secret.json /root/pull-secret.json
```

---

## Part 2: Bootstrap Layer (40 minutes)

### Step 6: Deploy VyOS Router

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-vyos.yml
```

**What this does**:
- Creates VyOS VM (2 vCPU, 4 GB RAM)
- Configures 3 VLANs (Management 1924, OpenShift 1925, Storage 1927)
- Sets up NAT gateway
- Configures DHCP and DNS forwarding

**Verify**:
```bash
virsh list | grep vyos
ssh vyos@192.168.122.2 "show version"
```

### Step 7: Configure DNS

**Option A: AWS Route53** (if using public DNS):
```bash
ansible-playbook playbooks/setup-route53-dns.yml \
  -e route53_zone_id=Z1234567890ABC \
  -e aap_fqdn=aap.sandbox3377.opentlc.com \
  -e aap_ip=10.241.64.9
```

**Option B: VyOS dnsmasq** (local lab only):
```bash
# Already configured in Step 6
# Test: ssh vyos@192.168.122.2 "nslookup aap.sandbox3377.opentlc.com"
```

### Step 8: Deploy AAP 2.6

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap-multi-node.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Estimated time**: 15-20 minutes

**Verify**:
```bash
curl -k https://aap.sandbox3377.opentlc.com/
# Should return AAP login page
```

**Login to Web UI**:
- URL: https://aap.sandbox3377.opentlc.com
- Username: `admin`
- Password: `<automationgateway_admin_password from vault>`

---

## Part 3: AAP Workflow Configuration (15 minutes)

### Step 9: Configure Workflows

```bash
# Configure Workflow 1 (Registry Infrastructure)
ansible-playbook playbooks/aap-configuration/configure-infrastructure-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# Configure Workflow 2 (Image Mirroring)
ansible-playbook playbooks/aap-configuration/configure-mirroring-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Verify in AAP Web UI**:
1. Navigate to **Resources → Templates**
2. Find **Workflow 1: Registry Infrastructure Deployment**
3. Find **Workflow 2: OpenShift Image Mirroring**

---

## Part 4: Registry Infrastructure (25 minutes)

### Step 10: Execute Workflow 1

**Via AAP Web UI**:
1. Go to **Resources → Templates**
2. Click **Workflow 1: Registry Infrastructure Deployment**
3. Click **Launch** (rocket icon)
4. Fill survey:
   - **Registry Type**: `quay` (recommended)
   - **Certificate Mode**: `selfsigned` (or `letsencrypt` if AWS configured)
5. Click **Next** → **Launch**

**Wait for completion** (15-20 minutes)

**Alternative (CLI)**:
```bash
ansible-playbook playbooks/site.yml --tags registry,certificates,haproxy
```

**Verify**:
```bash
# Registry health
curl -k https://registry.example.com:8443/health/instance

# Registry authentication
echo "SecureQuayPassword456!" | podman login --username init \
  --password-stdin registry.example.com:8443
```

---

## Part 5: Image Mirroring (60-90 minutes)

### Understanding Operator Presets

Before mirroring, understand what operators enable on your cluster:

**Atomic Presets** (Single Focus):
- `storage-operators` (~15 GB) — Persistent storage (ODF, LVMS) for stateful apps
- `networking-operators` (~16 GB) — Load balancers (MetalLB), advanced networking
- `observability-operators` (~22 GB) — Logging, metrics, tracing
- `security-operators` (~20 GB) — Compliance scanning, vulnerability detection
- `rhacm-operators` (~20 GB) — Multi-cluster management (hub-spoke)
- `virtualization-operators` (~25 GB) — Run VMs + containers unified platform
- `service-mesh-operators` (~18 GB) — Microservices traffic management (Istio)
- `openshift-ai-operators` (~35 GB) — AI/ML model training and serving

**Combination Presets** (Multi-Capability):
- `full-platform` (~70 GB) — Storage + Observability + Security + Networking (complete enterprise)
- `enterprise-ready` (~65 GB) — RHACM + Storage + Security (hub cluster)
- `developer-stack` (~60 GB) — Service Mesh + AI + Observability (dev workloads)
- `vm-platform` (~55 GB) — Virtualization + Storage + Security (VMware replacement)

**What you can actually do with each preset**:

| Preset | Cluster Capabilities After Installation |
|--------|----------------------------------------|
| **storage-operators** | Deploy databases (PostgreSQL, MongoDB), persistent apps (Jenkins, GitLab), stateful workloads |
| **networking-operators** | Expose services via LoadBalancer type, configure static IPs, multi-homed networking |
| **observability-operators** | Centralized logging across namespaces, custom dashboards, distributed tracing |
| **security-operators** | Automated CVE scanning, compliance reports (CIS, PCI-DSS), image signing enforcement |
| **rhacm-operators** | Manage 10+ spoke clusters from one hub, policy enforcement, app lifecycle across clusters |
| **virtualization-operators** | Run Windows/Linux VMs alongside containers, VM live migration, desktop workloads |
| **full-platform** | All above capabilities unified — production-ready enterprise cluster |

**Start with**: `storage-operators` for first deployment (small, fast, enables databases).  
**Scale to**: `full-platform` or `enterprise-ready` for production multi-cluster environments.

For complete preset details and operator lists, see: [Operator Preset Catalog](../reference/operator-preset-catalog.md)

---

### Step 11: Execute Workflow 2

**Via AAP Web UI**:
1. Go to **Resources → Templates**
2. Click **Workflow 2: OpenShift Image Mirroring**
3. Click **Launch**
4. Fill survey:
   - **Operator Preset**: Select from dropdown (see table above for capabilities)
   - **Start with**: `storage-operators` (15 GB, 20-30 min)
   - **Target Registry**: `registry.example.com:8443`
5. Select credentials when prompted:
   - Red Hat Registry Credentials
   - Target Registry Credentials
6. Click **Next** → **Launch**

**Progress monitoring**:
- Node 0: Verify Prerequisites (30 seconds)
- Node 1: Download Images (5-60 minutes depending on preset)
- Node 2: Push to Registry (10-90 minutes depending on preset)
- Node 3: Verify Mirror (2-5 minutes)

**Mirror additional presets**:
After `storage-operators` succeeds, you can mirror additional presets to add capabilities:
```bash
# Launch Workflow 2 again with different preset
- networking-operators (adds MetalLB, NMState)
- observability-operators (adds Loki, Tempo, cluster logging)
- security-operators (adds compliance operator, Quay registry)
```

### Step 12: Generate Pull Secret and ICSP

```bash
# Extract pull secret for cluster installation
ansible-playbook playbooks/extract-pull-secret.yml \
  -e target_registry=registry.example.com:8443 \
  -e registry_password=SecureQuayPassword456! \
  -e output_file=/tmp/disconnected-pull-secret.json

# Generate ImageContentSourcePolicy
ansible-playbook playbooks/extract-icsp.yml \
  -e target_registry=registry.example.com:8443 \
  -e output_file=/tmp/imageContentSourcePolicy.yaml
```

**Verify image count**:
```bash
ssh admin@registry.example.com \
  "sudo podman exec -it quay-app curl -sk https://localhost:8443/v2/_catalog" | \
  jq '.repositories | length'

# Expected: 200+ repositories for storage-operators
```

---

## Part 6: OpenShift Cluster Deployment (90-120 minutes)

### Step 13: Create install-config.yaml

```bash
mkdir -p ~/openshift-install
cd ~/openshift-install
```

**Create install-config.yaml**:
```yaml
apiVersion: v1
baseDomain: example.com
metadata:
  name: ocp4
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
compute:
- name: worker
  replicas: 2
controlPlane:
  name: master
  replicas: 3
platform:
  none: {}
pullSecret: |
  (paste content of /tmp/disconnected-pull-secret.json)
sshKey: |
  (paste content of ~/.ssh/id_rsa.pub)
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  (paste content of /opt/certificates/quay-rootCA/rootCA.pem)
  -----END CERTIFICATE-----
imageContentSources:
- mirrors:
  - registry.example.com:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.example.com:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Step 14: Generate Ignition Configs

```bash
openshift-install create manifests --dir=~/openshift-install

# Apply ImageContentSourcePolicy
cp /tmp/imageContentSourcePolicy.yaml \
   ~/openshift-install/manifests/image-content-source-policy.yaml

# Generate ignition configs
openshift-install create ignition-configs --dir=~/openshift-install
```

### Step 15: Deploy Bootstrap Node

```bash
# Create bootstrap VM
ansible-playbook playbooks/deploy-bootstrap-node.yml \
  -e ignition_config=/root/openshift-install/bootstrap.ign
```

### Step 16: Deploy Master Nodes

```bash
# Create 3 master VMs
for i in 1 2 3; do
  ansible-playbook playbooks/deploy-master-node.yml \
    -e master_node=master-$i \
    -e ignition_config=/root/openshift-install/master.ign
done
```

### Step 17: Monitor Bootstrap

```bash
openshift-install wait-for bootstrap-complete \
  --dir=~/openshift-install \
  --log-level=debug
```

**Expected**: Bootstrap complete in 15-30 minutes

### Step 18: Deploy Worker Nodes

```bash
# After bootstrap complete, remove bootstrap node
virsh destroy bootstrap && virsh undefine bootstrap

# Create 2 worker VMs
for i in 1 2; do
  ansible-playbook playbooks/deploy-worker-node.yml \
    -e worker_node=worker-$i \
    -e ignition_config=/root/openshift-install/worker.ign
done
```

### Step 19: Approve CSRs

```bash
# Watch for pending CSRs
export KUBECONFIG=~/openshift-install/auth/kubeconfig

watch "oc get csr | grep Pending"

# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve
```

**Repeat until all nodes join** (5-10 CSR approvals total)

### Step 20: Wait for Installation Complete

```bash
openshift-install wait-for install-complete \
  --dir=~/openshift-install \
  --log-level=debug
```

**Expected**: Installation complete in 30-45 minutes after bootstrap

---

## Part 7: Cluster Verification (15 minutes)

### Step 21: Verify Cluster Health

```bash
export KUBECONFIG=~/openshift-install/auth/kubeconfig

# Check nodes
oc get nodes
# Expected: 3 masters + 2 workers (5 total), all Ready

# Check cluster operators
oc get co
# Expected: All operators Available=True, Degraded=False

# Check cluster version
oc get clusterversion
# Expected: VERSION=4.21.x, AVAILABLE=True
```

### Step 22: Install Storage Operators

```bash
# Storage operators already mirrored in Part 5
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operator-index
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: registry.example.com:8443/redhat/redhat-operator-index:v4.21
  displayName: Red Hat Operators (Mirrored)
  publisher: Red Hat
EOF

# Wait for catalog source ready
oc get catalogsource -n openshift-marketplace
```

### Step 23: Access OpenShift Console

```bash
# Get console URL
oc whoami --show-console

# Get kubeadmin password
cat ~/openshift-install/auth/kubeadmin-password
```

**Login**:
- URL: https://console-openshift-console.apps.ocp4.example.com
- Username: `kubeadmin`
- Password: (from kubeadmin-password file)

---

## Part 8: Post-Installation (30 minutes)

### Step 24: Configure Identity Provider

```bash
# Example: HTPasswd provider
htpasswd -c -B -b /tmp/htpasswd admin AdminPassword123!

oc create secret generic htpass-secret \
  --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config

oc apply -f - <<EOF
apiVersion: config.openshift.com/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF
```

### Step 25: Create Storage Class

```bash
# If using local-storage-operator (mirrored in Part 5)
oc apply -f - <<EOF
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: local-disks
  namespace: openshift-local-storage
spec:
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
      - key: node-role.kubernetes.io/worker
        operator: In
        values:
        - ""
  storageClassDevices:
  - storageClassName: local-sc
    volumeMode: Filesystem
    fsType: xfs
    devicePaths:
    - /dev/vdb
EOF
```

### Step 26: Enable Monitoring Persistence

```bash
oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      volumeClaimTemplate:
        spec:
          storageClassName: local-sc
          resources:
            requests:
              storage: 40Gi
EOF
```

---

## Troubleshooting

### Bootstrap Fails

**Symptom**: `wait-for bootstrap-complete` times out

**Check**:
```bash
ssh core@bootstrap-node \
  "journalctl -u bootkube.service"
```

**Common fixes**:
- Verify pull secret includes registry.example.com
- Check CA certificate in additionalTrustBundle
- Verify ICSP configuration

### Nodes Not Joining

**Symptom**: Master/worker nodes stuck in NotReady

**Check**:
```bash
oc get csr | grep Pending
# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve
```

### Operators Unavailable

**Symptom**: `oc get co` shows operators Degraded=True

**Check**:
```bash
oc describe co <operator-name>
oc logs -n openshift-<namespace> <pod-name>
```

**Common fixes**:
- Verify catalog source created
- Check ImageContentSourcePolicy applied
- Verify registry accessible from cluster

---

## Summary

**What you built**:
- ✅ Bootstrap infrastructure (VyOS, DNS, AAP)
- ✅ Container registry with 200+ mirrored images
- ✅ OpenShift 4.21 cluster (5 nodes)
- ✅ Operator catalog (storage, networking, observability)
- ✅ Persistent monitoring and storage

**Total time**: 4-6 hours (varies based on bandwidth and hardware)

**Next steps**:
- Deploy applications to cluster
- Configure backups (etcd, persistent volumes)
- Set up CI/CD pipelines
- Configure log aggregation (Loki operator)

---

## Related Documentation

- [Getting Started with AAP Workflows](getting-started-with-aap-workflows.md)
- [Your First OpenShift Image Mirror](your-first-openshift-image-mirror.md)
- [Bootstrap vs Workflow Layers](../explanations/bootstrap-vs-workflow-layers.md)
- [Multi-Workflow Architecture](../explanations/multi-workflow-architecture.md)
