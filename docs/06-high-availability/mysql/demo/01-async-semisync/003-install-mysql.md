---
title: Bước 3 — Cài MySQL 8.0 + firewall trên 3 DB nodes
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/03-install-mysql.md
---

# Bước 3 — Cài MySQL 8.0 + firewall trên 3 DB nodes

## Mục tiêu
- Cài `mysql-server`, `mysql-shell`, `mysql-router` từ APT repo chính chủ Oracle.
- Áp config baseline cho replication: `server_id`, `gtid_mode=ON`, `log_bin`, `binlog_format=ROW`, `enforce_gtid_consistency=ON`, `log_slave_updates=ON`.
- Mở firewall các cổng `3306, 33060, 33061, 6446, 6447, 6032, 6033, 4444, 4567, 4568`.

## Cách chạy

```bash
bash demo/01-async-semisync/03-install-mysql.sh
```

## Diễn giải

Gọi [scripts/common/01-install-mysql.sh](../../scripts/common/01-install-mysql.sh) qua `vagrant provision install-mysql` trên `node1/2/3` (mgmt skip). Script:

1. Tải `mysql-apt-config_0.8.29-1_all.deb` (mặc định MySQL 8.0).
2. Dùng `debconf-set-selections` để cài silent với `root` password = `$MYSQL_ROOT_PWD` từ env.sh (`ChangeMe!Root#2026` — đổi cho production).
3. Map hostname → `server_id`: node1=1, node2=2, node3=3.
4. Sinh config `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf` với baseline replication.
5. Restart MySQL, in version + server_id + gtid_mode.
6. Tiếp theo gọi `02-firewall.sh` để mở ports trên UFW.

## Verify

```bash
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh "$N" -c "sudo systemctl is-active mysql && \
    mysql -uroot -p'ChangeMe!Root#2026' -e \"SELECT @@hostname,@@server_id,@@gtid_mode,@@log_bin,@@binlog_format,@@enforce_gtid_consistency;\""
done
```

Kết quả mong đợi:
```
active
+-----------+-------------+-------------+----------+----------------+---------------------------+
|@@hostname |@@server_id  |@@gtid_mode  |@@log_bin |@@binlog_format |@@enforce_gtid_consistency |
|node1      |1            |ON           |1         |ROW             |1                          |
+-----------+-------------+-------------+----------+----------------+---------------------------+
```

Và port 3306 listen `0.0.0.0`:
```bash
vagrant ssh node1 -c "sudo ss -tlnp | grep 3306"
# tcp LISTEN 0 151 0.0.0.0:3306 ...
```

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `mysql-apt-config` ko cài được (404) | Sửa URL .deb mới trong [01-install-mysql.sh](../../scripts/common/01-install-mysql.sh) |
| `error: Job for mysql.service failed` | `vagrant ssh nodeX -c "sudo journalctl -u mysql -n100"` — thường do AppArmor (bước 2 đã tắt) |
| `Plugin failed to load 'mysql_native_password'` | MySQL ≥ 8.0.34 deprecated; vẫn còn `default_authentication_plugin = mysql_native_password` trong cnf → OK |
| `Access denied for 'root'@'localhost'` | Kiểm tra `$MYSQL_ROOT_PWD` trong `env.sh` khớp với cnf đã set |

## Lưu ý bảo mật

- Password mặc định trong [env.sh](../../scripts/common/env.sh) chỉ phù hợp lab. Production phải đổi và quản lý qua secret manager.
- `bind-address=0.0.0.0` cho replication. Production: cân nhắc TLS bắt buộc + ACL theo subnet.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/03-install-mysql.md`
