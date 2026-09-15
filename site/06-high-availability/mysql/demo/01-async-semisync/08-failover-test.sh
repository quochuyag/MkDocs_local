#!/usr/bin/env bash
# 08-failover-test.sh — Simulate node1 down, promote node2, repoint node3.
# DESTRUCTIVE: làm thay đổi topology cluster. Chạy thủ công, không tự động trong run-all.
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

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}
mysql_exec() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

log "================ FAILOVER TEST ================"
log "Mục tiêu: node1 chết -> promote node2 -> reconfigure node3"

# Đảm bảo có schema smoke_db (từ bước 7). Nếu chưa có thì tạo nhanh.
HAS_DB=$(mysql_q node1 "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='smoke_db';" || echo 0)
if [[ "${HAS_DB}" != "1" ]]; then
  log "==> smoke_db chưa có, tạo lại nhanh trên node1"
  mysql_exec node1 "
    CREATE DATABASE IF NOT EXISTS smoke_db;
    CREATE TABLE IF NOT EXISTS smoke_db.t(
      id INT PRIMARY KEY AUTO_INCREMENT,
      val VARCHAR(64),
      ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6));
  "
fi

# 1 — Sentinel row trước khi halt
SENT_VAL="failover-sentinel-$(date +%s)"
log "==> Insert sentinel row trên node1 (val='${SENT_VAL}')"
mysql_exec node1 "INSERT INTO smoke_db.t(val) VALUES('${SENT_VAL}');"
SENT_ID=$(mysql_q node1 "SELECT id FROM smoke_db.t WHERE val='${SENT_VAL}';")
log "    sentinel id=${SENT_ID}"

# Đợi replica nhận
for N in node2 node3; do
  for i in $(seq 1 30); do
    GOT=$(mysql_q "$N" "SELECT COUNT(*) FROM smoke_db.t WHERE id=${SENT_ID};" 2>/dev/null || echo 0)
    [[ "$GOT" == "1" ]] && { log "    [$N] đã thấy sentinel"; break; }
    sleep 0.1
  done
done

# Capture GTID trước khi halt — để chọn replica có vị trí xa nhất
G1=$(mysql_q node1 "SELECT @@global.gtid_executed;")
G2=$(mysql_q node2 "SELECT @@global.gtid_executed;")
G3=$(mysql_q node3 "SELECT @@global.gtid_executed;")
log "==> gtid trước halt: node1=${G1} | node2=${G2} | node3=${G3}"

# 2 — HALT node1
log "==> Halt node1 (simulate crash)"
HALT_START=$(date +%s)
vagrant halt --force node1 2>&1 | tee -a "${LOG}"
sleep 2

# 3 — Đợi node2 detect IO error
log "==> Đợi node2 phát hiện master chết (poll Last_IO_Error)"
DETECT_START=$(date +%s)
for i in $(seq 1 60); do
  ERR=$(vagrant ssh node2 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"SHOW REPLICA STATUS\\G\" 2>/dev/null | awk -F': ' '/Last_IO_Error/ {print \$2; exit}'" | tr -d '\r')
  if [[ -n "$ERR" ]]; then
    DETECT_DUR=$(( $(date +%s) - DETECT_START ))
    log "    Detected after ${DETECT_DUR}s: ${ERR}"
    break
  fi
  sleep 1
done

# 4 — Promote node2
log "==> Promote node2 (chạy manual-failover.sh)"
PROMOTE_START=$(date +%s)
vagrant ssh node2 -c "sudo NEW_MASTER_IP=${NODE2_IP} bash /vagrant/scripts/async-semisync/manual-failover.sh" 2>&1 | tee -a "${LOG}" || {
  log "[WARN] manual-failover.sh exit code != 0 — tiếp tục để verify state thực tế"
}
PROMOTE_DUR=$(( $(date +%s) - PROMOTE_START ))
log "    promote xong sau ${PROMOTE_DUR}s"

# 5 — Verify node2 đã writable
RO2=$(mysql_q node2 "SELECT @@super_read_only;")
log "==> [node2] super_read_only=${RO2} (expect 0)"

# 6 — manual-failover.sh đã trỏ node3 sang node2_IP rồi (theo logic của script).
#     Verify lại node3 state.
sleep 2
SRC3=$(mysql_q node3 "SELECT host FROM performance_schema.replication_connection_configuration;")
IO3=$(mysql_q node3 "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status;")
SQL3=$(mysql_q node3 "SELECT SERVICE_STATE FROM performance_schema.replication_applier_status;")
log "==> [node3] Source=${SRC3} IO=${IO3} SQL=${SQL3} (expect node2-ish, ON, ON)"

# 7 — Write trên master mới
log "==> Write 50 rows lên node2 (master mới)"
W_START=$(date +%s.%N)
NEW_SQL=""
for i in $(seq 1 50); do
  NEW_SQL+="INSERT INTO smoke_db.t(val) VALUES('post-failover-${i}');"
done
echo "USE smoke_db; ${NEW_SQL}" | vagrant ssh node2 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
W_END=$(date +%s.%N)
W_DUR=$(awk -v s="${W_START}" -v e="${W_END}" 'BEGIN{printf "%.3f", e-s}')
log "    insert 50 rows xong sau ${W_DUR}s"

# 8 — Đợi node3 catch-up
log "==> Chờ node3 nhận 50 rows mới"
TOTAL_AFTER=$(mysql_q node2 "SELECT COUNT(*) FROM smoke_db.t;")
for i in $(seq 1 50); do
  GOT3=$(mysql_q node3 "SELECT COUNT(*) FROM smoke_db.t;" 2>/dev/null || echo 0)
  [[ "$GOT3" == "$TOTAL_AFTER" ]] && { log "    [node3] OK: ${GOT3}/${TOTAL_AFTER}"; break; }
  sleep 0.2
done

# 9 — Kết luận
log "================ KẾT LUẬN ================"
pass=true
[[ "$RO2" == "0" ]] || { log "[FAIL] node2 vẫn read_only"; pass=false; }
[[ "$IO3"  == "ON" ]] || { log "[FAIL] node3 IO thread = $IO3"; pass=false; }
[[ "$SQL3" == "ON" ]] || { log "[FAIL] node3 SQL thread = $SQL3"; pass=false; }
[[ "$GOT3" == "$TOTAL_AFTER" ]] || { log "[FAIL] node3 không catch-up sau failover"; pass=false; }

if $pass; then
  log "FAILOVER_PASS=true  detect_sec=${DETECT_DUR} promote_sec=${PROMOTE_DUR} write_sec=${W_DUR}"
  echo "FAILOVER_PASS=true" >> "${LOG}"
else
  log "FAILOVER_PASS=false — xem log"
  echo "FAILOVER_PASS=false" >> "${LOG}"
fi

log ""
log "Để recover node1 thành replica của node2 mới:"
log "  vagrant up node1"
log "  vagrant ssh node1 -c \"mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \\\"...\\\"\"  # xem 08-failover-test.md §'Khôi phục node1'"
log ""
log "Để reset toàn bộ và demo lại: bash demo/01-async-semisync/09-rollback.sh"
