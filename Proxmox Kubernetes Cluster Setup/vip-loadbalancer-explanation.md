# Understanding Virtual IP (VIP) Load Balancer in Kubernetes HA Setup

## What is a VIP Load Balancer?
A Virtual IP (VIP) is a floating IP address that can move between multiple servers, providing high availability for critical services. In a Kubernetes HA setup, it serves as the primary access point for the Kubernetes API server.

## Key Components
1. **Virtual IP**: A floating IP address (e.g., 10.10.0.100)
2. **Load Balancer Nodes**: 
   - Active Node (klb1)
   - Passive Node (klb2)
3. **Software Components**:
   - Keepalived: Manages the VIP movement
   - HAProxy: Handles traffic distribution

## How It Works

### Normal Operation
```
Kubernetes Nodes → VIP (10.10.0.100 on klb1) → HAProxy → kmaster1/kmaster2
```

### Failover Scenario
1. Active load balancer (klb1) fails
2. Keepalived detects the failure
3. VIP automatically moves to passive node (klb2)
4. Traffic continues flowing through klb2
5. No manual intervention required
6. No service interruption for Kubernetes components

## Benefits
1. **High Availability**:
   - Eliminates single point of failure
   - Automatic failover
   - No manual intervention needed

2. **Consistent Access**:
   - Single endpoint for all cluster components
   - Used as `--control-plane-endpoint` in Kubernetes configuration
   - Stable access point regardless of active load balancer

3. **Load Distribution**:
   - Balances traffic between master nodes
   - Prevents overloading of individual master nodes
   - Improves overall cluster performance

## Implementation Notes
- VIP must be in the same subnet as the load balancer nodes
- Keepalived uses VRRP (Virtual Router Redundancy Protocol)
- HAProxy configuration must include all master nodes as backends
- Health checks ensure traffic only goes to healthy master nodes
