#!/bin/bash
# demo-rescheduling.sh
# Shows pod placement before and after a node removal.

set -euo pipefail

TARGET_NODE="${1:?Usage: $0 <node-to-remove>}"

echo "════════════════════════════════════════"
echo " BEFORE: Pod distribution across nodes"
echo "════════════════════════════════════════"
kubectl get pods -o wide -A --field-selector=status.phase=Running \
  | grep -v "kube-system" \
  | awk '{printf "%-40s %-20s %-15s\n", $2, $8, $1}'

echo ""
echo "==> Removing node: ${TARGET_NODE}"
bash "$(dirname "$0")/remove-node.sh" "${TARGET_NODE}" \
  "$(($(kubectl get nodes --no-headers -l '!node-role.kubernetes.io/control-plane' | wc -l) - 1))"

echo ""
echo "==> Waiting 30s for pods to reschedule..."
sleep 30

echo ""
echo "════════════════════════════════════════"
echo " AFTER: Pod distribution across nodes"
echo "════════════════════════════════════════"
kubectl get pods -o wide -A --field-selector=status.phase=Running \
  | grep -v "kube-system" \
  | awk '{printf "%-40s %-20s %-15s\n", $2, $8, $1}'

echo ""
echo "==> Node status:"
kubectl get nodes -o wide
