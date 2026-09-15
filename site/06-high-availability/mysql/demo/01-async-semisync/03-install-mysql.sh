#!/usr/bin/env bash
# 03-install-mysql.sh — Cài MySQL 8.0 community + firewall trên 3 DB nodes.
# Chạy trên HOST. Gọi vagrant provider 'install-mysql' đã định nghĩa trong Vagrantfile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-install-mysql.log"
mkdir -p "${RESULTS}"

# Source env.sh để dùng MYSQL_ROOT_PWD trong verify
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

DB_NODES=(node1 node2 node3)

# Idempotency: skip provision nếu node đã có MySQL chạy + root auth OK
node_already_installed() {
  local n="$1"
  vagrant ssh "$n" -c "
    (sudo systemctl is-active --quiet mysql || sudo systemctl is-active --quiet mysqld) && \
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e 'SELECT 1' >/dev/null 2>&1
  " 2>/dev/null
}

for N in "${DB_NODES[@]}"; do
  if node_already_installed "${N}"; then
    log "==> ${N}: MySQL đã cài & auth OK → SKIP provision"
    continue
  fi
  log "==> install MySQL trên ${N} (tải ~250MB, có thể mất vài phút)"
  vagrant provision "${N}" --provision-with install-mysql 2>&1 | tee -a "${LOG}"
done

log "==> Verify MySQL service & cấu hình baseline"
for N in "${DB_NODES[@]}"; do
  log "    --- ${N} ---"
  vagrant ssh "${N}" -c "
    sudo systemctl is-active mysql || sudo systemctl is-active mysqld
    sudo ss -tlnp | grep ':3306 ' || true
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e \"
      SELECT CONCAT('host=',@@hostname,
                    ' sid=',@@server_id,
                    ' gtid=',@@gtid_mode,
                    ' binlog=',@@log_bin,
                    ' fmt=',@@binlog_format,
                    ' enforce_gtid=',@@enforce_gtid_consistency);\"
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 3 hoàn tất. Tiếp theo: bash demo/01-async-semisync/04-master-setup.sh"
