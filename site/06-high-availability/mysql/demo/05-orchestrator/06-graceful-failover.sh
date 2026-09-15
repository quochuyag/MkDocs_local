#!/usr/bin/env bash
# 06-graceful-failover.sh — Planned switchover qua API Orchestrator (không destroy VM).
# Mặc định: promote node2 thành master. Đổi qua env: NEW_MASTER_IP=192.168.10.13
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-graceful-failover.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

NEW_MASTER_IP="${NEW_MASTER_IP:-${NODE2_IP}}"
NEW_MASTER_HOST=""
case "${NEW_MASTER_IP}" in
  "${NODE1_IP}") NEW_MASTER_HOST="node1" ;;
  "${NODE2_IP}") NEW_MASTER_HOST="node2" ;;
  "${NODE3_IP}") NEW_MASTER_HOST="node3" ;;
  *) log "[FAIL] NEW_MASTER_IP không hợp lệ: ${NEW_MASTER_IP}"; exit 1 ;;
esac

log "================ GRACEFUL SWITCHOVER ================"
log "==> Target master mới: ${NEW_MASTER_HOST} (${NEW_MASTER_IP})"

# 1 — Current master
OLD_MASTER=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NODE1_IP}:${MYSQL_PORT} 2>/dev/null" | tr -d '\r' | tail -n1)
log "    current master: ${OLD_MASTER}"

# 2 — graceful-master-takeover
# LƯU Ý: dùng `-i <clusterHint>` thay vì `-alias ${CLUSTER_NAME}` — alias myCluster
# không set trong DetectClusterAliasQuery → orchestrator báo "Unable to determine
# cluster name. clusterHint=myCluster". `-i` accept bất kỳ instance của cluster.
log "==> Gọi graceful-master-takeover -i ${OLD_MASTER} -d ${NEW_MASTER_IP}:${MYSQL_PORT}"
START=$(date +%s)
OUT=$(vagrant ssh mgmt -c "orchestrator-client -c graceful-master-takeover -i ${OLD_MASTER} -d ${NEW_MASTER_IP}:${MYSQL_PORT} 2>&1" || true)
echo "${OUT}" | tee -a "${LOG}"
DUR=$(( $(date +%s) - START ))
log "    graceful-master-takeover xong sau ${DUR}s"

# 3 — Verify master mới
sleep 3
NEW=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NEW_MASTER_IP}:${MYSQL_PORT} 2>/dev/null" | tr -d '\r' | tail -n1)
log "    sau switchover: which-master = ${NEW}"
if echo "${NEW}" | grep -q "${NEW_MASTER_IP}"; then
  log "[OK] Master mới = ${NEW_MASTER_IP}"
else
  log "[FAIL] Master mới chưa đổi như mong đợi"
  exit 1
fi

# 4 — Test ghi vào master mới
log "==> Test INSERT vào master mới ${NEW_MASTER_HOST}"
vagrant ssh "${NEW_MASTER_HOST}" -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    USE smoke_db;
    INSERT INTO t(val) VALUES('post-graceful-switchover');
    SELECT @@hostname AS now_master, @@read_only;\"
" 2>&1 | tee -a "${LOG}"

# 5 — Topology mới
log "==> Topology sau switchover"
vagrant ssh mgmt -c "orchestrator-client -c topology -i ${NEW_MASTER_IP}:${MYSQL_PORT}" 2>&1 | tee -a "${LOG}"

log "==> Bước 6 hoàn tất. Để rollback master về node1: NEW_MASTER_IP=${NODE1_IP} bash 06-graceful-failover.sh"
