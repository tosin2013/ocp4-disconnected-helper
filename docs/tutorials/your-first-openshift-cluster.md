# Tutorial: Your First OpenShift Cluster (SNO on KVM)

Step-by-step tutorial for deploying your first OpenShift cluster using the Agent-Based Installer on KVM/libvirt.

**What You'll Learn**:
- Deploy a Single-Node OpenShift (SNO) cluster
- Use Agent-Based Installer automation
- Access the OpenShift Web Console
- Deploy your first application

**Time**: 60-90 minutes  
**Difficulty**: Beginner  
**Environment**: KVM/libvirt on CentOS Stream 10

---

## Prerequisites

Before starting, ensure you have:

1. **Hypervisor Access**:
   - KVM/libvirt installed and running
   - At least 32GB RAM available
   - At least 8 vCPU available
   - 150GB disk space available

2. **Network Connectivity**:
   - Internet access (for pulling pull secret)
   - OR mirror registry deployed (disconnected mode)

3. **Accounts**:
   - Red Hat account (for pull secret)
   - Access to this repository

---

## Step 1: Verify Prerequisites

Check your hypervisor resources:

```bash
# Check available memory
free -h
# Need: At least 32GB free

# Check CPU count
nproc
# Need: At least 8 cores

# Check disk space
df -h /data
# Need: At least 150GB available

# Verify libvirt is running
sudo systemctl status libvirtd
# Should show: active (running)

# Test virsh connection
virsh list --all
# Should list VMs (may be empty)
```

If any checks fail, free up resources or use a larger system.

---

## Step 2: Download Pull Secret

1. Open browser: https://console.redhat.com/openshift/install/pull-secret
2. Log in with Red Hat account
3. Click "Copy pull secret"
4. Save to file:

```bash
cat > /root/pull-secret.json << 'EOF'
<paste your pull secret here>
EOF

chmod 600 /root/pull-secret.json
```

Verify the file is valid JSON:
```bash
cat /root/pull-secret.json | jq .
# Should show formatted JSON with "auths" key
```

---

## Step 3: Install OpenShift Tools

Download and install `openshift-install` and `oc`:

```bash
# Set version
OCP_VERSION="4.21.0"

# Download openshift-install
cd /tmp
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz
sudo mv openshift-install /usr/local/bin/
sudo chmod +x /usr/local/bin/openshift-install

# Download oc CLI
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/
sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

# Verify installation
openshift-install version
oc version --client
```

---

## Step 4: Review Cluster Configuration

This repository includes pre-configured cluster definitions. Let's use the SNO with Quay registry:

```bash
cd /home/vpcuser/ocp4-disconnected-helper

# View SNO configuration
cat extra_vars/cluster-configs/sno-quay.yml
```

**Key settings you'll see**:
```yaml
cluster_name: "ocp4-sno"
base_domain: "sandbox3377.opentlc.com"
cluster_topology: "sno"
control_plane_replicas: 1
compute_replicas: 0
vm_memory_mb: 32768  # 32GB
vm_vcpus: 8
api_vip: "192.168.10.10"
ingress_vip: "192.168.10.10"  # Same as API for SNO
registry_type: "quay"
```

**Note**: For a real deployment, customize these values (especially `cluster_name` and `base_domain`).

---

## Step 5: Deploy Your Cluster

Now deploy the cluster with a single command:

```bash
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-quay.yml
```

**What happens**:
1. **Phase 0**: Validates prerequisites (openshift-install, pull secret, resources)
2. **Phase 1**: Prepares installation directory (`/root/openshift-install-ocp4-sno/`)
3. **Phase 2**: Generates cluster manifests (install-config, agent-config, ImageDigestMirrorSet)
4. **Phase 3**: Creates bootable ISO (~1.2GB, takes 5-15 minutes)
5. **Phase 4**: Configures DNS (dnsmasq records for API and apps)
6. **Phase 5**: Provisions VM and boots from ISO (3-5 minutes)
7. **Phase 6**: Monitors installation to completion (35-70 minutes)

**Total time**: 45-90 minutes

**What you'll see**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OpenShift Cluster Deployment - Agent-Based Installer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cluster: ocp4-sno.sandbox3377.opentlc.com
Topology: SNO
Registry: QUAY (registry.ocp4.sandbox3377.opentlc.com:8443)
OpenShift Version: 4.21

[... playbook output ...]

✅ OpenShift Cluster Deployment Complete

Access Information:
  API: https://api.ocp4-sno.sandbox3377.opentlc.com:6443
  Console: https://console-openshift-console.apps.ocp4-sno.sandbox3377.opentlc.com

Credentials:
  Location: /data/ocp-credentials/ocp4-sno-*
```

---

## Step 6: Verify Installation

Check that the VM is running:

```bash
virsh list
# Should show: ocp4-sno running
```

Check cluster nodes:

```bash
export KUBECONFIG=/data/ocp-credentials/ocp4-sno-kubeconfig
oc get nodes
```

Expected output:
```
NAME       STATUS   ROLES                         AGE   VERSION
master-0   Ready    control-plane,master,worker   15m   v1.34.1+xyz
```

Check cluster operators (all should be Available):

```bash
oc get co
```

Expected output (all AVAILABLE=True):
```
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED
authentication                             4.21.0    True        False         False
cloud-credential                           4.21.0    True        False         False
[... 30+ operators ...]
```

---

## Step 7: Access Web Console

1. **Get credentials**:
   ```bash
   cat /data/ocp-credentials/ocp4-sno-access-instructions.txt
   ```

2. **Find Console URL and password**:
   ```
   Web Console:
     https://console-openshift-console.apps.ocp4-sno.sandbox3377.opentlc.com

   Credentials:
     Username: kubeadmin
     Password: <shown in file>
   ```

3. **Open browser** to Console URL

4. **Login**:
   - Username: `kubeadmin`
   - Password: (from access-instructions.txt)

5. **Explore Console**:
   - Overview → Cluster status
   - Workloads → Pods (system pods running)
   - Networking → Services
   - Compute → Nodes

---

## Step 8: Deploy Your First Application

Let's deploy a simple web application to verify the cluster works.

### Create Project

```bash
oc new-project my-first-app
```

### Deploy Application

```bash
oc new-app httpd~https://github.com/sclorg/httpd-ex.git
```

This creates:
- BuildConfig (builds container image)
- ImageStream (stores built image)
- DeploymentConfig (deploys application)
- Service (cluster networking)

### Expose Application

```bash
oc expose svc/httpd-ex
```

This creates a Route (external access via Ingress).

### Check Deployment

```bash
# Watch build progress
oc logs -f bc/httpd-ex

