# HAProxy External URL Support

**Purpose**: Configure HAProxy to support both on-premise (direct IP) and cloud deployments (external DNS/URLs).

**Status**: 📋 PLANNING  
**Last Updated**: 2026-06-02  
**Reference**: [IBM Cloud Deployment Guide](https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html)

---

## Deployment Scenarios

### Scenario 1: On-Premise (Direct IP Access)

**Pattern**: Direct IP access to KVM host  
**Example**: `http://10.241.64.9:5000`

```
User → KVM Host IP → HAProxy → VM
```

**Use Cases**:
- Lab environments
- Internal corporate networks
- Air-gapped deployments
- Development/testing

**DNS**: Optional (can use /etc/hosts or no DNS)

---

### Scenario 2: Cloud with External URL (IBM Cloud, AWS, Azure)

**Pattern**: External DNS/hostname with cloud load balancer  
**Example**: `https://ocp-registry.apps.example.com`

```
User → External DNS → Cloud LB → KVM Host → HAProxy → VM
     (internet)        (public IP)   (private IP)
```

**Use Cases**:
- IBM Cloud VSI deployments
- AWS EC2 deployments
- Azure VM deployments
- Any cloud with public networking

**DNS**: Required (cloud provider DNS or external)

**Reference**: [IBM Cloud Deployment - DNS Configuration](https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html)

---

## IBM Cloud Deployment Pattern

### Architecture (from openshift-agent-install guide)

**IBM Cloud Resources**:
- **VSI (Virtual Server Instance)**: Runs KVM host
- **Floating IP**: Public IP attached to VSI
- **DNS Records**: Point to Floating IP
- **Security Groups**: Allow ports 80, 443, 5000, 6443, 8443, 9090

**DNS Examples** (from IBM Cloud guide):
```
api.ocp.example.com          → Floating IP (OpenShift API)
*.apps.ocp.example.com       → Floating IP (OpenShift routes)
registry.ocp.example.com     → Floating IP (Quay registry)
aap.example.com              → Floating IP (AAP web UI)
cockpit.example.com          → Floating IP (Cockpit)
```

