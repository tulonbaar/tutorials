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

echo "🚀 Starting Proxmox Setup..."

# 1. Configure NFS Storage
echo "📁 Configuring NFS Storage..."

# System Storage
pvesm add nfs hua-shared-system \
    --path "${NFS_MOUNT}/system-disks" \
    --server "${NFS_PRIMARY_IPS}" \
    --export "${NFS_EXPORT}/system-disks" \
    --options "soft,tcp,bg" \
    --content images,rootdir
check_status "System storage configuration"

# K8s Shared Storage
pvesm add nfs hua-shared-k8s \
    --path "${NFS_MOUNT}/k8s-shared" \
    --server "${NFS_PRIMARY_IPS}" \
    --export "${NFS_EXPORT}/k8s-shared" \
    --options "soft,tcp,bg" \
    --content images
check_status "K8s shared storage configuration"

# etcd Storage
pvesm add nfs hua-shared-etcd \
    --path "${NFS_MOUNT}/etcd-data" \
    --server "${NFS_PRIMARY_IPS}" \
    --export "${NFS_EXPORT}/etcd-data" \
    --options "soft,tcp,bg" \
    --content images
check_status "etcd storage configuration"

# 2. Create VM Template
echo "🔧 Creating VM Template..."

# Download Ubuntu Cloud Image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
check_status "Ubuntu image download"

# Create base template
qm create ${TEMPLATE_VMID} --memory 2048 --cores 2 --name ubuntu-cloud-template --net0 virtio,bridge=vmbr0
check_status "Template VM creation"

# Import disk
qm importdisk ${TEMPLATE_VMID} noble-server-cloudimg-amd64.img hua-shared-system
check_status "Disk import"

# Configure template
qm set ${TEMPLATE_VMID} --scsihw virtio-scsi-pci --scsi0 hua-shared-system:vm-${TEMPLATE_VMID}-disk-0
qm set ${TEMPLATE_VMID} --ide2 hua-shared-system:cloudinit
qm set ${TEMPLATE_VMID} --boot c --bootdisk scsi0
qm set ${TEMPLATE_VMID} --serial0 socket --vga serial0
qm set ${TEMPLATE_VMID} --agent enabled=1
qm template ${TEMPLATE_VMID}
check_status "Template configuration"

# 3. Create Master Nodes
echo "👑 Creating Master Nodes..."

# kmaster1
qm clone ${TEMPLATE_VMID} ${KMASTER1_VMID} --name kmaster1 --full
qm set ${KMASTER1_VMID} --memory ${MASTER_RAM} --cores ${MASTER_CPU} --sockets 1
qm set ${KMASTER1_VMID} --scsi0 hua-shared-system:${MASTER_STORAGE}
qm set ${KMASTER1_VMID} --net0 "virtio,bridge=vmbr0,tag=${VLAN_ID}"
qm set ${KMASTER1_VMID} --ipconfig0 "ip=${KMASTER1_IP}/24,gw=${VLAN_GATEWAY}"
pvesh set /cluster/ha/resources --sid "vm:${KMASTER1_VMID}" --group kubernetes --state enabled
check_status "kmaster1 creation"

# kmaster2
qm clone ${TEMPLATE_VMID} ${KMASTER2_VMID} --name kmaster2 --full
qm set ${KMASTER2_VMID} --memory ${MASTER_RAM} --cores ${MASTER_CPU} --sockets 1
qm set ${KMASTER2_VMID} --scsi0 hua-shared-system:${MASTER_STORAGE}
qm set ${KMASTER2_VMID} --net0 "virtio,bridge=vmbr0,tag=${VLAN_ID}"
qm set ${KMASTER2_VMID} --ipconfig0 "ip=${KMASTER2_IP}/24,gw=${VLAN_GATEWAY}"
pvesh set /cluster/ha/resources --sid "vm:${KMASTER2_VMID}" --group kubernetes --state enabled
check_status "kmaster2 creation"

# 4. Create Worker Nodes
echo "💪 Creating Worker Nodes..."

# Function to create worker node
create_worker() {
    local vmid=$1
    local name=$2
    local ip=$3
    
    qm clone ${TEMPLATE_VMID} ${vmid} --name ${name} --full
    qm set ${vmid} --memory ${WORKER_RAM} --cores ${WORKER_CPU} --sockets 1
    qm set ${vmid} --scsi0 hua-shared-system:${WORKER_STORAGE}
    qm set ${vmid} --net0 "virtio,bridge=vmbr0,tag=${VLAN_ID}"
    qm set ${vmid} --ipconfig0 "ip=${ip}/24,gw=${VLAN_GATEWAY}"
    pvesh set /cluster/ha/resources --sid "vm:${vmid}" --group kubernetes --state enabled
    check_status "${name} creation"
}

create_worker ${KNODE1_VMID} "knode1" ${KNODE1_IP}
create_worker ${KNODE2_VMID} "knode2" ${KNODE2_IP}
create_worker ${KNODE3_VMID} "knode3" ${KNODE3_IP}
create_worker ${KNODE4_VMID} "knode4" ${KNODE4_IP}

# 5. Create Load Balancer Nodes
echo "⚖️ Creating Load Balancer Nodes..."

# Function to create load balancer node
create_lb() {
    local vmid=$1
    local name=$2
    local ip=$3
    
    qm clone ${TEMPLATE_VMID} ${vmid} --name ${name} --full
    qm set ${vmid} --memory ${LB_RAM} --cores ${LB_CPU} --sockets 1
    qm set ${vmid} --scsi0 hua-shared-system:${LB_STORAGE}
    qm set ${vmid} --net0 "virtio,bridge=vmbr0,tag=${VLAN_ID}"
    qm set ${vmid} --ipconfig0 "ip=${ip}/24,gw=${VLAN_GATEWAY}"
    pvesh set /cluster/ha/resources --sid "vm:${vmid}" --group kubernetes --state enabled
    check_status "${name} creation"
}

create_lb ${KLB1_VMID} "klb1" ${KLB1_IP}
create_lb ${KLB2_VMID} "klb2" ${KLB2_IP}

# 6. Start VMs
echo "🚀 Starting VMs..."

for vmid in ${KMASTER1_VMID} ${KMASTER2_VMID} ${KNODE1_VMID} ${KNODE2_VMID} ${KNODE3_VMID} ${KNODE4_VMID} ${KLB1_VMID} ${KLB2_VMID}; do
    qm start ${vmid}
    check_status "Starting VM ${vmid}"
done

echo "✅ Proxmox setup completed successfully!"
echo "⚠️ Please wait a few minutes for all VMs to fully start before proceeding with node configuration."
