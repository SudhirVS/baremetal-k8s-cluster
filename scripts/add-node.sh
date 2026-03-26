#!/bin/bash
# add-node.sh
# Provisions a new worker via Terraform and joins it to the cluster.
# Usage: ./add-node.sh <new_worker_count>

set -euo pipefail

INFRA_DIR="$(dirname "$0")/../infra"
NEW_COUNT="${1:-3}"

echo "==> [1/3] Scaling infra to ${NEW_COUNT} workers via Terraform..."
terraform -chdir="${INFRA_DIR}" apply \
  -var="worker_count=${NEW_COUNT}" \
  -auto-approve

# Get the IP of the newest worker (last in the list)
NEW_NODE_IP=$(terraform -chdir="${INFRA_DIR}" output -json worker_ips \
  | python3 -c "import sys,json; ips=json.load(sys.stdin); print(ips[-1])")

echo "==> [2/3] New node IP: ${NEW_NODE_IP}. Waiting for SSH..."
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"${NEW_NODE_IP}" true 2>/dev/null; do
  sleep 5
done

echo "==> [3/3] Generating join command and joining node..."
JOIN_CMD=$(kubeadm token create --print-join-command)
ssh -o StrictHostKeyChecking=no ubuntu@"${NEW_NODE_IP}" "sudo ${JOIN_CMD}"

echo ""
echo "==> Done. Verify with: kubectl get nodes -o wide"
