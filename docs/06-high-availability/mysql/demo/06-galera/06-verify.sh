#!/usr/bin/env bash
# 06-verify.sh — Verify Galera cluster health. Read-only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

wsrep_var() {
  local node="$1" var="$2"
  mysql_q "$node" "SHOW STATUS LIKE '${var}';" | awk '{print $2}' | head -n1
}

log "================ VERIFY GALERA CLUSTER ================"

for N in node1 node2 node3; do
  log "--- ${N} ---"
  ACTIVE=$(vagrant ssh "$N" -c "sudo systemctl is-active mysql 2>/dev/null" | tr -d '\r' | tail -n1)
  [[ "${ACTIVE}" == "active" ]] && mark_ok "[$N] mysql active" || mark_fail "[$N] mysql=${ACTIVE}"

  for PORT in 3306 4567; do
    P=$(vagrant ssh "$N" -c "sudo ss -tlnp 2>/dev/null | grep ':${PORT} ' || true" | head -n1)
    [[ -n "$P" ]] && mark_ok "[$N] port ${PORT} listening" || mark_fail "[$N] port ${PORT} not listening"
  done

  CS=$(wsrep_var "$N" "wsrep_cluster_size")
  CSTATUS=$(wsrep_var "$N" "wsrep_cluster_status")
  LSC=$(wsrep_var "$N" "wsrep_local_state_comment")
  RDY=$(wsrep_var "$N" "wsrep_ready")
  CONN=$(wsrep_var "$N" "wsrep_connected")

  [[ "$CS" == "3" ]]         && mark_ok "[$N] wsrep_cluster_size=3" || mark_fail "[$N] wsrep_cluster_size=$CS"
  [[ "$CSTATUS" == "Primary" ]] && mark_ok "[$N] wsrep_cluster_status=Primary" || mark_fail "[$N] wsrep_cluster_status=$CSTATUS"
  [[ "$LSC" == "Synced" ]]   && mark_ok "[$N] wsrep_local_state_comment=Synced" || mark_fail "[$N] wsrep_local_state_comment=$LSC"
  [[ "$RDY" == "ON" ]]       && mark_ok "[$N] wsrep_ready=ON" || mark_fail "[$N] wsrep_ready=$RDY"
  [[ "$CONN" == "ON" ]]      && mark_ok "[$N] wsrep_connected=ON" || mark_fail "[$N] wsrep_connected=$CONN"
done

# innodb_autoinc_lock_mode=2 (Galera bắt buộc)
for N in node1 node2 node3; do
  ALM=$(mysql_q "$N" "SELECT @@innodb_autoinc_lock_mode;")
  [[ "$ALM" == "2" ]] && mark_ok "[$N] innodb_autoinc_lock_mode=2" || mark_fail "[$N] innodb_autoinc_lock_mode=$ALM"
done

log "================ KẾT QUẢ ================"
if $pass; then
  log "VERIFY_PASS=true"
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false"
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
