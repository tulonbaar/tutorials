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

echo "🚀 Starting Kubernetes Master Setup..."

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

# Initialize the first master node
if [ "$(hostname)" == "kmaster1" ]; then
    echo "👑 Initializing first master node..."
    
    # Pull required images
    kubeadm config images pull
    check_status "Image pull"
    
    # Initialize the cluster
    kubeadm init --control-plane-endpoint "${VIP_ADDRESS}:6443" \
        --upload-certs \
        --pod-network-cidr=10.244.0.0/16 \
        --apiserver-advertise-address=$(hostname -I | awk '{print $1}')
    check_status "Cluster initialization"
    
    # Configure kubectl
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    check_status "kubectl configuration"
    
    # Install Calico CNI
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
    check_status "Calico installation"
    
    # Save join commands
    kubeadm token create --print-join-command > /share/worker-join.sh
    kubeadm init phase upload-certs --upload-certs | grep -w "certificate-key" | awk '{print $3}' > /share/cert-key.txt
    check_status "Join command generation"
    
    echo "✅ First master node setup completed!"
    echo "⚠️ Please copy the join commands from /share/worker-join.sh for worker nodes"
    echo "⚠️ Use the certificate key from /share/cert-key.txt for additional control plane nodes"

else
    echo "👑 Joining additional master node..."
    # Join commands should be provided externally for additional master nodes
    echo "⚠️ Please run the appropriate kubeadm join command with the certificate key"
fi

echo "✅ Master node setup completed successfully!"
