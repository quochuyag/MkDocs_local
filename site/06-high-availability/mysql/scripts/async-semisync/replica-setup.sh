#!/usr/bin/env bash
# replica-setup.sh — chạy trên node2, node3. Cấu hình replica, dùng GTID auto-position.
# Idempotent:
#   - Plugin INSTALL chỉ chạy khi chưa có
#   - Nếu replica đã đang chạy & trỏ đúng SOURCE_HOST & Auto_Position=1 → skip CHANGE
#   - super_read_only được set lại cuối cùng (an toàn cả khi đã ON)
set -euo pipefail
source "$(dirname "$0")/../common/env.sh"
require_root

MASTER_HOST="${MASTER_HOST:-${NODE1_HOST}}"

log "==> [1/4] Cài plugin semi-sync replica (idempotent)"
mysql_root <<SQL
SET @cnt = (SELECT COUNT(*) FROM information_schema.plugins
            WHERE plugin_name='rpl_semi_sync_replica');
SET @sql = IF(@cnt=0,
              "INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so'",
              "DO 0 /* plugin already installed */");
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET GLOBAL rpl_semi_sync_replica_enabled = 1;
SQL

log "==> [2/4] Kiểm tra state replica hiện tại"
# Lấy IO/SQL state + source host hiện tại. NULL/empty nếu chưa CHANGE REPLICATION SOURCE.
IO_STATE=$(mysql_root -NB -e "SELECT IFNULL(SERVICE_STATE,'NONE') FROM performance_schema.replication_connection_status;" 2>/dev/null || echo "NONE")
SQL_STATE=$(mysql_root -NB -e "SELECT IFNULL(SERVICE_STATE,'NONE') FROM performance_schema.replication_applier_status;" 2>/dev/null || echo "NONE")
CURR_HOST=$(mysql_root -NB -e "SELECT IFNULL(HOST,'') FROM performance_schema.replication_connection_configuration;" 2>/dev/null || echo "")
AUTO_POS=$(mysql_root -NB -e "SELECT IFNULL(AUTO_POSITION,0) FROM performance_schema.replication_connection_configuration;" 2>/dev/null || echo "0")

log "    current: IO=${IO_STATE} SQL=${SQL_STATE} HOST='${CURR_HOST}' AUTO_POS=${AUTO_POS}"

if [[ "${IO_STATE}" == "ON" && "${SQL_STATE}" == "ON" \
      && "${CURR_HOST}" == "${MASTER_HOST}" && "${AUTO_POS}" == "1" ]]; then
  log "==> [3/4] Replica đã configured & chạy OK → SKIP CHANGE REPLICATION SOURCE"
else
  log "==> [3/4] Replica chưa OK → STOP/RESET/CHANGE REPLICATION SOURCE"
  mysql_root <<SQL
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${MASTER_HOST}',
  SOURCE_PORT=${MYSQL_PORT},
  SOURCE_USER='${REPL_USER}',
  SOURCE_PASSWORD='${REPL_PWD}',
  SOURCE_AUTO_POSITION=1,
  SOURCE_SSL=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SQL
  sleep 2
fi

log "==> [4/4] Set host này read-only để chống ghi nhầm"
mysql_root <<SQL
SET GLOBAL read_only = ON;
SET GLOBAL super_read_only = ON;
SQL

log "==> Replica state cuối:"
mysql_root -e "SHOW REPLICA STATUS\G" | egrep \
  'Replica_IO_Running|Replica_SQL_Running|Source_Host|Auto_Position|Seconds_Behind_Source|Last_IO_Error|Last_SQL_Error|Retrieved_Gtid_Set|Executed_Gtid_Set' \
  || true

log "==> Replica $(hostname) đã online"
