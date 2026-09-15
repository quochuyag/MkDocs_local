#!/usr/bin/env bash
# 01-precheck.sh — Kiểm tra backend đã ready.
# BACKEND=async-semisync (default) — Demo 01 đã chạy
# BACKEND=galera                   — Demo 06 đã chạy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/01-precheck.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

BACKEND="${BACKEND:-async-semisync}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
mark_fail() { printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; PRECHECK_PASS=false; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

PRECHECK_PASS=true

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

log "================ PRECHECK PROXYSQL (BACKEND=${BACKEND}) ================"

# Common: 4 VMs running, MySQL active trên 3 nodes
for N in node1 node2 node3 mgmt; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" == "running" ]] && mark_ok "[$N] running" || mark_fail "[$N] state=$STATE"
done

for N in node1 node2 node3; do
  ACTIVE=$(vagrant ssh "$N" -c "sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mysqld 2>/dev/null" | tr -d '\r' | tail -n1)
  [[ "$ACTIVE" == "active" ]] && mark_ok "[$N] mysql active" || mark_fail "[$N] mysql=$ACTIVE"
done

case "${BACKEND}" in
  async-semisync)
    log "--- backend=async-semisync: check semi-sync trên node1 ---"
    SEMI=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';" | awk '{print $2}')
    [[ "$SEMI" == "ON" ]] && mark_ok "[node1] semi-sync ON" || mark_fail "[node1] semi-sync=$SEMI (chạy Demo 01 trước)"
    for N in node2 node3; do
      IO=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'SHOW REPLICA STATUS\\G' 2>/dev/null" | awk -F': ' '/Replica_IO_Running/{print $2}' | tr -d ' \r')
      [[ "$IO" == "Yes" ]] && mark_ok "[$N] replica IO=Yes" || mark_fail "[$N] replica IO=$IO"
    done
    ;;
  galera)
    log "--- backend=galera: check wsrep_cluster_status=Primary trên 3 nodes ---"
    for N in node1 node2 node3; do
      CST=$(mysql_q "$N" "SHOW STATUS LIKE 'wsrep_cluster_status';" | awk '{print $2}')
      LSC=$(mysql_q "$N" "SHOW STATUS LIKE 'wsrep_local_state_comment';" | awk '{print $2}')
      [[ "$CST" == "Primary" && "$LSC" == "Synced" ]] && mark_ok "[$N] cluster=Primary local=Synced" || mark_fail "[$N] cluster=$CST local=$LSC (chạy Demo 06 trước)"
    done
    ;;
  *)
    mark_fail "BACKEND=${BACKEND} không hợp lệ. Dùng 'async-semisync' hoặc 'galera'."
    ;;
esac

log "================ KẾT QUẢ ================"
if $PRECHECK_PASS; then
  log "PRECHECK_PASS=true — sẵn sàng cài ProxySQL (BACKEND=${BACKEND})"
  echo "PRECHECK_PASS=true" >> "${LOG}"
  exit 0
else
  log "PRECHECK_PASS=false — chạy backend tương ứng trước (Demo 01 hoặc Demo 06)"
  echo "PRECHECK_PASS=false" >> "${LOG}"
  exit 1
fi
