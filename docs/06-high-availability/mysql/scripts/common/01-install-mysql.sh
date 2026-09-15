#!/usr/bin/env bash
# 01-install-mysql.sh — cài MySQL 8.0 community trên Ubuntu/Debian hoặc RHEL family.
# Sau khi xong: dịch vụ đang chạy, root password = $MYSQL_ROOT_PWD, listen 0.0.0.0:3306.
#
# Profile:
#   INSTALL_PROFILE=server     (default) — cài mysql-server + shell + router, config GR-ready
#   INSTALL_PROFILE=tools-only            — chỉ mysql-shell + mysql-router (cho mgmt host)
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_root

INSTALL_PROFILE="${INSTALL_PROFILE:-server}"

# --- Idempotency: skip nếu node này đã có MySQL chạy + root auth OK -------------
if [[ "${INSTALL_PROFILE}" == "server" ]] && \
   (systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null) && \
   mysql -uroot -p"${MYSQL_ROOT_PWD}" -e "SELECT 1" >/dev/null 2>&1; then
  log "==> MySQL đã cài & root auth OK trên $(hostname) → SKIP toàn bộ"
  mysql -uroot -p"${MYSQL_ROOT_PWD}" -e "SELECT VERSION(), @@server_id, @@gtid_mode;"
  exit 0
fi
# Tools-only idempotency: cần cả 3 — mysqlrouter, mysqlsh, mysql CLI
if [[ "${INSTALL_PROFILE}" == "tools-only" ]] && \
   command -v mysqlrouter >/dev/null && command -v mysqlsh >/dev/null && command -v mysql >/dev/null; then
  log "==> mysql-shell + mysql-router + mysql-client đã cài trên $(hostname) → SKIP"
  exit 0
fi

if command -v apt-get >/dev/null; then
  log "==> Cài MySQL 8.0 trên Debian/Ubuntu"
  DEBIAN_FRONTEND=noninteractive apt-get update
  apt-get install -y wget lsb-release gnupg ca-certificates dirmngr

  # --- Workaround: GPG key MySQL repo (A8D3785C) đã expire ---------------------
  # Triệu chứng: `apt-get update` báo `EXPKEYSIG B7B3B788A8D3785C ... is not signed`.
  # Mọi mysql-apt-config (kể cả 0.8.33-1) đều ship cùng key này; cần REFRESH metadata
  # expiration từ keyserver. Chiến lược 4 lớp, fail-soft:
  #   (1) Cài mysql-apt-config 0.8.33-1, pre-seed mysql-8.0 (đề phòng default đã đổi).
  #   (2) Refresh expiration của key đã có sẵn trong /etc/apt/trusted.gpg.d/mysql.gpg
  #       (thử nhiều keyserver, ưu tiên HTTPS vì hkp:80 thường bị firewall NAT chặn).
  #   (3) Probe `apt-get update` — nếu còn EXPKEYSIG, fallback [trusted=yes] cho LAB.
  #   (4) Cài MySQL 8.0 server/shell/router.

  # Dọn state hỏng từ lần trước (mysql.list cũ trỏ về key expired)
  rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/sources.list.d/mysql.list.distUpgrade

  # Pre-seed debconf — buộc 0.8.33+ chọn MySQL 8.0 (default mới có thể là 8.4-lts/innovation)
  debconf-set-selections <<'EOF'
