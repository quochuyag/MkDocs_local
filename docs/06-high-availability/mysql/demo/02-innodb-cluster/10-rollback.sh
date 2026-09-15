#!/usr/bin/env bash
# 10-rollback.sh — Tháo InnoDB Cluster. MODE=soft|hard (default: soft).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/10-rollback.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

# ADMIN_PWD chứa '#' (fragment delim) → URL-encode cho mysqlsh URI (xem env.sh::urlenc).
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

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

log "==> SOFT rollback: tháo cluster, giữ VMs"

# 1 — Stop + disable + clean mysqlrouter trên mgmt
log "--- mgmt: stop + clean mysqlrouter ---"
vagrant ssh mgmt -c "
  sudo systemctl stop mysqlrouter 2>/dev/null || true
  sudo systemctl disable mysqlrouter 2>/dev/null || true
  sudo rm -rf /var/lib/mysqlrouter /etc/systemd/system/mysqlrouter.service
  sudo systemctl daemon-reload || true
  echo '    mysqlrouter cleaned'
" 2>&1 | tee -a "${LOG}" || log "[WARN] mgmt unreachable; bỏ qua"

# 2 — Tìm 1 ONLINE node để dissolve (PRIMARY ưu tiên)
ALIVE_NODE=""
for N in node1 node2 node3; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null \
    | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  if [[ "$STATE" == "running" ]]; then
    ALIVE_NODE="$N"
    break
  fi
done

if [[ -z "${ALIVE_NODE}" ]]; then
  log "[WARN] Không có node nào running — không thể dissolve qua mysqlsh."
  log "       Chạy 'vagrant up node1' rồi rerun, hoặc dùng MODE=hard."
else
  log "--- ${ALIVE_NODE}: dba.getCluster().dissolve({force:true}) ---"
  vagrant ssh "${ALIVE_NODE}" -c "
    mysqlsh --uri='${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}' \
      -e \"try { dba.getCluster('${CLUSTER_NAME}').dissolve({force:true}); print('Dissolved'); } catch(e) { print('Dissolve warning: '+e.message); try { dba.dropMetadataSchema({force:true, clearReadOnly:true}); print('Metadata dropped'); } catch(e2){ print('drop meta: '+e2.message); } }\" 2>&1
  " 2>&1 | tee -a "${LOG}" || log "[WARN] dissolve raised — có thể đã dissolve trước đó"
fi

# 3 — STOP GROUP_REPLICATION + drop smoke_db trên các node còn sống (safety net)
for N in node1 node2 node3; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null \
    | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" != "running" ]] && { log "    skip ${N} (state=${STATE})"; continue; }
  log "--- ${N}: stop GR + drop smoke_db ---"
  vagrant ssh "${N}" -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
      STOP GROUP_REPLICATION;
      DROP DATABASE IF EXISTS smoke_db;
      SET GLOBAL super_read_only=0;
      SET GLOBAL read_only=0;
    \" 2>/dev/null || true
  " 2>&1 | tee -a "${LOG}"
done

log "==> Soft rollback xong."
log "    Để demo lại từ B5: bash demo/02-innodb-cluster/05-cluster-bootstrap.sh"
log "    Để cài lại Router:  bash demo/02-innodb-cluster/06-router-setup.sh"
