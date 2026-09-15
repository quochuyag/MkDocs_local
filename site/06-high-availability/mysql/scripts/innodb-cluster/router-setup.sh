#!/usr/bin/env bash
# router-setup.sh — chạy trên host muốn expose endpoint cho app (thường là mgmt hoặc app server).
# Router sẽ tự sinh config, listen 6446 (RW) và 6447 (RO).
set -euo pipefail
source "$(dirname "$0")/../common/env.sh"
require_root

RUNTIME_DIR=/var/lib/mysqlrouter

# Đảm bảo user mysqlrouter tồn tại (package install thường đã tạo)
id mysqlrouter >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin mysqlrouter

# Package install nạp /etc/apparmor.d/usr.bin.mysqlrouter ngay cả khi systemd apparmor
# service đã disable từ prepare-os → kernel vẫn enforce, chặn tạo /var/lib/mysqlrouter
# ("Cannot create directory ... AppArmor settings"). Unload profile.
if [[ -f /etc/apparmor.d/usr.bin.mysqlrouter ]] && command -v apparmor_parser >/dev/null; then
  log "==> Unload AppArmor profile cho mysqlrouter"
  apparmor_parser -R /etc/apparmor.d/usr.bin.mysqlrouter 2>/dev/null || true
  # Symlink vào disable/ để không nạp lại khi reboot
  mkdir -p /etc/apparmor.d/disable
  ln -sf /etc/apparmor.d/usr.bin.mysqlrouter /etc/apparmor.d/disable/usr.bin.mysqlrouter
fi

# `mysqlrouter --bootstrap --user mysqlrouter --directory <dir>` báo
# "Can't set ownership of file '/var/lib/mysqlrouter' to the user 'mysqlrouter'"
# khi dir đã tồn tại (package install pre-tạo). Xoá để bootstrap tự tạo fresh.
log "==> Dọn ${RUNTIME_DIR} cũ (để bootstrap tạo fresh với owner đúng)"
rm -rf "${RUNTIME_DIR}"

# Password chứa '#' → URL-encode cho URI bootstrap (xem env.sh::urlenc)
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

log "==> Bootstrap MySQL Router từ cluster ${CLUSTER_NAME}"
mysqlrouter --bootstrap "${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:${MYSQL_PORT}" \
            --directory "$RUNTIME_DIR" \
            --conf-use-sockets \
            --conf-bind-address 0.0.0.0 \
            --user mysqlrouter \
            --force

log "==> Tắt SysV init.d mysqlrouter (do package install kích hoạt) — sẽ thay bằng systemd unit"
# Package mysql-router ship /etc/init.d/mysqlrouter → systemd-sysv-generator có thể
# launch SẴN với /etc/mysqlrouter/mysqlrouter.conf (không có cluster info). Disable & stop.
systemctl stop  mysqlrouter 2>/dev/null || true
systemctl disable mysqlrouter 2>/dev/null || true
# Disable SysV via update-rc.d (idempotent)
command -v update-rc.d >/dev/null && update-rc.d -f mysqlrouter disable 2>/dev/null || true
# Kill bất kỳ mysqlrouter còn sót (chạy với /etc/mysqlrouter/mysqlrouter.conf)
pkill -f "mysqlrouter -c /etc/mysqlrouter" 2>/dev/null || true

log "==> Cài systemd unit"
# ExecStart phải foreground (không qua /var/lib/mysqlrouter/start.sh — start.sh fork
# mysqlrouter rồi exit → Type=simple coi service đã chết, status=inactive).
cat >/etc/systemd/system/mysqlrouter.service <<EOF
[Unit]
Description=MySQL Router (InnoDB Cluster bootstrap)
After=network.target

[Service]
Type=simple
User=mysqlrouter
ExecStart=/usr/bin/mysqlrouter -c ${RUNTIME_DIR}/mysqlrouter.conf
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now mysqlrouter

sleep 3
ss -tlnp | egrep "${ROUTER_RW_PORT}|${ROUTER_RO_PORT}" || true

log "==> Router ready:"
log "    Read-Write  endpoint: $(hostname -I | awk '{print $1}'):${ROUTER_RW_PORT}"
log "    Read-Only   endpoint: $(hostname -I | awk '{print $1}'):${ROUTER_RO_PORT}"
log "    Test: mysql -u${APP_USER} -p${APP_PWD} -h$(hostname -I|awk '{print $1}') -P${ROUTER_RW_PORT}"
