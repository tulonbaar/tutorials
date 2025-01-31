# High Availability Kubernetes Cluster Setup Guide

## Infrastructure Overview
### Proxmox HA Cluster
- Node1: 192.168.1.158 (pve1)
- Node2: 192.168.1.159 (pve2)
- Node3: 192.168.1.162 (pve-quorum)

### Shared Storage Configuration
#### NFS Storage Cluster (hua-shared)
- Primary IPs: 192.168.231.206, 192.168.231.207
- Secondary IPs: 192.168.232.206, 192.168.232.207
- Purpose: Shared storage for VM disks and configurations
- Mount Point: /mnt/hua-shared
- Storage Type: NFS
- High Availability: Active-Active configuration

#### Storage Layout
1. **System Storage** (hua-shared):
   - Master Nodes: 128GB each
   - Load Balancer Nodes: 32GB each
   - Worker Nodes: 256GB each
   - Path: /mnt/hua-shared/system-disks

2. **Cluster Shared Storage** (hua-shared):
   - Size: 1024GB (1TB)
   - Purpose: Shared storage for Kubernetes workloads
   - Path: /mnt/hua-shared/k8s-shared
   - Accessible by all worker nodes
   - Used for persistent volumes

3. **etcd Dedicated Storage** (hua-shared):
   - Size: 32GB
   - Purpose: Dedicated storage for etcd data
   - Path: /mnt/hua-shared/etcd-data
   - Accessible by master nodes only
   - Enhanced reliability for cluster state

### Resource Requirements
#### Master Nodes (Each):
- Name: kmaster1, kmaster2
- CPU: 8 vCPU
- RAM: 16GB
- System Storage: 128GB (hua-shared)
- etcd Storage: Access to shared etcd volume

#### Worker Nodes (Each):
- Names: knode1 through knode4
- CPU: 16 vCPU
- RAM: 64GB
- System Storage: 256GB (hua-shared)
- Cluster Storage: Access to 1TB shared volume
- Purpose: Application workloads and container storage

#### Load Balancer Nodes (Each):
- Names: klb1 (Active), klb2 (Passive)
- CPU: 2 vCPU
- RAM: 2GB
- System Storage: 32GB (hua-shared)
- Virtual IP (VIP): <VLAN10-VIP>

### Storage Configuration Steps

#### 1. Create Storage Directories
On the NFS server:
```bash
# Create storage directories
mkdir -p /mnt/hua-shared/{system-disks,k8s-shared,etcd-data}

# Set appropriate permissions
chmod 755 /mnt/hua-shared/{system-disks,k8s-shared,etcd-data}
```

#### 2. Configure Storage in Proxmox
```bash
# Add system disks storage
pvesm add nfs hua-shared-system --path /mnt/hua-shared/system-disks \
    --server 192.168.231.206,192.168.231.207 \
    --export /mnt/hua-shared/system-disks \
    --options soft,tcp,bg \
    --content images,rootdir

# Add Kubernetes shared storage
pvesm add nfs hua-shared-k8s --path /mnt/hua-shared/k8s-shared \
    --server 192.168.231.206,192.168.231.207 \
    --export /mnt/hua-shared/k8s-shared \
    --options soft,tcp,bg \
    --content images

# Add etcd storage
pvesm add nfs hua-shared-etcd --path /mnt/hua-shared/etcd-data \
    --server 192.168.231.206,192.168.231.207 \
    --export /mnt/hua-shared/etcd-data \
    --options soft,tcp,bg \
    --content images
```

#### 3. Configure etcd to Use Dedicated Storage
Add to master node configuration:
```yaml
# /etc/kubernetes/manifests/etcd.yaml
volumes:
- name: etcd-data
  nfs:
    server: 192.168.231.206
    path: /mnt/hua-shared/etcd-data
```

#### 4. Configure Storage Class for Cluster Storage
```yaml
# k8s-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-shared
provisioner: kubernetes.io/nfs
parameters:
  server: 192.168.231.206
  path: /mnt/hua-shared/k8s-shared
  readOnly: "false"
```

Apply the storage class:
```bash
kubectl apply -f k8s-storage-class.yaml
```

## VM Distribution for High Availability
#### pve1:
- kmaster1
- knode1
- knode3
- klb1

#### pve2:
- kmaster2
- knode2
- knode4
- klb2

#### pve3 (Quorum):
- No Kubernetes components (dedicated for Proxmox HA quorum)

