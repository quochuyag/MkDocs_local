#!/usr/bin/env bash
# 07-smoke-test.sh — Insert qua PRIMARY trực tiếp, đo lag đồng bộ trên 2 SECONDARY.
# Khác Demo 02: không qua Router, kết nối trực tiếp tới PRIMARY.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/07-smoke-test.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

ROWS="${ROWS:-200}"
TIMEOUT_SEC="${TIMEOUT_SEC:-30}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q_root() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

mysql_exec_root() {
  # Multi-statement với heredoc qua stdin
  local node="$1" sql="$2"
  printf '%s' "$sql" | vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
}

log "================ SMOKE TEST (ROWS=${ROWS}) qua PRIMARY ================"

# MEMBER_HOST trả về IP (report_host=192.168.10.x). vagrant ssh dùng hostname (node1..3).
ip_to_name() {
  case "$1" in
    "${NODE1_IP}") echo node1 ;;
    "${NODE2_IP}") echo node2 ;;
    "${NODE3_IP}") echo node3 ;;
    *) echo "$1" ;;
  esac
}
PRIMARY_IP=$(mysql_q_root node1 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
PRIMARY_HOST=$(ip_to_name "${PRIMARY_IP}")
log "==> Current PRIMARY = ${PRIMARY_HOST} (${PRIMARY_IP})"

# 1 — Setup schema
log "==> [${PRIMARY_HOST}] CREATE DATABASE + TABLE smoke_db.t"
mysql_exec_root "${PRIMARY_HOST}" "
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  USE smoke_db;
  CREATE TABLE t (
    id  INT PRIMARY KEY AUTO_INCREMENT,
    val VARCHAR(64) NOT NULL,
    ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
  ) ENGINE=InnoDB;
"

# 2 — Bulk insert qua PRIMARY
log "==> [${PRIMARY_HOST}] INSERT ${ROWS} rows..."
INSERT_START=$(date +%s.%N)
INSERT_SQL="USE smoke_db;"
for i in $(seq 1 "${ROWS}"); do
  INSERT_SQL+="INSERT INTO t(val) VALUES('row-${i}-$(date +%s)');"
done
mysql_exec_root "${PRIMARY_HOST}" "${INSERT_SQL}"
INSERT_END=$(date +%s.%N)
INSERT_DUR=$(awk -v s="${INSERT_START}" -v e="${INSERT_END}" 'BEGIN{printf "%.3f", e-s}')
log "==> insert ${ROWS} rows xong sau ${INSERT_DUR}s"

# 3 — Wait từng SECONDARY catch-up
wait_node() {
  local node="$1" target="${ROWS}" start now elapsed cnt
  wlog() { log "$@" >&2; }
  start=$(date +%s.%N)
  while :; do
    cnt=$(mysql_q_root "$node" "SELECT COUNT(*) FROM smoke_db.t;" 2>/dev/null || echo 0)
    cnt="${cnt:-0}"
    if [[ "$cnt" =~ ^[0-9]+$ && "$cnt" -ge "$target" ]]; then
      now=$(date +%s.%N)
      elapsed=$(awk -v s="$start" -v e="$now" 'BEGIN{printf "%.3f", e-s}')
      wlog "==> [$node] thấy ${cnt} rows sau ${elapsed}s"
      echo "$elapsed"
      return 0
    fi
    now=$(date +%s.%N)
    elapsed=$(awk -v s="$start" -v e="$now" 'BEGIN{printf "%.1f", e-s}')
    if awk -v e="$elapsed" -v t="$TIMEOUT_SEC" 'BEGIN{exit !(e>t)}'; then
      wlog "==> [$node] TIMEOUT sau ${elapsed}s — chỉ thấy ${cnt}/${target}"
      echo "TIMEOUT"
      return 1
    fi
    sleep 0.1
  done
}

LAG1=$(wait_node node1 || true)
LAG2=$(wait_node node2 || true)
LAG3=$(wait_node node3 || true)

# 4 — gtid_executed 3 node
log "==> So sánh gtid_executed:"
G1=$(mysql_q_root node1 "SELECT @@global.gtid_executed;")
G2=$(mysql_q_root node2 "SELECT @@global.gtid_executed;")
G3=$(mysql_q_root node3 "SELECT @@global.gtid_executed;")
log "    node1: ${G1}"
log "    node2: ${G2}"
log "    node3: ${G3}"

# 5 — Conclusion
log "================ KẾT LUẬN ================"
pass=true
if [[ "$LAG1" == "TIMEOUT" || "$LAG2" == "TIMEOUT" || "$LAG3" == "TIMEOUT" ]]; then
  log "[FAIL] Một node không catch-up trong ${TIMEOUT_SEC}s"
  pass=false
fi

if $pass; then
  log "SMOKE_PASS=true  insert=${INSERT_DUR}s lag1=${LAG1} lag2=${LAG2} lag3=${LAG3}"
  echo "SMOKE_PASS=true" >> "${LOG}"
  exit 0
else
  log "SMOKE_PASS=false — xem log"
  echo "SMOKE_PASS=false" >> "${LOG}"
  exit 1
fi
