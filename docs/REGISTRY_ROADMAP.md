# Registry Configuration Roadmap

**Purpose**: Plan and track different registry configurations for disconnected OpenShift deployments.

**Status**: 🗺️ ROADMAP (Planning phase)  
**Last Updated**: 2026-06-02  
**Owner**: Platform Team

---

## Overview

ocp4-disconnected-helper will support **three registry configurations** for different use cases and enterprise requirements:

1. **Red Hat Quay / mirror-registry** (Community/Small deployments)
2. **Harbor** (Enterprise, cloud-native focus)
3. **JFrog Artifactory** (Enterprise, multi-format artifacts)

Each configuration has distinct advantages, deployment patterns, and integration requirements.

---

## Registry Comparison Matrix

| Feature | Quay/mirror-registry | Harbor | JFrog Artifactory |
|---------|---------------------|--------|-------------------|
| **Vendor** | Red Hat (Quay) / Community (mirror-registry) | VMware/CNCF | JFrog |
| **License** | Open Source / Red Hat subscription | Open Source (Apache 2.0) | Open Source / Commercial |
| **Primary Use Case** | OpenShift disconnected | Cloud-native registries | Universal artifact management |
| **Container Registry** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Helm Charts** | ❌ No | ✅ Yes | ✅ Yes |
| **Maven/NPM/PyPI** | ❌ No | ❌ No | ✅ Yes (universal) |
| **Image Signing** | ✅ Yes (Cosign) | ✅ Yes (Notary, Cosign) | ✅ Yes (multiple) |
| **Vulnerability Scanning** | ✅ Clair | ✅ Trivy | ✅ Xray |
| **Replication** | ✅ Geo-replication | ✅ Multi-registry | ✅ Multi-site |
| **RBAC** | ✅ Yes | ✅ Yes | ✅ Advanced |
| **Storage Backend** | S3, local, Azure, GCS | S3, local, Azure, GCS | S3, local, Azure, GCS, NFS |
| **Resource Requirements** | Low (2GB RAM) | Medium (4GB RAM) | High (8GB+ RAM) |
| **OpenShift Integration** | ✅ Native (imageContentSourcePolicy) | ✅ Via ImageContentSourcePolicy | ✅ Via ImageContentSourcePolicy |
| **HA/Clustering** | ✅ Yes (Quay) / ❌ No (mirror-registry) | ✅ Yes | ✅ Yes |
| **Air-Gap Sync** | ✅ oc-mirror | ✅ Manual sync | ✅ oc-mirror + JFrog CLI |
| **Red Hat Support** | ✅ Yes (Quay subscription) | ❌ Community | ✅ Yes (JFrog partnership) |

---

## Configuration 1: Red Hat Quay / mirror-registry

### Use Cases
- **Best for**: 
  - Small to medium OpenShift deployments
  - Red Hat support requirement
  - Pure container image mirroring
  - Budget-conscious organizations

### Deployment Options

#### Option 1A: mirror-registry (Podman-based, standalone)
**Pros**:
- ✅ Lightweight (2GB RAM, single container)
- ✅ Quick setup (15 minutes)
- ✅ No external dependencies
- ✅ Built-in oc-mirror integration

**Cons**:
- ❌ No HA/clustering
- ❌ Limited UI features
- ❌ No advanced RBAC
- ❌ No geo-replication

**Resource Requirements**:
- vCPU: 2
- RAM: 4GB
- Disk: 500GB (expandable based on mirror size)

**Implementation Status**: 🟢 READY (existing playbook)
- Playbook: `playbooks/deploy-mirror-registry.yml`
- Docs: Mirror registry already documented in existing codebase

#### Option 1B: Red Hat Quay (Full enterprise)
**Pros**:
- ✅ Full HA and clustering
- ✅ Geo-replication
- ✅ Advanced RBAC
- ✅ Red Hat support
- ✅ Clair vulnerability scanning

**Cons**:
- ❌ Higher resource requirements (8GB+ RAM per replica)
- ❌ Requires Quay subscription
- ❌ Complex setup (database, Redis, storage)

