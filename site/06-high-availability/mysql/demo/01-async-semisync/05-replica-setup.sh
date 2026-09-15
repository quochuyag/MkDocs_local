#!/usr/bin/env bash
# 05-replica-setup.sh — Cấu hình node2,3 thành semi-sync replica của node1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-replica-setup.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

REPLICAS=(node2 node3)

for N in "${REPLICAS[@]}"; do
  log "==> replica-setup trên ${N}"
  vagrant ssh "${N}" -c "sudo bash /vagrant/scripts/async-semisync/replica-setup.sh" 2>&1 | tee -a "${LOG}"
done

log "==> Chờ 3s để replica IO/SQL thread khởi động"
sleep 3

log "==> Verify trên các replica"
for N in "${REPLICAS[@]}"; do
  log "    --- ${N} ---"
  vagrant ssh "${N}" -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"SHOW REPLICA STATUS\\G\" \
      | egrep 'Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_IO_Error|Last_SQL_Error|Auto_Position|Retrieved_Gtid_Set|Executed_Gtid_Set'
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
      SHOW STATUS LIKE 'Rpl_semi_sync_replica_status';
      SELECT @@read_only,@@super_read_only;\"
  " 2>&1 | tee -a "${LOG}"
done

log "==> Verify trên master: phải thấy 2 clients, status=ON"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SHOW STATUS LIKE 'Rpl_semi_sync_source%';
    SELECT host,event_name FROM performance_schema.replication_connection_status;\" 2>/dev/null || true
" 2>&1 | tee -a "${LOG}"

log "==> Bước 5 hoàn tất. Tiếp theo: bash demo/01-async-semisync/06-verify.sh"
