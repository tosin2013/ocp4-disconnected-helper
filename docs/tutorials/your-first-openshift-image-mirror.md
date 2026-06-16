---
layout: default
title: Your First OpenShift Image Mirror
parent: Tutorials
nav_order: 2
---

# Tutorial: Your First OpenShift Image Mirror

**Time to Complete**: 45-60 minutes  
**Prerequisites**: Completed [Getting Started with AAP Workflows](getting-started-with-aap-workflows.md) OR have a working container registry  
**What You'll Learn**: Mirror OpenShift container images for disconnected deployment  
**End State**: Container registry populated with OpenShift 4.21 images and storage operators

---

## What You Will Build

By the end of this tutorial, you will have:
- ✅ Container registry with OpenShift 4.21.18 release images
- ✅ Storage operators mirrored (local-storage, ODF, etc.)
- ✅ Pull secret configured for disconnected installation
- ✅ ImageContentSourcePolicy (ICSP) for cluster deployment

This is everything needed to install OpenShift in a disconnected environment!

---

## Understanding the Mirroring Process

OpenShift disconnected deployments require two types of images:

1. **Release Images**: Core OpenShift container images (kubelet, API server, etc.)
2. **Operator Images**: Optional operators (storage, networking, observability)

The `oc-mirror` tool downloads these from Red Hat's public registry (`registry.redhat.io`) and pushes them to your private registry.

**The Challenge**: A full mirror is ~150GB. This tutorial mirrors only what you need to get started (~50GB).

---

## Step 1: Verify Prerequisites

Before starting, ensure you have a working container registry.

### If You Completed the Previous Tutorial

Check that Workflow 1 deployed successfully:

```bash
ssh admin@192.168.10.10 "podman ps"
```

Expected output:
```
CONTAINER ID  IMAGE                                 STATUS
...           quay.io/redhat/quay:latest            Up 10 minutes
...           docker.io/library/postgres:13         Up 10 minutes
...           docker.io/library/redis:latest        Up 10 minutes
```

### If You're Starting Fresh

You need a registry accessible at a hostname/IP with TLS. If you don't have one:

```bash
# Quick registry deployment (Quay mirror-registry)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-mirror-registry.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

---

## Step 2: Understand Operator Presets

This project includes **8 curated operator presets** for common use cases. For this tutorial, we'll use the `storage-operators` preset.

View available presets:

```bash
ls extra_vars/operators/
```

You will see:
```
networking-operators.yml
observability-operators.yml
openshift-ai-operators.yml
rhacm-operators.yml
security-operators.yml
service-mesh-operators.yml
storage-operators.yml
virtualization-operators.yml
```

Inspect the storage preset:

```bash
cat extra_vars/operators/storage-operators.yml
```

Output:
```yaml
---
# Storage Operators Preset
# Use case: Persistent storage for OpenShift workloads
# Operators: local-storage, ODF, NFS, Hostpath

operator_preset_name: "storage-operators"

operators:
  - name: local-storage-operator
    catalog: redhat-operator-index
  - name: odf-operator
    catalog: redhat-operator-index
  - name: nfs-provisioner-operator
    catalog: redhat-marketplace-index
...
```

**Why This Matters**: Operator names must be exact. The validation framework catches typos **before** wasting 30 minutes downloading.

---

## Step 3: Validate Operator Selection (Critical Step!)

**Always validate before mirroring!** This prevents failures 10-30 minutes into the download.

Run the validation playbook:

```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml
```

Wait 5-10 seconds. You will see:

```
TASK [Display validation results] **********************************************
ok: [localhost] => {
    "msg": [
        "==============================================",
        "Operator Validation Results",
        "==============================================",
        "",
        "✅ All 5 operators validated successfully!",
        "",
        "Valid Operators:",
        "  ✅ local-storage-operator (redhat-operator-index)",
        "  ✅ odf-operator (redhat-operator-index)",
        "  ✅ nfs-provisioner-operator (redhat-marketplace-index)",
        ...
    ]
}
```

If any operators are invalid, you'll see:

```
❌ Invalid Operators:
  ❌ local-storage (redhat-operator-index)
     Suggestion: Did you mean 'local-storage-operator'?
```

**Fix any errors before proceeding!**

---

## Step 4: Download Images to Disk

Now download OpenShift images to a TAR file. This is a two-stage process:
1. **Download to disk** (this step - happens in connected/DMZ environment)
2. **Push to registry** (next step - happens in disconnected environment)

Run the download playbook:

```bash
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e openshift_version=4.21.18
```

This will take **30-60 minutes** depending on your internet speed. You'll see:

```
TASK [Download OpenShift images with oc-mirror] ********************************
...
info: Mirroring 1234 images (50.2 GB total)...
...
info: Writing image set to /data/oc-mirror/oc-mirror-workspace/...
```

**Go get lunch!** 🍔

When complete, you will see:

```
TASK [Display download summary] ************************************************
ok: [localhost] => {
    "msg": [
        "✅ Download complete!",
        "Images: 1234 mirrored",
        "Size: 50.2 GB",
        "TAR file: /data/oc-mirror/oc-mirror-workspace/mirror_seq1_000000.tar",
        ...
    ]
}
```

Verify the TAR file exists:

```bash
ls -lh /data/oc-mirror/oc-mirror-workspace/
```

Expected output:
```
-rw-r--r--. 1 root root 50G Jun 16 14:32 mirror_seq1_000000.tar
-rw-r--r--. 1 root root 12K Jun 16 14:32 imageContentSourcePolicy.yaml
-rw-r--r--. 1 root root  8K Jun 16 14:32 catalogSource.yaml
```

---

## Step 5: Push Images to Your Registry

Now push the downloaded images to your private registry:

```bash
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e target_registry=registry.example.com:8443 \
  -e registry_username=init \
  -e registry_password=<password-from-quay-credentials>