**Resource Requirements**:
- vCPU: 4
- RAM: 8GB
- Disk: 500GB (+ external database)
- Database: PostgreSQL (external or containerized)
- Cache: Redis (external or containerized)

**Implementation Status**: 🔴 NOT STARTED (roadmap item)
- Estimated Effort: 2 weeks
- Dependencies: PostgreSQL playbook, Redis playbook
- Priority: P3 (optional, enterprise upgrade path)

---

## Configuration 2: Harbor

### Use Cases
- **Best for**:
  - Cloud-native organizations (CNCF stack)
  - Helm chart repository requirement
  - Multi-tenancy with project isolation
  - Open-source preference
  - Kubernetes-native deployments

### Deployment Architecture

**Harbor Components**:
- Core (API, web UI)
- JobService (garbage collection, replication)
- Registry (container storage)
- Trivy (vulnerability scanning)
- Notary (image signing)
- Database (PostgreSQL)
- Cache (Redis)

**Resource Requirements**:
- vCPU: 4
- RAM: 8GB (16GB recommended for production)
- Disk: 500GB (expandable)
- Database: PostgreSQL 12+ (external or containerized)
- Cache: Redis (external or containerized)

### Harbor Advantages for OpenShift

1. **Helm Chart Repository**
   - Store Helm charts alongside container images
   - Useful for operators and custom applications
   - Integrated with Harbor UI

2. **Project-Based Multi-Tenancy**
   - Isolate registries by team/environment
   - Fine-grained RBAC per project
   - Quota management per project

3. **Trivy Vulnerability Scanning**
   - Built-in image scanning
   - Policy enforcement (block vulnerable images)
   - CVE database updates

4. **Replication**
   - Push-based replication to remote Harbor instances
   - Pull-based replication from DockerHub, Quay, etc.
   - Filter rules (by tag, label, resource)

### Implementation Status: 🟡 IN PROGRESS
- Airflow DAG: `airflow/dags/ocp_harbor_registry.py` (exists in v4.20.0)
- AAP Job Template: To be created in Phase 3 (Task 3.5)
- Cloud-init template: To be created for Harbor VM
- Documentation: Harbor-specific setup guide needed

### Roadmap Tasks for Harbor

#### Task H.1: Create Harbor VM Template
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 3 days  
**Dependencies**: Task 1.1 (Libvirt templates)

**Description**: Create `templates/libvirt/harbor-vm.xml.j2` with Harbor-specific resources.

**Implementation**:
```xml
<!-- Harbor VM: 4 vCPU, 8GB RAM, 500GB disk -->
<domain type='kvm'>
  <name>{{ vm_name }}</name>
  <memory unit='MiB'>8192</memory>
  <vcpu>4</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='/var/lib/libvirt/images/harbor-vm.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <source file='/var/lib/libvirt/images/harbor-cloud-init.iso'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <source network='{{ vm_network }}'/>
      <model type='virtio'/>
    </interface>
  </devices>
</domain>
```

#### Task H.2: Create Harbor Cloud-Init Templates
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 2 days  
**Dependencies**: Task 1.2 (Cloud-init templates)

**Description**: Create cloud-init configs for automated Harbor VM setup.

**Files**:
- `templates/cloud-init/harbor-user-data.yml.j2`
- `templates/cloud-init/harbor-meta-data.yml.j2`
- `templates/cloud-init/harbor-network-config.yml.j2`

**Key Cloud-Init Tasks**:
```yaml
#cloud-config
packages:
  - podman
  - podman-compose
  - python3-pip
  - openssl

runcmd:
  # Install docker-compose (Harbor uses docker-compose.yml)
  - pip3 install docker-compose

  # Download Harbor installer
  - wget https://github.com/goharbor/harbor/releases/download/v2.10.0/harbor-offline-installer-v2.10.0.tgz
  - tar xvf harbor-offline-installer-v2.10.0.tgz -C /opt/

  # Configure Harbor
  - cp /opt/harbor/harbor.yml.tmpl /opt/harbor/harbor.yml
  - sed -i 's/hostname: reg.mydomain.com/hostname: {{ harbor_hostname }}/' /opt/harbor/harbor.yml
  - sed -i 's/harbor_admin_password: Harbor12345/harbor_admin_password: {{ harbor_admin_password }}/' /opt/harbor/harbor.yml

  # Install Harbor
  - cd /opt/harbor && ./install.sh --with-trivy --with-chartmuseum
```

