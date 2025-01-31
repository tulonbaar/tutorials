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

echo "🚀 Starting Kubernetes Worker Setup..."

# Install required packages
echo "📦 Installing dependencies..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
check_status "Base package installation"

# Add Kubernetes repository
echo "📦 Adding Kubernetes repository..."
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
check_status "Repository setup"

# Install Kubernetes packages
echo "📦 Installing Kubernetes packages..."
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
check_status "Kubernetes installation"

# Configure containerd
echo "🐋 Configuring containerd..."
cat > /etc/modules-load.d/containerd.conf << EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system
check_status "System configuration"

# Install containerd
echo "🐋 Installing containerd..."
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
check_status "Containerd setup"

# Configure NFS client for shared storage
echo "📁 Configuring NFS client..."
apt-get install -y nfs-common
check_status "NFS client installation"

# Mount shared storage
echo "📁 Mounting shared storage..."
mkdir -p /mnt/k8s-shared
echo "${NFS_PRIMARY_IPS%,*}:${NFS_EXPORT}/k8s-shared /mnt/k8s-shared nfs defaults,soft,timeo=180,retrans=2 0 0" >> /etc/fstab
mount -a
check_status "Storage mount"

echo "✅ Worker node setup completed successfully!"
echo "⚠️ Please run the join command from the master node to join this node to the cluster"
