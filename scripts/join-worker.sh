#!/bin/bash
# join-worker.sh
# Run on each worker node. Pass the join command from bootstrap-cluster.sh output.
# Usage: ./join-worker.sh "<kubeadm join command>"

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 '<kubeadm join command>'"
  exit 1
fi

echo "==> Joining worker to cluster..."
eval "$1"

echo "==> Worker joined. Verify on control plane with: kubectl get nodes"
