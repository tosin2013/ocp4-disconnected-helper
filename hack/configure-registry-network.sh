#!/bin/bash
#
# Configure Registry VM Network via Console
# Workaround for cloud-init static IP failure on CentOS Stream 9
#

set -e

export LIBVIRT_DEFAULT_URI="qemu:///system"

VM_NAME="registry"
STATIC_IP="192.168.10.10"
GATEWAY="192.168.10.1"
DNS1="192.168.10.1"
DNS2="161.26.0.10"
VM_USER="admin"

echo "Configuring static IP for ${VM_NAME} via virsh console commands..."

# Wait for VM to boot
echo "Waiting for VM to boot (60 seconds)..."
sleep 60

# Check if VM is running
if ! virsh domstate "${VM_NAME}" | grep -q "running"; then
    echo "ERROR: VM ${VM_NAME} is not running"
    exit 1
fi

echo "Attempting network configuration via console automation..."
echo "NOTE: This is experimental - manual console configuration may be required"

# Try using expect to automate console interaction
if command -v expect &> /dev/null; then
    cat > /tmp/configure-network.exp << 'EOF'
#!/usr/bin/expect -f

set timeout 30
set vm_name [lindex $argv 0]
set static_ip [lindex $argv 1]
set gateway [lindex $argv 2]
set dns1 [lindex $argv 3]
set dns2 [lindex $argv 4]
set vm_user [lindex $argv 5]

spawn virsh console $vm_name

# Wait for login prompt
expect {
    "login:" {
        send "$vm_user\r"
        exp_continue
    }
    "Password:" {
        send "\r"
        exp_continue
    }
    "*$ " {
        # Logged in
    }
    timeout {
        puts "Timeout waiting for login"
        exit 1
    }
}

# Configure static IP via nmcli
send "sudo nmcli con mod 'System eth0' ipv4.method manual ipv4.addresses ${static_ip}/24 ipv4.gateway ${gateway} ipv4.dns '${dns1} ${dns2}'\r"
expect "*$ "

send "sudo nmcli con down 'System eth0'\r"
expect "*$ "

send "sudo nmcli con up 'System eth0'\r"
expect "*$ "

send "ip addr show eth0\r"
expect "*$ "

send "exit\r"
expect eof
EOF

    chmod +x /tmp/configure-network.exp
    /tmp/configure-network.exp "${VM_NAME}" "${STATIC_IP}" "${GATEWAY}" "${DNS1}" "${DNS2}" "${VM_USER}"

    rm -f /tmp/configure-network.exp
else
    echo "ERROR: expect command not found"
    echo "Install with: sudo dnf install -y expect"
    echo ""
    echo "MANUAL CONFIGURATION REQUIRED:"
    echo "1. Access VM console: virsh console ${VM_NAME}"
    echo "2. Login as: ${VM_USER} (no password)"
    echo "3. Run these commands:"
    echo ""
    echo "sudo nmcli con mod 'System eth0' ipv4.method manual ipv4.addresses ${STATIC_IP}/24 ipv4.gateway ${GATEWAY} ipv4.dns '${DNS1} ${DNS2}'"
    echo "sudo nmcli con down 'System eth0'"
    echo "sudo nmcli con up 'System eth0'"
    echo "ip addr show eth0"
    echo ""
    exit 1
fi

# Verify SSH access
echo "Waiting for SSH to become available on ${STATIC_IP}:22..."
for i in {1..30}; do
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${VM_USER}@${STATIC_IP}" "echo 'SSH OK'" 2>/dev/null; then
        echo "✅ SSH access confirmed on ${STATIC_IP}"
        exit 0
    fi
    echo "  Attempt $i/30..."
    sleep 10
done

echo "ERROR: SSH still not accessible after configuration"
exit 1