```

**Finding the registry password**:
```bash
ssh admin@192.168.10.10 "cat /opt/mirror-registry/credentials.txt"
```

This will take **20-40 minutes**. You'll see:

```
TASK [Push images to registry with oc-mirror] **********************************
...
info: Pushing 1234 images to registry.example.com:8443...
...
info: ✓ 1234 / 1234 images pushed successfully
```

When complete:

```
TASK [Display push summary] ****************************************************
ok: [localhost] => {
    "msg": [
        "✅ Push complete!",
        "Registry: registry.example.com:8443",
        "Images: 1234 pushed",
        "Failed: 0",
        ...
    ]
}
```

---

## Step 6: Verify Images in Registry

Verify images were pushed successfully:

```bash
# Test registry authentication
export REGISTRY_URL=registry.example.com:8443
export REGISTRY_USER=init
export REGISTRY_PASS=<password>

echo "$REGISTRY_PASS" | podman login --username "$REGISTRY_USER" \
  --password-stdin "$REGISTRY_URL"
```

Expected output:
```
Login Succeeded!
```

List mirrored repositories:

```bash
curl -sk -u "$REGISTRY_USER:$REGISTRY_PASS" \
  "https://$REGISTRY_URL/v2/_catalog" | jq -r '.repositories[]' | head -10
```

Expected output:
```
openshift/release-images
openshift/ocp-v4.0-art-dev
redhat/redhat-operator-index
redhat/local-storage-operator
redhat/odf-operator
...
```

---

## Step 7: Create Pull Secret for Disconnected Installation

Combine your Red Hat pull secret with your registry credentials:

```bash
# Get Red Hat pull secret
cat ~/pull-secret.json

# Merge with registry auth
cat > ~/merged-pull-secret.json <<EOF
{
  "auths": {
    "cloud.openshift.com": { ... },
    "quay.io": { ... },
    "registry.redhat.io": { ... },
    "registry.example.com:8443": {
      "auth": "$(echo -n "$REGISTRY_USER:$REGISTRY_PASS" | base64 -w0)"
    }
  }
}
EOF
```

Test the merged pull secret:

```bash
podman login --authfile ~/merged-pull-secret.json "$REGISTRY_URL"
```

Expected output:
```
Login Succeeded!
```

**Save this file!** You'll need it for OpenShift installation.

---

## Step 8: Extract ImageContentSourcePolicy

The ICSP tells OpenShift to pull images from your registry instead of Red Hat's:

```bash
cat /data/oc-mirror/oc-mirror-workspace/imageContentSourcePolicy.yaml
```

Output:
```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: mirror-0
spec:
  repositoryDigestMirrors:
  - mirrors:
    - registry.example.com:8443/openshift/release-images
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - registry.example.com:8443/openshift/ocp-v4.0-art-dev
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  ...
```

**Copy this to your OpenShift installation directory!**

---

## What You've Accomplished

Congratulations! You now have:

✅ **Mirrored Content**:
- OpenShift 4.21.18 release images (~30GB)
- Storage operators (local-storage, ODF, NFS) (~20GB)
- Catalog metadata for operator installation

✅ **Configuration Files**:
- Pull secret with registry credentials
- ImageContentSourcePolicy (ICSP) for cluster installation
- CatalogSource for OperatorHub

✅ **Skills Gained**:
- Using operator presets for curated deployments
- Running operator validation before mirroring
- Two-stage mirroring (download → push)
- Creating pull secrets for disconnected installation
- Understanding ICSP configuration

---

## Next Steps

Now that you have mirrored images:

1. **Install OpenShift** in disconnected mode using your registry
2. **Mirror additional operators** using other presets
3. **Set up cluster upgrades** (mirror new OpenShift versions)

Continue with:
- [Tutorial: End-to-End Disconnected Deployment](end-to-end-disconnected-deployment.md) (coming soon)
- [How-To: Add Custom Operators](../how-to/add-custom-operators.md)
- [How-To: Mirror OpenShift Upgrades](../how-to/mirror-openshift-upgrades.md)

---

## Troubleshooting

### Issue: Operator validation fails with "package not found"

**Symptom**:
```
❌ Invalid Operators:
  ❌ local-storage (redhat-operator-index)
```

**Solution**: Operator name typo. Use the discovery tool:

```bash
./scripts/discover-operators.sh --search storage
```

This shows exact operator names. Update your preset file with the correct name.

### Issue: oc-mirror fails with "port 55000 already bound"

**Symptom**:
```
[ERROR] [Executor] 55000 is already bound and cannot be used
```

**Solution**: Stale Ansible async cache. Clear it:

```bash
sudo rm -rf /root/.ansible_async/*
```

Then re-run the playbook.

See [Known Failure Patterns](../../CLAUDE.md#known-failure-patterns--v10-v12) for more details.

### Issue: Registry authentication fails after push

**Symptom**:
```
Error: unable to retrieve auth token: unauthorized
```

**Solution**: Check registry credentials:

```bash
ssh admin@192.168.10.10 "cat /opt/mirror-registry/credentials.txt"
```

Use the exact username/password from this file.

---

## Further Reading

**Architecture**:
- [Explanation: oc-mirror Two-Stage Workflow](../explanations/oc-mirror-two-stage-workflow.md)
- [ADR-0003: oc-mirror for Image Mirroring](../adrs/0003-oc-mirror-image-mirroring.md)

**Operations**:
- [Operator Validation Framework](../reference/operator-validation-framework.md)
- [Operator Presets Reference](../reference/operator-presets.md)
