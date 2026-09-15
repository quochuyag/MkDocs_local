#!/usr/bin/env bash
# 03-discover-topology.sh — Cho Orchestrator phát hiện cluster của Demo 01.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-discover-topology.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> Discover từ node1 (master)"
vagrant ssh mgmt -c "orchestrator-client -c discover -i ${NODE1_IP}:${MYSQL_PORT}" 2>&1 | tee -a "${LOG}"

# Force discover các replica để Orchestrator pick up nhanh (không phải đợi InstancePollSeconds)
log "==> Discover node2 + node3 (replicas) để force seed metadata"
vagrant ssh mgmt -c "
  orchestrator-client -c discover -i ${NODE2_IP}:${MYSQL_PORT} || true
  orchestrator-client -c discover -i ${NODE3_IP}:${MYSQL_PORT} || true
" 2>&1 | tee -a "${LOG}"

log "==> Đợi 5s cho Orchestrator probe cluster"
sleep 5

log "==> Topology"
vagrant ssh mgmt -c "orchestrator-client -c topology -i ${NODE1_IP}:${MYSQL_PORT}" 2>&1 | tee -a "${LOG}"

log "==> which-cluster-instances"
vagrant ssh mgmt -c "orchestrator-client -c which-cluster-instances -i ${NODE1_IP}:${MYSQL_PORT}" 2>&1 | tee -a "${LOG}"

log "==> which-cluster-master (master ghi-được của cluster)"
vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NODE1_IP}:${MYSQL_PORT}" 2>&1 | tee -a "${LOG}"

log "==> Bước 3 hoàn tất. Tiếp theo: bash demo/05-orchestrator/04-verify.sh"
