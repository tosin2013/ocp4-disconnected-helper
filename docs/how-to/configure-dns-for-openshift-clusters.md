# How to Configure DNS for OpenShift Clusters

This guide explains DNS configuration options for OpenShift cluster deployment using the Agent-Based Installer.

## DNS Provider Options

The `openshift_cluster_deploy` role supports three DNS providers:

| Provider | Use Case | Requirements | Automation |
|----------|----------|--------------|------------|
| **dnsmasq** | Local development, lab environments | dnsmasq package, sudo access | Fully automated |
| **route53** | Production AWS deployments | AWS credentials, Route53 hosted zone | Fully automated |
| **none** | External DNS, corporate DNS servers | Manual configuration | Instructions only |

---

## Option 1: dnsmasq (Local Development)

**Best for**: Lab environments, local testing, disconnected deployments

### Prerequisites

```bash
# Install dnsmasq (if not already installed)
sudo dnf install -y dnsmasq

# Enable and start dnsmasq
sudo systemctl enable --now dnsmasq
```

### Configuration

Set `dns_provider: "dnsmasq"` in your cluster configuration:

```yaml
# extra_vars/cluster-configs/my-cluster.yml
dns_provider: "dnsmasq"
```

### What It Does

The role automatically:
1. Installs dnsmasq (if needed)
2. Creates `/etc/dnsmasq.d/openshift-<cluster_name>.conf`
3. Configures DNS records:
   - `api.<cluster>.example.com` → API VIP
   - `*.apps.<cluster>.example.com` → Ingress VIP
   - Node records (for compact/HA)
4. Restarts dnsmasq service
5. Validates DNS resolution

### DNS Records Created

**SNO**:
```
api.ocp4-sno.sandbox3377.opentlc.com → 192.168.10.10
*.apps.ocp4-sno.sandbox3377.opentlc.com → 192.168.10.10
```

**Compact (3-node)**:
```
api.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.20
*.apps.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.21
master-0.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.30
master-1.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.31
master-2.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.32
```

**HA (3 control + 3 workers)**:
```
api.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.40
*.apps.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.41
master-0.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.50
master-1.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.51
master-2.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.52
worker-0.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.60
worker-1.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.61
worker-2.ocp4-ha.sandbox3377.opentlc.com → 192.168.10.62
```

### Testing

```bash
# Test API endpoint
dig api.ocp4-sno.sandbox3377.opentlc.com @127.0.0.1

# Test apps wildcard
dig test.apps.ocp4-sno.sandbox3377.opentlc.com @127.0.0.1

# Test node record (compact/HA)
dig master-0.ocp4-compact.sandbox3377.opentlc.com @127.0.0.1
```

### Advanced Options

```yaml
# Optional: Custom upstream DNS servers
dns_upstream_servers:
  - "8.8.8.8"
  - "8.8.4.4"

# Optional: Enable query logging
dns_enable_logging: true

# Optional: Cache size (default 1000)
dns_cache_size: 2000
```

---

## Option 2: Route53 (Production AWS)

**Best for**: Production deployments on AWS, public cloud environments

### Prerequisites

```bash
# Install AWS CLI
pip install awscli
# or
sudo dnf install -y awscli

# Configure AWS credentials
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json

# Verify credentials
aws sts get-caller-identity
```

### Route53 Hosted Zone

You must have a Route53 hosted zone for your base domain:

```bash
# List hosted zones
aws route53 list-hosted-zones

# Example output:
# {
#   "HostedZones": [
#     {
#       "Id": "/hostedzone/Z1234567890ABC",
#       "Name": "sandbox3377.opentlc.com."
#     }
#   ]
# }
```

### Configuration

Set `dns_provider: "route53"` in your cluster configuration:

```yaml
# extra_vars/cluster-configs/my-cluster.yml
dns_provider: "route53"
base_domain: "sandbox3377.opentlc.com"

# Optional: Provide zone ID directly (otherwise auto-discovered)
route53_zone_id: "Z1234567890ABC"

# Optional: Custom TTL (default 300 seconds)
route53_ttl: 600
```

### What It Does

The role automatically:
1. Validates AWS CLI and credentials
2. Discovers Route53 hosted zone ID (if not provided)
3. Generates Route53 change batch JSON
4. Creates/updates DNS records via `aws route53 change-resource-record-sets`
5. Waits for changes to propagate (INSYNC)
6. Validates DNS resolution

### DNS Records Created

Same structure as dnsmasq, but in Route53:
- A records for API and node hostnames
- Wildcard A record for apps (e.g., `*.apps.ocp4.example.com`)

### Testing

```bash
# Test with public DNS
dig api.ocp4-sno.sandbox3377.opentlc.com

# Test apps wildcard
dig test.apps.ocp4-sno.sandbox3377.opentlc.com
```

### Troubleshooting

**Error: "Unable to locate credentials"**
```bash
# Re-run aws configure
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
```

**Error: "Hosted zone not found"**
```bash
# Verify zone exists
aws route53 list-hosted-zones

# Provide zone ID explicitly
route53_zone_id: "Z1234567890ABC"
```

---

## Option 3: Manual DNS (none)

**Best for**: Corporate DNS servers, external DNS providers

### Configuration

Set `dns_provider: "none"`:

```yaml
dns_provider: "none"
```

### Manual DNS Configuration Required

The role will display instructions but will NOT configure DNS automatically. You must manually create:

**SNO**:
```
A record: api.ocp4-sno.sandbox3377.opentlc.com → 192.168.10.10
A record: *.apps.ocp4-sno.sandbox3377.opentlc.com → 192.168.10.10
```

**Compact**:
```
A record: api.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.20
A record: *.apps.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.21
A record: master-0.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.30
A record: master-1.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.31
A record: master-2.ocp4-compact.sandbox3377.opentlc.com → 192.168.10.32
```

**HA**: Same as compact + worker node records

---

## DNS Requirements by Topology

### SNO (Single-Node OpenShift)
- **Minimum**: 2 DNS records
  - API endpoint (`api.<cluster>.<domain>`)
  - Apps wildcard (`*.apps.<cluster>.<domain>`)
- **VIPs**: Single IP for both API and Ingress

### Compact (3-Node)
- **Minimum**: 5 DNS records
  - API endpoint
  - Apps wildcard
  - 3 control plane node records
- **VIPs**: Separate API and Ingress VIPs

### HA (3 Control + 2+ Workers)
- **Minimum**: 7+ DNS records
  - API endpoint
  - Apps wildcard
  - 3 control plane node records
  - 2+ worker node records
- **VIPs**: Separate API, Ingress, and node IPs

---

## Testing DNS Configuration

```bash
# Run DNS configuration test playbook
ansible-playbook playbooks/test-dns-configuration.yml

# Test specific provider
ansible-playbook playbooks/test-dns-configuration.yml --tags dnsmasq
```

---

## Integration with Cluster Deployment

DNS configuration runs automatically during cluster deployment:

```bash
# Full deployment (includes DNS as Phase 4)
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-quay.yml

# DNS configuration only (Phase 4)
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-quay.yml \
  --tags dns,phase4
```

---

## See Also

- [OpenShift DNS Operator Documentation](https://docs.openshift.com/container-platform/4.21/networking/dns-operator.html)
- [Agent-Based Installer Guide](https://docs.openshift.com/container-platform/4.21/installing/installing_with_agent_based_installer/installing-with-agent-based-installer.html)
- ADR-0035: Adopt OpenShift Agent-Based Installer