#### Task H.3: Create playbooks/provision-harbor-vm.yml
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 1 week  
**Dependencies**: Task 1.4 (reusable task), Task H.1, Task H.2

**Description**: Provision Harbor VM using community.libvirt.

**Implementation**:
```yaml
---
- name: Provision Harbor Registry VM
  hosts: localhost
  gather_facts: yes
  vars:
    vm_name: "harbor-registry"
    vm_memory: 8192
    vm_cpus: 4
    vm_disk_size: 500
    vm_template: "templates/libvirt/harbor-vm.xml.j2"
    cloud_init_user_data_template: "templates/cloud-init/harbor-user-data.yml.j2"
    cloud_init_meta_data_template: "templates/cloud-init/harbor-meta-data.yml.j2"
    cloud_init_network_config_template: "templates/cloud-init/harbor-network-config.yml.j2"
    harbor_hostname: "harbor.example.com"
    harbor_admin_password: "{{ vault_harbor_admin_password }}"

  tasks:
    - name: Provision Harbor VM using reusable task
      ansible.builtin.include_tasks: tasks/provision-vm-libvirt.yml
```

#### Task H.4: Create docs/harbor-registry-setup.md
**Status**: 🔴 NOT STARTED  
**Priority**: P3  
**Effort**: 2 days  
**Dependencies**: Task H.3

**Description**: Comprehensive Harbor setup and integration guide.

**Content Outline**:
1. Harbor architecture overview
2. Installation and configuration
3. Project and user management
4. Replication configuration (pull from DockerHub, push to remote Harbor)
5. Vulnerability scanning setup
6. Helm chart repository usage
7. OpenShift integration (ImageContentSourcePolicy)
8. oc-mirror integration for air-gapped sync
9. Backup and recovery
10. Troubleshooting

#### Task H.5: Harbor HAProxy Configuration
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 1 day  
**Dependencies**: Task H.3

**Description**: Configure HAProxy on KVM host to route traffic to Harbor VM.

**HAProxy Config**:
```haproxy
# Harbor HTTPS (web UI + registry)
frontend harbor_https
    bind *:8443 ssl crt /etc/haproxy/certs/harbor.pem
    default_backend harbor_backend

backend harbor_backend
    balance roundrobin
    server harbor1 192.168.122.10:443 check ssl verify none

# Harbor HTTP (redirect to HTTPS)
frontend harbor_http
    bind *:8080
    redirect scheme https code 301
```

---

## Configuration 3: JFrog Artifactory

### Use Cases
- **Best for**:
  - Universal artifact management (containers + Maven + NPM + PyPI + Helm)
  - Large enterprises with multiple artifact types
  - Integrated CI/CD pipelines
  - Advanced build metadata and provenance tracking
  - Organizations already using JFrog ecosystem

### Deployment Architecture

**JFrog Platform Components**:
- Artifactory (artifact storage and management)
- Xray (vulnerability scanning and license compliance)
- Pipelines (CI/CD orchestration, optional)
- Distribution (artifact distribution, optional)

**Resource Requirements**:
- vCPU: 8 (Artifactory is Java-based, CPU-intensive)
- RAM: 16GB minimum (32GB recommended for production)
- Disk: 1TB (multi-format artifacts require more space)
- Database: PostgreSQL 13+ (external or containerized)

### JFrog Advantages for Enterprise

1. **Universal Artifact Support**
   - Container images (Docker, OCI)
   - Helm charts
   - Maven/Gradle (Java)
   - NPM/Yarn (JavaScript)
   - PyPI (Python)
   - RPM/Debian packages
   - Generic binaries

2. **Advanced Metadata and Provenance**
   - Build info integration (CI/CD metadata)
   - Dependency graph and impact analysis
   - SBOM (Software Bill of Materials) generation
   - Artifact properties and labels

