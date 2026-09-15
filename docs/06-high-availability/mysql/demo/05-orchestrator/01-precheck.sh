#!/usr/bin/env bash
# 01-precheck.sh — Kiểm tra Demo 01 (async/semi-sync) đã chạy thành công.
# MHA chỉ cài lên TOP của 1 cụm master + replicas đã có sẵn.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/01-precheck.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
mark_fail() { printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; PRECHECK_PASS=false; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

PRECHECK_PASS=true

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

log "================ PRECHECK DEMO 01 (Async/Semi-sync) ================"

# 1 — 4 VMs running
for N in node1 node2 node3 mgmt; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" == "running" ]] && mark_ok "[$N] running" || mark_fail "[$N] state=$STATE (cần 'running')"
done

# 2 — MySQL active + semi-sync trên 3 DB nodes
for N in node1 node2 node3; do
  ACTIVE=$(vagrant ssh "$N" -c "sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mysqld 2>/dev/null" | tr -d '\r' | tail -n1)
  [[ "$ACTIVE" == "active" ]] && mark_ok "[$N] mysql active" || mark_fail "[$N] mysql=$ACTIVE"
done

# 3 — node1 là master với semi-sync ON
SEMI=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';" | awk '{print $2}')
CLIENTS=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';" | awk '{print $2}')
[[ "$SEMI" == "ON" ]]      && mark_ok "[node1] semi-sync source ON" || mark_fail "[node1] semi-sync source=$SEMI"
[[ "$CLIENTS" == "2" ]]    && mark_ok "[node1] 2 semi-sync clients connected" || mark_fail "[node1] semi-sync clients=$CLIENTS"

# 4 — node2, node3 là replica với IO/SQL running
for N in node2 node3; do
  STATUS=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'SHOW REPLICA STATUS\\G' 2>/dev/null")
  IO=$(echo "$STATUS" | awk -F': ' '/Replica_IO_Running/{print $2}' | tr -d ' \r')
  SQ=$(echo "$STATUS" | awk -F': ' '/Replica_SQL_Running/{print $2}' | tr -d ' \r' | head -1)
  [[ "$IO" == "Yes" ]] && mark_ok "[$N] Replica_IO_Running=Yes" || mark_fail "[$N] Replica_IO_Running=$IO"
  [[ "$SQ" == "Yes" ]] && mark_ok "[$N] Replica_SQL_Running=Yes" || mark_fail "[$N] Replica_SQL_Running=$SQ"
done

# 5 — report_host phải set (Orchestrator dùng SHOW SLAVE HOSTS để discover)
for N in node1 node2 node3; do
  RH=$(mysql_q "$N" "SELECT @@report_host;")
  [[ -n "$RH" ]] && mark_ok "[$N] report_host='${RH}'" || mark_fail "[$N] report_host trống (Orchestrator cần để discover)"
done

log "================ KẾT QUẢ ================"
if $PRECHECK_PASS; then
  log "PRECHECK_PASS=true — sẵn sàng cài Orchestrator."
  echo "PRECHECK_PASS=true" >> "${LOG}"
  exit 0
else
  log "PRECHECK_PASS=false — chạy Demo 01 (../01-async-semisync/run-all.sh) trước khi tiếp tục."
  echo "PRECHECK_PASS=false" >> "${LOG}"
  exit 1
fi
