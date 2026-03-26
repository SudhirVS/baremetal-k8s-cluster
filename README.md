# Bare-Metal Kubernetes Node Scaling — Complete Runbook

## Project Structure

```
baremetal-k8s-cluster/
├── infra/
│   ├── main.tf                  # Root: provisions VMs via libvirt
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars         # Your values go here
│   └── modules/node/main.tf     # Reusable VM module
├── k8s/
│   ├── apps/
│   │   ├── stateless/nginx.yaml
│   │   └── stateful/redis.yaml
│   └── storage/
│       ├── storageclass.yaml
│       └── local-pv.yaml
└── scripts/
    ├── bootstrap-cluster.sh     # Init control plane + install Calico
    ├── join-worker.sh           # Join a worker node
    ├── add-node.sh              # Terraform + join new worker
    ├── remove-node.sh           # Cordon + drain + delete + Terraform
    ├── autoscaler-sim.sh        # CPU/Mem polling loop
    ├── autoscaler-sim.service   # systemd unit for autoscaler
    └── demo-rescheduling.sh     # Before/after pod placement demo
```

---

## 1. Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.6 | `apt install terraform` |
| libvirt / KVM | any | `apt install qemu-kvm libvirt-daemon-system` |
| kubectl | ≥ 1.29 | via k8s apt repo |
| kubeadm | ≥ 1.29 | via k8s apt repo |
| metrics-server | latest | kubectl apply (step 3) |

System requirements per node: 2 vCPU, 2 GB RAM, 20 GB disk.

---

## 2. Infrastructure Setup (Terraform)

```bash
# Edit your SSH public key and IPs
vim infra/terraform.tfvars

cd infra
terraform init
terraform apply -auto-approve

# Outputs: control_plane_ip, worker_ips
terraform output
```

---

## 3. Kubernetes Cluster Setup

### 3a. Bootstrap control plane (run ON the control-plane VM)

```bash
ssh ubuntu@192.168.122.10
sudo bash /tmp/bootstrap-cluster.sh
# Copy the printed "kubeadm join ..." command
```

### 3b. Join workers (run ON each worker VM)

```bash
ssh ubuntu@192.168.122.11
sudo kubeadm join 192.168.122.10:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Repeat for 192.168.122.12
```

### 3c. Install metrics-server (needed for autoscaler-sim)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for bare-metal (no TLS cert on kubelet)
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### 3d. Verify cluster

```bash
kubectl get nodes -o wide
# Expected:
# NAME                STATUS   ROLES           AGE   VERSION
# k8s-control-plane   Ready    control-plane   2m    v1.29.x
# k8s-worker-1        Ready    <none>          1m    v1.29.x
# k8s-worker-2        Ready    <none>          1m    v1.29.x
```

---

## 4. Deploy Applications

### 4a. Stateless — nginx

```bash
kubectl apply -f k8s/apps/stateless/nginx.yaml

kubectl get pods -o wide
# 4 replicas spread across workers via topologySpreadConstraints

# Test
curl http://192.168.122.11:30080
```

### 4b. Stateful — Redis

```bash
# Create storage class and PV first
kubectl apply -f k8s/storage/storageclass.yaml
kubectl apply -f k8s/storage/local-pv.yaml

# Deploy Redis StatefulSet
kubectl apply -f k8s/apps/stateful/redis.yaml

kubectl get pods -o wide
kubectl get pvc

# Test persistence
kubectl exec -it redis-0 -- redis-cli set demo "hello-baremetal"
kubectl exec -it redis-0 -- redis-cli get demo
# → "hello-baremetal"
```

---

## 5. Scale Up — Add a Node

```bash
# From your local machine (with Terraform + kubectl configured)
bash scripts/add-node.sh 3   # scale from 2 → 3 workers

# Watch pods reschedule to new node
kubectl get pods -o wide -w
```

What happens:
- Terraform provisions `k8s-worker-3` VM
- cloud-init installs containerd + kubeadm
- Script SSHs in and runs `kubeadm join`
- Scheduler places new pods on the new node

---

## 6. Scale Down — Remove a Node

