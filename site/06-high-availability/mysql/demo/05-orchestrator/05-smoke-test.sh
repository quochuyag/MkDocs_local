#!/usr/bin/env bash
# 05-smoke-test.sh — Insert qua master, đọc trên 2 replica, đo lag.
# Orchestrator không phải proxy → connect trực tiếp tới master/replica.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-smoke-test.log"
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
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

mysql_exec() {
  local node="$1" sql="$2"
  printf '%s' "$sql" | vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' 2>/dev/null" >/dev/null
}

# Current master = which-cluster-master từ Orchestrator (writeable master của cluster)
MASTER=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NODE1_IP}:${MYSQL_PORT} 2>/dev/null" | tr -d '\r' | tail -n1)
log "==> Master theo Orchestrator = ${MASTER}"

# Convert IP → hostname (node1/2/3) cho vagrant ssh
case "${MASTER}" in
  *"${NODE1_IP}"*) MASTER_HOST="node1" ;;
  *"${NODE2_IP}"*) MASTER_HOST="node2" ;;
  *"${NODE3_IP}"*) MASTER_HOST="node3" ;;
  *) MASTER_HOST="node1"; log "[WARN] Không parse được master IP, fallback node1" ;;
esac

log "================ SMOKE TEST (ROWS=${ROWS}) qua MASTER=${MASTER_HOST} ================"

# 1 — Setup schema + bulk insert
mysql_exec "${MASTER_HOST}" "
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  USE smoke_db;
  CREATE TABLE t(id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(64), ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)) ENGINE=InnoDB;
"

INSERT_START=$(date +%s.%N)
INSERT_SQL="USE smoke_db;"
for i in $(seq 1 "${ROWS}"); do INSERT_SQL+="INSERT INTO t(val) VALUES('row-${i}');"; done
mysql_exec "${MASTER_HOST}" "${INSERT_SQL}"
INSERT_END=$(date +%s.%N)
INSERT_DUR=$(awk -v s="${INSERT_START}" -v e="${INSERT_END}" 'BEGIN{printf "%.3f", e-s}')
log "==> insert ${ROWS} rows xong sau ${INSERT_DUR}s"

# 2 — Wait từng node
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
  log "SMOKE_PASS=false"
  echo "SMOKE_PASS=false" >> "${LOG}"
  exit 1
fi
