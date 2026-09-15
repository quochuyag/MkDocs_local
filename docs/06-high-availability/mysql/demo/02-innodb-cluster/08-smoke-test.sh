#!/usr/bin/env bash
# 08-smoke-test.sh — Write qua Router :6446, đọc qua :6447 + direct, đo lag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/08-smoke-test.log"
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
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

router_q() {
  # mgmt -> Router (port) bằng clusteradmin (app user trong lab)
  local port="$1" sql="$2"
  vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${port} -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

router_exec_multi() {
  # Truyền 1 phiên duy nhất với nhiều câu để tránh handshake N lần
  local port="$1" sql="$2"
  printf '%s' "$sql" | vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${port} 2>/dev/null" >/dev/null
}

log "================ SMOKE TEST (ROWS=${ROWS}) qua Router ================"

# 0 — Xác định primary hiện tại (để verify Router route đúng)
PRIMARY_HOST=$(mysql_q_root node1 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
log "==> Current PRIMARY = ${PRIMARY_HOST}"

# 1 — Setup schema qua Router :6446
log "==> [mgmt:${ROUTER_RW_PORT}] CREATE DATABASE + TABLE smoke_db.t"
router_exec_multi "${ROUTER_RW_PORT}" "
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  USE smoke_db;
  CREATE TABLE t (
    id  INT PRIMARY KEY AUTO_INCREMENT,
    val VARCHAR(64) NOT NULL,
    ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
  ) ENGINE=InnoDB;
"

# Xác nhận Router đã route insert đến PRIMARY (qua hostname đọc lại từ :6446)
RW_HOST_BEFORE=$(router_q "${ROUTER_RW_PORT}" "SELECT @@hostname;")
log "    :${ROUTER_RW_PORT} đang point đến: ${RW_HOST_BEFORE} (expect = ${PRIMARY_HOST})"
[[ "${RW_HOST_BEFORE}" == "${PRIMARY_HOST}" ]] || log "[WARN] :${ROUTER_RW_PORT} không trỏ đúng primary?"

# 2 — Bulk insert qua Router :6446 (tất cả trong 1 phiên)
log "==> [mgmt:${ROUTER_RW_PORT}] INSERT ${ROWS} rows..."
INSERT_START=$(date +%s.%N)
INSERT_SQL="USE smoke_db;"
for i in $(seq 1 "${ROWS}"); do
  INSERT_SQL+="INSERT INTO t(val) VALUES('row-${i}-$(date +%s)');"
done
router_exec_multi "${ROUTER_RW_PORT}" "${INSERT_SQL}"
INSERT_END=$(date +%s.%N)
INSERT_DUR=$(awk -v s="${INSERT_START}" -v e="${INSERT_END}" 'BEGIN{printf "%.3f", e-s}')
log "==> insert ${ROWS} rows xong sau ${INSERT_DUR}s"

# 3 — Wait từng node trực tiếp đến khi đạt ROWS
# IMPORTANT: stdout của wait_node được bắt qua $(); chỉ echo giá trị "elapsed" hoặc "TIMEOUT" ra stdout.
# Mọi log trace phải đẩy sang stderr (wlog) để không trộn vào kết quả capture.
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

# 4 — Đọc qua Router :6447 (RO) — 6 lần để bắt round-robin
log "==> [mgmt:${ROUTER_RO_PORT}] 6 hits — kỳ vọng round-robin giữa 2 secondaries, mỗi hit thấy đủ ${ROWS} rows"
declare -A RO_HIT_COUNT
RO_HAS_PRIMARY=false
RO_ALL_OK=true
for i in 1 2 3 4 5 6; do
  RESULT=$(router_q "${ROUTER_RO_PORT}" "SELECT CONCAT(@@hostname,'|',(SELECT COUNT(*) FROM smoke_db.t));" || echo "FAIL|0")
  HOST="${RESULT%%|*}"
  CNT="${RESULT##*|}"
  log "    :${ROUTER_RO_PORT} hit #$i -> host=${HOST} count=${CNT}"
  RO_HIT_COUNT["$HOST"]=$(( ${RO_HIT_COUNT["$HOST"]:-0} + 1 ))
  [[ "$HOST" == "$PRIMARY_HOST" ]] && RO_HAS_PRIMARY=true
  if [[ ! "$CNT" =~ ^[0-9]+$ || "$CNT" -lt "$ROWS" ]]; then
    RO_ALL_OK=false
  fi
done

# 5 — gtid_executed 3 node
log "==> So sánh gtid_executed:"
G1=$(mysql_q_root node1 "SELECT @@global.gtid_executed;")
G2=$(mysql_q_root node2 "SELECT @@global.gtid_executed;")
G3=$(mysql_q_root node3 "SELECT @@global.gtid_executed;")
log "    node1: ${G1}"
log "    node2: ${G2}"
log "    node3: ${G3}"

# 6 — Conclusion
log "================ KẾT LUẬN ================"
pass=true
if [[ "$LAG1" == "TIMEOUT" || "$LAG2" == "TIMEOUT" || "$LAG3" == "TIMEOUT" ]]; then
  log "[FAIL] Một node không catch-up trong ${TIMEOUT_SEC}s"
  pass=false
fi
if $RO_HAS_PRIMARY; then
  log "[FAIL] :${ROUTER_RO_PORT} đã route đến PRIMARY (sai policy)"
  pass=false
fi
$RO_ALL_OK || { log "[FAIL] Một hit :${ROUTER_RO_PORT} không thấy đủ ${ROWS} rows"; pass=false; }

# Phân phối hit (in để inspect)
log "    Phân phối :${ROUTER_RO_PORT}:"
for k in "${!RO_HIT_COUNT[@]}"; do log "      $k = ${RO_HIT_COUNT[$k]} hit(s)"; done

if $pass; then
  log "SMOKE_PASS=true  insert=${INSERT_DUR}s lag1=${LAG1} lag2=${LAG2} lag3=${LAG3}"
  echo "SMOKE_PASS=true" >> "${LOG}"
  exit 0
else
  log "SMOKE_PASS=false — xem log để biết checkpoint nào FAIL"
  echo "SMOKE_PASS=false" >> "${LOG}"
  exit 1
fi
