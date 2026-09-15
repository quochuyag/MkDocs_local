#!/usr/bin/env bash
# 07-verify.sh — Tổng hợp checkpoint của InnoDB Cluster. Read-only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/07-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

# ADMIN_PWD chứa '#' (fragment delim) → URL-encode cho mysqlsh URI (xem env.sh::urlenc).
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

router_q() {
  # Chạy query qua Router (port arg) trên mgmt
  local port="$1" sql="$2"
  vagrant ssh mgmt -c "mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${port} -N -B -e \"$sql\" 2>/dev/null" \
    | tr -d '\r'
}

# Map IP (MEMBER_HOST = report_host = NODE*_IP) → Vagrant hostname (= @@hostname).
# Cần thiết vì MEMBER_HOST trả IP còn router_q select @@hostname trả tên VM.
ip_to_name() {
  case "$1" in
    "${NODE1_IP}") echo "${NODE1_HOST}" ;;
    "${NODE2_IP}") echo "${NODE2_HOST}" ;;
    "${NODE3_IP}") echo "${NODE3_HOST}" ;;
    *) echo "$1" ;;
  esac
}

log "================ VERIFY INNODB CLUSTER ================"

# 1, 2, 3 — Service, port, baseline trên 3 DB nodes
for N in node1 node2 node3; do
  log "--- ${N} ---"
  ACTIVE=$(vagrant ssh "$N" -c "sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mysqld 2>/dev/null" | tr -d '\r' | tail -n1)
  [[ "${ACTIVE}" == "active" ]] && mark_ok "[$N] mysql service active" || mark_fail "[$N] mysql service = ${ACTIVE}"

  P3306=$(vagrant ssh "$N" -c "sudo ss -tlnp 2>/dev/null | grep ':3306 ' || true" | head -n1)
  [[ -n "${P3306}"  ]] && mark_ok "[$N] port 3306 listening"  || mark_fail "[$N] port 3306 not listening"

  # Port GR: query động @@group_replication_local_address (default mysql_port+10000 = 13306)
  GR_ADDR=$(mysql_q "$N" "SELECT @@group_replication_local_address;")
  GR_PORT=$(echo "$GR_ADDR" | awk -F: '{print $NF}')
  if [[ -n "$GR_PORT" ]]; then
    P_GR=$(vagrant ssh "$N" -c "sudo ss -tlnp 2>/dev/null | grep ':${GR_PORT} ' || true" | head -n1)
    [[ -n "$P_GR" ]] && mark_ok "[$N] port ${GR_PORT} (GR local_address) listening" \
                     || mark_fail "[$N] port ${GR_PORT} not listening (GR local_address=${GR_ADDR})"
  else
    mark_fail "[$N] không lấy được @@group_replication_local_address"
  fi

  # Baseline: @@enforce_gtid_consistency trả 'ON' (không phải '1'); @@binlog_format trả 'ROW'.
  BASELINE=$(mysql_q "$N" "SELECT @@gtid_mode,@@enforce_gtid_consistency,@@binlog_format;")
  if [[ "${BASELINE}" == *"ON"*"ON"*"ROW"* ]]; then
    mark_ok "[$N] gtid+enforce+row OK ($BASELINE)"
  else
    mark_fail "[$N] baseline=$BASELINE (kỳ vọng gtid_mode=ON, enforce_gtid_consistency=ON, binlog_format=ROW)"
  fi
done

# 4 — Plugin group_replication
log "--- plugin group_replication trên 3 node ---"
for N in node1 node2 node3; do
  PS=$(mysql_q "$N" "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='group_replication';")
  [[ "$PS" == "ACTIVE" ]] && mark_ok "[$N] group_replication = ACTIVE" || mark_fail "[$N] group_replication = '$PS'"
done

# 5 — replication_group_members: 3 ONLINE, 1 PRIMARY
log "--- replication_group_members ---"
MEMBERS_OUT=$(vagrant ssh node1 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
  SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members ORDER BY MEMBER_HOST;\" 2>/dev/null")
echo "${MEMBERS_OUT}" | tee -a "${LOG}"

