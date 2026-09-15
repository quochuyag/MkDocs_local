#!/usr/bin/env bash
# node-setup.sh — chạy trên CẢ 3 nodes trước khi bootstrap cluster.
# Dùng mysqlsh dba.configureInstance() để chuẩn hoá config cho GR.
set -euo pipefail
source "$(dirname "$0")/../common/env.sh"
require_root

log "==> Tạo cluster admin user (dùng cho dba.* APIs)"
mysql_root <<SQL
CREATE USER IF NOT EXISTS '${ADMIN_USER}'@'%' IDENTIFIED BY '${ADMIN_PWD}';
GRANT ALL PRIVILEGES ON *.* TO '${ADMIN_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# Password chứa '#' nên phải URL-encode cho mysqlsh URI (xem env.sh::urlenc)
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"
URI_LOCAL="${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}"

log "==> Cấu hình instance cho InnoDB Cluster (sẽ tự sửa my.cnf + restart nếu cần)"
# Dùng JS heredoc — CLI form `-- dba configureInstance '{...}'` bị mysqlsh parse JSON
# như connection-options (đẻ lỗi "Invalid values in connection options: clusterAdmin,...").
# Không truyền clusterAdmin/clusterAdminPassword: user đã được SQL step ở trên tạo;
# configureInstance sẽ throw "account already exists, clusterAdminPassword is not allowed".
mysqlsh --uri="${URI_LOCAL}" <<JS || true
dba.configureInstance(null, {
  interactive: false,
  restart: true
});
JS

log "==> Đợi MySQL phục hồi sau restart"
for i in {1..30}; do
  if mysqladmin -uroot -p"${MYSQL_ROOT_PWD}" ping &>/dev/null; then break; fi
  sleep 2
done

log "==> Verify instance ready"
# checkInstanceConfiguration cần password — truyền qua dict thứ 2.
mysqlsh --uri="${URI_LOCAL}" <<JS
dba.checkInstanceConfiguration({
  user: '${ADMIN_USER}',
  password: '${ADMIN_PWD}',
  host: '127.0.0.1',
  port: ${MYSQL_PORT}
});
JS

log "==> Node $(hostname) sẵn sàng tham gia InnoDB Cluster"
