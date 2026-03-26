# Kubernetes Node Scaling on AWS EC2 — Complete Runbook

## Project Structure

```
baremetal-k8s-cluster/
├── infra/
│   ├── main.tf                  # VPC, SG, key pair, EC2 instances
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars         # Your values go here
│   └── modules/node/main.tf     # Reusable EC2 node module
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
    ├── add-node.sh              # Terraform + join new EC2 worker
    ├── remove-node.sh           # Cordon + drain + delete + Terraform destroy
    ├── autoscaler-sim.sh        # CPU/Mem polling loop
    ├── autoscaler-sim.service   # systemd unit for autoscaler
    └── demo-rescheduling.sh     # Before/after pod placement demo
```

---

## 1. Prerequisites

| Tool | Install |
|------|---------|
| Terraform ≥ 1.6 | https://developer.hashicorp.com/terraform/install |
| AWS CLI v2 | `winget install Amazon.AWSCLI` |
| kubectl ≥ 1.29 | `winget install Kubernetes.kubectl` |
| SSH key pair | `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa` |

Configure AWS credentials:
```bash
aws configure
# AWS Access Key ID:     <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region:        us-east-1
# Default output format: json
```

---

## 2. Infrastructure Setup (Terraform → AWS EC2)

```bash
# 1. Fill in your values
vim infra/terraform.tfvars
#   ssh_pubkey       = "$(cat ~/.ssh/id_rsa.pub)"
#   allowed_ssh_cidr = "$(curl -s ifconfig.me)/32"

# 2. Deploy
cd infra
terraform init
terraform apply -auto-approve

# 3. Get IPs
terraform output
# control_plane_public_ip  = "54.x.x.x"
# control_plane_private_ip = "10.0.1.x"
# worker_public_ips        = ["54.x.x.x", "54.x.x.x"]
```

What Terraform creates:
- VPC + public subnet + internet gateway
- Security group (SSH, K8s API :6443, NodePorts 30000-32767, intra-cluster)
- EC2 key pair from your public key
- 1 control-plane + N worker `t3.medium` instances
- Each instance runs cloud-init to install containerd + kubeadm on boot

---

## 3. Kubernetes Cluster Setup

### 3a. Bootstrap control plane

```bash
# Wait ~3 min for cloud-init to finish, then:
ssh -i ~/.ssh/id_rsa ubuntu@<control_plane_public_ip>

sudo bash /tmp/bootstrap-cluster.sh
# Prints the kubeadm join command at the end — copy it
```

### 3b. Join workers

```bash
# On each worker:
ssh -i ~/.ssh/id_rsa ubuntu@<worker_public_ip>
sudo kubeadm join 10.0.1.x:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### 3c. Configure kubectl on your local machine

```bash
# Copy kubeconfig from control plane
scp -i ~/.ssh/id_rsa ubuntu@<control_plane_public_ip>:~/.kube/config ~/.kube/config

# Replace the private IP in the kubeconfig with the public IP
sed -i 's|https://10.0.1.*:6443|https://<control_plane_public_ip>:6443|' ~/.kube/config

kubectl get nodes -o wide
# NAME                STATUS   ROLES           AGE   VERSION
# k8s-control-plane   Ready    control-plane   2m    v1.29.x
# k8s-worker-1        Ready    <none>          1m    v1.29.x
# k8s-worker-2        Ready    <none>          1m    v1.29.x
```

### 3d. Install metrics-server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

---

## 4. Deploy Applications

### 4a. Stateless — nginx

```bash
kubectl apply -f k8s/apps/stateless/nginx.yaml
kubectl get pods -o wide

# Test (use any worker public IP)
curl http://<worker_public_ip>:30080
```

### 4b. Stateful — Redis

```bash
kubectl apply -f k8s/storage/storageclass.yaml
kubectl apply -f k8s/storage/local-pv.yaml
kubectl apply -f k8s/apps/stateful/redis.yaml

kubectl get pods -o wide
kubectl get pvc

# Test persistence
kubectl exec -it redis-0 -- redis-cli set demo "hello-ec2"
kubectl exec -it redis-0 -- redis-cli get demo
# → "hello-ec2"
```

---

## 5. Scale Up — Add a Node

```bash
# SSH_KEY_PATH is used by add-node.sh to SSH into the new EC2 instance
export SSH_KEY_PATH=~/.ssh/id_rsa
bash scripts/add-node.sh 3   # scale from 2 → 3 workers

kubectl get pods -o wide -w
```

What happens:
1. Terraform launches a new `t3.medium` EC2 instance (`k8s-worker-3`)
2. cloud-init installs containerd + kubeadm (~3 min)
3. Script waits for `/tmp/node-ready` sentinel, then SSHs in and runs `kubeadm join`
4. Scheduler places pending/new pods on the new node

---

## 6. Scale Down — Remove a Node

```bash
bash scripts/remove-node.sh k8s-worker-3 2

kubectl get pods -o wide -w
```

What happens:
1. `kubectl cordon` → node marked Unschedulable
2. `kubectl drain` → pods evicted with 30s grace period
3. `kubectl delete node` → removed from cluster
4. Terraform terminates the EC2 instance

---

## 7. Autoscaler Simulation

### Run as systemd service on the control plane

```bash
# Copy project to control plane
scp -i ~/.ssh/id_rsa -r . ubuntu@<control_plane_public_ip>:/opt/k8s-cluster/

# Install and start
ssh -i ~/.ssh/id_rsa ubuntu@<control_plane_public_ip>
sudo cp /opt/k8s-cluster/scripts/autoscaler-sim.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now autoscaler-sim
sudo journalctl -fu autoscaler-sim
```

### Trigger scale-up (load test)

```bash
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

---

## 9. Estimated AWS Cost

| Resource | Type | $/hr | $/day |
|----------|------|------|-------|
| control-plane | t3.medium | $0.0416 | ~$1.00 |
| worker-1 | t3.medium | $0.0416 | ~$1.00 |
| worker-2 | t3.medium | $0.0416 | ~$1.00 |
| 3× EBS gp3 20GB | storage | — | ~$0.15 |
| **Total (2 workers)** | | | **~$3.15/day** |

Stop instances when not in use: `terraform destroy -auto-approve`

---

## 10. Teardown

```bash
cd infra
terraform destroy -auto-approve
```

This terminates all EC2 instances, deletes the VPC, SG, and key pair.
