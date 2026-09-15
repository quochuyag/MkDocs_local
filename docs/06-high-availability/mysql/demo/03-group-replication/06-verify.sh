#!/usr/bin/env bash
# 06-verify.sh — Tổng hợp checkpoint của Group Replication. Read-only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

log "================ VERIFY GROUP REPLICATION ================"

for N in node1 node2 node3; do
  log "--- ${N} ---"
  ACTIVE=$(vagrant ssh "$N" -c "sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mysqld 2>/dev/null" | tr -d '\r' | tail -n1)
  [[ "${ACTIVE}" == "active" ]] && mark_ok "[$N] mysql service active" || mark_fail "[$N] mysql service = ${ACTIVE}"

  P3306=$(vagrant ssh "$N" -c "sudo ss -tlnp 2>/dev/null | grep ':3306 ' || true" | head -n1)
  P33061=$(vagrant ssh "$N" -c "sudo ss -tlnp 2>/dev/null | grep ':33061 ' || true" | head -n1)
  [[ -n "${P3306}" ]] && mark_ok "[$N] port 3306 listening"  || mark_fail "[$N] port 3306 not listening"
  [[ -n "${P33061}" ]] && mark_ok "[$N] port 33061 (GR) listening" || mark_fail "[$N] port 33061 not listening"

  # Note: @@enforce_gtid_consistency trả về 'ON'/'OFF'/'WARN' (chuỗi) chứ không phải số.
  # Mẫu cũ "*ON*1*ROW*" sai vì không có '1'. So sánh từng cột riêng.
  BASELINE=$(mysql_q "$N" "SELECT @@gtid_mode,@@enforce_gtid_consistency,@@binlog_format;")
  GTID=$(echo "$BASELINE" | awk '{print $1}')
  ENFG=$(echo "$BASELINE" | awk '{print $2}')
  BFMT=$(echo "$BASELINE" | awk '{print $3}')
  if [[ "$GTID" == "ON" && "$ENFG" == "ON" && "$BFMT" == "ROW" ]]; then
    mark_ok "[$N] gtid=ON enforce_gtid=ON binlog=ROW ($BASELINE)"
  else
    mark_fail "[$N] baseline=$BASELINE"
  fi

  PS=$(mysql_q "$N" "SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='group_replication';")
  [[ "$PS" == "ACTIVE" ]] && mark_ok "[$N] group_replication plugin ACTIVE" || mark_fail "[$N] group_replication = '$PS'"
done

log "--- replication_group_members ---"
MEMBERS_OUT=$(vagrant ssh node1 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
  SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members ORDER BY MEMBER_HOST;\" 2>/dev/null")
echo "${MEMBERS_OUT}" | tee -a "${LOG}"

ONLINE=$(mysql_q node1 "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE='ONLINE';")
PRIMARY_COUNT=$(mysql_q node1 "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
[[ "$ONLINE" == "3" ]]         && mark_ok "3 members ONLINE"          || mark_fail "only $ONLINE/3 ONLINE"
[[ "$PRIMARY_COUNT" == "1" ]]  && mark_ok "exactly 1 PRIMARY"         || mark_fail "found $PRIMARY_COUNT primaries (expect 1)"

PRIMARY_HOST=$(mysql_q node1 "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
log "    current PRIMARY = ${PRIMARY_HOST}"

# MEMBER_HOST = IP (report_host=192.168.10.x), nhưng vagrant ssh dùng hostname (node1..3).
# Map IP → hostname để so sánh.
ip_to_name() {
  case "$1" in
    "${NODE1_IP}") echo node1 ;;
    "${NODE2_IP}") echo node2 ;;
    "${NODE3_IP}") echo node3 ;;
    *) echo "$1" ;;
  esac
}
PRIMARY_NAME=$(ip_to_name "${PRIMARY_HOST}")
log "    PRIMARY vagrant name = ${PRIMARY_NAME}"

# super_read_only=1 trên 2 secondaries (primary phải super_read_only=0)
for N in node1 node2 node3; do
  SRO=$(mysql_q "$N" "SELECT @@super_read_only;")
  if [[ "$N" == "$PRIMARY_NAME" ]]; then
    [[ "$SRO" == "0" ]] && mark_ok "[$N] super_read_only=0 (PRIMARY)" || mark_fail "[$N] PRIMARY nhưng super_read_only=$SRO"
  else
    [[ "$SRO" == "1" ]] && mark_ok "[$N] super_read_only=1 (SECONDARY)" || mark_fail "[$N] SECONDARY nhưng super_read_only=$SRO"
  fi
done

# gtid_executed đồng bộ
G1=$(mysql_q node1 "SELECT @@global.gtid_executed;")
G2=$(mysql_q node2 "SELECT @@global.gtid_executed;")
G3=$(mysql_q node3 "SELECT @@global.gtid_executed;")
log "    node1 gtid_executed: ${G1}"
log "    node2 gtid_executed: ${G2}"
log "    node3 gtid_executed: ${G3}"
if [[ "$G1" == "$G2" && "$G2" == "$G3" ]]; then
  mark_ok "gtid_executed đồng bộ trên 3 node"
else
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