3. **Xray Integration**
   - Deep vulnerability scanning (all artifact types)
   - License compliance enforcement
   - Policy enforcement (block deployment of vulnerable artifacts)
   - Impact analysis (which builds are affected by a CVE)

4. **Multi-Site Replication**
   - Push replication (active)
   - Pull replication (on-demand)
   - Event-based replication triggers
   - Smart replication (delta sync)

### Implementation Status: 🟡 IN PROGRESS
- Airflow DAG: `airflow/dags/ocp_jfrog_agent_deployment.py` (exists in v4.20.0)
- AAP Job Template: To be created in Phase 3 (Task 3.5)
- Cloud-init template: To be created for JFrog VM
- JFrog CLI integration: Existing scripts in airflow/dags/
- Documentation: JFrog-specific setup guide needed

### Roadmap Tasks for JFrog Artifactory

#### Task J.1: Create JFrog VM Template
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 3 days  
**Dependencies**: Task 1.1 (Libvirt templates)

**Description**: Create `templates/libvirt/jfrog-vm.xml.j2` with JFrog-specific resources.

**Implementation**:
```xml
<!-- JFrog VM: 8 vCPU, 16GB RAM, 1TB disk -->
<domain type='kvm'>
  <name>{{ vm_name }}</name>
  <memory unit='MiB'>16384</memory>
  <vcpu>8</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='/var/lib/libvirt/images/jfrog-vm.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <source file='/var/lib/libvirt/images/jfrog-cloud-init.iso'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <source network='{{ vm_network }}'/>
      <model type='virtio'/>
    </interface>
  </devices>
</domain>
```

#### Task J.2: Create JFrog Cloud-Init Templates
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 2 days  
**Dependencies**: Task 1.2 (Cloud-init templates)

**Description**: Create cloud-init configs for automated JFrog VM setup.

**Files**:
- `templates/cloud-init/jfrog-user-data.yml.j2`
- `templates/cloud-init/jfrog-meta-data.yml.j2`
- `templates/cloud-init/jfrog-network-config.yml.j2`

**Key Cloud-Init Tasks**:
```yaml
#cloud-config
packages:
  - java-11-openjdk
  - postgresql-server
  - python3-pip

runcmd:
  # Initialize PostgreSQL
  - postgresql-setup --initdb
  - systemctl enable --now postgresql

  # Download JFrog Artifactory
  - wget https://releases.jfrog.io/artifactory/bintray-artifactory/org/artifactory/oss/jfrog-artifactory-oss/[RELEASE]/jfrog-artifactory-oss-[RELEASE]-linux.tar.gz
  - tar xvf jfrog-artifactory-oss-*.tar.gz -C /opt/
  - mv /opt/artifactory-oss-* /opt/artifactory

  # Configure Artifactory
  - /opt/artifactory/app/bin/installService.sh
  - systemctl enable --now artifactory.service

  # Install JFrog CLI
  - curl -fL https://getcli.jfrog.io | sh
  - mv jfrog /usr/local/bin/
```

#### Task J.3: Create playbooks/provision-jfrog-vm.yml
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 1 week  
**Dependencies**: Task 1.4 (reusable task), Task J.1, Task J.2

**Description**: Provision JFrog Artifactory VM using community.libvirt.

**Implementation**:
```yaml
---
- name: Provision JFrog Artifactory VM
  hosts: localhost
  gather_facts: yes
  vars:
    vm_name: "jfrog-artifactory"
    vm_memory: 16384
    vm_cpus: 8
    vm_disk_size: 1000  # 1TB
    vm_template: "templates/libvirt/jfrog-vm.xml.j2"
    cloud_init_user_data_template: "templates/cloud-init/jfrog-user-data.yml.j2"
    cloud_init_meta_data_template: "templates/cloud-init/jfrog-meta-data.yml.j2"
    cloud_init_network_config_template: "templates/cloud-init/jfrog-network-config.yml.j2"

  tasks:
    - name: Provision JFrog VM using reusable task
      ansible.builtin.include_tasks: tasks/provision-vm-libvirt.yml
```

#### Task J.4: Create docs/jfrog-registry-setup.md
**Status**: 🔴 NOT STARTED  
**Priority**: P3  
**Effort**: 3 days  
**Dependencies**: Task J.3

