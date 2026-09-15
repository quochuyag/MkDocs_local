#!/usr/bin/env bash
# 07-failover-test.sh — halt master → MHA auto-failover. DESTRUCTIVE.
# Đo PROMOTE_RTO (manager phát hiện + chọn master mới + relay binlog + promote) và VIP move.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/07-failover.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "================ FAILOVER TEST (MHA) ================"

# 0 — Xác định master hiện tại (qua showsalves trên node1)
log "==> Xác định master ban đầu (kỳ vọng = node1)"
PRIMARY_HOST="node1"

# Insert sentinel
SENT_VAL="mha-sentinel-$(date +%s)"
vagrant ssh "${PRIMARY_HOST}" -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    CREATE DATABASE IF NOT EXISTS smoke_db;
    CREATE TABLE IF NOT EXISTS smoke_db.t(id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(64), ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
    INSERT INTO smoke_db.t(val) VALUES('${SENT_VAL}');
  \"
" 2>&1 | tee -a "${LOG}"

# Đợi 2 replica thấy sentinel
for N in node2 node3; do
  for i in $(seq 1 30); do
    GOT=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e \"SELECT COUNT(*) FROM smoke_db.t WHERE val='${SENT_VAL}';\" 2>/dev/null" | tr -d '\r')
    [[ "$GOT" == "1" ]] && { log "    [$N] đã thấy sentinel"; break; }
    sleep 0.5
  done
done

# 1 — HALT master
log "==> Halt --force ${PRIMARY_HOST} (simulate crash)"
HALT_TS=$(date +%s)
vagrant halt --force "${PRIMARY_HOST}" 2>&1 | tee -a "${LOG}"

# 2 — Poll MHA log đến khi thấy "Master failover ... completed successfully"
log "==> Poll /var/log/mha/${CLUSTER_NAME}/manager.log đến khi failover hoàn tất (timeout 120s)"
NEW_MASTER=""
PROMOTE_RTO=""
for i in $(seq 1 60); do
  LINE=$(vagrant ssh mgmt -c "sudo grep -E 'Master failover .* completed successfully|Selected .* as a new master|New master is' /var/log/mha/${CLUSTER_NAME}/manager.log 2>/dev/null | tail -n5" | tr -d '\r' || true)
  if echo "$LINE" | grep -q "completed successfully"; then
    NEW_MASTER=$(echo "$LINE" | grep -oE "Master failover from [^ ]+ to [^ :]+" | awk '{print $NF}' | head -n1)
    [[ -z "$NEW_MASTER" ]] && NEW_MASTER=$(echo "$LINE" | grep -oE "(new master|New master).*:[0-9]+" | head -n1)
    PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
    log "    Failover hoàn tất sau ${PROMOTE_RTO}s. New master line: ${LINE}"
    break
  fi
  (( i % 5 == 0 )) && log "    chờ... (${i}*2s)"
  sleep 2
done

if [[ -z "${PROMOTE_RTO}" ]]; then
  log "[FAIL] MHA không hoàn tất failover trong 120s — xem log full:"
  vagrant ssh mgmt -c "sudo tail -n 60 /var/log/mha/${CLUSTER_NAME}/manager.log" 2>&1 | tee -a "${LOG}"
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi

# 3 — Xác định master mới (qua read_only=0)
log "==> Xác định master mới qua @@read_only=0"
NEW_MASTER_HOST=""
for N in node2 node3; do
  RO=$(vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e 'SELECT @@read_only;' 2>/dev/null" | tr -d '\r')
  log "    ${N}: read_only=${RO}"
  if [[ "$RO" == "0" ]]; then NEW_MASTER_HOST="$N"; fi
done

if [[ -z "${NEW_MASTER_HOST}" ]]; then
  log "[FAIL] Không có node nào có read_only=0 — failover chưa hoàn tất"
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi
log "    NEW MASTER = ${NEW_MASTER_HOST}"

# 4 — VIP đã move sang master mới chưa?
log "==> Kiểm tra VIP ${VIP} có trên ${NEW_MASTER_HOST}"
VIP_HERE=$(vagrant ssh "${NEW_MASTER_HOST}" -c "ip -4 addr show | grep -c '${VIP}/24' || true" | tr -d '\r')
[[ "${VIP_HERE}" -ge "1" ]] && log "    [OK] VIP đã trên ${NEW_MASTER_HOST}" || log "    [WARN] VIP chưa thấy trên ${NEW_MASTER_HOST} (kiểm tra master_ip_failover.sh hoặc SSH key)"

# 5 — Bulk insert post-failover qua master mới
log "==> Insert post-failover qua ${NEW_MASTER_HOST}"
WRITE_RTO=""
for i in $(seq 1 60); do
  if vagrant ssh "${NEW_MASTER_HOST}" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"INSERT INTO smoke_db.t(val) VALUES('post-mha-failover');\" 2>/dev/null" >/dev/null; then
    WRITE_RTO=$(( $(date +%s) - HALT_TS ))
    log "    ${NEW_MASTER_HOST} chấp nhận INSERT sau ${WRITE_RTO}s"
    break
  fi
  sleep 1
done

# 6 — Verify replica còn lại đã follow master mới
OTHER=""
for N in node2 node3; do
  [[ "$N" != "${NEW_MASTER_HOST}" ]] && OTHER="$N"
done
log "==> ${OTHER} đã CHANGE REPLICATION SOURCE về ${NEW_MASTER_HOST}?"
SRC=$(vagrant ssh "${OTHER}" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'SHOW REPLICA STATUS\\G' 2>/dev/null" | awk -F': ' '/Source_Host/{print $2}' | tr -d ' \r' | head -1)
log "    ${OTHER} Source_Host = ${SRC}"

# 7 — Kết luận
log "================ KẾT LUẬN ================"
pass=true
[[ -n "${NEW_MASTER_HOST}" ]] || { log "[FAIL] không có master mới"; pass=false; }
[[ -n "${WRITE_RTO}" ]]       || { log "[FAIL] master mới không nhận INSERT"; pass=false; }

if $pass; then
  log "FAILOVER_PASS=true PROMOTE_RTO=${PROMOTE_RTO}s WRITE_RTO=${WRITE_RTO}s old=${PRIMARY_HOST} new=${NEW_MASTER_HOST}"
  echo "FAILOVER_PASS=true" >> "${LOG}"
else
  log "FAILOVER_PASS=false"
  echo "FAILOVER_PASS=false" >> "${LOG}"
fi

log ""
log "Lưu ý: MHA tự dừng manager sau failover. Để demo lại, cần restart manager:"
log "  vagrant ssh mgmt -c \"sudo nohup masterha_manager --conf=/etc/mha/${CLUSTER_NAME}.cnf --remove_dead_master_conf --ignore_last_failover >/var/log/mha/${CLUSTER_NAME}/manager.stdout 2>&1 &\""
log "Để rebuild ${PRIMARY_HOST} thành replica: bash demo/04-mha/08-rebuild-old-master.sh"
