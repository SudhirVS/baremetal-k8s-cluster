#!/bin/bash
# remove-node.sh
# Safely drains and removes a worker node, then destroys its VM via Terraform.
# Usage: ./remove-node.sh <node-name> <new_worker_count>

set -euo pipefail

NODE_NAME="${1:?Usage: $0 <node-name> <new_worker_count>}"
NEW_COUNT="${2:?Usage: $0 <node-name> <new_worker_count>}"
INFRA_DIR="$(dirname "$0")/../infra"

echo "==> [1/4] Cordoning ${NODE_NAME} (no new pods scheduled)..."
kubectl cordon "${NODE_NAME}"

echo "==> [2/4] Draining ${NODE_NAME} (evicting pods gracefully)..."
kubectl drain "${NODE_NAME}" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30 \
  --timeout=120s

echo "==> [3/4] Deleting node from cluster..."
kubectl delete node "${NODE_NAME}"

echo "==> [4/4] Scaling down Terraform to ${NEW_COUNT} workers..."
terraform -chdir="${INFRA_DIR}" apply \
  -var="worker_count=${NEW_COUNT}" \
  -auto-approve

echo ""
echo "==> Done. Remaining nodes:"
kubectl get nodes -o wide
