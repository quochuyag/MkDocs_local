#!/usr/bin/env bash
# 05-cluster-bootstrap.sh — Tạo InnoDB Cluster trên node1, add node2 + node3 via Clone Plugin.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-cluster-bootstrap.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

# ADMIN_PWD chứa '#' (fragment delim) → URL-encode cho mysqlsh URI (xem env.sh::urlenc).
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> Trigger cluster-bootstrap trên node1 (tạo cluster + add 2 node — clone có thể mất 1-3 phút)"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/innodb-cluster/cluster-bootstrap.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 5s cho recovery threads ổn định"
sleep 5

log "==> Verify cluster.status()"
vagrant ssh node1 -c "
  mysqlsh --uri='${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}' \
    -e \"print(JSON.stringify(dba.getCluster('${CLUSTER_NAME}').status(),null,2));\"
" 2>&1 | tee -a "${LOG}"

log "==> Poll trạng thái cho đến khi 3 member ONLINE (timeout 180s, 1 SSH session)"
# Đẩy poll vào trong VM để tránh 180 SSH handshakes; chỉ in dòng STATUS=... cuối cùng ra stdout.
POLL_OUT=$(vagrant ssh node1 -c "
  cnt=0
  for i in \$(seq 1 90); do
    cnt=\$(mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e \"
      SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE='ONLINE';\" 2>/dev/null | tr -d '\r')
    if [ \"\${cnt}\" = '3' ]; then
      echo \"STATUS=ONLINE3 ELAPSED=\$((i*2))s\"
      exit 0
    fi
    if [ \$((i % 5)) -eq 0 ]; then echo \"    progress: \${cnt}/3 ONLINE (\$((i*2))s)\"; fi
    sleep 2
  done
  echo \"STATUS=TIMEOUT COUNT=\${cnt}\"
" 2>&1 | tr -d '\r')
echo "${POLL_OUT}" | tee -a "${LOG}" >/dev/null
ONLINE_COUNT=$(echo "${POLL_OUT}" | sed -n 's/.*STATUS=ONLINE3.*/3/p; s/.*STATUS=TIMEOUT COUNT=\([0-9]*\).*/\1/p' | tail -n1)
ONLINE_COUNT="${ONLINE_COUNT:-0}"

if [[ "${ONLINE_COUNT}" == "3" ]]; then
  log "    Tất cả 3 member ONLINE: $(echo "${POLL_OUT}" | grep -o 'ELAPSED=[^ ]*')"
else
  log "[WARN] Sau 180s vẫn không đủ 3 ONLINE — chỉ ${ONLINE_COUNT}/3"
  log "       Kiểm tra: vagrant ssh node1 -c \"mysqlsh ... -e 'dba.getCluster().status()'\""
fi

log "==> Members info (final)"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
    FROM performance_schema.replication_group_members;\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 5 hoàn tất. Tiếp theo: bash demo/02-innodb-cluster/06-router-setup.sh"