## Architecture Overview
- 2 Master Nodes (Control Plane)
- 4 Worker Nodes
- 2 Load Balancers for API Server (Active-Passive configuration with Keepalived)
- Highly Available etcd Cluster

### Network Requirements
- Management Network: 192.168.1.0/24 (Proxmox hosts)
- VLAN Tag: 10
- Kubernetes Network: 10.10.0.0/24
- Gateway: 10.10.0.1
- DNS: 192.168.1.29 192.168.1.76

#### IP Address Allocation:
- Load Balancer VIP: <VLAN10-VIP> (e.g., 10.10.0.100)
- kmaster1: <VLAN10-KMASTER1-IP> (e.g., 10.10.0.30)
- kmaster2: <VLAN10-KMASTER2-IP> (e.g., 10.10.0.39)
- knode1: <VLAN10-KNODE1-IP> (e.g., 10.10.0.31)
- knode2: <VLAN10-KNODE2-IP> (e.g., 10.10.0.32)
- knode3: <VLAN10-KNODE3-IP> (e.g., 10.10.0.33)
- knode4: <VLAN10-KNODE4-IP> (e.g., 10.10.0.34)
- k8s-lb-1: <VLAN10-LB1-IP> (e.g., 10.10.0.15)
- k8s-lb-2: <VLAN10-LB2-IP> (e.g., 10.10.0.16)

## 1. Proxmox HA Cluster Configuration

### 1.1 Configure Shared Storage
On all Proxmox nodes:
```bash
# Add shared storage to Proxmox
pvesm add nfs hua-shared --path /mnt/hua-shared \
    --server 192.168.231.206,192.168.231.207 \
    --export /mnt/hua-shared \
    --options soft,tcp,bg \
    --content images,rootdir

# Verify storage is added and accessible
pvesm status
```

### 1.2 Create VM Template
On pve1:
```bash
# Download Ubuntu Cloud Image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Create VM template
qm create 9000 --memory 2048 --cores 2 --name ubuntu-cloud-template --net0 virtio,bridge=vmbr0

# Import disk to shared storage
qm importdisk 9000 noble-server-cloudimg-amd64.img hua-shared

# Configure VM to use shared storage
qm set 9000 --scsihw virtio-scsi-pci --scsi0 hua-shared:vm-9000-disk-0
qm set 9000 --ide2 hua-shared:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000

# Verify template is available on both nodes
qm list
```

### 1.3 Create VMs with HA Configuration
For each node (example for kmaster1):
```bash
# Clone from template
qm clone 9000 10030 --name kmaster1 --full

# Configure resources
qm set 10030 --memory 16384 --cores 8 --sockets 1

# Configure storage on shared storage
qm set 10030 --scsi0 hua-shared:128

# Configure networks
qm set 10030 --net0 virtio,bridge=vmbr0,tag=10

# Enable HA
pvesh set /cluster/ha/resources --sid vm:10030 --group kubernetes --state enabled

# Start VM
qm start 10030
```

Repeat for other VMs with appropriate resources:
- kmaster1: ID 10030
- kmaster2: ID 10039
- knode1: ID 10031
- knode2: ID 10032
- knode3: ID 10033
- knode4: ID 10034
- klb1: ID 10041
- klb2: ID 10042

### 1.4 Verify HA Status
```bash
# Check HA status
pvesh get /cluster/ha/status

# Check resource distribution
pvesh get /cluster/ha/resources
```

## 2. Network Configuration

### 2.1 Configure Network Interface (All Nodes)
On each node, edit `/etc/netplan/00-installer-config.yaml`:
```yaml
network:
  version: 2
  ethernets:
    ens18:  # Primary interface
      dhcp4: no
  vlans:
    ens18.10:
      id: 10
      link: ens18
      addresses: [<NODE-IP>/24]  # Use appropriate IP from allocation above
      gateway4: <VLAN10-GATEWAY>
      nameservers:
        addresses: [<VLAN10-DNS>]
      routes:
        - to: 192.168.1.0/24  # Route to Proxmox management network
          via: <VLAN10-GATEWAY>
```

Apply network configuration:
```bash
sudo netplan try
sudo netplan apply
```

### 2.2 Verify Network Configuration
```bash
# Verify VLAN interface
ip addr show ens18.10

# Test network connectivity
ping -c 3 <VLAN10-GATEWAY>

# Test DNS resolution
nslookup kubernetes.io
```

