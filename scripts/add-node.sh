#!/bin/bash
# add-node.sh
# Provisions a new EC2 worker via Terraform and joins it to the cluster.
# Usage: ./add-node.sh <new_worker_count>
# Run from a machine that has both Terraform and kubectl configured.

set -euo pipefail

INFRA_DIR="$(dirname "$0")/../infra"
NEW_COUNT="${1:-3}"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"

echo "==> [1/3] Scaling infra to ${NEW_COUNT} workers via Terraform..."
terraform -chdir="${INFRA_DIR}" apply \
  -var="worker_count=${NEW_COUNT}" \
  -auto-approve

# Get the public IP of the newest worker (last in the list)
NEW_NODE_IP=$(terraform -chdir="${INFRA_DIR}" output -json worker_public_ips \
  | python3 -c "import sys,json; ips=json.load(sys.stdin); print(ips[-1])")

echo "==> [2/3] New node public IP: ${NEW_NODE_IP}. Waiting for SSH + cloud-init..."
# Wait for cloud-init to finish (node-ready sentinel file written at end of user_data)
until ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    ubuntu@"${NEW_NODE_IP}" "test -f /tmp/node-ready" 2>/dev/null; do
  echo "    ...waiting for node-ready"
  sleep 10
done

echo "==> [3/3] Generating join command and joining node..."
JOIN_CMD=$(kubeadm token create --print-join-command)
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no ubuntu@"${NEW_NODE_IP}" "sudo ${JOIN_CMD}"

echo ""
echo "==> Done. Verify with: kubectl get nodes -o wide"