**Description**: Comprehensive JFrog Artifactory setup and integration guide.

**Content Outline**:
1. JFrog platform architecture overview
2. Installation and configuration
3. Repository types (local, remote, virtual)
4. User and permission management
5. Docker registry configuration
6. Xray vulnerability scanning setup
7. Replication configuration
8. OpenShift integration (ImageContentSourcePolicy)
9. oc-mirror + JFrog CLI integration for air-gapped sync
10. Build info and metadata tracking
11. Backup and recovery
12. Troubleshooting

#### Task J.5: JFrog HAProxy Configuration
**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Effort**: 1 day  
**Dependencies**: Task J.3

**Description**: Configure HAProxy on KVM host to route traffic to JFrog VM.

**HAProxy Config**:
```haproxy
# JFrog Artifactory HTTPS (web UI + registries)
frontend jfrog_https
    bind *:8082 ssl crt /etc/haproxy/certs/jfrog.pem
    default_backend jfrog_backend

backend jfrog_backend
    balance roundrobin
    server jfrog1 192.168.122.20:8082 check ssl verify none

# JFrog Docker Registry (separate port for oc-mirror)
frontend jfrog_docker
    bind *:5001
    default_backend jfrog_docker_backend

backend jfrog_docker_backend
    balance roundrobin
    server jfrog1 192.168.122.20:5001 check
```

---

## HAProxy Configuration Summary

**KVM Host HAProxy Routes** (all registries):

```haproxy
# /etc/haproxy/haproxy.cfg

global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# Quay/mirror-registry (port 5000)
frontend quay_registry
    bind *:5000
    default_backend quay_backend

backend quay_backend
    balance roundrobin
    server quay1 192.168.122.5:5000 check

# Harbor (port 8443 HTTPS, 8080 HTTP redirect)
frontend harbor_https
    bind *:8443 ssl crt /etc/haproxy/certs/harbor.pem
    default_backend harbor_backend

backend harbor_backend
    balance roundrobin
    server harbor1 192.168.122.10:443 check ssl verify none

frontend harbor_http
    bind *:8080
    redirect scheme https code 301

# JFrog Artifactory (port 8082 web UI, 5001 Docker registry)
frontend jfrog_https
    bind *:8082 ssl crt /etc/haproxy/certs/jfrog.pem
    default_backend jfrog_backend

backend jfrog_backend
    balance roundrobin
    server jfrog1 192.168.122.20:8082 check ssl verify none

frontend jfrog_docker
    bind *:5001
    default_backend jfrog_docker_backend

backend jfrog_docker_backend
    balance roundrobin
    server jfrog1 192.168.122.20:5001 check

# AAP Controller (port 8443 - shared with Harbor, separate via SNI or different IP)
# Note: For production, use separate IPs or SNI routing
frontend aap_https
    bind *:8444 ssl crt /etc/haproxy/certs/aap.pem
    default_backend aap_backend

backend aap_backend
    balance roundrobin
    server aap1 192.168.122.30:443 check ssl verify none

# OpenShift API (port 6443)
frontend ocp_api
    bind *:6443
    mode tcp
    default_backend ocp_api_backend

backend ocp_api_backend
    mode tcp
    balance roundrobin
    server ocp-master-0 192.168.122.100:6443 check
    server ocp-master-1 192.168.122.101:6443 check
    server ocp-master-2 192.168.122.102:6443 check

# OpenShift Console (port 443)
frontend ocp_console
    bind *:443 ssl crt /etc/haproxy/certs/ocp.pem
    default_backend ocp_console_backend

backend ocp_console_backend
    balance roundrobin
    server ocp-master-0 192.168.122.100:443 check ssl verify none
    server ocp-master-1 192.168.122.101:443 check ssl verify none
    server ocp-master-2 192.168.122.102:443 check ssl verify none

# HAProxy Stats (port 9000)
listen stats
    bind *:9000
    stats enable
    stats uri /
    stats refresh 10s
    stats admin if TRUE
```

---

## Decision Matrix: Choosing a Registry

### Selection Criteria