**HAProxy Role**:
- Terminates SSL/TLS (using Let's Encrypt or custom certs)
- Routes by hostname (SNI) to correct backend VM
- Provides single entry point for all services

---

## HAProxy Configuration: Flexible URL Support

### Variables for Deployment Type

```yaml
# inventory/group_vars/all.yml

# Deployment type: onprem or cloud
deployment_type: "cloud"  # or "onprem"

# External URLs (for cloud deployments)
external_domain: "example.com"
ocp_cluster_name: "ocp"

# Service URLs
quay_url: "registry.{{ ocp_cluster_name }}.{{ external_domain }}"     # registry.ocp.example.com
aap_url: "aap.{{ external_domain }}"                                  # aap.example.com
ocp_api_url: "api.{{ ocp_cluster_name }}.{{ external_domain }}"      # api.ocp.example.com
ocp_apps_url: "*.apps.{{ ocp_cluster_name }}.{{ external_domain }}"  # *.apps.ocp.example.com
cockpit_url: "cockpit.{{ external_domain }}"                          # cockpit.example.com

# SSL/TLS
ssl_cert_provider: "letsencrypt"  # or "selfsigned" or "custom"
letsencrypt_email: "admin@example.com"

# Internal VM IPs (backends)
quay_vm_ip: "192.168.122.5"
aap_vm_ip: "192.168.122.30"
ocp_master_ips:
  - "192.168.122.100"
  - "192.168.122.101"
  - "192.168.122.102"
```

### HAProxy Configuration Template

**File**: `templates/haproxy/haproxy.cfg.j2`

```jinja2
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    
    # SSL/TLS
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  http-server-close
    option  forwardfor except 127.0.0.0/8
    timeout connect 5000
    timeout client  50000
    timeout server  50000

{% if deployment_type == 'cloud' %}
#
# CLOUD DEPLOYMENT MODE: SNI-based routing
#

# Quay Registry (HTTPS with SNI)
frontend quay_https
    bind *:443 ssl crt /etc/haproxy/certs/{{ quay_url }}.pem
    http-request set-header X-Forwarded-Proto https
    acl is_quay hdr(host) -i {{ quay_url }}
    use_backend quay_backend if is_quay

backend quay_backend
    balance roundrobin
    option httpchk GET /health HTTP/1.1\r\nHost:\ {{ quay_url }}
    server quay1 {{ quay_vm_ip }}:443 check ssl verify none

# AAP Controller (HTTPS with SNI)
frontend aap_https
    bind *:443 ssl crt /etc/haproxy/certs/{{ aap_url }}.pem
    http-request set-header X-Forwarded-Proto https
    acl is_aap hdr(host) -i {{ aap_url }}
    use_backend aap_backend if is_aap

backend aap_backend
    balance roundrobin
    option httpchk GET /api/v2/ping/ HTTP/1.1\r\nHost:\ {{ aap_url }}
    server aap1 {{ aap_vm_ip }}:443 check ssl verify none

# OpenShift API (TCP mode, no SNI needed)
frontend ocp_api
    bind *:6443
    mode tcp
    option tcplog
    default_backend ocp_api_backend

backend ocp_api_backend
    mode tcp
    balance roundrobin
{% for ip in ocp_master_ips %}
    server ocp-master-{{ loop.index0 }} {{ ip }}:6443 check
{% endfor %}

# OpenShift Console/Routes (HTTPS with wildcard SNI)
frontend ocp_apps_https
    bind *:443 ssl crt /etc/haproxy/certs/{{ ocp_cluster_name }}.{{ external_domain }}.pem
    http-request set-header X-Forwarded-Proto https
    acl is_ocp_apps hdr(host) -m end .apps.{{ ocp_cluster_name }}.{{ external_domain }}
    use_backend ocp_apps_backend if is_ocp_apps

backend ocp_apps_backend
    balance roundrobin
{% for ip in ocp_master_ips %}
    server ocp-master-{{ loop.index0 }} {{ ip }}:443 check ssl verify none
{% endfor %}

# Cockpit (HTTPS with SNI)
frontend cockpit_https
    bind *:9090 ssl crt /etc/haproxy/certs/{{ cockpit_url }}.pem
    http-request set-header X-Forwarded-Proto https
    default_backend cockpit_backend

backend cockpit_backend
    balance roundrobin
    server kvm-host 127.0.0.1:9090 check ssl verify none

{% else %}
#
# ON-PREMISE MODE: Port-based routing (no SNI)
#

# Quay Registry (port 5000)
frontend quay_registry
    bind *:5000
    default_backend quay_backend

backend quay_backend
    balance roundrobin
    server quay1 {{ quay_vm_ip }}:5000 check

# AAP Controller (port 8443)
frontend aap_https
    bind *:8443 ssl crt /etc/haproxy/certs/aap-selfsigned.pem
    default_backend aap_backend

backend aap_backend
    balance roundrobin
    server aap1 {{ aap_vm_ip }}:443 check ssl verify none

# OpenShift API (port 6443)
frontend ocp_api
    bind *:6443
    mode tcp
    option tcplog
    default_backend ocp_api_backend

backend ocp_api_backend
    mode tcp
    balance roundrobin
{% for ip in ocp_master_ips %}
    server ocp-master-{{ loop.index0 }} {{ ip }}:6443 check
{% endfor %}

# OpenShift Console (port 443)
frontend ocp_console
    bind *:443 ssl crt /etc/haproxy/certs/ocp-selfsigned.pem
    default_backend ocp_console_backend

backend ocp_console_backend
    balance roundrobin
{% for ip in ocp_master_ips %}
    server ocp-master-{{ loop.index0 }} {{ ip }}:443 check ssl verify none
{% endfor %}

# Cockpit (port 9090)
frontend cockpit_https
    bind *:9090 ssl crt /etc/haproxy/certs/cockpit-selfsigned.pem
    default_backend cockpit_backend

backend cockpit_backend
    balance roundrobin
    server kvm-host 127.0.0.1:9090 check ssl verify none

{% endif %}

# HAProxy Stats (always enabled)
listen stats
    bind *:9000
    stats enable
    stats uri /
    stats refresh 10s
    stats admin if TRUE
```

---

## SSL Certificate Management

### Option 1: Let's Encrypt (Cloud Deployments)

**Requirements**:
- Valid DNS records pointing to public IP
- HTTP port 80 accessible (for ACME challenge)
- Internet connectivity

**Implementation**:
```yaml
# playbooks/setup-haproxy-letsencrypt.yml
---
- name: Setup HAProxy with Let's Encrypt Certificates
  hosts: localhost
  become: yes
  vars:
    letsencrypt_email: "admin@example.com"
    domains:
      - "{{ quay_url }}"
      - "{{ aap_url }}"
      - "*.apps.{{ ocp_cluster_name }}.{{ external_domain }}"
      - "api.{{ ocp_cluster_name }}.{{ external_domain }}"
      - "{{ cockpit_url }}"
  
  tasks:
    - name: Install certbot
      ansible.builtin.dnf:
        name:
          - certbot
          - python3-certbot-dns-cloudflare  # or other DNS plugin
        state: present
    
    - name: Obtain Let's Encrypt certificates
      ansible.builtin.command:
        cmd: >
          certbot certonly --standalone -d {{ item }}
          --email {{ letsencrypt_email }}
          --agree-tos --non-interactive
      loop: "{{ domains }}"
      args:
        creates: "/etc/letsencrypt/live/{{ item }}/fullchain.pem"
    
    - name: Create HAProxy cert bundles
      ansible.builtin.shell: |
        cat /etc/letsencrypt/live/{{ item }}/fullchain.pem \
            /etc/letsencrypt/live/{{ item }}/privkey.pem \
            > /etc/haproxy/certs/{{ item }}.pem
      loop: "{{ domains }}"
      args:
        creates: "/etc/haproxy/certs/{{ item }}.pem"
    
    - name: Set up cert renewal cron
      ansible.builtin.cron:
        name: "Renew Let's Encrypt certs"
        minute: "0"
        hour: "2"
        job: "certbot renew --quiet && systemctl reload haproxy"
```

### Option 2: Self-Signed Certificates (On-Premise)

**Implementation**:
```yaml
# playbooks/setup-haproxy-selfsigned.yml
---
- name: Setup HAProxy with Self-Signed Certificates
  hosts: localhost
  become: yes
  vars:
    cert_country: "US"
    cert_state: "State"
    cert_locality: "City"
    cert_organization: "Example Org"
    cert_common_name: "{{ ansible_default_ipv4.address }}"
  
  tasks:
    - name: Generate self-signed certificates
      ansible.builtin.command:
        cmd: >
          openssl req -new -newkey rsa:2048 -days 365 -nodes -x509
          -subj "/C={{ cert_country }}/ST={{ cert_state }}/L={{ cert_locality }}/O={{ cert_organization }}/CN={{ item }}"
          -keyout /etc/haproxy/certs/{{ item }}-key.pem
          -out /etc/haproxy/certs/{{ item }}-cert.pem
      loop:
        - aap-selfsigned
        - ocp-selfsigned
        - cockpit-selfsigned
      args:
        creates: "/etc/haproxy/certs/{{ item }}-cert.pem"
    
    - name: Combine cert and key for HAProxy
      ansible.builtin.shell: |
        cat /etc/haproxy/certs/{{ item }}-cert.pem \
            /etc/haproxy/certs/{{ item }}-key.pem \
            > /etc/haproxy/certs/{{ item }}.pem
      loop:
        - aap-selfsigned
        - ocp-selfsigned
        - cockpit-selfsigned
```

---

## IBM Cloud Deployment Guide Integration

### Reference Architecture

From [IBM Cloud Deployment Guide](https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html):

**IBM Cloud Components**:
1. **VPC (Virtual Private Cloud)**
   - Private network for VSIs
   - Subnets for management and workloads

2. **VSI (Virtual Server Instance)**
   - Runs KVM hypervisor
   - Hosts all VMs (Quay, AAP, OpenShift nodes)

3. **Floating IP**
   - Public IP attached to VSI
   - Single entry point for all services

4. **DNS Configuration**
   - Cloud DNS or external DNS provider
   - Wildcard records for OpenShift apps
   - Individual records for services

5. **Security Groups**
   - Allow HTTP/HTTPS (80, 443)
   - Allow OpenShift API (6443)
   - Allow Quay (5000)
   - Allow AAP (8443)
   - Allow Cockpit (9090)

### HAProxy Configuration for IBM Cloud

**Inventory** (`inventory/ibm-cloud.yml`):
```yaml
all:
  vars:
    # Deployment type
    deployment_type: "cloud"
    
    # IBM Cloud Floating IP (public)
    external_ip: "52.116.XXX.XXX"
    
    # DNS configuration
    external_domain: "example.com"
    ocp_cluster_name: "ocp"
    
    # Service URLs
    quay_url: "registry.{{ ocp_cluster_name }}.{{ external_domain }}"
    aap_url: "aap.{{ external_domain }}"
    ocp_api_url: "api.{{ ocp_cluster_name }}.{{ external_domain }}"
    ocp_apps_wildcard: "*.apps.{{ ocp_cluster_name }}.{{ external_domain }}"
    cockpit_url: "cockpit.{{ external_domain }}"
    
    # SSL certificates
    ssl_cert_provider: "letsencrypt"
    letsencrypt_email: "admin@example.com"
    
    # Backend VMs (internal IPs on VSI)
    quay_vm_ip: "192.168.122.5"
    aap_vm_ip: "192.168.122.30"
    ocp_master_ips:
      - "192.168.122.100"
      - "192.168.122.101"
      - "192.168.122.102"

  hosts:
    kvm-host:
      ansible_host: "{{ external_ip }}"
      ansible_user: "root"
```

### DNS Records Required

**IBM Cloud DNS or External Provider** (e.g., Cloudflare, Route53):

```
# A Records
registry.ocp.example.com    → 52.116.XXX.XXX (Floating IP)
aap.example.com             → 52.116.XXX.XXX
api.ocp.example.com         → 52.116.XXX.XXX
cockpit.example.com         → 52.116.XXX.XXX

# Wildcard (for OpenShift routes)
*.apps.ocp.example.com      → 52.116.XXX.XXX
```

### Firewall Rules (IBM Cloud Security Group)

```yaml
# Inbound rules
- protocol: tcp
  port_range: 80
  source: 0.0.0.0/0
  description: "HTTP (Let's Encrypt ACME)"

- protocol: tcp
  port_range: 443
  source: 0.0.0.0/0
  description: "HTTPS (Quay, AAP, OCP Console)"

- protocol: tcp
  port_range: 6443
  source: 0.0.0.0/0
  description: "OpenShift API"

- protocol: tcp
  port_range: 8443
  source: 0.0.0.0/0
  description: "AAP Web UI (alternative port)"

- protocol: tcp
  port_range: 9090
  source: 0.0.0.0/0
  description: "Cockpit Web Console"

- protocol: tcp
  port_range: 22
  source: YOUR_IP/32
  description: "SSH (restricted)"
```

---

## Playbook: Setup HAProxy (Flexible)

**File**: `playbooks/setup-haproxy.yml`

```yaml
---
- name: Setup HAProxy with External URL Support
  hosts: localhost
  become: yes
  vars_files:
    - ../inventory/group_vars/all.yml
  
  tasks:
    - name: Install HAProxy
      ansible.builtin.dnf:
        name:
          - haproxy
          - openssl
        state: present
    
    - name: Create HAProxy certs directory
      ansible.builtin.file:
        path: /etc/haproxy/certs
        state: directory
        mode: '0700'
    
    - name: Generate HAProxy configuration
      ansible.builtin.template:
        src: ../templates/haproxy/haproxy.cfg.j2
        dest: /etc/haproxy/haproxy.cfg
        validate: 'haproxy -c -f %s'
      notify: Reload HAProxy
    
    - name: Setup SSL certificates
      ansible.builtin.include_tasks: "tasks/haproxy-{{ ssl_cert_provider }}-certs.yml"
    
    - name: Enable and start HAProxy
      ansible.builtin.systemd:
        name: haproxy
        enabled: yes
        state: started
    
    - name: Open firewall ports
      ansible.posix.firewalld:
        port: "{{ item }}/tcp"
        permanent: yes
        state: enabled
        immediate: yes
      loop:
        - 80      # HTTP (Let's Encrypt)
        - 443     # HTTPS (Quay, AAP, OCP)
        - 5000    # Quay (on-prem mode)
        - 6443    # OpenShift API
        - 8443    # AAP (on-prem mode)
        - 9000    # HAProxy stats
        - 9090    # Cockpit
      when: ansible_facts.services['firewalld.service'] is defined
    
    - name: Display deployment info
      ansible.builtin.debug:
        msg:
          - "✅ HAProxy configured for {{ deployment_type }} deployment"
          - ""
{% if deployment_type == 'cloud' %}
          - "🌐 External URLs:"
          - "   Quay Registry:      https://{{ quay_url }}"
          - "   AAP Controller:     https://{{ aap_url }}"
          - "   OpenShift API:      https://{{ ocp_api_url }}:6443"
          - "   OpenShift Console:  https://console-openshift-console.apps.{{ ocp_cluster_name }}.{{ external_domain }}"
          - "   Cockpit:            https://{{ cockpit_url }}:9090"
          - ""
          - "📋 DNS Records Required:"
          - "   {{ quay_url }} → {{ external_ip }}"
          - "   {{ aap_url }} → {{ external_ip }}"
          - "   {{ ocp_api_url }} → {{ external_ip }}"
          - "   *.apps.{{ ocp_cluster_name }}.{{ external_domain }} → {{ external_ip }}"
          - "   {{ cockpit_url }} → {{ external_ip }}"
{% else %}
          - "🏠 On-Premise URLs (Direct IP):"
          - "   Quay Registry:      http://{{ ansible_default_ipv4.address }}:5000"
          - "   AAP Controller:     https://{{ ansible_default_ipv4.address }}:8443"
          - "   OpenShift API:      https://{{ ansible_default_ipv4.address }}:6443"
          - "   OpenShift Console:  https://{{ ansible_default_ipv4.address }}:443"
          - "   Cockpit:            https://{{ ansible_default_ipv4.address }}:9090"
{% endif %}
          - ""
          - "📊 HAProxy Stats:     http://{{ ansible_default_ipv4.address }}:9000"
  
  handlers:
    - name: Reload HAProxy
      ansible.builtin.systemd:
        name: haproxy
        state: reloaded
```

---

## Testing & Validation

### Test 1: DNS Resolution (Cloud)

```bash
# From external machine
dig registry.ocp.example.com +short
# Should return: 52.116.XXX.XXX (Floating IP)

dig api.ocp.example.com +short
# Should return: 52.116.XXX.XXX
```

### Test 2: HAProxy Routing

```bash
# Test Quay backend
curl -k https://registry.ocp.example.com/health
# Should return: {"database_healthy":true,...}

# Test AAP backend
curl -k https://aap.example.com/api/v2/ping/
# Should return: {"version":"2.5.0",...}

# Test OpenShift API
curl -k https://api.ocp.example.com:6443/healthz
# Should return: ok
```

### Test 3: SSL/TLS Validation

```bash
# Check Let's Encrypt certificate
openssl s_client -connect registry.ocp.example.com:443 -servername registry.ocp.example.com < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates

# Should show:
# issuer=C=US, O=Let's Encrypt, CN=R3
# notBefore=...
# notAfter=... (90 days from issue)
```

---

## Migration: On-Premise → Cloud

If you start on-premise and later move to cloud:

**Step 1**: Update inventory
```yaml
# Change deployment_type
deployment_type: "onprem"  →  deployment_type: "cloud"

# Add external URLs
external_domain: "example.com"
ocp_cluster_name: "ocp"
```

**Step 2**: Setup DNS records (before HAProxy reconfiguration)

**Step 3**: Obtain SSL certificates (Let's Encrypt)

**Step 4**: Reconfigure HAProxy
```bash
ansible-playbook playbooks/setup-haproxy.yml
```

**Step 5**: Update clients
- Update ImageContentSourcePolicy (new registry URL)
- Update kubeconfig (new API URL)
- Update bookmarks (new console URL)

---

## Summary

**Key Decisions**:

| Deployment Type | URLs | SSL Certs | HAProxy Mode |
|----------------|------|-----------|--------------|
| **On-Premise** | IP:port | Self-signed | Port-based routing |
| **Cloud (IBM/AWS/Azure)** | DNS names | Let's Encrypt | SNI-based routing |

**Flexible Configuration**:
- Single HAProxy config template supports both modes
- Inventory variable `deployment_type` switches behavior
- DNS records optional for on-prem, required for cloud
- SSL certificates auto-generated based on mode

**IBM Cloud Pattern** (from proven guide):
- Floating IP → HAProxy → Internal VMs
- DNS points to Floating IP
- Let's Encrypt for valid SSL
- Security Groups for firewall rules

---

## Next Steps

1. **Decide deployment type** (on-premise or cloud)
2. **Create inventory** (`inventory/onprem.yml` or `inventory/ibm-cloud.yml`)
3. **Setup DNS** (if cloud deployment)
4. **Run**: `ansible-playbook playbooks/setup-haproxy.yml`
5. **Validate** URLs and SSL certificates
6. **Document** external URLs for team

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-02  
**Reference**: [IBM Cloud Deployment Guide](https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html)
