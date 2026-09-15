#!/usr/bin/env bash
# 05-secondary-setup.sh — Join node2 và node3 vào group đã bootstrap.
# Gọi upstream scripts/group-replication/secondary-setup.sh trên từng node.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-secondary-setup.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

for N in node2 node3; do
  log "==> [${N}] join group (sẽ restart MySQL + START GROUP_REPLICATION)"
  vagrant ssh "${N}" -c "sudo bash /vagrant/scripts/group-replication/secondary-setup.sh" 2>&1 | tee -a "${LOG}"
done

log "==> Đợi recovery channel pull dữ liệu từ donor (timeout 180s, 1 SSH session)"
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
  log "       Debug: vagrant ssh node2 -c \"sudo journalctl -u mysql -n 100\""
fi

log "==> Members info (final)"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
    FROM performance_schema.replication_group_members ORDER BY MEMBER_HOST;\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 5 hoàn tất. Tiếp theo: bash demo/03-group-replication/06-verify.sh"