| Requirement | Recommended Registry |
|-------------|---------------------|
| **OpenShift-only deployment** | Quay/mirror-registry |
| **Budget-constrained** | mirror-registry (free) |
| **Need Helm chart repository** | Harbor or JFrog |
| **Multi-format artifacts (Maven, NPM, PyPI)** | JFrog Artifactory |
| **CNCF ecosystem preference** | Harbor |
| **Red Hat support requirement** | Quay (with subscription) |
| **Advanced SBOM and provenance** | JFrog Artifactory |
| **Simple, lightweight** | mirror-registry |
| **High availability requirement** | Quay or Harbor or JFrog |
| **Air-gapped sync** | All (oc-mirror support) |

### Quick Decision Tree

```
Do you need Maven/NPM/PyPI artifacts?
├─ YES → JFrog Artifactory
└─ NO
   ├─ Do you need Helm charts?
   │  ├─ YES → Harbor
   │  └─ NO
   │     ├─ Do you need HA/geo-replication?
   │     │  ├─ YES → Red Hat Quay
   │     │  └─ NO → mirror-registry
```

---

## Implementation Timeline

### Phase 1.5: Registry Configuration (Weeks 5-8, parallel with Phase 2)

**Task 1.5.1: HAProxy Setup on KVM Host**
- Status: 🔴 NOT STARTED
- Priority: P1 (BLOCKER for all registry configs)
- Effort: 1 week
- Deliverable: `playbooks/setup-haproxy.yml`

**Task 1.5.2: Quay/mirror-registry Configuration**
- Status: 🟢 READY (existing playbook)
- Priority: P1
- Effort: 1 day (documentation update)
- Deliverable: Update existing playbook for v4.21.0

**Task 1.5.3: Harbor Configuration**
- Status: 🔴 NOT STARTED
- Priority: P2
- Effort: 2 weeks
- Deliverable: Tasks H.1-H.5 complete

**Task 1.5.4: JFrog Configuration**
- Status: 🔴 NOT STARTED
- Priority: P2
- Effort: 2 weeks
- Deliverable: Tasks J.1-J.5 complete

### Parallel Execution

All three registry configurations can be implemented in parallel:
- Week 5: HAProxy setup (shared)
- Weeks 5-6: Quay/mirror-registry (simplest, validates HAProxy)
- Weeks 6-8: Harbor (moderate complexity)
- Weeks 6-8: JFrog (highest complexity)

---

## Testing Strategy

### Registry Validation Checklist

For each registry configuration:

