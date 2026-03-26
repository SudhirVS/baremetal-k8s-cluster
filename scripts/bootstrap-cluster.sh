#!/bin/bash
# bootstrap-cluster.sh
# Run this on the control-plane node after Terraform provisioning

set -euo pipefail

CONTROL_PLANE_IP="192.168.122.10"
POD_CIDR="10.244.0.0/16"

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
