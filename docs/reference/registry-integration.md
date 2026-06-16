# Registry Integration Reference

Complete reference for integrating OpenShift Agent-Based Installer with container registries in disconnected environments.

---

## Overview

The Agent-Based Installer supports multiple container registry types for mirroring OpenShift container images in disconnected/air-gapped environments.

**Supported Registries**:
- **Quay** (Project maintained) - Red Hat's open-source container registry
- **Harbor** (Community contribution) - CNCF graduated project registry
- **JFrog Artifactory** (Community contribution) - Universal artifact manager

All registries use **ImageDigestMirrorSet** (IDMS) for redirecting image pulls to the mirror registry.

---

## Architecture

### Image Pull Flow (Disconnected)

```
OpenShift Node                Mirror Registry              Red Hat Registry
┌─────────────┐              ┌────────────┐              ┌─────────────────┐
│             │              │            │              │                 │
│ oc/podman   │──(1) Pull──→ │ Quay       │──(2) N/A ──→ │ quay.io         │
│             │   request    │ Harbor     │   (offline)  │ registry.rh.io  │
│             │              │ JFrog      │              │                 │
│             │←─(3) Image───│            │              │                 │
└─────────────┘              └────────────┘              └─────────────────┘
       │                             ▲
       │                             │
       └─────(4) IDMS redirects)─────┘
```

**Flow**:
1. Node requests image from `quay.io/openshift-release-dev/ocp-release`
2. **ImageDigestMirrorSet** intercepts and redirects to mirror registry
3. Mirror registry serves cached image
4. Node never contacts external registry (disconnected)

---

## Quay Mirror Registry (Primary)

**Project Status**: Maintained by this repository  
**Documentation**: Complete, tested, production-ready

### Architecture

```
Quay Mirror Registry v2 (Podman Pod)
┌────────────────────────────────────────┐
│  ┌──────────┐  ┌──────────┐           │
│  │ quay-app │  │ postgres │           │
│  │  :8443   │  │  :5432   │           │
│  └──────────┘  └──────────┘           │
│                                        │
│  ┌──────────┐  ┌──────────┐           │
│  │  redis   │  │  pause   │           │
│  │  :6379   │  │          │           │
│  └──────────┘  └──────────┘           │
└────────────────────────────────────────┘
         │
         ▼
  Storage: /opt/mirror-registry/quay-storage/
```

### Registry Path Structure

```
registry.example.com:8443/
└── ocp4/                           # Organization
    └── openshift4/                 # Repository
        ├── ocp-release@sha256:...  # Release image
        ├── oauth-proxy@sha256:...  # Component images
        └── ...
```

**ImageDigestMirrorSet**:
```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: quay-mirror
spec:
  imageDigestMirrors:
  - mirrors:
    - registry.example.com:8443/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - registry.example.com:8443/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Configuration Variables

```yaml
# extra_vars/cluster-configs/sno-quay.yml
registry_type: "quay"
registry_url: "registry.sandbox3377.opentlc.com:8443"
registry_username: "init"  # Default Quay mirror-registry user
registry_password: "<from vault or survey>"

# Loaded from roles/openshift_cluster_deploy/vars/quay.yml
registry_mirror_paths:
  - source: quay.io/openshift-release-dev/ocp-release
    mirrors:
      - "{{ registry_url }}/ocp4/openshift4"
  - source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
    mirrors:
      - "{{ registry_url }}/ocp4/openshift4"
  - source: registry.redhat.io/ubi8
    mirrors:
      - "{{ registry_url }}/ocp4/ubi8"
  - source: registry.redhat.io/ubi9
    mirrors:
      - "{{ registry_url }}/ocp4/ubi9"
```

### Deployment

**Deploy Quay Mirror Registry**:
```bash
# Deploy registry VM with Quay
ansible-playbook playbooks/site.yml \
  --tags registry \
  -e registry_type=quay
```

**Mirror OpenShift Images**:
```bash
# Download to disk (DMZ workflow)
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/ocp-versions/ocp-4.21.yml