- [ ] **Provisioning**: VM created via Ansible playbook
- [ ] **Installation**: Registry software installed and running
- [ ] **HAProxy**: Traffic routes correctly from host to VM
- [ ] **Web UI Access**: UI accessible via HAProxy (http://host-ip:port)
- [ ] **Image Push**: Can push test image via podman/docker
- [ ] **Image Pull**: Can pull test image via podman/docker
- [ ] **oc-mirror Integration**: Can sync OpenShift release images
- [ ] **ImageContentSourcePolicy**: OpenShift nodes use registry for pulls
- [ ] **SSL/TLS**: HTTPS enabled with valid certificates
- [ ] **Authentication**: User login works (UI + CLI)
- [ ] **RBAC**: Permissions enforced correctly
- [ ] **Vulnerability Scanning**: CVE scanning works (Harbor/JFrog)
- [ ] **Backup/Restore**: Backup procedure validated
- [ ] **Monitoring**: Prometheus metrics exposed (if applicable)

### oc-mirror Test Plan

Test oc-mirror sync for each registry:

```bash
# Test 1: Full OpenShift release mirror
oc-mirror --config=imageset-config.yaml docker://HOST_IP:PORT

# Test 2: Operator catalog mirror
oc-mirror --config=operator-catalog.yaml docker://HOST_IP:PORT

# Test 3: Incremental update
oc-mirror --continue-on-error docker://HOST_IP:PORT
```

Expected results:
- All images synced successfully
- ImageContentSourcePolicy YAML generated
- Catalog sources created for operators
- Disconnected cluster can install operators

---

## Migration Path Between Registries

Organizations may want to switch registries over time:

### mirror-registry → Quay
**Reason**: Need HA, geo-replication, advanced features  
**Complexity**: Low (same vendor)  
**Migration**: Export images, import to Quay, update ICSP

### mirror-registry → Harbor
**Reason**: Need Helm charts, Trivy scanning  
**Complexity**: Medium (different platform)  
**Migration**: Use Harbor replication (pull from mirror-registry)

### Quay/Harbor → JFrog
**Reason**: Consolidate all artifact types  
**Complexity**: High (different platform + multi-format)  
**Migration**: JFrog can proxy/replicate from Quay/Harbor

---

## Cost Considerations

### Operating Costs (Annual)

| Registry | License | Support | Infrastructure | Total |
|----------|---------|---------|----------------|-------|
| **mirror-registry** | Free | Community | VM costs only | ~$100-500/year |
| **Red Hat Quay** | $5k-15k/year | Included | VM + database | ~$7k-20k/year |
| **Harbor** | Free | Community | VM + database | ~$500-2k/year |
| **JFrog Artifactory OSS** | Free | Community | VM + database | ~$1k-3k/year |
| **JFrog Artifactory Pro** | $10k-50k/year | Included | VM + database | ~$12k-60k/year |

**Note**: Infrastructure costs assume cloud VM pricing. On-prem costs are fixed (one-time hardware purchase).

### Resource Costs (Monthly, Cloud VMs)

| Registry | vCPU | RAM | Disk | Estimated Cost (AWS) |
|----------|------|-----|------|---------------------|
| mirror-registry | 2 | 4GB | 500GB | ~$50/month |
| Quay | 4 | 8GB | 500GB | ~$100/month |
| Harbor | 4 | 8GB | 500GB | ~$100/month |
| JFrog | 8 | 16GB | 1TB | ~$250/month |

---

## Recommended Configuration by Deployment Size

### Small Deployment (1-3 OpenShift clusters)
**Recommended**: mirror-registry  
**Why**: Low cost, simple, sufficient for container-only workloads

### Medium Deployment (4-10 OpenShift clusters)
**Recommended**: Harbor  
**Why**: Helm chart support, Trivy scanning, still open-source

### Large Deployment (10+ OpenShift clusters)
**Recommended**: Red Hat Quay or JFrog Artifactory  
**Why**: HA, geo-replication, enterprise support

### Multi-Artifact Enterprise
**Recommended**: JFrog Artifactory  
**Why**: Universal artifact management, advanced metadata, SBOM generation

---

## Next Steps

### Immediate (Phase 0-1)
1. ✅ Complete Task 0.4: Cockpit + Libvirt setup
2. 🔴 Execute Task 1.5.1: HAProxy setup on KVM host (NEW)
3. 🟢 Execute Task 1.5.2: Validate existing mirror-registry playbook

### Short-Term (Phase 1-2, Weeks 5-8)
4. 🔴 Execute Task H.1-H.5: Harbor configuration (parallel)
5. 🔴 Execute Task J.1-J.5: JFrog configuration (parallel)

### Long-Term (Phase 4, Post-v4.21.0)
6. Publish registry comparison whitepaper
7. Create registry migration guides
8. Develop automated registry health checks
9. Build registry failover automation

---

## References

1. **Red Hat Quay Documentation**  
   https://access.redhat.com/documentation/en-us/red_hat_quay/

2. **mirror-registry for Red Hat OpenShift**  
   https://docs.openshift.com/container-platform/4.14/installing/disconnected_install/installing-mirroring-installation-images.html

3. **Harbor Documentation**  
   https://goharbor.io/docs/

4. **JFrog Artifactory Documentation**  
   https://jfrog.com/help/r/jfrog-artifactory-documentation

5. **oc-mirror Plugin Documentation**  
   https://docs.openshift.com/container-platform/4.14/installing/disconnected_install/installing-mirroring-disconnected.html

6. **ImageContentSourcePolicy**  
   https://docs.openshift.com/container-platform/4.14/openshift_images/image-configuration.html

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-02  
**Status**: 🗺️ ROADMAP (Planning)  
**Next Review**: After Phase 1 completion