## 3. Load Balancer Setup

### 3.1 Create HAProxy VMs and Install Required Packages
On both k8s-lb-1 and k8s-lb-2:
```bash
# Install HAProxy and Keepalived
sudo apt update
sudo apt install -y haproxy keepalived
```

### 3.2 Configure HAProxy
On both load balancers, edit `/etc/haproxy/haproxy.cfg`:
```conf
frontend kubernetes-frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server kmaster1 <VLAN10-KMASTER1-IP>:6443 check fall 3 rise 2
    server kmaster2 <VLAN10-KMASTER2-IP>:6443 check fall 3 rise 2
```

### 3.3 Configure Keepalived
On k8s-lb-1 (Active), create `/etc/keepalived/keepalived.conf`:
```conf
vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state MASTER
    interface ens18.10  # VLAN interface
    virtual_router_id 51
    priority 101
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass kubernetes
    }
    virtual_ipaddress {
        <VLAN10-VIP>/24
    }
    track_script {
        check_haproxy
    }
}
```

On k8s-lb-2 (Passive), create `/etc/keepalived/keepalived.conf`:
```conf
vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface ens18.10  # VLAN interface
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass kubernetes
    }
    virtual_ipaddress {
        <VLAN10-VIP>/24
    }
    track_script {
        check_haproxy
    }
}
```

### 3.4 Start Services
On both load balancers:
```bash
sudo systemctl enable haproxy keepalived
sudo systemctl restart haproxy keepalived

# Verify services are running
sudo systemctl status haproxy keepalived
```

### 3.5 Test Load Balancer Failover
```bash
# On Active load balancer (k8s-lb-1)
ip addr show # Should show the VIP

# Test failover by stopping HAProxy on active node
sudo systemctl stop haproxy

# On Passive load balancer (k8s-lb-2)
ip addr show # Should now show the VIP
```

## 4. Control Plane Initialization

### 4.1 Initialize First Master
On k8s-master-1:
```bash
# Initialize the cluster with HAProxy VIP endpoint
sudo kubeadm init --control-plane-endpoint "<VLAN10-VIP>:6443" \
    --upload-certs \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=<VLAN10-KMASTER1-IP>  # Use node's VLAN 10 IP

# Save the output commands for:
# 1. kubeadm join for additional control plane nodes
# 2. kubeadm join for worker nodes
```

### 4.2 Configure kubectl
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 4.3 Install CNI (Calico)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
```

### 4.4 Join Second Master
On k8s-master-2:
```bash
# Use the control plane join command from previous output
sudo kubeadm join <VLAN10-VIP>:6443 \
    --token <TOKEN> \
    --discovery-token-ca-cert-hash <HASH> \
    --control-plane \
    --certificate-key <CERT-KEY>
```

## 5. Join Worker Nodes

On each worker node (k8s-worker-1 through k8s-worker-4):
```bash
# Use the worker join command from previous output
sudo kubeadm join <VLAN10-VIP>:6443 \
    --token <TOKEN> \
    --discovery-token-ca-cert-hash <HASH>
```

## 6. Verify Cluster
```bash
# Check nodes
kubectl get nodes

# Verify control plane pods
kubectl get pods -n kube-system
```

## 7. Recommended Free Management Tools

### 7.1 Rancher
- Web-based management interface
- Multi-cluster management
- User authentication and RBAC
- Monitoring and logging integration
- Easy application deployment

Installation:
```bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.<YOUR-DOMAIN>
```

### 7.2 Kubernetes Dashboard
- Official web UI for Kubernetes
- Resource visualization
- Basic cluster management

Installation:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### 7.3 Lens
- Desktop application
- Real-time cluster statistics
- Terminal access
- Resource management
- Free Lens Community Edition

### 7.4 Monitoring Stack
```bash
# Install Prometheus Operator
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/0-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/1-crds.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/

# Install Grafana
# Grafana will be installed as part of the above stack
```

## Best Practices
1. Regular etcd backups
2. Use pod security policies
3. Implement network policies
4. Regular system updates
5. Monitor cluster health
6. Use namespaces for workload isolation

## Maintenance Tasks
1. Certificate rotation (yearly)
2. Kubernetes version upgrades
3. Node maintenance and updates
4. Backup verification
5. Security audits

## Security Recommendations
1. Enable RBAC
2. Use Pod Security Standards
3. Regular security updates
4. Network segmentation
5. Audit logging
6. Container image scanning
