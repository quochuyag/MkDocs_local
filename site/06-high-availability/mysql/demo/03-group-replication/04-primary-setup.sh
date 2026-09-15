#!/usr/bin/env bash
# 04-primary-setup.sh — Bootstrap Group Replication trên node1.
# Gọi upstream scripts/group-replication/primary-setup.sh:
#   - Ghi /etc/mysql/mysql.conf.d/zz-group-replication.cnf
#   - Restart MySQL
#   - Tạo user repl@% với mysql_native_password
#   - CHANGE REPLICATION SOURCE ... FOR CHANNEL 'group_replication_recovery'
#   - SET group_replication_bootstrap_group=ON; START GROUP_REPLICATION; (sau đó OFF)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-primary-setup.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> Bootstrap Group Replication trên node1 (chỉ chạy 1 lần)"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/group-replication/primary-setup.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 5s cho GR coordinator ổn định"
sleep 5

log "==> Verify node1 đã là PRIMARY và ở trạng thái ONLINE"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
    FROM performance_schema.replication_group_members;\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 4 hoàn tất. Tiếp theo: bash demo/03-group-replication/05-secondary-setup.sh"
