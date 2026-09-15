#!/usr/bin/env bash
# 03-install-mysql.sh — Cài MySQL 8.0 community + shell + router trên 3 DB nodes.
# Chạy trên HOST. Gọi vagrant provisioner 'install-mysql' đã định nghĩa trong Vagrantfile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-install-mysql.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

DB_NODES=(node1 node2 node3)

for N in "${DB_NODES[@]}"; do
  log "==> install MySQL trên ${N} (tải ~250MB, có thể mất vài phút)"
  vagrant provision "${N}" --provision-with install-mysql 2>&1 | tee -a "${LOG}"
done

log "==> Verify MySQL service & baseline cho InnoDB Cluster"
for N in "${DB_NODES[@]}"; do
  log "    --- ${N} ---"
  vagrant ssh "${N}" -c "
    sudo systemctl is-active mysql || sudo systemctl is-active mysqld
    sudo ss -tlnp | grep ':3306 ' || true
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e \"
      SELECT CONCAT('host=',@@hostname,
                    ' sid=',@@server_id,
                    ' gtid=',@@gtid_mode,
                    ' enforce_gtid=',@@enforce_gtid_consistency,
                    ' binlog=',@@log_bin,
                    ' fmt=',@@binlog_format,
                    ' report_host=',@@report_host);
      SELECT plugin_name,plugin_status FROM information_schema.plugins WHERE plugin_name='clone';\"
    echo 'mysqlsh:';     command -v mysqlsh && mysqlsh --version
    echo 'mysqlrouter:'; command -v mysqlrouter && mysqlrouter --version
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 3 hoàn tất. Tiếp theo: bash demo/02-innodb-cluster/04-node-setup.sh"