# Push to Quay registry
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/ocp-versions/ocp-4.21.yml
```

### Pros

✅ **Officially supported** - Red Hat's mirror-registry tool  
✅ **Simple deployment** - Single Podman pod, automated  
✅ **Well-documented** - Extensive OpenShift docs  
✅ **Integrated tooling** - oc-mirror works seamlessly  
✅ **Project maintained** - Complete testing coverage  

### Cons

❌ **Limited features** - Basic registry only (no UI)  
❌ **No replication** - Single-node deployment  
❌ **Manual backup** - No built-in backup/restore  

---

## Harbor (Community Contribution)

**Project Status**: Community maintained  
**Documentation**: Community-provided examples

### Architecture

```
Harbor Registry (Docker Compose)
┌────────────────────────────────────────┐
│  ┌──────────┐  ┌──────────┐           │
│  │  Harbor  │  │ postgres │           │
│  │   Core   │  │          │           │
│  │  :443    │  └──────────┘           │
│  └──────────┘                          │
│                                        │
│  ┌──────────┐  ┌──────────┐           │
│  │  Redis   │  │ Registry │           │
│  │          │  │  (v2)    │           │
│  └──────────┘  └──────────┘           │
└────────────────────────────────────────┘
```

### Registry Path Structure

```
harbor.example.com/
└── ocp4-project/                   # Project (not organization)
    └── openshift4/                 # Repository
        ├── ocp-release@sha256:...  # Release image
        ├── oauth-proxy@sha256:...  # Component images
        └── ...
```

**Key Difference**: Harbor uses **Projects** (not organizations) for namespace isolation.

**ImageDigestMirrorSet**:
```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: harbor-mirror
spec:
  imageDigestMirrors:
  - mirrors:
    - harbor.example.com/ocp4-project/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - harbor.example.com/ocp4-project/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Configuration Variables

```yaml
# extra_vars/cluster-configs/sno-harbor.yml
registry_type: "harbor"
registry_url: "harbor.sandbox3377.opentlc.com"
registry_username: "admin"
registry_password: "<harbor admin password>"

# Loaded from roles/openshift_cluster_deploy/vars/harbor.yml
registry_mirror_paths:
  - source: quay.io/openshift-release-dev/ocp-release
    mirrors:
      - "{{ registry_url }}/ocp4-project/openshift4"
  - source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
    mirrors:
      - "{{ registry_url }}/ocp4-project/openshift4"
  - source: registry.redhat.io/ubi8
    mirrors:
      - "{{ registry_url }}/ocp4-project/ubi8"
  - source: registry.redhat.io/ubi9
    mirrors:
      - "{{ registry_url }}/ocp4-project/ubi9"
```

### Deployment

**Deploy Harbor** (Community playbook required - not in this repo):
```bash
# Example Harbor deployment (community-provided)
ansible-playbook community/deploy-harbor.yml \
  -e harbor_admin_password=<password>
```

**Create Harbor Project**:
```bash
# Via Harbor Web UI or API
curl -X POST "https://harbor.example.com/api/v2.0/projects" \
  -H "Authorization: Basic <base64_admin_password>" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "ocp4-project",
    "public": false
  }'
```

**Mirror OpenShift Images**:
```bash
# Use oc-mirror with Harbor registry
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/ocp-versions/ocp-4.21.yml

ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/ocp-versions/ocp-4.21.yml \
  -e registry_type=harbor
```

### Pros

✅ **Rich Web UI** - Intuitive project/repository management  
✅ **RBAC** - Fine-grained access control  
✅ **Replication** - Multi-site registry synchronization  
✅ **Vulnerability scanning** - Trivy/Clair integration  
✅ **CNCF graduated** - Production-grade, widely adopted  

### Cons

❌ **Complex deployment** - Docker Compose, multiple components  
❌ **Community support** - Not officially maintained by this repo  
❌ **Heavier resources** - More RAM/CPU than Quay mirror-registry  

### Harbor-Specific Notes

