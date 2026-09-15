#!/usr/bin/env bash
# 08-failover-test.sh — halt PRIMARY, đợi GR auto-elect, đo RTO trên SECONDARY.
# Khác Demo 02: không có Router → app phải tự sniff PRIMARY mới (script poll qua secondary).
# DESTRUCTIVE: halt 1 VM. Chạy thủ công.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/08-failover.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q_root() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

mysql_exec_root() {
  local node="$1" sql="$2"
  printf '%s' "$sql" | vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
}

log "================ FAILOVER TEST ================"

# MEMBER_HOST trả về IP (report_host=192.168.10.x). vagrant ssh dùng hostname (node1..3).
ip_to_name() {
  case "$1" in
    "${NODE1_IP}") echo node1 ;;
    "${NODE2_IP}") echo node2 ;;
    "${NODE3_IP}") echo node3 ;;
    *) echo "$1" ;;
  esac
}

# 0 — Identify current PRIMARY
PRIMARY_IP=$(mysql_q_root node1 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';" || \
              mysql_q_root node2 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
PRIMARY_HOST=$(ip_to_name "${PRIMARY_IP}")
log "==> Primary trước halt: ${PRIMARY_HOST} (${PRIMARY_IP})"
if [[ -z "${PRIMARY_IP}" ]]; then
  log "[FATAL] Không xác định được primary — cluster có vấn đề."
  exit 1
fi

SECONDARIES=()
for N in node1 node2 node3; do
  [[ "$N" != "$PRIMARY_HOST" ]] && SECONDARIES+=("$N")
done
QUERY_NODE="${SECONDARIES[0]}"
log "==> Sau halt sẽ query qua: ${QUERY_NODE}"

# 1 — Sentinel insert qua PRIMARY (đảm bảo có data)
HAS_DB=$(mysql_q_root "${PRIMARY_HOST}" "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='smoke_db';" || echo 0)
if [[ "${HAS_DB}" != "1" ]]; then
  log "==> smoke_db chưa có, tạo nhanh trên PRIMARY"
  mysql_exec_root "${PRIMARY_HOST}" "
    CREATE DATABASE IF NOT EXISTS smoke_db;
    CREATE TABLE IF NOT EXISTS smoke_db.t(
      id INT PRIMARY KEY AUTO_INCREMENT,
      val VARCHAR(64),
      ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6));
  "
fi

SENT_VAL="failover-sentinel-$(date +%s)"
log "==> Insert sentinel row trên ${PRIMARY_HOST} (val='${SENT_VAL}')"
mysql_exec_root "${PRIMARY_HOST}" "INSERT INTO smoke_db.t(val) VALUES('${SENT_VAL}');"
SENT_ID=$(mysql_q_root "${PRIMARY_HOST}" "SELECT id FROM smoke_db.t WHERE val='${SENT_VAL}';")
log "    sentinel id=${SENT_ID}"

# Đợi 2 secondary thấy sentinel trước khi halt
for N in "${SECONDARIES[@]}"; do
  for i in $(seq 1 30); do
    GOT=$(mysql_q_root "$N" "SELECT COUNT(*) FROM smoke_db.t WHERE id=${SENT_ID};" 2>/dev/null || echo 0)
    [[ "$GOT" == "1" ]] && { log "    [$N] đã thấy sentinel"; break; }
    sleep 0.1
  done
done

# 2 — HALT primary
log "==> Halt --force ${PRIMARY_HOST}"
HALT_TS=$(date +%s)
vagrant halt --force "${PRIMARY_HOST}" 2>&1 | tee -a "${LOG}"

