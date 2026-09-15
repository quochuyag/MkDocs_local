#!/usr/bin/env bash
# 06-failover-demo.sh — Halt 1 backend → ProxySQL detect, đẩy ra OFFLINE_HARD.
# Test traffic vẫn flow qua các backend còn lại. DESTRUCTIVE (halt 1 VM).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-failover.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

TARGET_NODE="${TARGET_NODE:-node3}"  # halt node3 mặc định (1 trong các reader)
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

admin_q() {
  vagrant ssh mgmt -c "mysql -uadmin -padmin -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -N -B -e \"$1\" 2>/dev/null" | tr -d '\r'
}

app_q() {
  vagrant ssh mgmt -c "mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P${PROXYSQL_MYSQL_PORT} -N -B -e \"$1\" 2>/dev/null" | tr -d '\r'
}

log "================ FAILOVER DEMO (halt ${TARGET_NODE}) ================"

# Lấy IP của TARGET
TARGET_IP=""
case "${TARGET_NODE}" in
  node1) TARGET_IP="${NODE1_IP}" ;;
  node2) TARGET_IP="${NODE2_IP}" ;;
  node3) TARGET_IP="${NODE3_IP}" ;;
  *) log "[FAIL] TARGET_NODE không hợp lệ"; exit 1 ;;
esac

log "==> Trước halt: runtime_mysql_servers"
admin_q "SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;" | tee -a "${LOG}"

# Halt
log "==> Halt --force ${TARGET_NODE} (${TARGET_IP})"
HALT_TS=$(date +%s)
vagrant halt --force "${TARGET_NODE}" 2>&1 | tee -a "${LOG}"

# Poll ProxySQL status cho đến khi ${TARGET_IP} chuyển sang SHUNNED hoặc OFFLINE_HARD (timeout 30s)
log "==> Poll status của ${TARGET_IP} (timeout 30s)"
NEW_STATUS=""
DETECT_RTO=""
for i in $(seq 1 30); do
  ST=$(admin_q "SELECT status FROM runtime_mysql_servers WHERE hostname='${TARGET_IP}' ORDER BY hostgroup_id LIMIT 1;")
  if [[ "$ST" == "SHUNNED" || "$ST" == "OFFLINE_HARD" ]]; then
    NEW_STATUS="$ST"
    DETECT_RTO=$(( $(date +%s) - HALT_TS ))
    log "    ProxySQL detected ${TARGET_IP} = ${NEW_STATUS} sau ${DETECT_RTO}s"
    break
  fi
  (( i % 5 == 0 )) && log "    status=${ST} (${i}s)"
  sleep 1
done

# Verify traffic vẫn OK qua các backend còn sống
log "==> 6 SELECT qua :${PROXYSQL_MYSQL_PORT} (phải không hit ${TARGET_IP})"
HIT_TARGET=false
for i in 1 2 3 4 5 6; do
  H=$(app_q "SELECT @@hostname;" || echo FAIL)
  log "    hit #$i → ${H}"
  if [[ "${H}" == "${TARGET_NODE}" ]]; then HIT_TARGET=true; fi
done

# Trạng thái cuối
log "==> Sau halt: runtime_mysql_servers"
admin_q "SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;" | tee -a "${LOG}"

log "================ KẾT LUẬN ================"
pass=true
[[ -n "${NEW_STATUS}" ]] || { log "[FAIL] ProxySQL không detect ${TARGET_IP} offline"; pass=false; }
$HIT_TARGET && { log "[FAIL] Vẫn có request route vào ${TARGET_NODE} sau halt"; pass=false; }

if $pass; then
  log "FAILOVER_PASS=true  DETECT_RTO=${DETECT_RTO}s  TARGET=${TARGET_NODE}  NEW_STATUS=${NEW_STATUS}"
  echo "FAILOVER_PASS=true" >> "${LOG}"
else
  echo "FAILOVER_PASS=false" >> "${LOG}"
fi

log ""
log "Recovery: vagrant up ${TARGET_NODE}  →  ProxySQL tự re-include khi probe lại thấy ONLINE"
