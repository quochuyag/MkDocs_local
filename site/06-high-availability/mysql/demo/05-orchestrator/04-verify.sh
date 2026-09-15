#!/usr/bin/env bash
# 04-verify.sh — API health + topology JSON + replication health (read-only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "================ VERIFY ORCHESTRATOR ================"

# 1 — service active
ACTIVE=$(vagrant ssh mgmt -c "sudo systemctl is-active orchestrator 2>/dev/null" | tr -d '\r' | tail -n1)
[[ "${ACTIVE}" == "active" ]] && mark_ok "orchestrator service active" || mark_fail "orchestrator service = ${ACTIVE}"

# 2 — port 3000 listening
P=$(vagrant ssh mgmt -c "sudo ss -tlnp 2>/dev/null | grep ':3000 ' || true" | head -n1)
[[ -n "${P}" ]] && mark_ok "port 3000 listening" || mark_fail "port 3000 not listening"

# 3 — HTTP API /api/health
H=$(vagrant ssh mgmt -c "curl -fsS -u admin:'${ADMIN_PWD}' http://127.0.0.1:3000/api/health 2>/dev/null" | head -c 200 || echo "FAIL")
if echo "$H" | grep -q "OK"; then mark_ok "API /api/health OK"; else mark_fail "API /api/health response: $H"; fi

# 4 — Topology shows 3 nodes
TOPO=$(vagrant ssh mgmt -c "orchestrator-client -c topology -i ${NODE1_IP}:${MYSQL_PORT} 2>&1" | tr -d '\r')
echo "${TOPO}" | tee -a "${LOG}"
NODE_COUNT=$(echo "${TOPO}" | grep -cE "${NODE1_IP}|${NODE2_IP}|${NODE3_IP}" || true)
[[ "${NODE_COUNT}" -ge "3" ]] && mark_ok "topology has 3 nodes ($NODE_COUNT lines match)" || mark_fail "topology only $NODE_COUNT/3 nodes"

# 5 — which-cluster-master = node1
# NOTE: dùng `which-cluster-master` (master ghi-được của cluster), KHÔNG dùng
#       `which-master -i nodeN` (vốn trả parent của nodeN → ":0" nếu nodeN là master).
WM=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NODE1_IP}:${MYSQL_PORT} 2>&1" | tr -d '\r' | tail -n1)
log "    which-cluster-master = ${WM}"
if echo "${WM}" | grep -q "${NODE1_IP}"; then
  mark_ok "current master = ${NODE1_IP}"
else
  mark_fail "current master unexpected: ${WM}"
fi

# 6 — replication-analysis: no DeadMaster
RA=$(vagrant ssh mgmt -c "orchestrator-client -c replication-analysis 2>/dev/null" | tr -d '\r')
echo "${RA}" | tee -a "${LOG}"
if echo "${RA}" | grep -qE "DeadMaster|UnreachableMaster"; then
  mark_fail "replication-analysis báo issue: $(echo "$RA" | grep -E 'Dead|Unreachable')"
else
  mark_ok "replication-analysis sạch (không có DeadMaster)"
fi

log "================ KẾT QUẢ ================"
if $pass; then
  log "VERIFY_PASS=true — Orchestrator sẵn sàng."
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false — xem log."
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
