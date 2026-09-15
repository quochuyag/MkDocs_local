#!/usr/bin/env bash
# 07-force-failover-test.sh — halt master, đợi Orchestrator auto-recover, đo RTO.
# DESTRUCTIVE.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/07-force-failover.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

log "================ FORCE FAILOVER TEST (Orchestrator) ================"

# 0 — Current master
MASTER=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NODE1_IP}:${MYSQL_PORT} 2>/dev/null" | tr -d '\r' | tail -n1)
case "${MASTER}" in
  *"${NODE1_IP}"*) MASTER_HOST="node1"; MASTER_IP="${NODE1_IP}" ;;
  *"${NODE2_IP}"*) MASTER_HOST="node2"; MASTER_IP="${NODE2_IP}" ;;
  *"${NODE3_IP}"*) MASTER_HOST="node3"; MASTER_IP="${NODE3_IP}" ;;
  *) log "[FAIL] không parse được master"; exit 1 ;;
esac
log "==> Master ban đầu: ${MASTER_HOST} (${MASTER_IP})"

# 1 — Sentinel insert
SENT="orc-failover-$(date +%s)"
vagrant ssh "${MASTER_HOST}" -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    CREATE DATABASE IF NOT EXISTS smoke_db;
    CREATE TABLE IF NOT EXISTS smoke_db.t(id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(64), ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6));
    INSERT INTO smoke_db.t(val) VALUES('${SENT}');\"
" 2>&1 | tee -a "${LOG}"

# 2 — Đảm bảo recovery sẵn sàng:
#     (a) enable-global-recoveries (lỡ có ai disabled)
#     (b) ack mọi recovery cũ → tránh RecoveryPeriodBlockSeconds chặn lần này
log "==> Đảm bảo recoveries enabled + acknowledge mọi recovery cũ"
vagrant ssh mgmt -c "
  curl -fsS -u admin:'${ADMIN_PWD}' 'http://127.0.0.1:3000/api/enable-global-recoveries' 2>/dev/null || true
  echo
  orchestrator-client -c ack-all-recoveries -r 'force-failover-demo' 2>&1 || true
" 2>&1 | tee -a "${LOG}"

# 3 — HALT master
log "==> Halt --force ${MASTER_HOST}"
HALT_TS=$(date +%s)
vagrant halt --force "${MASTER_HOST}" 2>&1 | tee -a "${LOG}"

# 4 — Poll replication-analysis cho đến khi thấy DeadMaster + auto-recover.
#     Nếu sau 60s vẫn chưa promote, chủ động gọi force-master-failover (belt-and-braces).
log "==> Poll Orchestrator detection (timeout 120s)"
NEW_MASTER_IP=""
PROMOTE_RTO=""
FORCED=false
for i in $(seq 1 60); do
  ANALYSIS=$(vagrant ssh mgmt -c "orchestrator-client -c replication-analysis 2>/dev/null" | tr -d '\r' || true)
  if (( i % 5 == 0 )); then
    log "    progress (${i}*2s): ${ANALYSIS:0:120}..."
  fi

  # Sau 30 vòng × 2s = 60s mà chưa promote → kích force-master-failover chủ động
  if ! ${FORCED} && (( i == 30 )); then
    log "    [poke] 60s không tự promote — chủ động gọi force-master-failover -i ${MASTER_IP}:${MYSQL_PORT}"
    vagrant ssh mgmt -c "orchestrator-client -c force-master-failover -i ${MASTER_IP}:${MYSQL_PORT} 2>&1 || true" \
      2>&1 | tee -a "${LOG}" || true
    FORCED=true
  fi

  # Kiểm tra master mới qua which-cluster-master từ 1 replica còn sống
  for ALIVE in node1 node2 node3; do
    [[ "$ALIVE" == "${MASTER_HOST}" ]] && continue
    ALIVE_IP=""
    case "$ALIVE" in node1) ALIVE_IP="${NODE1_IP}" ;; node2) ALIVE_IP="${NODE2_IP}" ;; node3) ALIVE_IP="${NODE3_IP}" ;; esac
    CUR_M=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${ALIVE_IP}:${MYSQL_PORT} 2>/dev/null" | tr -d '\r' | tail -n1 || true)
    if [[ -n "${CUR_M}" && "${CUR_M}" != *"${MASTER_IP}"* && "${CUR_M}" != "" ]]; then
      NEW_MASTER_IP=$(echo "${CUR_M}" | grep -oE '[0-9.]+:[0-9]+' | head -n1 | cut -d: -f1)
      [[ -n "${NEW_MASTER_IP}" && "${NEW_MASTER_IP}" != "${MASTER_IP}" ]] && {
        PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
        log "    NEW MASTER detected: ${NEW_MASTER_IP} (qua ${ALIVE}) sau ${PROMOTE_RTO}s"
        break 2
      }
    fi
  done
  sleep 2