- **Projects vs Organizations**: Harbor uses Projects for namespacing (not Quay organizations)
- **Path structure**: `<registry>/<project>/<repository>` (vs Quay's `<registry>/<org>/<repo>`)
- **Authentication**: Supports multiple auth backends (LDAP, OIDC, local)
- **Quota management**: Per-project storage quotas

---

## JFrog Artifactory (Community Contribution)

**Project Status**: Community maintained  
**Documentation**: Community-provided examples

### Architecture

```
JFrog Artifactory (Enterprise)
┌────────────────────────────────────────┐
│  ┌─────────────────┐                  │
│  │  Artifactory    │                  │
│  │  (Java/Tomcat)  │                  │
│  │    :8081/8082   │                  │
│  └─────────────────┘                  │
│          │                             │
│          ▼                             │
│  ┌─────────────────┐                  │
│  │  PostgreSQL     │                  │
│  │  (Metadata)     │                  │
│  └─────────────────┘                  │
└────────────────────────────────────────┘
```

### Registry Path Structure

```
jfrog.example.com/
└── ocp4-docker-local/              # Docker repository (local)
    └── openshift4/                 # Namespace
        ├── ocp-release@sha256:...  # Release image
        ├── oauth-proxy@sha256:...  # Component images
        └── ...
```

**Key Difference**: JFrog uses **repositories** (not projects/organizations). Docker images stored in `<repo>/<namespace>/<image>`.

**ImageDigestMirrorSet**:
```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: jfrog-mirror
spec:
  imageDigestMirrors:
  - mirrors:
    - jfrog.example.com/ocp4-docker-local/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - jfrog.example.com/ocp4-docker-local/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Configuration Variables

```yaml
# extra_vars/cluster-configs/sno-jfrog.yml
registry_type: "jfrog"
registry_url: "jfrog.sandbox3377.opentlc.com"
registry_username: "admin"
registry_password: "<jfrog admin password>"

# Loaded from roles/openshift_cluster_deploy/vars/jfrog.yml
registry_mirror_paths:
  - source: quay.io/openshift-release-dev/ocp-release
    mirrors:
      - "{{ registry_url }}/ocp4-docker-local/openshift4"
  - source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
    mirrors:
      - "{{ registry_url }}/ocp4-docker-local/openshift4"
  - source: registry.redhat.io/ubi8
    mirrors:
      - "{{ registry_url }}/ocp4-docker-local/ubi8"
  - source: registry.redhat.io/ubi9
    mirrors:
      - "{{ registry_url }}/ocp4-docker-local/ubi9"
```

### Deployment

**Deploy JFrog Artifactory** (Community - not in this repo):
```bash
# Example JFrog deployment (community/commercial)
# Requires JFrog license or trial
```

**Create Docker Repository**:
```bash
# Via JFrog Web UI or API
curl -X PUT "https://jfrog.example.com/artifactory/api/repositories/ocp4-docker-local" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "rclass": "local",
    "packageType": "docker",
    "dockerApiVersion": "V2"
  }'
```

**Mirror OpenShift Images**:
```bash
# Use oc-mirror with JFrog registry
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/ocp-versions/ocp-4.21.yml \
  -e registry_type=jfrog
```

### Pros

✅ **Universal artifact manager** - Docker + Maven + NPM + ... all in one  
✅ **Enterprise features** - HA, replication, backup, RBAC  
✅ **Advanced caching** - Remote repository proxying  
✅ **Audit trails** - Complete access/download logging  
✅ **Commercial support** - JFrog enterprise support available  

### Cons

❌ **Commercial license** - Free tier limited, enterprise costly  
❌ **Heavy resource usage** - Java-based, high memory footprint  
❌ **Complex setup** - Many configuration options  
❌ **Community support only** - Not officially maintained by this repo  

### JFrog-Specific Notes

- **Access tokens**: Use access tokens (not password) for authentication
- **Docker Registry v2**: Must enable Docker Registry API v2 in repository settings
- **Repository types**: Use `local` (not `remote` or `virtual`) for mirrors
- **Path structure**: `<registry>/<docker-repo>/<namespace>/<image>`

---

## Comparison Matrix

| Feature | Quay | Harbor | JFrog |
|---------|------|--------|-------|
| **Deployment** | ✅ Simple (Podman) | ⚠️ Moderate (Docker Compose) | ⚠️ Complex (Java/Tomcat) |
| **Web UI** | ❌ No | ✅ Yes | ✅ Yes |
| **RBAC** | ⚠️ Basic | ✅ Advanced | ✅ Advanced |
| **Replication** | ❌ No | ✅ Yes | ✅ Yes |
| **Vulnerability Scanning** | ❌ No | ✅ Yes (Trivy) | ✅ Yes (Xray) |
| **HA** | ❌ No | ⚠️ Manual | ✅ Built-in |
| **Project Support** | ✅ Maintained | ⚠️ Community | ⚠️ Community |
| **License** | ✅ Apache 2.0 | ✅ Apache 2.0 | ⚠️ Commercial |
| **Resource Usage** | ✅ Light | ⚠️ Moderate | ❌ Heavy |

---

## Switching Registries

### From Quay to Harbor

1. **Deploy Harbor registry**
2. **Create Harbor project**: `ocp4-project`
3. **Mirror images to Harbor**:
   ```bash
   ansible-playbook playbooks/push-to-registry-v2.yml \
     -e @extra_vars/ocp-versions/ocp-4.21.yml \
     -e registry_type=harbor
   ```
4. **Deploy new cluster** with Harbor config:
   ```bash
   ansible-playbook playbooks/deploy-openshift-cluster.yml \
     -e @extra_vars/cluster-configs/sno-harbor.yml
   ```

**Note**: ImageDigestMirrorSet paths differ - cluster redeploy required.

### Updating Existing Cluster Registry

**Warning**: Changing ImageDigestMirrorSet on running cluster triggers node reboot.

```bash
# Update IDMS
oc apply -f manifests/imagedigestmirrorset-harbor.yaml

