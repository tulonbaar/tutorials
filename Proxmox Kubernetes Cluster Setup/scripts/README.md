# Kubernetes HA Cluster Setup Scripts

This directory contains scripts for setting up a High Availability Kubernetes cluster on Proxmox.

## Script Overview

1. `00-variables.sh`: Contains all configuration variables
2. `01-proxmox-setup.sh`: Sets up Proxmox VMs and storage
3. `02-loadbalancer-setup.sh`: Configures HAProxy and Keepalived
4. `03-master-setup.sh`: Sets up Kubernetes master nodes
5. `04-worker-setup.sh`: Sets up Kubernetes worker nodes

## Usage Instructions

1. First, edit `00-variables.sh` to match your environment:
   - Update IP addresses
   - Adjust resource allocations if needed
   - Modify storage paths if different

2. On the Proxmox host:
   ```bash
   chmod +x 01-proxmox-setup.sh
   ./01-proxmox-setup.sh
   ```

3. On each load balancer node:
   ```bash
   chmod +x 02-loadbalancer-setup.sh
   ./02-loadbalancer-setup.sh
   ```

4. On the master nodes:
   ```bash
   chmod +x 03-master-setup.sh
   ./03-master-setup.sh
   ```

5. On the worker nodes:
   ```bash
   chmod +x 04-worker-setup.sh
   ./04-worker-setup.sh
   ```

## Important Notes

- Run scripts in order (01 → 02 → 03 → 04)
- Ensure all VMs can reach each other before proceeding
- The first master node will generate join commands for other nodes
- Save the join commands and certificate key for adding other nodes

## Verification

After running all scripts, verify the cluster:
```bash
kubectl get nodes
kubectl get pods -n kube-system
```

## Troubleshooting

1. If a node fails to join:
   - Check network connectivity
   - Verify the join command is correct
   - Look at `/var/log/syslog` for errors

2. If pods won't start:
   - Check CNI installation
   - Verify node status
   - Check kubelet logs
