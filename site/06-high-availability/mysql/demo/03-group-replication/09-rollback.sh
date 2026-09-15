#!/usr/bin/env bash
# 09-rollback.sh — Tháo Group Replication. MODE=soft|hard (default: soft).
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
  log "==> Hoàn tất hard rollback."
  exit 0
fi

log "==> SOFT rollback: STOP GROUP_REPLICATION + xoá config + drop smoke_db"

for N in node1 node2 node3; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" != "running" ]] && { log "    skip ${N} (state=${STATE})"; continue; }
  log "--- ${N}: stop GR + drop smoke_db + xoá config ---"
  vagrant ssh "${N}" -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
      STOP GROUP_REPLICATION;
      RESET REPLICA ALL FOR CHANNEL 'group_replication_recovery';
      DROP DATABASE IF EXISTS smoke_db;
      SET GLOBAL super_read_only=0;
      SET GLOBAL read_only=0;
    \" 2>/dev/null || true
    sudo rm -f /etc/mysql/mysql.conf.d/zz-group-replication.cnf /etc/my.cnf.d/zz-group-replication.cnf
    sudo systemctl restart mysql 2>/dev/null || sudo systemctl restart mysqld 2>/dev/null || true
  " 2>&1 | tee -a "${LOG}"
done

log "==> Soft rollback xong."
log "    Để demo lại từ B4: bash demo/03-group-replication/04-primary-setup.sh"
log "    Để hard rollback (destroy VMs): MODE=hard bash demo/03-group-replication/09-rollback.sh"
