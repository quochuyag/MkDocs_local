#!/usr/bin/env bash
# 05-smoke-test.sh — INSERT/SELECT qua :6033 + verify R/W split.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-smoke-test.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

ROWS="${ROWS:-100}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

app_q() {
  vagrant ssh mgmt -c "mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P${PROXYSQL_MYSQL_PORT} -N -B -e \"$1\" 2>/dev/null" | tr -d '\r'
}

app_exec() {
  printf '%s' "$1" | vagrant ssh mgmt -c "mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P${PROXYSQL_MYSQL_PORT} 2>/dev/null" >/dev/null
}

admin_q() {
  vagrant ssh mgmt -c "mysql -uadmin -padmin -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -N -B -e \"$1\" 2>/dev/null" | tr -d '\r'
}

log "================ SMOKE TEST PROXYSQL (ROWS=${ROWS}) ================"

# 1 — Setup schema appdb.t qua :6033 (appuser chỉ có quyền appdb.*)
log "==> [appuser:${PROXYSQL_MYSQL_PORT}] CREATE TABLE appdb.t"
app_exec "
  CREATE DATABASE IF NOT EXISTS appdb;
  DROP TABLE IF EXISTS appdb.t;
  CREATE TABLE appdb.t(
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    val VARCHAR(64) NOT NULL,
    ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
  ) ENGINE=InnoDB;
"

# 2 — Insert (must route to writer HG10)
log "==> INSERT ${ROWS} rows qua :${PROXYSQL_MYSQL_PORT}"
START=$(date +%s.%N)
SQL="USE appdb;"
for i in $(seq 1 "${ROWS}"); do SQL+="INSERT INTO t(val) VALUES('row-${i}');"; done
app_exec "${SQL}"
END=$(date +%s.%N)
DUR=$(awk -v s="${START}" -v e="${END}" 'BEGIN{printf "%.3f", e-s}')
log "    insert ${ROWS} rows xong sau ${DUR}s"

# 3 — Select để bắt round-robin reader HG20
log "==> 8 SELECT @@hostname qua :${PROXYSQL_MYSQL_PORT} (kỳ vọng round-robin reader)"
declare -A READER_HIT_COUNT
for i in 1 2 3 4 5 6 7 8; do
  H=$(app_q "SELECT @@hostname;" || echo "FAIL")
  READER_HIT_COUNT["$H"]=$(( ${READER_HIT_COUNT["$H"]:-0} + 1 ))
  log "    hit #$i → ${H}"
done

log "    Phân phối hits:"
for k in "${!READER_HIT_COUNT[@]}"; do log "      $k = ${READER_HIT_COUNT[$k]}"; done

# 4 — Verify R/W split qua stats_mysql_connection_pool
log "==> stats_mysql_connection_pool (admin)"
admin_q "SELECT hostgroup, srv_host, status, ConnFree, ConnUsed, Queries FROM stats_mysql_connection_pool ORDER BY hostgroup, srv_host;" | tee -a "${LOG}"

# 5 — stats_mysql_query_digest top 5 (ProxySQL admin SQLite: dùng SUBSTR thay LEFT)
log "==> Top 5 query digest"
admin_q "SELECT digest, count_star, sum_time, schemaname, hostgroup, SUBSTR(digest_text, 1, 80) AS query FROM stats_mysql_query_digest ORDER BY sum_time DESC LIMIT 5;" | tee -a "${LOG}"

# 6 — Count vs direct DB (sanity)
COUNT_PROXY=$(app_q "SELECT COUNT(*) FROM appdb.t;")
log "    count qua proxy:6033 = ${COUNT_PROXY} (kỳ vọng = ${ROWS})"

log "================ KẾT LUẬN ================"
pass=true
[[ "$COUNT_PROXY" == "${ROWS}" ]] || { log "[FAIL] count mismatch"; pass=false; }
if (( ${#READER_HIT_COUNT[@]} < 2 )); then
  log "[WARN] SELECT chỉ hit 1 host — kiểm tra query rule '^SELECT' có gán đúng HG20 không"
fi

if $pass; then
  log "SMOKE_PASS=true"
  echo "SMOKE_PASS=true" >> "${LOG}"
  exit 0
else
  echo "SMOKE_PASS=false" >> "${LOG}"
  exit 1
fi
