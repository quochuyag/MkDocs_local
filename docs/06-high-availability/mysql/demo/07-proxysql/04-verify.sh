#!/usr/bin/env bash
# 04-verify.sh — Verify ProxySQL state + app connect.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

admin_q() {
  vagrant ssh mgmt -c "mysql -uadmin -padmin -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -N -B -e \"$1\" 2>/dev/null" | tr -d '\r'
}

app_q() {
  vagrant ssh mgmt -c "mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P${PROXYSQL_MYSQL_PORT} -N -B -e \"$1\" 2>/dev/null" | tr -d '\r'
}

log "================ VERIFY PROXYSQL ================"

# 1 — Service + ports
ACTIVE=$(vagrant ssh mgmt -c "sudo systemctl is-active proxysql 2>/dev/null" | tr -d '\r' | tail -n1)
[[ "$ACTIVE" == "active" ]] && mark_ok "proxysql service active" || mark_fail "proxysql=$ACTIVE"

for PORT in "${PROXYSQL_ADMIN_PORT}" "${PROXYSQL_MYSQL_PORT}"; do
  P=$(vagrant ssh mgmt -c "sudo ss -tlnp 2>/dev/null | grep ':${PORT} ' || true" | head -n1)
  [[ -n "$P" ]] && mark_ok "port ${PORT} listening" || mark_fail "port ${PORT} not listening"
done

# 2 — runtime_mysql_servers status
SERVERS=$(admin_q "SELECT COUNT(*) FROM runtime_mysql_servers;")
ONLINE=$(admin_q "SELECT COUNT(*) FROM runtime_mysql_servers WHERE status='ONLINE';")
log "    runtime_mysql_servers: ${SERVERS} rows, ${ONLINE} ONLINE"
[[ "$ONLINE" -ge "3" ]] && mark_ok "≥3 servers ONLINE" || mark_fail "chỉ ${ONLINE} ONLINE"

# 3 — Monitor probes (ProxySQL admin SQLite không có UNIX_TIMESTAMP — inject từ shell)
SINCE_US=$(( ($(date +%s) - 60) * 1000000 ))
PING_OK=$(admin_q "SELECT COUNT(*) FROM mysql_server_ping_log WHERE time_start_us > ${SINCE_US} AND ping_error IS NULL;")
PING_OK="${PING_OK:-0}"
log "    Recent ping probes (60s window): ${PING_OK}"
[[ "$PING_OK" -ge "3" ]] && mark_ok "monitor probes healthy" || mark_fail "monitor probes thấp (${PING_OK})"

# 4 — App connect qua :6033
HN=$(app_q "SELECT @@hostname;")
[[ -n "$HN" ]] && mark_ok "appuser connect :${PROXYSQL_MYSQL_PORT} → @@hostname=$HN" || mark_fail "appuser connect FAIL"

# 5 — Query rules visible
RULES=$(admin_q "SELECT COUNT(*) FROM runtime_mysql_query_rules WHERE active=1;")
log "    active query rules: ${RULES}"
[[ "$RULES" -ge "2" ]] && mark_ok "≥2 active query rules" || mark_fail "ít rules: ${RULES}"

log "================ KẾT QUẢ ================"
if $pass; then
  log "VERIFY_PASS=true"
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false"
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
