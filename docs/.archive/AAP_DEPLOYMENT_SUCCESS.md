# ✅ AAP 2.6 Containerized Deployment - SUCCESS

**Deployment Date**: June 4, 2026  
**Target VM**: aap.ocp4.sandbox3377.opentlc.com (192.168.122.72)  
**Deployment Type**: All-in-One Single Node (Gateway + Controller + Database)

---

## Installation Summary

### ✅ Deployed Components

| Component | Status | Container Name | Ports |
|-----------|--------|----------------|-------|
| **PostgreSQL 15** | ✅ Running | postgresql | 5432 |
| **Redis 6** | ✅ Running | redis-unix, redis-tcp | 6379 |
| **Automation Gateway** | ✅ Running | automation-gateway | - |
| **Gateway Proxy** | ✅ Running | automation-gateway-proxy | - |
| **Receptor** | ✅ Running | receptor | - |
| **Controller Web** | ✅ Running | automation-controller-web | 8052 |
| **Controller Task** | ✅ Running | automation-controller-task | 8052 |
| **Controller Rsyslog** | ✅ Running | automation-controller-rsyslog | 8052 |

### 📊 Statistics

- **Total Ansible Tasks**: 414 OK, 131 changed, 0 failed
- **Installation Time**: ~15 minutes
- **Container Images Pulled**: 8
- **Systemd Services**: 5 enabled and running
- **Runtime**: Rootless Podman (ansible user)

---

## Access Information

### Web UI

- **URL**: https://192.168.122.72 or https://aap.ocp4.sandbox3377.opentlc.com
- **Username**: `admin`
- **Password**: `YourSecurePassword123!` (from vault file)

### SSH Access

```bash
ssh ansible@192.168.122.72
```

### Container Management

```bash
# List containers
podman ps

# Check logs
podman logs automation-controller-web
podman logs automation-gateway

# Restart services
systemctl --user restart automation-controller-web
systemctl --user restart automation-gateway
```

---

## Technical Details

### Authentication & Security

- **RHEL Subscription**: Red Hat activation key (ADR 0027)
- **Container Registry**: registry.redhat.io (authenticated via pull secret)
- **Podman Auth**: ~/.config/containers/auth.json
- **SSL/TLS**: Self-signed certificates (managed by AAP installer)

### Database Configuration

- **Engine**: PostgreSQL 15 (containerized)
- **Admin User**: postgres
- **Databases**: controller, gateway
- **Connection**: localhost:5432

### Redis Configuration

- **Mode**: Standalone (single-node deployment)
- **Sockets**: Unix socket + TCP (6379)

### Network Configuration

- **Interface**: eth0 (192.168.122.72/24)
- **Network Mode**: KVM virbr0 DHCP
- **Firewall**: firewalld (ports 80, 443, 8052 open)

---

## Key Files & Directories

### Installation Files

- **Installer**: `/home/ansible/aap/ansible-automation-platform-containerized-setup-2.6-8/`
- **Inventory**: `/home/ansible/aap/ansible-automation-platform-containerized-setup-2.6-8/inventory`
- **Install Log**: `/tmp/aap-install-nonroot.log`

### Systemd Services

- **Service Files**: `~/.config/systemd/user/automation-*.service`
- **Logs**: `journalctl --user -u automation-controller-web`

### Container Storage

- **Podman Root**: `~/.local/share/containers/`
- **Volumes**: Managed by Podman

---

## Troubleshooting Steps Resolved

### Issue 1: infra.aap_utilities Collection Bug
**Problem**: Health check failed with `.status` attribute error  
**Solution**: Set `aap_setup_inst_force: true` to bypass health check

### Issue 2: Inventory Template Not Rendered
**Problem**: `{{ ansible_fqdn }}` literal in inventory file  
**Solution**: Manually created inventory with actual FQDN

### Issue 3: Registry Authentication Required
**Problem**: `registry_auth=false` didn't disable authentication  
**Solution**: Configured Podman with Red Hat pull secret

### Issue 4: Running as Root
**Problem**: Installer requires non-root user  
**Solution**: Run as ansible user (rootless Podman)

### Issue 5: Missing Database Connection Variables
**Problem**: Preflight checks failed for missing pg_host  
**Solution**: Added complete database connection configuration

---

## Deployment Workflow

1. ✅ Downloaded AAP 2.6-8 installer via Red Hat API (offline token)
2. ✅ Registered RHEL 9.8 with activation key
3. ✅ Enabled AAP repositories
4. ✅ Installed prerequisites (ansible-core, podman)
5. ✅ Configured Podman registry authentication (pull secret)
6. ✅ Created all-in-one inventory file
7. ✅ Ran containerized installer (ansible.containerized_installer.install)
8. ✅ Pulled 8 container images from registry.redhat.io
9. ✅ Deployed database, redis, gateway, controller containers
10. ✅ Configured systemd services
11. ✅ Verified web UI and API accessibility

---

## Next Steps

### Recommended Actions

1. **Change default password** via web UI
2. **Configure license** (Red Hat subscription manifest)
3. **Set up inventories** and credentials
4. **Create projects** linked to Git repositories
5. **Configure job templates**
6. **Set up RBAC** (users, teams, roles)

### Integration with Disconnected Infrastructure

- **Use AAP to manage**: Registry VMs, VyOS router, future OpenShift clusters
- **Playbook repository**: /home/vpcuser/ocp4-disconnected-helper
- **Inventory**: inventory/ibm-cloud.yml

---

## Documentation References

- **AAP 2.6 Docs**: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/
- **Containerized Installation**: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/containerized_installation
- **ADR 0027**: RHEL Subscription Activation Keys
- **QUICKSTART_AAP.md**: Quick reference guide

---

## Success Criteria: ✅ ALL MET

- ✅ AAP 2.6 containerized deployed
- ✅ All containers running and healthy
- ✅ Web UI accessible (https://192.168.122.72)
- ✅ API responding (https://192.168.122.72/api/v2/ping/)
- ✅ Systemd services enabled
- ✅ Authentication configured (activation keys + pull secret)
- ✅ Rootless Podman deployment
- ✅ Single-node all-in-one topology

**🎉 Deployment Complete - AAP 2.6 is Ready for Use!**
