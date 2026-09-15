#!/usr/bin/env bash
# 07-smoke-test.sh — Multi-master write test:
#   1) Insert tuần tự trên node1 → đo sync lag trên node2/3 (kỳ vọng ~0)
#   2) Insert song song trên cả 3 node → verify consistency (count đồng nhất, không xung đột PK)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/07-smoke-test.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

ROWS="${ROWS:-150}"
TIMEOUT_SEC="${TIMEOUT_SEC:-15}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

mysql_exec() {
  local node="$1" sql="$2"
  printf '%s' "$sql" | vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
}

log "================ SMOKE TEST GALERA (ROWS=${ROWS}) ================"

# Setup schema — Galera bắt buộc PK
log "==> Setup schema smoke_db.t (PK, InnoDB)"
mysql_exec node1 "
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  USE smoke_db;
  CREATE TABLE t(
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    src VARCHAR(16) NOT NULL,
    val VARCHAR(64) NOT NULL,
    ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
  ) ENGINE=InnoDB;
"

# === Part 1: Insert tuần tự trên node1, đo lag trên node2/3 ===
log "==> Part 1: Bulk insert ${ROWS} rows trên node1"
INSERT_START=$(date +%s.%N)
SQL="USE smoke_db;"
for i in $(seq 1 "${ROWS}"); do SQL+="INSERT INTO t(src,val) VALUES('node1','seq-${i}');"; done
mysql_exec node1 "${SQL}"
INSERT_END=$(date +%s.%N)
DUR=$(awk -v s="${INSERT_START}" -v e="${INSERT_END}" 'BEGIN{printf "%.3f", e-s}')
log "    insert ${ROWS} rows xong sau ${DUR}s"

wait_node() {
  local node="$1" target="${ROWS}" start now elapsed cnt
  wlog() { log "$@" >&2; }
  start=$(date +%s.%N)
  while :; do
    cnt=$(mysql_q "$node" "SELECT COUNT(*) FROM smoke_db.t;" 2>/dev/null || echo 0)
    cnt="${cnt:-0}"
    if [[ "$cnt" =~ ^[0-9]+$ && "$cnt" -ge "$target" ]]; then
      now=$(date +%s.%N)
      elapsed=$(awk -v s="$start" -v e="$now" 'BEGIN{printf "%.3f", e-s}')
      wlog "==> [$node] thấy ${cnt} rows sau ${elapsed}s"
      echo "$elapsed"; return 0
    fi
    now=$(date +%s.%N)
    elapsed=$(awk -v s="$start" -v e="$now" 'BEGIN{printf "%.1f", e-s}')
    if awk -v e="$elapsed" -v t="$TIMEOUT_SEC" 'BEGIN{exit !(e>t)}'; then
      wlog "==> [$node] TIMEOUT (${cnt}/${target})"; echo "TIMEOUT"; return 1
    fi
    sleep 0.05
  done
}

LAG2=$(wait_node node2 || true)
LAG3=$(wait_node node3 || true)

# === Part 2: Insert song song 3 nodes ===
PARALLEL_ROWS="${PARALLEL_ROWS:-50}"
log "==> Part 2: Insert song song ${PARALLEL_ROWS} rows trên mỗi node (multi-master)"
for N in node1 node2 node3; do
  (
    SQL2="USE smoke_db;"
    for i in $(seq 1 "${PARALLEL_ROWS}"); do
      SQL2+="INSERT INTO t(src,val) VALUES('${N}','par-${i}-$$');"
    done
    mysql_exec "$N" "${SQL2}"
    log "    [$N] đã insert ${PARALLEL_ROWS} rows"
  ) &
done
wait

sleep 2  # đợi cert-replication settle
log "==> Sau parallel insert: total expected = ${ROWS} + 3*${PARALLEL_ROWS} = $(( ROWS + 3 * PARALLEL_ROWS ))"
EXPECTED=$(( ROWS + 3 * PARALLEL_ROWS ))
for N in node1 node2 node3; do
  C=$(mysql_q "$N" "SELECT COUNT(*) FROM smoke_db.t;")
  SRC1=$(mysql_q "$N" "SELECT COUNT(*) FROM smoke_db.t WHERE src='node1';")
  SRC2=$(mysql_q "$N" "SELECT COUNT(*) FROM smoke_db.t WHERE src='node2';")
  SRC3=$(mysql_q "$N" "SELECT COUNT(*) FROM smoke_db.t WHERE src='node3';")
  log "    [$N] total=$C  node1=${SRC1} node2=${SRC2} node3=${SRC3}"
done

log "================ KẾT LUẬN ================"
pass=true
[[ "$LAG2" == "TIMEOUT" || "$LAG3" == "TIMEOUT" ]] && { log "[FAIL] Part 1 lag timeout"; pass=false; }

# Check parallel consistency: cả 3 node phải báo cùng total
C1=$(mysql_q node1 "SELECT COUNT(*) FROM smoke_db.t;")
C2=$(mysql_q node2 "SELECT COUNT(*) FROM smoke_db.t;")
C3=$(mysql_q node3 "SELECT COUNT(*) FROM smoke_db.t;")
if [[ "$C1" == "$C2" && "$C2" == "$C3" ]]; then
  log "[OK] Consistency: 3 nodes báo total=${C1}"
else
  log "[FAIL] Inconsistent counts: ${C1}/${C2}/${C3}"; pass=false
fi

if $pass; then
  log "SMOKE_PASS=true  insert=${DUR}s lag2=${LAG2} lag3=${LAG3} parallel_total=${C1}"
  echo "SMOKE_PASS=true" >> "${LOG}"
  exit 0
else
  log "SMOKE_PASS=false"
  echo "SMOKE_PASS=false" >> "${LOG}"
  exit 1
fi
