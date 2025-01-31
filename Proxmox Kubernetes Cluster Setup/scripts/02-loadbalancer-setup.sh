#!/bin/bash
source ./00-variables.sh

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1 successful"
    else
        echo "❌ $1 failed"
        exit 1
    fi
}

echo "🚀 Starting Load Balancer Setup..."

# Install required packages
echo "📦 Installing required packages..."
apt-get update
apt-get install -y haproxy keepalived
check_status "Package installation"

# Configure HAProxy
echo "⚖️ Configuring HAProxy..."
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend kubernetes-frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server kmaster1 ${KMASTER1_IP}:6443 check fall 3 rise 2
    server kmaster2 ${KMASTER2_IP}:6443 check fall 3 rise 2
EOF
check_status "HAProxy configuration"

# Configure Keepalived
echo "🔄 Configuring Keepalived..."

# Determine if this is the active or backup load balancer
if [ "$(hostname)" == "klb1" ]; then
    STATE="MASTER"
    PRIORITY=101
else
    STATE="BACKUP"
    PRIORITY=100
fi

cat > /etc/keepalived/keepalived.conf << EOF
vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state ${STATE}
    interface ens18.${VLAN_ID}
    virtual_router_id 51
    priority ${PRIORITY}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass kubernetes
    }
    virtual_ipaddress {
        ${VIP_ADDRESS}/24
    }
    track_script {
        check_haproxy
    }
}
EOF
check_status "Keepalived configuration"

# Start and enable services
echo "🚀 Starting services..."
systemctl enable haproxy keepalived
systemctl restart haproxy keepalived
check_status "Service startup"

# Verify services
echo "🔍 Verifying services..."
systemctl status haproxy --no-pager
systemctl status keepalived --no-pager
check_status "Service verification"

echo "✅ Load Balancer setup completed successfully!"