# Nodes will reboot to apply changes
oc get nodes -w

# After reboot, verify image pulls work
oc get pods -A
```

---

## Certificate Management

All registries support **TLS certificates**:

### Self-Signed CA (Disconnected)

```bash
# Generate self-signed CA
ansible-playbook playbooks/setup-certificates.yml \
  -e ssl_cert_provider=selfsigned

# Distribute CA to nodes (via agent-config.yaml)
# Embedded in ISO automatically
```

### Let's Encrypt (Cloud)

```bash
# Generate Let's Encrypt cert (requires AWS Route53)
ansible-playbook playbooks/setup-certificates.yml \
  -e ssl_cert_provider=letsencrypt
```

**agent-config.yaml** (auto-generated):
```yaml
apiVersion: v1alpha1
kind: AgentConfig
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  <self-signed CA cert>
  -----END CERTIFICATE-----
```

---

## Troubleshooting

### Image Pull Fails

**Error**: `ImagePullBackOff` or `ErrImagePull`

**Debug**:
```bash
# Check pod events
oc describe pod <pod-name>

# Check image pull from node
oc debug node/<node-name>
chroot /host
podman pull <registry-url>/<image>

# Common causes:
# - Registry unreachable (DNS, firewall)
# - Certificate not trusted
# - ImageDigestMirrorSet misconfigured
```

### IDMS Not Applied

**Error**: Nodes still pulling from `quay.io`

**Check**:
```bash
# Verify IDMS exists
oc get imagedigestmirrorset

# Check IDMS content
oc get imagedigestmirrorset -o yaml

# Verify nodes see IDMS (via Machine Config)
oc get machineconfig | grep image

# Force MachineConfig update
oc patch machineconfig <config-name> --type=merge -p '{}'
```

### Certificate Trust Issues

**Error**: `x509: certificate signed by unknown authority`

**Fix**:
```bash
# Verify CA in agent-config.yaml
cat /root/openshift-install-<cluster>/agent-config.yaml | grep -A 20 additionalTrustBundle

# Re-generate ISO with correct CA
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-quay.yml \
  --tags phase1,phase2,phase3
```

---

## Related Documentation

- [Deploy OpenShift Cluster (Agent-Based)](../how-to/deploy-openshift-cluster-agent-based.md)
- [Configure Operator Catalog for Disconnected](../how-to/configure-operator-catalog-for-disconnected.md)
- [Switch Registry Types](../how-to/switch-registry-types.md)
- [Resolve Registry TLS Authentication](../how-to/resolve-registry-tls-authentication.md)
- ADR-0017: Quay Mirror Registry

---

## References

- [OpenShift Disconnected Installation](https://docs.openshift.com/container-platform/4.21/installing/disconnected_install/index.html)
- [ImageDigestMirrorSet](https://docs.openshift.com/container-platform/4.21/openshift_images/image-configuration.html)
- [Harbor Documentation](https://goharbor.io/docs/)
- [JFrog Artifactory](https://jfrog.com/artifactory/)
