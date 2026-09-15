#!/usr/bin/env bash
# 09-rollback.sh — Tháo replication. MODE=soft|hard (default: soft).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/09-rollback.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

MODE="${MODE:-soft}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

if [[ "${MODE}" == "hard" ]]; then
  log "==> HARD rollback: destroy toàn bộ VMs"
  vagrant destroy -f 2>&1 | tee -a "${LOG}"
  rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
  log "==> Hoàn tất hard rollback. Logs vẫn còn ở ${RESULTS}/"
  exit 0
fi

log "==> SOFT rollback: tháo replication, giữ VMs"

# Replicas trước
for N in node2 node3; do
  log "--- ${N} ---"
  vagrant ssh "${N}" -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
      STOP REPLICA;
      RESET REPLICA ALL;
      SET GLOBAL super_read_only=0;
      SET GLOBAL read_only=0;
      UNINSTALL PLUGIN rpl_semi_sync_replica;\" 2>/dev/null || true
    sudo rm -f /etc/mysql/mysql.conf.d/zz-semisync.cnf
  " 2>&1 | tee -a "${LOG}"
done

# Master (nếu vẫn up)
log "--- node1 ---"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SET GLOBAL rpl_semi_sync_source_enabled=0;
    UNINSTALL PLUGIN rpl_semi_sync_source;
    DROP DATABASE IF EXISTS smoke_db;
    RESET MASTER;\" 2>/dev/null || true
  sudo rm -f /etc/mysql/mysql.conf.d/zz-semisync.cnf
" 2>&1 | tee -a "${LOG}" || log "[WARN] node1 unreachable (đã halt cho failover demo?). Bỏ qua, chạy 'vagrant up node1' để hoàn thiện rollback."

log "==> Soft rollback xong. Để demo lại từ bước 4: bash 04-master-setup.sh"
