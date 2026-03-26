#!/bin/bash
# bootstrap-cluster.sh
# Run ON the control-plane EC2 instance after Terraform provisioning.
# The private IP is auto-detected from the EC2 metadata service.

set -euo pipefail

# EC2 metadata — gets the private IP assigned by AWS (used by kubeadm internally)
CONTROL_PLANE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
POD_CIDR="10.244.0.0/16"

echo "==> Control plane private IP: ${CONTROL_PLANE_IP}"
echo "==> Initializing control plane..."
kubeadm init \
  --apiserver-advertise-address="${CONTROL_PLANE_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --cri-socket unix:///run/containerd/containerd.sock \
  | tee /tmp/kubeadm-init.log

echo "==> Setting up kubeconfig..."
mkdir -p "$HOME/.kube"
cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "==> Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

echo "==> Waiting for control plane to be Ready..."
kubectl wait --for=condition=Ready node/"$(hostname)" --timeout=120s

echo ""
echo "==> Join command for workers:"
kubeadm token create --print-join-command