# 3 — Poll từ secondary cho đến khi có PRIMARY mới (timeout 60s, 1 SSH session)
log "==> Poll từ ${QUERY_NODE} đến khi có primary mới (timeout 60s)"
POLL_OUT=$(vagrant ssh "${QUERY_NODE}" -c "
  for i in \$(seq 1 60); do
    np=\$(mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"
      SELECT MEMBER_HOST FROM performance_schema.replication_group_members
       WHERE MEMBER_ROLE='PRIMARY' AND MEMBER_STATE='ONLINE' AND MEMBER_HOST <> '${PRIMARY_IP}'
       LIMIT 1;\" 2>/dev/null | tr -d '\r' | tr -d '[:space:]')
    if [ -n \"\${np}\" ]; then
      echo \"FOUND=\${np} AT=\${i}\"
      exit 0
    fi
    if [ \$((i % 5)) -eq 0 ]; then echo \"    progress: \${i}s\"; fi
    sleep 1
  done
  echo \"FOUND= AT=60\"
" 2>&1 | tr -d '\r')
echo "${POLL_OUT}" | tee -a "${LOG}" >/dev/null
NEW_PRIMARY_IP=$(echo "${POLL_OUT}" | sed -n 's/.*FOUND=\([^ ]*\) .*/\1/p' | tail -n1)
NEW_PRIMARY=$(ip_to_name "${NEW_PRIMARY_IP}")
PROMOTE_RTO=""
if [[ -n "${NEW_PRIMARY}" ]]; then
  PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
  log "    NEW PRIMARY = ${NEW_PRIMARY} sau ${PROMOTE_RTO}s"
fi

if [[ -z "${NEW_PRIMARY}" ]]; then
  log "[FAIL] Không có primary mới sau 60s — có thể mất quorum"
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi

# 4 — Đo WRITE_RTO: từ halt đến khi NEW_PRIMARY chấp nhận INSERT
log "==> Đo WRITE_RTO: poll INSERT vào ${NEW_PRIMARY} (timeout 60s)"
WRITE_RTO=""
for i in $(seq 1 60); do
  if printf 'INSERT INTO smoke_db.t(val) VALUES("post-failover-probe");' | \
       vagrant ssh "${NEW_PRIMARY}" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' smoke_db 2>/dev/null" >/dev/null; then
    WRITE_RTO=$(( $(date +%s) - HALT_TS ))
    log "    ${NEW_PRIMARY} chấp nhận INSERT sau ${WRITE_RTO}s"
    break
  fi
  (( i % 5 == 0 )) && log "    chờ... (${i}s)"
  sleep 1
done

if [[ -z "${WRITE_RTO}" ]]; then
  log "[FAIL] ${NEW_PRIMARY} không chấp nhận INSERT sau 60s"
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi

# 5 — Bulk insert post-failover
log "==> [${NEW_PRIMARY}] INSERT 50 rows post-failover..."
W_START=$(date +%s.%N)
NEW_SQL="USE smoke_db;"
for i in $(seq 1 50); do
  NEW_SQL+="INSERT INTO t(val) VALUES('post-failover-${i}');"
done
printf '%s' "${NEW_SQL}" | vagrant ssh "${NEW_PRIMARY}" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
W_END=$(date +%s.%N)
W_DUR=$(awk -v s="${W_START}" -v e="${W_END}" 'BEGIN{printf "%.3f", e-s}')
log "    insert 50 rows xong sau ${W_DUR}s"

# 6 — Đợi secondary còn sống catch-up
OTHER_SEC=""
for N in "${SECONDARIES[@]}"; do
  [[ "$N" != "$NEW_PRIMARY" ]] && OTHER_SEC="$N"
done
log "==> Chờ ${OTHER_SEC} (secondary còn sống) catch-up"
TOTAL=$(mysql_q_root "${NEW_PRIMARY}" "SELECT COUNT(*) FROM smoke_db.t;")
CAUGHT=false
for i in $(seq 1 50); do
  GOT=$(mysql_q_root "${OTHER_SEC}" "SELECT COUNT(*) FROM smoke_db.t;" 2>/dev/null || echo 0)
  if [[ "$GOT" == "$TOTAL" ]]; then
    log "    [${OTHER_SEC}] OK: ${GOT}/${TOTAL}"
    CAUGHT=true
    break
  fi
  sleep 0.2
done

# 7 — Kết luận
log "================ KẾT LUẬN ================"
pass=true
[[ -n "${NEW_PRIMARY}" && "${NEW_PRIMARY}" != "${PRIMARY_HOST}" ]] || { log "[FAIL] không có primary mới khác primary cũ"; pass=false; }
$CAUGHT || { log "[FAIL] secondary còn sống không catch-up"; pass=false; }

if $pass; then
  log "FAILOVER_PASS=true  PROMOTE_RTO=${PROMOTE_RTO}s WRITE_RTO=${WRITE_RTO}s old=${PRIMARY_HOST} new=${NEW_PRIMARY}"
  echo "FAILOVER_PASS=true" >> "${LOG}"
else
  log "FAILOVER_PASS=false — xem log"
  echo "FAILOVER_PASS=false" >> "${LOG}"
fi

log ""
log "Để khôi phục ${PRIMARY_HOST} làm SECONDARY trong group:"
log "  vagrant up ${PRIMARY_HOST}"
log "  vagrant ssh ${PRIMARY_HOST} -c \"mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'START GROUP_REPLICATION;'\""
log "  (nếu GTID tụt nhiều → CLONE INSTANCE FROM 'repl'@'${NEW_PRIMARY}':3306)"