# Check pods
oc get pods

# Get route URL
oc get route httpd-ex -o jsonpath='{.spec.host}'
```

### Access Application

```bash
# Get the route
ROUTE=$(oc get route httpd-ex -o jsonpath='{.spec.host}')

# Test via curl
curl http://$ROUTE

# Or open in browser:
echo "http://$ROUTE"
```

You should see: "Welcome to your static httpd application on OpenShift"

**Congratulations!** You've deployed your first application on OpenShift.

---

## Step 9: Explore More

### Check Resource Usage

```bash
# Node resource usage
oc adm top node

# Pod resource usage
oc adm top pods -n my-first-app
```

### View Logs

```bash
# Application logs
oc logs -f deployment/httpd-ex
```

### Scale Application

```bash
# Scale to 3 replicas
oc scale deployment/httpd-ex --replicas=3

# Check pods
oc get pods
# Should show 3 httpd-ex pods
```

### Web Console Tasks

In the Web Console (https://console-openshift-console.apps.<cluster>.<domain>):

1. **Navigate to Developer perspective** (top-left dropdown)
2. **View Topology** → See your application visually
3. **Click on httpd-ex** → View details, logs, events
4. **Try scaling** via the UI (up/down arrows)

---

## Step 10: Clean Up (Optional)

If this was a test cluster, you can delete it:

### Delete Application

```bash
oc delete project my-first-app
```

### Delete Cluster

```bash
# Stop and delete VM
virsh destroy ocp4-sno
virsh undefine ocp4-sno

# Remove VM disk
rm -f /data/libvirt-images/ocp4-sno.qcow2

# Remove installation files
rm -rf /root/openshift-install-ocp4-sno

# Remove ISO
rm -f /data/iso/ocp4-sno-agent.x86_64.iso

# Remove credentials
rm -rf /data/ocp-credentials/ocp4-sno-*
```

---

## What You Learned

✅ Deploy OpenShift cluster with Agent-Based Installer  
✅ Use Ansible automation for KVM provisioning  
✅ Access OpenShift Web Console  
✅ Use `oc` CLI for cluster management  
✅ Deploy containerized applications  
✅ Expose applications via Routes  
✅ Scale applications  

---

## Next Steps

Now that you have a working cluster, explore:

1. **Deploy More Complex Apps**:
   - Multi-tier applications (frontend + backend + database)
   - Use Templates or Helm charts
   - Try OpenShift Source-to-Image (S2I) builds

2. **Configure Authentication**:
   - Add htpasswd users
   - Configure LDAP or OAuth
   - Delete kubeadmin (security best practice)

3. **Install Operators**:
   - Browse OperatorHub (Web Console → Operators)
   - Install monitoring, logging, or storage operators
   - Deploy operators from your mirror registry

4. **Try Different Topologies**:
   - Deploy 3-node Compact cluster
   - Deploy HA cluster (6+ nodes)
   - Compare performance and features

5. **Explore Bare Metal**:
   - Follow bare metal deployment guide
   - Boot physical servers from ISO
   - Configure external load balancer

---

## Troubleshooting

### Deployment Stuck at Bootstrap

**Symptoms**: Phase 6 stuck at "Waiting for bootstrap complete"

**Debug**:
```bash
# Check VM console
virsh console ocp4-sno

# Check installation logs
tail -f /root/openshift-install-ocp4-sno/.openshift_install.log

# Common causes:
# - Network connectivity (DNS, registry)
# - Insufficient resources (OOM)
# - Pull secret invalid
```

### Can't Access Web Console

**Symptoms**: Browser can't reach Console URL

**Check**:
```bash
# Verify DNS resolution
dig +short console-openshift-console.apps.ocp4-sno.sandbox3377.opentlc.com
# Should return Ingress VIP

# Verify router pods running
oc get pods -n openshift-ingress
# Should show 1 router pod Running

# Check router service
oc get svc -n openshift-ingress
```

### Application Build Fails

**Symptoms**: `oc new-app` build fails

**Debug**:
```bash
# Check build logs
oc logs -f bc/httpd-ex

# Common causes:
# - Git repository unreachable (network)
# - Builder image pull fails (registry)
# - Insufficient resources (build pod OOM)
```

---

## Related Tutorials

- [Deploy 3-Node Compact Cluster](deploy-compact-cluster.md) (coming soon)
- [Deploy HA Cluster with Load Balancer](deploy-ha-cluster.md) (coming soon)
- [Configure Operators from Mirror Registry](configure-disconnected-operators.md)

---

## Get Help

- **Documentation**: [docs/how-to/](../how-to/)
- **ADRs**: [docs/adrs/](../adrs/)
- **Issues**: https://github.com/tosin2013/ocp4-disconnected-helper/issues
- **OpenShift Docs**: https://docs.openshift.com/
