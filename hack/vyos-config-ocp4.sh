#!/bin/vbash
# VyOS Configuration for OpenShift Disconnected Helper
# Uses upstream VLAN IDs with simplified IP scheme
# Reference: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html

source /opt/vyatta/etc/functions/script-template
configure

# Display current interfaces
run show interfaces

# ============================================================================
# VLAN 1924 - Management Network (192.168.10.0/24)
# Usage: Registry VM, AAP VM, Bastion, Management tools
# ============================================================================
set interfaces ethernet eth1 address 192.168.10.1/24
set interfaces ethernet eth1 description 'Management-Base'
set interfaces ethernet eth1 vif 1924 description 'Management-VLAN'
set interfaces ethernet eth1 vif 1924 address '192.168.10.1/24'

# ============================================================================
# VLAN 1925 - OpenShift Network (192.168.20.0/24)
# Usage: OpenShift master nodes, worker nodes, OpenShift services
# ============================================================================
set interfaces ethernet eth2 address 192.168.20.1/24
set interfaces ethernet eth2 description 'OpenShift-Base'
set interfaces ethernet eth2 vif 1925 description 'OpenShift-VLAN'
set interfaces ethernet eth2 vif 1925 address '192.168.20.1/24'

# ============================================================================
# VLAN 1927 - Storage Network (192.168.30.0/24)
# Usage: NFS servers, persistent storage, backup services
# ============================================================================
set interfaces ethernet eth3 address 192.168.30.1/24
set interfaces ethernet eth3 description 'Storage-Base'
set interfaces ethernet eth3 vif 1927 description 'Storage-VLAN'
set interfaces ethernet eth3 vif 1927 address '192.168.30.1/24'

run show interfaces

# ============================================================================
# NAT Configuration - Allow all networks to access external
# ============================================================================

# NAT for VyOS itself
set nat source rule 10 outbound-interface name 'eth0'
set nat source rule 10 source address 192.168.122.2
set nat source rule 10 translation address masquerade
show nat source
commit
run ping 1.1.1.1 count 3 interface 192.168.122.2

# NAT for Management Network
set nat source rule 11 outbound-interface name 'eth0'
set nat source rule 11 source address 192.168.10.0/24
set nat source rule 11 translation address masquerade
show nat source
commit
run ping 1.1.1.1 count 3 interface 192.168.10.1

# NAT for OpenShift Network
set nat source rule 12 outbound-interface name 'eth0'
set nat source rule 12 source address 192.168.20.0/24
set nat source rule 12 translation address masquerade
show nat source
commit
run ping 1.1.1.1 count 3 interface 192.168.20.1

# NAT for Storage Network
set nat source rule 13 outbound-interface name 'eth0'
set nat source rule 13 source address 192.168.30.0/24
set nat source rule 13 translation address masquerade
show nat source
commit
run ping 1.1.1.1 count 3 interface 192.168.30.1

# ============================================================================
# DHCP Server Configuration
# ============================================================================

# Management Network DHCP (192.168.10.0/24)
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 option default-router '192.168.10.1'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 option name-server '1.1.1.1'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 option domain-name 'example.com'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 lease '86400'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 range 0 start 192.168.10.10
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 range 0 stop '192.168.10.254'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 subnet-id '1'

# Static DHCP reservations for Management Network
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 static-mapping registry-vm mac-address '52:54:00:10:00:10'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 static-mapping registry-vm ip-address '192.168.10.10'

set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 static-mapping aap-vm mac-address '52:54:00:10:00:20'
set service dhcp-server shared-network-name Management subnet 192.168.10.0/24 static-mapping aap-vm ip-address '192.168.10.20'

commit

# OpenShift Network DHCP (192.168.20.0/24)
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 option default-router '192.168.20.1'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 option name-server '1.1.1.1'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 option domain-name 'example.com'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 lease '86400'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 range 0 start 192.168.20.10
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 range 0 stop '192.168.20.254'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 subnet-id '2'

# Static DHCP reservations for OpenShift masters
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-master-1 mac-address '52:54:00:20:00:11'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-master-1 ip-address '192.168.20.11'

set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-master-2 mac-address '52:54:00:20:00:12'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-master-2 ip-address '192.168.20.12'

set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-master-3 mac-address '52:54:00:20:00:13'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-master-3 ip-address '192.168.20.13'

# Static DHCP reservations for OpenShift workers
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-worker-1 mac-address '52:54:00:20:00:21'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-worker-1 ip-address '192.168.20.21'

set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-worker-2 mac-address '52:54:00:20:00:22'
set service dhcp-server shared-network-name OpenShift subnet 192.168.20.0/24 static-mapping ocp-worker-2 ip-address '192.168.20.22'

commit

# Storage Network DHCP (192.168.30.0/24)
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 option default-router '192.168.30.1'
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 option name-server '1.1.1.1'
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 option domain-name 'example.com'
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 lease '86400'
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 range 0 start 192.168.30.10
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 range 0 stop '192.168.30.254'
set service dhcp-server shared-network-name Storage subnet 192.168.30.0/24 subnet-id '3'

commit

# ============================================================================
# DNS Forwarding
# ============================================================================
set service dns forwarding listen-address 192.168.10.1
set service dns forwarding listen-address 192.168.20.1
set service dns forwarding listen-address 192.168.30.1
set service dns forwarding allow-from 192.168.10.0/24
set service dns forwarding allow-from 192.168.20.0/24
set service dns forwarding allow-from 192.168.30.0/24

commit

# ============================================================================
# Firewall Rules - Allow inter-VLAN communication
# ============================================================================
set firewall group network-group INTERNAL_NETS network '192.168.10.0/24'
set firewall group network-group INTERNAL_NETS network '192.168.20.0/24'
set firewall group network-group INTERNAL_NETS network '192.168.30.0/24'

commit

# Save configuration
save

# Display final configuration
run show configuration
run show interfaces
run show dhcp server statistics

exit
