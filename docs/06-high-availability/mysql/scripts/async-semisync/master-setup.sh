#!/usr/bin/env bash
# master-setup.sh — chạy trên node1 (master). Bật semi-sync, tạo repl user, cấp GTID seed.
# Idempotent: rerun nhiều lần OK (plugin check, CREATE USER IF NOT EXISTS, config overwrite).
set -euo pipefail
source "$(dirname "$0")/../common/env.sh"
require_root

log "==> [1/4] Cài plugin semi-sync source (idempotent)"
# Dùng prepared SQL conditional: chỉ INSTALL nếu plugin chưa có. INSTALL PLUGIN
# không hỗ trợ IF NOT EXISTS trong MySQL 8.0 → cần check qua information_schema.
mysql_root <<SQL
SET @cnt = (SELECT COUNT(*) FROM information_schema.plugins
            WHERE plugin_name='rpl_semi_sync_source');
SET @sql = IF(@cnt=0,
              "INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so'",
              "DO 0 /* plugin already installed */");
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET GLOBAL rpl_semi_sync_source_enabled = 1;
SET GLOBAL rpl_semi_sync_source_timeout = 10000;   -- 10s rồi fallback async
SQL

log "==> [2/4] Ghi config bền vững vào zz-semisync.cnf"
CONF=/etc/mysql/mysql.conf.d/zz-semisync.cnf
[[ -d /etc/mysql/mysql.conf.d ]] || CONF=/etc/my.cnf.d/zz-semisync.cnf
cat >"$CONF" <<'EOF'
[mysqld]
plugin_load_add                = "semisync_source.so;semisync_replica.so"
rpl_semi_sync_source_enabled   = 1
rpl_semi_sync_source_timeout   = 10000
rpl_semi_sync_replica_enabled  = 1
EOF

log "==> [3/4] Tạo / cập nhật replication user (idempotent)"
mysql_root <<SQL
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PWD}';
ALTER USER '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PWD}';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${REPL_USER}'@'%';
FLUSH PRIVILEGES;
SQL

log "==> [4/4] Xuất master state (GTID set) cho bước add replica"
mysql_root -e "SHOW MASTER STATUS\G; SELECT @@global.gtid_executed AS gtid_executed;"

log "==> Master sẵn sàng. Tiếp theo: chạy replica-setup.sh trên node2/node3."
