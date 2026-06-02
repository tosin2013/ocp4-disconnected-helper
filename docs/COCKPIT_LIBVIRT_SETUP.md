# Cockpit + Libvirt Setup for Headless KVM Management

**Approach**: Use **Cockpit web console** for libvirt/KVM management on headless servers.

**Reference**: [OpenShift Agent Install - Developer Guide](https://tosin2013.github.io/openshift-agent-install/developer-guide.html) - proven approach.

---

## Why Cockpit?

### ✅ Advantages

- **Web-based GUI**: Access via browser (no X11/virt-manager needed)
- **Remote access**: Manage VMs from laptop/desktop browser
- **Proven approach**: Used successfully in openshift-agent-install project
- **Multi-purpose**: Also useful for OpenShift deployment monitoring
- **Lightweight**: Low overhead, runs on server
- **Integrated**: Native RHEL/CentOS tool (Red Hat Cockpit)

### ❌ What It Replaces

- ~~virt-manager~~ (requires X11, GUI desktop)
- ~~VNC/SPICE viewers~~ (requires desktop client)
- Pure CLI approach (still works, but Cockpit adds convenience)

---

## Installation

### Step 1: Install Cockpit + Libvirt Plugin

```yaml
# Updated playbooks/setup-dependencies.yml
---
- name: Install ocp4-disconnected-helper Dependencies (with Cockpit)
  hosts: localhost
  become: yes
  
  tasks:
    - name: Ensure system is RHEL/CentOS Stream 9.4+
      ansible.builtin.assert:
        that:
          - ansible_distribution in ['RedHat', 'CentOS']
          - ansible_distribution_major_version | int >= 9
        fail_msg: "This playbook requires RHEL/CentOS Stream 9.4 or later"
    
    - name: Install base packages
      ansible.builtin.dnf:
        name:
          # Ansible
          - ansible-core
          - python3-pip
          
          # Libvirt/KVM (headless stack)
          - libvirt
          - libvirt-client          # virsh CLI
          - qemu-kvm                 # KVM hypervisor
          - virt-install             # CLI VM installer
          - python3-libvirt          # Python bindings
          - genisoimage              # Cloud-init ISOs
          - qemu-img                 # Disk management
          
          # Cockpit (web-based management)
          - cockpit                  # Core web console
          - cockpit-machines         # VM management plugin
          - cockpit-storaged         # Storage management
          
          # Utilities
          - wget
          - curl
          - git
        state: present
    
    - name: Enable and start libvirtd
      ansible.builtin.systemd:
        name: libvirtd
        enabled: yes
        state: started
    
    - name: Enable and start Cockpit
      ansible.builtin.systemd:
        name: cockpit.socket
        enabled: yes
        state: started
    
    - name: Open firewall for Cockpit (port 9090)
      ansible.posix.firewalld:
        port: 9090/tcp
        permanent: yes
        state: enabled
        immediate: yes
      when: ansible_facts.services['firewalld.service'] is defined
    
    - name: Install Ansible collections
      ansible.builtin.command:
        cmd: ansible-galaxy collection install community.libvirt ansible.posix
      changed_when: false
    
    - name: Create ocp4-disconnected-helper directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - /var/lib/libvirt/images
        - /opt/ocp4-disconnected-helper
        - /opt/ocp4-disconnected-helper/logs
    
    - name: Verify libvirt connection
      community.libvirt.virt:
        command: list_vms
      register: libvirt_test
    
    - name: Get server IP address
      ansible.builtin.set_fact:
        server_ip: "{{ ansible_default_ipv4.address }}"
    
    - name: Display setup summary
      ansible.builtin.debug:
        msg:
          - "✅ ocp4-disconnected-helper dependencies installed successfully"
          - "✅ Libvirt connection: {{ libvirt_test.list_vms | length }} VMs found"
          - "✅ Cockpit web console: http://{{ server_ip }}:9090"
          - ""
          - "🌐 Access Cockpit:"
          - "   URL: http://{{ server_ip }}:9090"
          - "   Username: {{ ansible_user_id }}"
          - "   Password: [your system password]"
          - ""
          - "📖 Navigate to: Virtual Machines → Create VM"
          - ""
          - "Next step: Run playbooks to deploy infrastructure"
```

---

## Step 2: Access Cockpit Web Console

After installation:

1. **Open browser** on your laptop/desktop:
   ```
   http://<server-ip>:9090
   ```

2. **Login** with your system credentials:
   - Username: Your SSH username (e.g., `vpcuser`)
   - Password: Your system password

3. **Navigate to Virtual Machines**:
   - Left sidebar → **Virtual Machines**
   - Click **Create VM** to see the interface

---

## VM Management Workflows

### Via Cockpit Web UI

#### Create VM (GUI):
1. Virtual Machines → **Create VM**
2. Fill in details:
   - Name: `registry-vm`
   - Installation source: **Local install media** (ISO)
   - Operating system: RHEL 9
   - Storage: 60 GB
   - Memory: 8 GB
3. Click **Create**

#### Manage VM (GUI):
- **Start/Stop**: Click VM → Start/Stop button
- **Console**: Click VM → Console (VNC in browser)
- **Edit**: Click VM → Edit (change RAM, CPU, disks)
- **Delete**: Click VM → Delete

---

### Via CLI (Ansible/virsh)

**Cockpit and CLI work together** - VMs created via Ansible appear in Cockpit GUI.

#### Create VM (CLI - Ansible):
```yaml
- name: Create VM (appears in Cockpit)
  community.libvirt.virt:
    command: define
    xml: "{{ lookup('template', 'templates/libvirt/registry-vm.xml.j2') }}"

- name: Start VM
  community.libvirt.virt:
    name: registry-vm
    state: running
```

**Result**: VM appears in Cockpit → Virtual Machines list automatically.

---

## Hybrid Approach (Recommended)

**Best practice**: Use both Cockpit and Ansible:

| Task | Tool | Why |
|------|------|-----|
| **Create VMs** | Ansible playbooks | Automated, reproducible, version-controlled |
| **Monitor VMs** | Cockpit GUI | Visual dashboard, resource graphs |
| **Debug VMs** | Cockpit console | Browser-based VNC access |
| **Quick edits** | Cockpit GUI | Fast RAM/CPU adjustments |
| **Production** | Ansible playbooks | Consistent, tested deployments |

---

## Integration with v4.21.0 Migration

### Updated Task 0.4: Cockpit + Libvirt Validation

```bash
# Quick validation playbook
cat > playbooks/validate-cockpit-libvirt.yml <<'EOF'
---
- name: Validate Cockpit + Libvirt Setup
  hosts: localhost
  become: yes
  
  tasks:
    - name: Check Cockpit is running
      ansible.builtin.systemd:
        name: cockpit.socket
        state: started
      register: cockpit_status
    
    - name: Check libvirtd is running
      ansible.builtin.systemd:
        name: libvirtd
        state: started
      register: libvirt_status
    
    - name: Test virsh CLI
      ansible.builtin.command:
        cmd: virsh list --all
      register: virsh_test
      changed_when: false
    
    - name: Test community.libvirt collection
      community.libvirt.virt:
        command: list_vms
      register: libvirt_collection_test
    
    - name: Get server IP
      ansible.builtin.set_fact:
        server_ip: "{{ ansible_default_ipv4.address }}"
    
    - name: Display validation results
      ansible.builtin.debug:
        msg:
          - "✅ Cockpit Status: {{ cockpit_status.status.ActiveState }}"
          - "✅ Libvirt Status: {{ libvirt_status.status.ActiveState }}"
          - "✅ virsh CLI: {{ virsh_test.stdout_lines | length }} VMs"
          - "✅ community.libvirt: {{ libvirt_collection_test.list_vms | length }} VMs"
          - ""
          - "🌐 Cockpit URL: http://{{ server_ip }}:9090"
          - ""
          - "✅ VALIDATION PASSED - Ready for Phase 1"
EOF

ansible-playbook playbooks/validate-cockpit-libvirt.yml
```

**Success Criteria**:
- [x] Cockpit accessible at http://server-ip:9090
- [x] Virtual Machines tab shows in Cockpit
- [x] `virsh list` works
- [x] `community.libvirt` collection works
- [x] Can create test VM via GUI or CLI

---

## Cockpit Features for OpenShift Deployment

**Future benefit**: Cockpit will be useful when deploying OpenShift (per openshift-agent-install guide):

### OCP Node Monitoring:
- **Resource usage**: CPU, RAM, network per VM
- **Console access**: Troubleshoot bootstrap/master/worker nodes
- **Quick restart**: Fix hung nodes without SSH
- **Storage view**: Monitor disk usage during image pulls

### Network Debugging:
- **Network graphs**: Traffic per VM
- **Bridge inspection**: Verify OCP network connectivity
- **Firewall rules**: Cockpit firewall GUI

### Multi-VM Dashboard:
- **All nodes visible**: Bootstrap, 3 masters, 2+ workers
- **Health at a glance**: Which VMs are running
- **Resource totals**: Aggregate RAM/CPU usage

---

## Security Considerations

### Cockpit Access Control:

```bash
# Restrict Cockpit to specific IP (optional)
sudo firewall-cmd --zone=public --add-rich-rule='
  rule family="ipv4"
  source address="192.168.1.0/24"
  port protocol="tcp" port="9090" accept'
```

### SSL/TLS (Production):

```bash
# Enable HTTPS (Cockpit auto-generates self-signed cert)
# Access via: https://server-ip:9090

# For custom cert:
sudo cp your-cert.pem /etc/cockpit/ws-certs.d/
sudo systemctl restart cockpit
```

---

## Troubleshooting

### Cockpit not accessible:

```bash
# Check service
sudo systemctl status cockpit.socket

# Check firewall
sudo firewall-cmd --list-ports | grep 9090

# Manual firewall open
sudo firewall-cmd --add-port=9090/tcp --permanent
sudo firewall-cmd --reload
```

### Virtual Machines tab missing:

```bash
# Install VM plugin
sudo dnf install cockpit-machines

# Restart Cockpit
sudo systemctl restart cockpit
```

### VMs not showing in Cockpit:

```bash
# Check libvirtd
sudo systemctl status libvirtd

# Cockpit uses system connection (qemu:///system)
virsh --connect qemu:///system list --all
```

---

## Updated Phase 1 Workflow

With Cockpit + HAProxy installed:

### 1. **Install HAProxy on KVM host** (load balancer)
```bash
ansible-playbook playbooks/setup-haproxy.yml
```

HAProxy runs **on the host**, not in a VM. It routes traffic:
- `http://host-ip:5000` → Quay registry VM
- `https://host-ip:8443` → AAP controller VM
- `https://host-ip:443` → OpenShift API/console VMs

### 2. **Create VMs via Ansible** (automated)
```bash
ansible-playbook playbooks/provision-registry-vm.yml
ansible-playbook playbooks/provision-aap-vm.yml
ansible-playbook playbooks/provision-ocp-nodes-vms.yml
```

### 3. **Monitor in Cockpit** (visual)
- Open http://server-ip:9090
- Navigate to Virtual Machines
- See all VMs running with resource graphs

### 4. **Access services via HAProxy** (no VM direct access)
- Quay web UI: `http://host-ip:5000`
- AAP web UI: `https://host-ip:8443`
- OpenShift console: `https://host-ip:443`

### 5. **Debug if needed** (GUI console)
- Click VM → Console
- Browser-based VNC access (no SSH needed)
- View boot logs, cloud-init output

### 6. **Quick adjustments** (GUI)
- Need more RAM? → Edit VM → Change memory → Restart
- No playbook edit needed for one-off changes

---

## Comparison: Cockpit vs Pure Headless

| Feature | Pure Headless (CLI only) | Cockpit + CLI |
|---------|-------------------------|---------------|
| **VM Creation** | `virt-install` or Ansible | Same + GUI option ✅ |
| **VM Monitoring** | `virsh list`, manual checks | Visual dashboard ✅ |
| **Console Access** | `virsh console` (serial) | Browser VNC ✅ |
| **Resource Graphs** | Manual (top, virsh domstats) | Built-in graphs ✅ |
| **Learning Curve** | Steep (XML, virsh commands) | Gentle (GUI + CLI) ✅ |
| **Remote Access** | SSH only | SSH + Web UI ✅ |
| **Automation** | ✅ Full Ansible support | ✅ Same (Cockpit doesn't interfere) |
| **X11 Required** | ❌ No | ❌ No |
| **OCP Deployment** | CLI only | GUI monitoring ✅ |

**Winner**: Cockpit + CLI (best of both worlds)

---

## References

1. **OpenShift Agent Install - Developer Guide**  
   https://tosin2013.github.io/openshift-agent-install/developer-guide.html  
   → Proven Cockpit + libvirt approach

2. **HAProxy Forwarder Guide**  
   https://tosin2013.github.io/openshift-agent-install/haproxy-forwarder-guide/  
   → Headless VM management patterns

3. **Cockpit Project**  
   https://cockpit-project.org/  
   → Official documentation

4. **Red Hat Cockpit Documentation**  
   https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_systems_using_the_rhel_9_web_console/  
   → RHEL-specific guide

---

**Created**: 2026-06-02  
**Approach**: Cockpit web console (recommended)  
**Next**: Update Task 0.4 to validate Cockpit + libvirt setup
