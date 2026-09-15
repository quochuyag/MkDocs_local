#!/usr/bin/env bash
# 07-smoke-test.sh — Insert N rows lên master, đo thời gian replica catch-up.
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

log "================ SMOKE TEST (ROWS=${ROWS}) ================"

# 1 — Setup schema trên master
log "==> [node1] CREATE DATABASE + TABLE smoke_db.t"
mysql_exec node1 "
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  USE smoke_db;
  CREATE TABLE t (
    id  INT PRIMARY KEY AUTO_INCREMENT,
    val VARCHAR(64) NOT NULL,
    ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
  ) ENGINE=InnoDB;
" 2>&1 | tee -a "${LOG}"

# Capture baseline yes_tx
YES_TX_BEFORE=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';" | awk '{print $2}')
log "==> [node1] yes_tx trước insert: ${YES_TX_BEFORE}"

# 2 — Bulk insert có timing
log "==> [node1] INSERT ${ROWS} rows..."
INSERT_START=$(date +%s.%N)
INSERT_SQL=""
for i in $(seq 1 "${ROWS}"); do
  INSERT_SQL+="INSERT INTO t(val) VALUES('row-${i}-$(date +%s)');"
done
# Truyền 1 phiên duy nhất để tránh handshake N lần
echo "USE smoke_db; ${INSERT_SQL}" | vagrant ssh node1 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
INSERT_END=$(date +%s.%N)
INSERT_DUR=$(awk -v s="${INSERT_START}" -v e="${INSERT_END}" 'BEGIN{printf "%.3f", e-s}')
log "==> [node1] insert ${ROWS} rows xong trong ${INSERT_DUR}s"

# 3 — Đợi replicas catch-up
wait_replica() {
  local node="$1"
  local target="$ROWS"
  local start now elapsed cnt
  start=$(date +%s.%N)
  while :; do
    cnt=$(mysql_q "$node" "SELECT COUNT(*) FROM smoke_db.t;" 2>/dev/null || echo "0")
    cnt="${cnt:-0}"
    if [[ "$cnt" =~ ^[0-9]+$ && "$cnt" -ge "$target" ]]; then
      now=$(date +%s.%N)
      elapsed=$(awk -v s="$start" -v e="$now" 'BEGIN{printf "%.3f", e-s}')
      log "==> [$node] thấy ${cnt} rows sau ${elapsed}s"
      echo "$elapsed"
      return 0
    fi
    now=$(date +%s.%N)
    elapsed=$(awk -v s="$start" -v e="$now" 'BEGIN{printf "%.1f", e-s}')
    if awk -v e="$elapsed" -v t="$TIMEOUT_SEC" 'BEGIN{exit !(e>t)}'; then
      log "==> [$node] TIMEOUT sau ${elapsed}s — chỉ thấy ${cnt}/${target}"
      echo "TIMEOUT"
      return 1
    fi
    sleep 0.1
  done
}

LAG2=$(wait_replica node2 || true)
LAG3=$(wait_replica node3 || true)

# 4 — Capture yes_tx sau insert
YES_TX_AFTER=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';" | awk '{print $2}')
NO_TX=$(mysql_q node1 "SHOW STATUS LIKE 'Rpl_semi_sync_source_no_tx';" | awk '{print $2}')
log "==> [node1] yes_tx sau insert: ${YES_TX_AFTER} (delta=$((YES_TX_AFTER-YES_TX_BEFORE)), no_tx=${NO_TX})"

# 5 — So sánh gtid_executed 3 node
log "==> So sánh gtid_executed:"
G1=$(mysql_q node1 "SELECT @@global.gtid_executed;")
G2=$(mysql_q node2 "SELECT @@global.gtid_executed;")
G3=$(mysql_q node3 "SELECT @@global.gtid_executed;")
log "    node1: ${G1}"
log "    node2: ${G2}"
log "    node3: ${G3}"

# 6 — Check replica không có write thật (super_read_only)
RO2=$(mysql_q node2 "SELECT @@super_read_only;")
RO3=$(mysql_q node3 "SELECT @@super_read_only;")

# 7 — Kết luận
log "================ KẾT LUẬN ================"
pass=true
if [[ "$LAG2" == "TIMEOUT" || "$LAG3" == "TIMEOUT" ]]; then
  log "[FAIL] Replica không catch-up trong ${TIMEOUT_SEC}s"
  pass=false
fi
if [[ "$G1" != "$G2" || "$G1" != "$G3" ]]; then
  log "[WARN] gtid_executed chưa khớp hoàn toàn (có thể đang còn lag tail)"
fi
if [[ "$RO2" != "1" || "$RO3" != "1" ]]; then
  log "[FAIL] Replica không phải super_read_only"
  pass=false
fi
DELTA=$((YES_TX_AFTER-YES_TX_BEFORE))
if [[ "$DELTA" -lt 1 ]]; then
  log "[FAIL] yes_tx không tăng -> semi-sync không hoạt động"
  pass=false
fi

if $pass; then
  log "SMOKE_PASS=true  insert=${INSERT_DUR}s replica2_lag=${LAG2}s replica3_lag=${LAG3}s"
  echo "SMOKE_PASS=true" >> "${LOG}"
  exit 0
else
  log "SMOKE_PASS=false — xem log để biết checkpoint nào FAIL"
  echo "SMOKE_PASS=false" >> "${LOG}"
  exit 1
fi
