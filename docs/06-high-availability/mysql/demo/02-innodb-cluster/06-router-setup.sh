#!/usr/bin/env bash
# 06-router-setup.sh — Cài MySQL Router trên mgmt + bootstrap từ cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-router-setup.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> [mgmt] Cài mysql-router + mysql-shell + mysql-client qua common installer (có GPG key handling)"
# Dùng scripts/common/01-install-mysql.sh với INSTALL_PROFILE=tools-only:
# - Pre-seed debconf cho mysql-apt-config 0.8.33-1 (newer than 0.8.29)
# - Refresh GPG key expiration từ keyserver (key B7B3B788A8D3785C ship cùng mysql-apt-config hay expired)
# - Fallback [trusted=yes] nếu refresh fail (LAB only)
# - Cài mysql-shell + mysql-router + mysql-community-client
vagrant ssh mgmt -c "sudo INSTALL_PROFILE=tools-only bash /vagrant/scripts/common/01-install-mysql.sh" 2>&1 | tee -a "${LOG}"

log "==> [mgmt] Verify tools versions"
vagrant ssh mgmt -c "
  mysqlrouter --version
  mysqlsh --version
  mysql --version
" 2>&1 | tee -a "${LOG}"

log "==> [mgmt] Mở firewall 6446, 6447 (idempotent) — phải allow 22/tcp TRƯỚC enable"
# Bug-fix: vagrant ssh chạy 'ufw --force enable' không pre-allow OpenSSH → các
# kết nối SSH mới (vagrant ssh -c) bị block, lần invocation kế tiếp exit 255 với
# 0 output → tee không log gì, set -o pipefail kill bước này. Allow 22 trước.
vagrant ssh mgmt -c "
  if command -v ufw >/dev/null; then
    sudo ufw allow OpenSSH || sudo ufw allow 22/tcp
    sudo ufw allow ${ROUTER_RW_PORT}/tcp || true
    sudo ufw allow ${ROUTER_RO_PORT}/tcp || true
    sudo ufw --force enable || true
  fi
" 2>&1 | tee -a "${LOG}"

log "==> [mgmt] Bootstrap MySQL Router từ cluster (chạy router-setup.sh)"
# router-setup.sh dùng env.sh đã được mount qua /vagrant
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/innodb-cluster/router-setup.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 3s cho Router warm-up + kết nối tới cluster metadata"
sleep 3

log "==> [mgmt] Verify service & listening ports"
vagrant ssh mgmt -c "
  sudo systemctl status mysqlrouter --no-pager | head -n 20 || true
  sudo ss -tlnp | egrep ':6446 |:6447 ' || true
" 2>&1 | tee -a "${LOG}"

log "==> [mgmt] Test routing :6446 (RW) — 3 lần, kỳ vọng đều ra PRIMARY"
vagrant ssh mgmt -c "
  for i in 1 2 3; do
    H=\$(mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${ROUTER_RW_PORT} -N -e 'SELECT @@hostname' 2>/dev/null || echo FAIL)
    echo \"    :${ROUTER_RW_PORT} hit #\$i -> \$H\"
  done
" 2>&1 | tee -a "${LOG}"

log "==> [mgmt] Test routing :6447 (RO) — 3 lần, kỳ vọng round-robin secondaries"
vagrant ssh mgmt -c "
  for i in 1 2 3; do
    H=\$(mysql -u${ADMIN_USER} -p'${ADMIN_PWD}' -h127.0.0.1 -P${ROUTER_RO_PORT} -N -e 'SELECT @@hostname' 2>/dev/null || echo FAIL)
    echo \"    :${ROUTER_RO_PORT} hit #\$i -> \$H\"
  done
" 2>&1 | tee -a "${LOG}"

log "==> Bước 6 hoàn tất. Tiếp theo: bash demo/02-innodb-cluster/07-verify.sh"