```bash
bash scripts/remove-node.sh k8s-worker-3 2   # remove worker-3, scale back to 2

# Watch pods move off the drained node
kubectl get pods -o wide -w
```

What happens:
1. `kubectl cordon` → node marked Unschedulable
2. `kubectl drain` → pods evicted gracefully (30s grace period)
3. `kubectl delete node` → removed from cluster
4. Terraform destroys the VM

---

## 7. Autoscaler Simulation

### Run manually (foreground)

```bash
bash scripts/autoscaler-sim.sh
```

### Run as systemd service (background, persistent)

```bash
sudo cp scripts/autoscaler-sim.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now autoscaler-sim
sudo journalctl -fu autoscaler-sim
```

### Trigger scale-up manually (load test)

```bash
# Generate CPU load on workers
kubectl run load --image=busybox --restart=Never -- \
  sh -c "while true; do :; done"

# Watch autoscaler react within ~60s
sudo journalctl -fu autoscaler-sim
```

### Thresholds (edit in autoscaler-sim.sh)

| Variable | Default | Meaning |
|----------|---------|---------|
| CPU_SCALE_UP | 70% | Add node if avg CPU > 70% |
| CPU_SCALE_DOWN | 20% | Remove node if avg CPU < 20% |
| MEM_SCALE_UP | 75% | Add node if avg MEM > 75% |
| MIN_WORKERS | 2 | Never go below 2 workers |
| MAX_WORKERS | 5 | Never exceed 5 workers |
| COOLDOWN | 180s | Wait between scaling actions |

---

## 8. Workload Rescheduling Demo

```bash
bash scripts/demo-rescheduling.sh k8s-worker-2
```

Sample output:

```
════════════════════════════════════════
 BEFORE: Pod distribution across nodes
════════════════════════════════════════
nginx-7d4b9c-abc12          k8s-worker-1        default
nginx-7d4b9c-def34          k8s-worker-2        default
nginx-7d4b9c-ghi56          k8s-worker-1        default
nginx-7d4b9c-jkl78          k8s-worker-2        default
redis-0                     k8s-worker-1        default

==> Removing node: k8s-worker-2
[cordon → drain → delete → terraform destroy]

════════════════════════════════════════
 AFTER: Pod distribution across nodes
════════════════════════════════════════
nginx-7d4b9c-abc12          k8s-worker-1        default
nginx-7d4b9c-def34          k8s-worker-1        default   ← rescheduled
nginx-7d4b9c-ghi56          k8s-worker-1        default
nginx-7d4b9c-jkl78          k8s-worker-1        default   ← rescheduled
redis-0                     k8s-worker-1        default   ← PVC stays bound
```

---

## 9. Capacity Planning Basics

### Rule of thumb for bare-metal

```
Allocatable CPU per node  = Total CPU  - 0.1 core  (kubelet overhead)
Allocatable MEM per node  = Total MEM  - 300 MiB   (system + kubelet)

Required nodes = ceil(sum(pod CPU requests) / allocatable CPU per node)
Buffer         = +1 node (N+1 redundancy)
```

### Example (this cluster)

| Node | Allocatable CPU | Allocatable MEM |
|------|----------------|----------------|
| worker-1 | 1.9 cores | 1.7 GB |
| worker-2 | 1.9 cores | 1.7 GB |
| **Total** | **3.8 cores** | **3.4 GB** |

nginx (4 pods × 100m) = 400m CPU → fits easily  
Redis (1 pod × 100m + 128Mi) → fits on any single node  
Buffer node triggers at 70% → ~2.66 cores used → add node 3

---

## 10. Trade-offs vs Cloud Autoscaling

| Aspect | Bare-Metal (this setup) | Cloud Autoscaler |
|--------|------------------------|-----------------|
| Speed | 3–5 min (VM boot + join) | 60–90 sec |
| Cost | Fixed hardware cost | Pay-per-use |
| Control | Full control | Limited to provider API |
| Complexity | Manual join, no cloud API | Fully automated |
| Failure recovery | Manual intervention | Auto-replace |
| Spot/preemptible | Not available | Available (cost savings) |
| Scale to zero | Not practical | Supported |
| Best for | Predictable, stable workloads | Bursty, variable workloads |
