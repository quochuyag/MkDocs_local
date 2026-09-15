#!/usr/bin/env bash
# 08-rebuild-old-master.sh — Sau failover, rebuild master cũ (node1) thành replica của master mới.
# Tham số: NEW_MASTER (env hoặc arg) — node mới đang là master. Mặc định auto-detect.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/08-rebuild-old-master.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

OLD_MASTER="${OLD_MASTER:-node1}"
NEW_MASTER="${NEW_MASTER:-${1:-}}"

if [[ -z "${NEW_MASTER}" ]]; then
  log "==> Auto-detect master mới qua read_only=0"
  for N in node2 node3; do
    RO=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e 'SELECT @@read_only;' 2>/dev/null" | tr -d '\r' || echo 1)
    if [[ "$RO" == "0" ]]; then NEW_MASTER="$N"; break; fi
  done
fi

if [[ -z "${NEW_MASTER}" ]]; then
  log "[FAIL] Không xác định được master mới. Truyền: NEW_MASTER=node2 bash 08-rebuild-old-master.sh"
  exit 1
fi
log "==> OLD_MASTER=${OLD_MASTER}  NEW_MASTER=${NEW_MASTER}"

log "==> Power-on ${OLD_MASTER}"
vagrant up "${OLD_MASTER}" 2>&1 | tee -a "${LOG}"

log "==> Đợi MySQL trên ${OLD_MASTER} sẵn sàng"
for i in $(seq 1 60); do
  if vagrant ssh "${OLD_MASTER}" -c "mysqladmin -uroot -p'${MYSQL_ROOT_PWD}' ping 2>/dev/null | grep -q alive"; then
    log "    MySQL trên ${OLD_MASTER} ready (${i}s)"
    break
  fi
  sleep 2
done

# Xác định NEW_MASTER_IP
case "${NEW_MASTER}" in
  node1) NEW_MASTER_IP="${NODE1_IP}" ;;
  node2) NEW_MASTER_IP="${NODE2_IP}" ;;
  node3) NEW_MASTER_IP="${NODE3_IP}" ;;
  *)     log "[FAIL] NEW_MASTER không hợp lệ: ${NEW_MASTER}"; exit 1 ;;
esac

log "==> Configure ${OLD_MASTER} làm replica của ${NEW_MASTER} (${NEW_MASTER_IP})"
vagrant ssh "${OLD_MASTER}" -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' <<SQL
    STOP REPLICA;
    RESET REPLICA ALL;
    CHANGE REPLICATION SOURCE TO
      SOURCE_HOST='${NEW_MASTER_IP}',
      SOURCE_USER='${REPL_USER}',
      SOURCE_PASSWORD='${REPL_PWD}',
      SOURCE_AUTO_POSITION=1,
      GET_SOURCE_PUBLIC_KEY=1;
    START REPLICA;
    SET GLOBAL read_only=1;
    SET GLOBAL super_read_only=1;
SQL
" 2>&1 | tee -a "${LOG}"

sleep 3
log "==> Verify ${OLD_MASTER} đã trở thành replica"
vagrant ssh "${OLD_MASTER}" -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'SHOW REPLICA STATUS\\G' 2>/dev/null | egrep 'Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind|Last_IO_Error|Last_SQL_Error' || true
" 2>&1 | tee -a "${LOG}"

log "==> Restart MHA manager (đã tự dừng sau failover)"
vagrant ssh mgmt -c "
  sudo bash -c '
    # Xoá lock failover (cho phép manager start lại sau failover gần đây)
    rm -f /var/lib/mha/${CLUSTER_NAME}/*.failover.complete 2>/dev/null || true
    # Add lại entry server1 nếu đã bị remove_dead_master_conf xoá
    grep -q \"^\\[server1\\]\" /etc/mha/${CLUSTER_NAME}.cnf || cat >>/etc/mha/${CLUSTER_NAME}.cnf <<EOF

[server1]
hostname=${NODE1_IP}
candidate_master=1
EOF
    masterha_check_repl --conf=/etc/mha/${CLUSTER_NAME}.cnf
    nohup masterha_manager --conf=/etc/mha/${CLUSTER_NAME}.cnf \\
       --remove_dead_master_conf --ignore_last_failover \\
       >/var/log/mha/${CLUSTER_NAME}/manager.stdout 2>&1 &
  '
" 2>&1 | tee -a "${LOG}"

sleep 3
log "==> masterha_check_status"
vagrant ssh mgmt -c "sudo masterha_check_status --conf=/etc/mha/${CLUSTER_NAME}.cnf" 2>&1 | tee -a "${LOG}" || true

log "==> Bước 8 hoàn tất. ${OLD_MASTER} đã làm replica của ${NEW_MASTER}."
