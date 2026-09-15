#!/usr/bin/env bash
# 09-failover-test.sh — halt primary, đợi GR auto-elect, đo RTO qua Router :6446.
# DESTRUCTIVE: halt 1 VM. Chạy thủ công, không tự động trong run-all.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/09-failover.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

# ADMIN_PWD chứa '#' (fragment delim) → URL-encode cho mysqlsh URI (xem env.sh::urlenc).
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q_root() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

router_q() {
  local port="$1" sql="$2"
  vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${port} -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

router_exec_multi() {
  local port="$1" sql="$2"
  printf '%s' "$sql" | vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${port} 2>/dev/null" >/dev/null
}

log "================ FAILOVER TEST ================"
log "Mục tiêu: halt primary -> GR tự bầu -> Router tự reroute :6446"

# 0 — Identify current primary
PRIMARY_HOST=$(mysql_q_root node1 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';" || \
                mysql_q_root node2 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
log "==> Primary trước halt: ${PRIMARY_HOST}"
if [[ -z "${PRIMARY_HOST}" ]]; then
  log "[FATAL] Không xác định được primary — cluster có vấn đề."
  exit 1
fi

# Xác định 2 secondary để chọn 1 cái làm "query target" sau khi halt
SECONDARIES=()
for N in node1 node2 node3; do
  [[ "$N" != "$PRIMARY_HOST" ]] && SECONDARIES+=("$N")
done
QUERY_NODE="${SECONDARIES[0]}"
log "==> Sau halt sẽ query trạng thái qua: ${QUERY_NODE}"

# 1 — Sentinel insert qua Router :6446
HAS_DB=$(mysql_q_root "${PRIMARY_HOST}" "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='smoke_db';" || echo 0)
if [[ "${HAS_DB}" != "1" ]]; then
  log "==> smoke_db chưa có, tạo nhanh qua Router :${ROUTER_RW_PORT}"
  router_exec_multi "${ROUTER_RW_PORT}" "
    CREATE DATABASE IF NOT EXISTS smoke_db;
    CREATE TABLE IF NOT EXISTS smoke_db.t(
      id INT PRIMARY KEY AUTO_INCREMENT,
      val VARCHAR(64),
      ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6));
  "
fi

SENT_VAL="failover-sentinel-$(date +%s)"
log "==> Insert sentinel row qua mgmt:${ROUTER_RW_PORT} (val='${SENT_VAL}')"
router_exec_multi "${ROUTER_RW_PORT}" "INSERT INTO smoke_db.t(val) VALUES('${SENT_VAL}');"
SENT_ID=$(router_q "${ROUTER_RW_PORT}" "SELECT id FROM smoke_db.t WHERE val='${SENT_VAL}';")
log "    sentinel id=${SENT_ID}"

# Đợi 2 secondary thấy sentinel trước khi halt
for N in "${SECONDARIES[@]}"; do
  for i in $(seq 1 30); do
    GOT=$(mysql_q_root "$N" "SELECT COUNT(*) FROM smoke_db.t WHERE id=${SENT_ID};" 2>/dev/null || echo 0)
    [[ "$GOT" == "1" ]] && { log "    [$N] đã thấy sentinel"; break; }
    sleep 0.1
  done
done

# Snapshot cluster.status() trước halt
log "==> cluster.status() trước halt:"
vagrant ssh "${QUERY_NODE}" -c "
  mysqlsh --uri='${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}' \
    -e \"print(JSON.stringify(dba.getCluster('${CLUSTER_NAME}').status(),null,2));\" 2>/dev/null
" | tail -n 60 | tee -a "${LOG}" || true

# 2 — HALT primary
log "==> Halt --force ${PRIMARY_HOST} (simulate crash)"
HALT_TS=$(date +%s)
vagrant halt --force "${PRIMARY_HOST}" 2>&1 | tee -a "${LOG}"

# 3 — Poll cluster.status() từ secondary, chờ NEW primary
log "==> Poll cluster.status() từ ${QUERY_NODE} đến khi có primary mới (timeout 60s, 1 SSH session)"
# Đẩy poll vào trong VM để tránh 60 SSH handshakes; in dòng "FOUND=<host> AT=<sec>" cuối cùng.
POLL_OUT=$(vagrant ssh "${QUERY_NODE}" -c "
  for i in \$(seq 1 60); do
    np=\$(mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"
      SELECT MEMBER_HOST FROM performance_schema.replication_group_members
       WHERE MEMBER_ROLE='PRIMARY' AND MEMBER_STATE='ONLINE' AND MEMBER_HOST <> '${PRIMARY_HOST}'
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
NEW_PRIMARY=$(echo "${POLL_OUT}" | sed -n 's/.*FOUND=\([^ ]*\) .*/\1/p' | tail -n1)
PROMOTE_RTO=""
if [[ -n "${NEW_PRIMARY}" ]]; then
  PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
  log "    NEW PRIMARY = ${NEW_PRIMARY} sau ${PROMOTE_RTO}s"
fi

if [[ -z "${NEW_PRIMARY}" ]]; then
  log "[FAIL] Không có primary mới sau 60s — có thể mất quorum"
  log "       Khắc phục: vagrant ssh ${QUERY_NODE} -c \"mysqlsh ... -e 'dba.getCluster().forceQuorumUsingPartitionOf(...)'\""
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi

# 4 — Đo WRITE_RTO: từ halt đến khi :6446 nhận INSERT
log "==> Đo WRITE_RTO: poll :${ROUTER_RW_PORT} insert đến khi thành công (timeout 60s)"
WRITE_RTO=""
for i in $(seq 1 60); do
  if router_q "${ROUTER_RW_PORT}" "SELECT 1;" >/dev/null 2>&1; then
    # Cần thêm: ghi thật để verify không phải read-only
    if printf 'INSERT INTO smoke_db.t(val) VALUES("post-failover-probe");' | \
         vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${ROUTER_RW_PORT} smoke_db 2>/dev/null" >/dev/null; then
      WRITE_RTO=$(( $(date +%s) - HALT_TS ))
      log "    :${ROUTER_RW_PORT} chấp nhận INSERT sau ${WRITE_RTO}s"
      break
    fi
  fi
  if (( i % 5 == 0 )); then
    log "    chờ... (${i}s)"
  fi
  sleep 1
done

if [[ -z "${WRITE_RTO}" ]]; then
  log "[FAIL] Router :${ROUTER_RW_PORT} không chấp nhận INSERT sau 60s"
  echo "FAILOVER_PASS=false" >> "${LOG}"
  exit 1
fi

# 5 — Verify Router :6446 trỏ đến NEW_PRIMARY
RW_HOST_AFTER=$(router_q "${ROUTER_RW_PORT}" "SELECT @@hostname;")
log "==> :${ROUTER_RW_PORT} đang point đến: ${RW_HOST_AFTER} (expect = ${NEW_PRIMARY})"

# 6 — Bulk insert post-failover qua :6446
log "==> [mgmt:${ROUTER_RW_PORT}] INSERT 50 rows post-failover..."
W_START=$(date +%s.%N)
NEW_SQL="USE smoke_db;"
for i in $(seq 1 50); do
  NEW_SQL+="INSERT INTO t(val) VALUES('post-failover-${i}');"
done
printf '%s' "${NEW_SQL}" | vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${ROUTER_RW_PORT} 2>/dev/null" >/dev/null
W_END=$(date +%s.%N)
W_DUR=$(awk -v s="${W_START}" -v e="${W_END}" 'BEGIN{printf "%.3f", e-s}')
log "    insert 50 rows xong sau ${W_DUR}s"

# 7 — Đợi secondary còn sống catch-up
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

# 8 — Kết luận
log "================ KẾT LUẬN ================"
pass=true
[[ -n "${NEW_PRIMARY}" && "${NEW_PRIMARY}" != "${PRIMARY_HOST}" ]] || { log "[FAIL] không có primary mới khác primary cũ"; pass=false; }
[[ "${RW_HOST_AFTER}" == "${NEW_PRIMARY}" ]] || { log "[FAIL] :${ROUTER_RW_PORT} chưa trỏ đến primary mới (${RW_HOST_AFTER} != ${NEW_PRIMARY})"; pass=false; }
$CAUGHT || { log "[FAIL] secondary còn sống không catch-up"; pass=false; }

if $pass; then
  log "FAILOVER_PASS=true  PROMOTE_RTO=${PROMOTE_RTO}s WRITE_RTO=${WRITE_RTO}s old_primary=${PRIMARY_HOST} new_primary=${NEW_PRIMARY}"
  echo "FAILOVER_PASS=true" >> "${LOG}"
else
  log "FAILOVER_PASS=false — xem log"
  echo "FAILOVER_PASS=false" >> "${LOG}"
fi

log ""
log "Để khôi phục ${PRIMARY_HOST} thành member của cluster (post-failover):"
log "  vagrant up ${PRIMARY_HOST}"
log "  vagrant ssh ${PRIMARY_HOST} -c \"mysqlsh --uri='${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}' \\"
log "       -e \\\"dba.getCluster('${CLUSTER_NAME}').rejoinInstance('${ADMIN_USER}@${PRIMARY_HOST}:${MYSQL_PORT}',{password:'${ADMIN_PWD}'});\\\"\""
log ""
log "Để reset toàn bộ và demo lại: bash demo/02-innodb-cluster/10-rollback.sh"
