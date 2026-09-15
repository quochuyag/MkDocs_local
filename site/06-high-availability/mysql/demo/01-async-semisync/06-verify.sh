#!/usr/bin/env bash
# 06-verify.sh — Tổng hợp checkpoint của cluster Async/Semi-sync.
# Read-only, an toàn rerun nhiều lần.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"   # clear log mỗi lần verify

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

# Helper: chạy mysql query ngắn gọn, in 1 dòng
mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

log "================ VERIFY ASYNC / SEMI-SYNC CLUSTER ================"

# 1 & 2 & 3 — Service, port, baseline
for N in node1 node2 node3; do
  log "--- ${N} ---"
  ACTIVE=$(vagrant ssh "$N" -c "sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mysqld 2>/dev/null" | tr -d '\r' | tail -n1)
  if [[ "${ACTIVE}" == "active" ]]; then mark_ok "[$N] mysql service active"; else mark_fail "[$N] mysql service = ${ACTIVE}"; fi

  PORT=$(vagrant ssh "$N" -c "sudo ss -tlnp 2>/dev/null | grep ':3306 ' || true" | head -n1)
  if [[ -n "${PORT}" ]]; then mark_ok "[$N] port 3306 listening"; else mark_fail "[$N] port 3306 not listening"; fi

  BASELINE=$(mysql_q "$N" "SELECT @@gtid_mode,@@log_bin,@@binlog_format;")
  if [[ "${BASELINE}" == *"ON"*"1"*"ROW"* ]]; then mark_ok "[$N] gtid+binlog baseline OK ($BASELINE)"; else mark_fail "[$N] baseline=$BASELINE"; fi
done

# 4 — Plugin semi-sync
log "--- plugin semi-sync trên 3 node ---"
P1=$(mysql_q node1 "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='rpl_semi_sync_source';")
P2=$(mysql_q node2 "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='rpl_semi_sync_replica';")
P3=$(mysql_q node3 "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='rpl_semi_sync_replica';")
[[ "$P1" == "ACTIVE" ]] && mark_ok "[node1] rpl_semi_sync_source = ACTIVE" || mark_fail "[node1] rpl_semi_sync_source = '$P1'"
[[ "$P2" == "ACTIVE" ]] && mark_ok "[node2] rpl_semi_sync_replica = ACTIVE" || mark_fail "[node2] rpl_semi_sync_replica = '$P2'"
[[ "$P3" == "ACTIVE" ]] && mark_ok "[node3] rpl_semi_sync_replica = ACTIVE" || mark_fail "[node3] rpl_semi_sync_replica = '$P3'"

# 5 & 6 — Master status & clients
log "--- master status & clients ---"
SRC_STATUS=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';" | awk '{print $2}')
SRC_CLIENTS=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';" | awk '{print $2}')
[[ "$SRC_STATUS"  == "ON" ]] && mark_ok "[node1] Rpl_semi_sync_source_status = ON"  || mark_fail "[node1] source_status=$SRC_STATUS"
[[ "$SRC_CLIENTS" == "2"  ]] && mark_ok "[node1] Rpl_semi_sync_source_clients = 2" || mark_fail "[node1] clients=$SRC_CLIENTS (expect 2)"

# 7, 8, 9, 10 — Replica state
for N in node2 node3; do
  log "--- ${N} replica state ---"
  IO=$(mysql_q "$N" "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status;")
  SQL=$(mysql_q "$N" "SELECT SERVICE_STATE FROM performance_schema.replication_applier_status;")
  LAG=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"SHOW REPLICA STATUS\\G\" 2>/dev/null | awk -F': ' '/Seconds_Behind_Source/ {print \$2; exit}'" | tr -d '\r')
  IOERR=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"SHOW REPLICA STATUS\\G\" 2>/dev/null | awk -F': ' '/Last_IO_Error/ {print \$2; exit}'" | tr -d '\r')
  SQLERR=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"SHOW REPLICA STATUS\\G\" 2>/dev/null | awk -F': ' '/Last_SQL_Error/ {print \$2; exit}'" | tr -d '\r')
  SRO=$(mysql_q "$N" "SELECT @@super_read_only;")
  RPL_STATUS=$(mysql_q "$N" "SHOW STATUS LIKE 'Rpl_semi_sync_replica_status';" | awk '{print $2}')

  [[ "$IO"  == "ON" ]] && mark_ok "[$N] IO thread ON"   || mark_fail "[$N] IO=$IO"
  [[ "$SQL" == "ON" ]] && mark_ok "[$N] SQL thread ON"  || mark_fail "[$N] SQL=$SQL"
  if [[ "$LAG" =~ ^[0-9]+$ && "$LAG" -le 2 ]]; then mark_ok "[$N] lag=${LAG}s"; else mark_fail "[$N] lag=${LAG}"; fi
  [[ -z "$IOERR"  ]] && mark_ok "[$N] no IO error"      || mark_fail "[$N] IO error: $IOERR"
  [[ -z "$SQLERR" ]] && mark_ok "[$N] no SQL error"     || mark_fail "[$N] SQL error: $SQLERR"
  [[ "$SRO" == "1" ]] && mark_ok "[$N] super_read_only=1" || mark_fail "[$N] super_read_only=$SRO"
  [[ "$RPL_STATUS" == "ON" ]] && mark_ok "[$N] Rpl_semi_sync_replica_status=ON" || mark_fail "[$N] replica_status=$RPL_STATUS"
done

log "==================== KẾT QUẢ ===================="
if $pass; then
  log "VERIFY_PASS=true — cluster sẵn sàng cho smoke test."
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false — kiểm tra log để xem checkpoint nào FAIL."
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