mysql-apt-config mysql-apt-config/select-server  select mysql-8.0
mysql-apt-config mysql-apt-config/select-product select Ok
mysql-apt-config mysql-apt-config/select-tools   select Enabled
mysql-apt-config mysql-apt-config/select-preview select Disabled
mysql-apt-config mysql-apt-config/repo-distro    select ubuntu
mysql-apt-config mysql-apt-config/repo-codename  select jammy
EOF

  MYSQL_APT_VER="0.8.33-1"
  wget -qO /tmp/mysql-apt.deb \
    "https://repo.mysql.com/mysql-apt-config_${MYSQL_APT_VER}_all.deb" || \
  wget -qO /tmp/mysql-apt.deb \
    "https://dev.mysql.com/get/mysql-apt-config_${MYSQL_APT_VER}_all.deb"
  DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt.deb || true

  # --- Đảm bảo mysql.list có ĐỦ các repo (mysql-8.0 + mysql-tools) -------------
  # Lý do: khi `dpkg -i` cài lại cùng version (0.8.33-1 over 0.8.33-1), postinst có
  # thể KHÔNG regen /etc/apt/sources.list.d/mysql.list → chỉ có mysql-8.0 (chứa
  # mysql-server) mà thiếu mysql-tools (chứa mysql-shell, mysql-router) → bước
  # `apt-get install mysql-shell` fail với "Unable to locate package mysql-shell".
  # Chiến lược: (1) force dpkg-reconfigure để regen theo debconf đã pre-seed,
  #             (2) failsafe ghi đè mysql.list nếu vẫn thiếu mysql-tools.
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive mysql-apt-config || true

  if [[ ! -f /etc/apt/sources.list.d/mysql.list ]] || \
     ! grep -qE '^deb .* mysql-tools($| )' /etc/apt/sources.list.d/mysql.list; then
    log "==> mysql.list thiếu mysql-tools repo → ghi đè thủ công"
    CODENAME=$(lsb_release -cs 2>/dev/null || echo jammy)
    cat >/etc/apt/sources.list.d/mysql.list <<EOF
deb http://repo.mysql.com/apt/ubuntu/ ${CODENAME} mysql-apt-config
deb http://repo.mysql.com/apt/ubuntu/ ${CODENAME} mysql-8.0
deb http://repo.mysql.com/apt/ubuntu/ ${CODENAME} mysql-tools
EOF
  fi
  log "==> /etc/apt/sources.list.d/mysql.list:"
  cat /etc/apt/sources.list.d/mysql.list

  # --- Refresh expiration của MySQL signing key --------------------------------
  # mysql-apt-config cài key vào /etc/apt/trusted.gpg.d/mysql.gpg với expiration cũ.
  # `gpg --refresh-keys` kéo metadata mới (gồm chữ ký gia hạn expiration) từ keyserver.
  TRUSTED_KEY=/etc/apt/trusted.gpg.d/mysql.gpg
  REFRESH_OK=0
  if [[ -f "${TRUSTED_KEY}" ]]; then
    log "==> Refresh expiration cho ${TRUSTED_KEY}"
    for KS in \
        hkps://keyserver.ubuntu.com:443 \
        hkps://keys.openpgp.org:443 \
        hkps://pgp.mit.edu:443 \
        hkp://keyserver.ubuntu.com:80; do
      if timeout 30 gpg --no-default-keyring --keyring "${TRUSTED_KEY}" \
              --keyserver "${KS}" --refresh-keys 2>/dev/null; then
        log "    refresh OK qua ${KS}"
        REFRESH_OK=1
        break
      fi
    done
    [[ "${REFRESH_OK}" == "0" ]] && log "    refresh fail trên mọi keyserver"
  fi

  # --- Probe: thử apt-get update; nếu còn lỗi key -> [trusted=yes] fallback ----
  # Lưu output ra file VÀ in ra stdout (bằng `tee` đứng cuối) để debug được khi fail.
  # `|| true` BẮT BUỘC: apt-get update trả về 100 khi GPG key expired (E: not signed).
  # Không có `|| true`, `set -o pipefail` + `set -e` sẽ kill script trước khi grep chạy
  # → fallback [trusted=yes] không bao giờ engage.
  PROBE_LOG=$(mktemp)
  apt-get update 2>&1 | tee "${PROBE_LOG}" || true
  if grep -qE 'EXPKEYSIG|NO_PUBKEY|is not signed' "${PROBE_LOG}"; then
    log "==> WARNING: key MySQL repo vẫn lỗi sau refresh → fallback [trusted=yes] (LAB ONLY)"
    if [[ -f /etc/apt/sources.list.d/mysql.list ]]; then
      # Replace bất kỳ option block hiện có (vd [signed-by=...]) bằng [trusted=yes]
      sed -i -E 's|^deb (\[[^]]+\] )?(http)|deb [trusted=yes] \2|'      /etc/apt/sources.list.d/mysql.list
      sed -i -E 's|^deb-src (\[[^]]+\] )?(http)|deb-src [trusted=yes] \2|' /etc/apt/sources.list.d/mysql.list
    fi
    apt-get update
  fi
  rm -f "${PROBE_LOG}"

  if [[ "${INSTALL_PROFILE}" == "tools-only" ]]; then
    log "==> tools-only profile: cài mysql-shell + mysql-router + mysql-community-client (bỏ qua mysql-server)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-shell mysql-router mysql-community-client
    log "==> Tools đã cài: $(mysqlsh --version 2>&1 | head -1) / $(mysqlrouter --version 2>&1 | head -1) / $(mysql --version 2>&1 | head -1)"
    exit 0
  fi

  echo "mysql-community-server mysql-community-server/root-pass password ${MYSQL_ROOT_PWD}" | debconf-set-selections
  echo "mysql-community-server mysql-community-server/re-root-pass password ${MYSQL_ROOT_PWD}" | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-shell mysql-router