done

if [[ -z "${NEW_MASTER_IP}" ]]; then
  log "[FAIL] Orchestrator chưa promote master mới sau 120s"
  log "       Xem audit: vagrant ssh mgmt -c 'orchestrator-client -c audit-recovery'"
  vagrant ssh mgmt -c "orchestrator-client -c audit-recovery 2>&1 | tail -n 30" | tee -a "${LOG}" || true
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi

# 5 — Verify replica còn lại đã follow master mới
NEW_MASTER_HOST=""
case "${NEW_MASTER_IP}" in
  "${NODE1_IP}") NEW_MASTER_HOST="node1" ;;
  "${NODE2_IP}") NEW_MASTER_HOST="node2" ;;
  "${NODE3_IP}") NEW_MASTER_HOST="node3" ;;
esac
log "==> New master = ${NEW_MASTER_HOST}"

OTHER=""
for N in node1 node2 node3; do
  [[ "$N" != "${MASTER_HOST}" && "$N" != "${NEW_MASTER_HOST}" ]] && OTHER="$N"
done
if [[ -n "${OTHER}" ]]; then
  SRC=$(vagrant ssh "${OTHER}" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'SHOW REPLICA STATUS\\G' 2>/dev/null" | awk -F': ' '/Source_Host/{print $2}' | tr -d ' \r' | head -1)
  log "    ${OTHER} Source_Host = ${SRC}"
fi

# 6 — Test ghi vào master mới
WRITE_RTO=""
for i in $(seq 1 30); do
  if vagrant ssh "${NEW_MASTER_HOST}" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"USE smoke_db; INSERT INTO t(val) VALUES('post-force-failover');\" 2>/dev/null" >/dev/null; then
    WRITE_RTO=$(( $(date +%s) - HALT_TS ))
    log "    ${NEW_MASTER_HOST} chấp nhận INSERT sau ${WRITE_RTO}s"
    break
  fi
  sleep 1
done

# 7 — Kết luận
log "================ KẾT LUẬN ================"
pass=true
[[ -n "${NEW_MASTER_IP}" ]] || { log "[FAIL] không có master mới"; pass=false; }
[[ -n "${WRITE_RTO}" ]]     || { log "[FAIL] master mới chưa nhận INSERT"; pass=false; }

if $pass; then
  log "FAILOVER_PASS=true PROMOTE_RTO=${PROMOTE_RTO}s WRITE_RTO=${WRITE_RTO}s old=${MASTER_HOST} new=${NEW_MASTER_HOST}"
  echo "FAILOVER_PASS=true" >> "${LOG}"
else
  log "FAILOVER_PASS=false"
  echo "FAILOVER_PASS=false" >> "${LOG}"
fi

log ""
log "Để khôi phục ${MASTER_HOST}:"
log "  vagrant up ${MASTER_HOST}"
log "  vagrant ssh ${MASTER_HOST} -c \"mysql -uroot -p... -e 'CHANGE REPLICATION SOURCE TO SOURCE_HOST=\\\"${NEW_MASTER_IP}\\\", SOURCE_AUTO_POSITION=1, ...; START REPLICA;'\""
