#!/bin/bash
# autoscaler-sim.sh
# Polls cluster CPU/Memory via kubectl top. Adds a node if over threshold,
# removes one if underutilized. Runs as a loop (use with systemd or cron).

set -euo pipefail

# ── Thresholds ────────────────────────────────────────────────────────────────
CPU_SCALE_UP=70      # % avg CPU across nodes → add node
CPU_SCALE_DOWN=20    # % avg CPU across nodes → remove node
MEM_SCALE_UP=75      # % avg Memory across nodes → add node
MIN_WORKERS=2        # never go below this
MAX_WORKERS=5        # never exceed this
POLL_INTERVAL=60     # seconds between checks
COOLDOWN=180         # seconds to wait after a scaling action

INFRA_DIR="$(dirname "$0")/../infra"
LAST_ACTION=0

# ── Helpers ───────────────────────────────────────────────────────────────────
current_worker_count() {
  kubectl get nodes --no-headers \
    -l '!node-role.kubernetes.io/control-plane' | wc -l | tr -d ' '
}

# Returns average CPU% across all worker nodes using kubectl top
avg_cpu_percent() {
  local total=0 count=0
  while IFS= read -r line; do
    # kubectl top nodes outputs: NAME  CPU(cores)  CPU%  MEMORY(bytes)  MEMORY%
    cpu_pct=$(echo "$line" | awk '{gsub(/%/,"",$3); print $3}')
    total=$((total + cpu_pct))
    count=$((count + 1))
  done < <(kubectl top nodes --no-headers \
    -l '!node-role.kubernetes.io/control-plane' 2>/dev/null)
  [ "$count" -eq 0 ] && echo 0 && return
  echo $((total / count))
}

avg_mem_percent() {
  local total=0 count=0
  while IFS= read -r line; do
    mem_pct=$(echo "$line" | awk '{gsub(/%/,"",$5); print $5}')
    total=$((total + mem_pct))
    count=$((count + 1))
  done < <(kubectl top nodes --no-headers \
    -l '!node-role.kubernetes.io/control-plane' 2>/dev/null)
  [ "$count" -eq 0 ] && echo 0 && return
  echo $((total / count))
}

in_cooldown() {
  local now; now=$(date +%s)
  [ $((now - LAST_ACTION)) -lt $COOLDOWN ]
}

scale_up() {
  local current="$1"
  local new=$((current + 1))
  echo "[$(date)] SCALE UP: ${current} → ${new} workers (CPU=${2}%, MEM=${3}%)"
  "$(dirname "$0")/add-node.sh" "${new}"
  LAST_ACTION=$(date +%s)
}

scale_down() {
  local current="$1"
  local new=$((current - 1))
  # Pick the least-loaded worker to remove
  local target
  target=$(kubectl top nodes --no-headers \
    -l '!node-role.kubernetes.io/control-plane' 2>/dev/null \
    | sort -k3 -n | head -1 | awk '{print $1}')
  echo "[$(date)] SCALE DOWN: ${current} → ${new} workers. Removing ${target} (CPU=${2}%)"
  "$(dirname "$0")/remove-node.sh" "${target}" "${new}"
  LAST_ACTION=$(date +%s)
}

# ── Main loop ─────────────────────────────────────────────────────────────────
echo "[$(date)] Autoscaler started. Poll=${POLL_INTERVAL}s Cooldown=${COOLDOWN}s"

while true; do
  WORKERS=$(current_worker_count)
  CPU=$(avg_cpu_percent)
  MEM=$(avg_mem_percent)

  echo "[$(date)] Workers=${WORKERS} CPU=${CPU}% MEM=${MEM}%"

  if in_cooldown; then
    echo "[$(date)] In cooldown, skipping."
  elif [ "$CPU" -ge "$CPU_SCALE_UP" ] || [ "$MEM" -ge "$MEM_SCALE_UP" ]; then
    if [ "$WORKERS" -lt "$MAX_WORKERS" ]; then
      scale_up "$WORKERS" "$CPU" "$MEM"
    else
      echo "[$(date)] At MAX_WORKERS=${MAX_WORKERS}, cannot scale up."
    fi
  elif [ "$CPU" -le "$CPU_SCALE_DOWN" ]; then
    if [ "$WORKERS" -gt "$MIN_WORKERS" ]; then
      scale_down "$WORKERS" "$CPU" "$MEM"
    else
      echo "[$(date)] At MIN_WORKERS=${MIN_WORKERS}, cannot scale down."
    fi
  else
    echo "[$(date)] Within normal range, no action."
  fi

  sleep "${POLL_INTERVAL}"
done