elif command -v dnf >/dev/null; then
  log "==> Cài MySQL 8.0 trên RHEL/Rocky"
  dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-5.noarch.rpm || \
  dnf install -y https://dev.mysql.com/get/mysql80-community-release-el8-9.noarch.rpm
  dnf -qy module disable mysql || true
  dnf install -y mysql-community-server mysql-shell mysql-router
  systemctl enable --now mysqld
  # đổi temp password sang $MYSQL_ROOT_PWD
  TEMP_PWD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}' | tail -n1)
  mysql --connect-expired-password -uroot -p"${TEMP_PWD}" \
    -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PWD}';"
else
  echo "Distro không hỗ trợ" >&2; exit 1
fi

log "==> Cấu hình bind-address + server_id"
HOST=$(hostname)
# report_host phải là IP routable trong cluster — KHÔNG để hostname vì Ubuntu/Debian
# inject `127.0.2.1 nodeN` vào /etc/hosts (cloud-init convention); GR refuse loopback
# với "resolves to an IP address (127.0.2.1) that does not match a real network interface".
case "$HOST" in
  "${NODE1_HOST}") SID=1; REPORT_HOST="${NODE1_IP}" ;;
  "${NODE2_HOST}") SID=2; REPORT_HOST="${NODE2_IP}" ;;
  "${NODE3_HOST}") SID=3; REPORT_HOST="${NODE3_IP}" ;;
  *)               SID=$(( ( RANDOM % 1000 ) + 10 )); REPORT_HOST="$(hostname -I | awk '{print $1}')" ;;
esac

CONF=/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf
[[ -d /etc/mysql/mysql.conf.d ]] || CONF=/etc/my.cnf.d/zz-mysql-ha.cnf
mkdir -p "$(dirname "$CONF")"

cat >"$CONF" <<EOF
[mysqld]
server_id                = ${SID}
bind-address             = 0.0.0.0
mysqlx_bind_address      = 0.0.0.0
default_authentication_plugin = mysql_native_password
log_bin                  = mysql-bin
binlog_format            = ROW
binlog_expire_logs_seconds = 604800
gtid_mode                = ON
enforce_gtid_consistency = ON
log_slave_updates        = ON
relay_log                = relay-bin
relay_log_recovery       = ON
sync_binlog              = 1
innodb_flush_log_at_trx_commit = 1
report_host              = ${REPORT_HOST}
EOF

systemctl restart mysql || systemctl restart mysqld
sleep 3
mysql -uroot -p"${MYSQL_ROOT_PWD}" -e "SELECT VERSION(), @@server_id, @@gtid_mode;"
log "==> MySQL ready trên $(hostname)"
