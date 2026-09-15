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

# 1 — 4 VMs running. Detect not_created sớm: VMs chưa tồn tại → các check sau sẽ fail liên hoàn.
NOT_CREATED_COUNT=0
for N in node1 node2 node3 mgmt; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  if [[ "$STATE" == "running" ]]; then
    mark_ok "[$N] running"
  else
    mark_fail "[$N] state=$STATE (cần 'running')"
    [[ "$STATE" == "not_created" ]] && NOT_CREATED_COUNT=$((NOT_CREATED_COUNT+1))
  fi
done

# Exit sớm nếu ≥1 VM not_created — không có ý nghĩa check MySQL/replication vì SSH sẽ fail.
if (( NOT_CREATED_COUNT > 0 )); then
  log ""
  log "[FATAL] ${NOT_CREATED_COUNT}/4 VMs ở trạng thái 'not_created' — VirtualBox không có VM nào."
  log "  Nguyên nhân thường gặp: vagrant destroy đã chạy, hoặc VBox bị xoá VMs từ registry."
  log ""
  log "  Cách fix:"
  log "    1) Recreate VMs + setup async/semi-sync (Demo 01):"
  log "         bash demo/01-async-semisync/run-all.sh"
  log "       (Linux/macOS/WSL/Git Bash. Trên Windows PS: .\\demo\\01-async-semisync\\run-all.ps1)"
  log ""
  log "    2) Sau khi Demo 01 PASS, quay lại Demo 04:"
  log "         bash demo/04-mha/run-all.sh"
  log ""
  log "  Hoặc auto-bootstrap (chạy Demo 01 trước rồi tiếp tục):"
  log "         BOOTSTRAP_DEMO01=1 bash demo/04-mha/run-all.sh"
  log ""
  echo "PRECHECK_PASS=false" >> "${LOG}"
  exit 1
fi

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

# 5 — relay_log_purge=0 (MHA cần). Auto-fix nếu =1 vì variable này dynamic + persist được.
for N in node2 node3; do
  RLP=$(mysql_q "$N" "SELECT @@relay_log_purge;")
  if [[ "$RLP" == "0" ]]; then
    mark_ok "[$N] relay_log_purge=0 (MHA-ready)"
  else
    log "    [$N] relay_log_purge=$RLP → auto-fix: SET PERSIST relay_log_purge=0"
    vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"SET PERSIST relay_log_purge=0; SET GLOBAL relay_log_purge=0;\" 2>&1 | grep -v Warning" 2>&1 | tee -a "${LOG}" || true
    RLP2=$(mysql_q "$N" "SELECT @@relay_log_purge;")
    [[ "$RLP2" == "0" ]] && mark_ok "[$N] relay_log_purge=0 (auto-fixed, persisted)" || mark_fail "[$N] relay_log_purge=$RLP2 (auto-fix thất bại)"
  fi
done

log "================ KẾT QUẢ ================"
if $PRECHECK_PASS; then
  log "PRECHECK_PASS=true — sẵn sàng cài MHA."
  echo "PRECHECK_PASS=true" >> "${LOG}"
  exit 0
else
  log "PRECHECK_PASS=false — chạy Demo 01 (../01-async-semisync/run-all.sh) trước khi tiếp tục."
  echo "PRECHECK_PASS=false" >> "${LOG}"
  exit 1
fi