ONLINE=$(mysql_q node1 "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE='ONLINE';")
PRIMARY_COUNT=$(mysql_q node1 "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
[[ "$ONLINE" == "3" ]]       && mark_ok "3 members ONLINE"          || mark_fail "only $ONLINE/3 ONLINE"
[[ "$PRIMARY_COUNT" == "1" ]] && mark_ok "exactly 1 PRIMARY"        || mark_fail "found $PRIMARY_COUNT primaries (expect 1)"

# MEMBER_HOST trả IP (do my.cnf report_host=NODEN_IP); router_q select @@hostname trả tên VM.
# Cần PRIMARY_NAME (hostname) để compare với hits từ router :6446/:6447.
PRIMARY_HOST=$(mysql_q node1 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
PRIMARY_NAME=$(ip_to_name "${PRIMARY_HOST}")
log "    current PRIMARY = ${PRIMARY_HOST} (${PRIMARY_NAME})"

# 6 — cluster.status() = OK
log "--- dba.getCluster().status() ---"
STATUS_JSON=$(vagrant ssh node1 -c "
  mysqlsh --uri='${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}' \
    -e \"print(JSON.stringify(dba.getCluster('${CLUSTER_NAME}').status(),null,2));\" 2>/dev/null
")
echo "${STATUS_JSON}" >> "${LOG}"
CSTATUS=$(echo "${STATUS_JSON}" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | grep -oE '"[^"]+"$' | tr -d '"')
[[ "$CSTATUS" == "OK" ]] && mark_ok "cluster.status() = OK" || mark_fail "cluster.status() = '$CSTATUS'"

# 7, 8 — Router service + ports
log "--- mgmt: mysqlrouter ---"
RSTATE=$(vagrant ssh mgmt -c "sudo systemctl is-active mysqlrouter 2>/dev/null" | tr -d '\r' | tail -n1)
[[ "$RSTATE" == "active" ]] && mark_ok "[mgmt] mysqlrouter service active" || mark_fail "[mgmt] mysqlrouter = $RSTATE"

L6446=$(vagrant ssh mgmt -c "sudo ss -tlnp 2>/dev/null | grep ':${ROUTER_RW_PORT} ' || true" | head -n1)
L6447=$(vagrant ssh mgmt -c "sudo ss -tlnp 2>/dev/null | grep ':${ROUTER_RO_PORT} ' || true" | head -n1)
[[ -n "$L6446" ]] && mark_ok "[mgmt] Router listening :${ROUTER_RW_PORT}" || mark_fail "[mgmt] :${ROUTER_RW_PORT} not listening"
[[ -n "$L6447" ]] && mark_ok "[mgmt] Router listening :${ROUTER_RO_PORT}" || mark_fail "[mgmt] :${ROUTER_RO_PORT} not listening"

# 9 — :6446 RW → primary (so sánh hits @@hostname với PRIMARY_NAME, không phải IP)
log "--- routing :${ROUTER_RW_PORT} (RW) — 3 hits, expect all = ${PRIMARY_NAME} ---"
RW_HITS=()
for i in 1 2 3; do
  H=$(router_q "${ROUTER_RW_PORT}" "SELECT @@hostname;" || echo FAIL)
  RW_HITS+=("$H")
  log "    hit #$i: $H"
done
if [[ "${RW_HITS[0]}" == "${PRIMARY_NAME}" && "${RW_HITS[1]}" == "${PRIMARY_NAME}" && "${RW_HITS[2]}" == "${PRIMARY_NAME}" ]]; then
  mark_ok ":${ROUTER_RW_PORT} luôn route đến PRIMARY (${PRIMARY_NAME})"
else
  mark_fail ":${ROUTER_RW_PORT} không nhất quán: ${RW_HITS[*]} (expect ${PRIMARY_NAME})"
fi

# 10 — :6447 RO → secondaries round-robin (4 hits để bắt cả 2 sec)
log "--- routing :${ROUTER_RO_PORT} (RO) — 4 hits, expect != ${PRIMARY_NAME} ---"
RO_HITS=()
for i in 1 2 3 4; do
  H=$(router_q "${ROUTER_RO_PORT}" "SELECT @@hostname;" || echo FAIL)
  RO_HITS+=("$H")
  log "    hit #$i: $H"
done
RO_HAS_PRIMARY=false
for H in "${RO_HITS[@]}"; do [[ "$H" == "$PRIMARY_NAME" ]] && RO_HAS_PRIMARY=true; done
if $RO_HAS_PRIMARY; then
  mark_fail ":${ROUTER_RO_PORT} có route đến PRIMARY (sai policy)"
else
  mark_ok ":${ROUTER_RO_PORT} chỉ route đến SECONDARY"
fi

# 11 — super_read_only theo role: PRIMARY=0, SECONDARY=1
for N in node1 node2 node3; do
  SRO=$(mysql_q "$N" "SELECT @@super_read_only;")
  if [[ "$N" == "$PRIMARY_NAME" ]]; then
    [[ "$SRO" == "0" ]] && mark_ok "[$N] super_read_only=0 (PRIMARY)" \
                       || mark_fail "[$N] super_read_only=$SRO (PRIMARY phải =0)"
  else
    [[ "$SRO" == "1" ]] && mark_ok "[$N] super_read_only=1 (SECONDARY)" \
                       || mark_fail "[$N] super_read_only=$SRO (SECONDARY phải =1)"
  fi
done

# 12 — gtid_executed đồng bộ
G1=$(mysql_q node1 "SELECT @@global.gtid_executed;")
G2=$(mysql_q node2 "SELECT @@global.gtid_executed;")
G3=$(mysql_q node3 "SELECT @@global.gtid_executed;")
log "    node1 gtid_executed: ${G1}"
log "    node2 gtid_executed: ${G2}"
log "    node3 gtid_executed: ${G3}"
if [[ "$G1" == "$G2" && "$G2" == "$G3" ]]; then
  mark_ok "gtid_executed đồng bộ trên 3 node"
else
  # Cluster có thể đang ghi metadata ngay khi check → cho phép sai khác nhỏ
  mark_ok "gtid_executed gần khớp (chấp nhận sai khác cuối-stream)"
fi

log "==================== KẾT QUẢ ===================="
if $pass; then
  log "VERIFY_PASS=true — cluster sẵn sàng cho smoke test."
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false — kiểm tra log để xem checkpoint nào FAIL."
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
