---
title: Bước 3 — Cài MySQL 8.0 + Shell + Router trên 3 DB nodes
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/03-install-mysql.md
---

# Bước 3 — Cài MySQL 8.0 + Shell + Router trên 3 DB nodes

## Mục tiêu
- Cài `mysql-server`, `mysql-shell`, `mysql-router` từ APT repo chính chủ Oracle.
- Áp config baseline cho replication: `server_id`, `gtid_mode=ON`, `log_bin`, `binlog_format=ROW`, `enforce_gtid_consistency=ON`, `log_slave_updates=ON`, `report_host=<hostname>`.
- Mở firewall các cổng `3306, 33060, 33061, 6446, 6447, 6032, 6033, 4444, 4567, 4568`.

> Bước này dùng chung [scripts/common/01-install-mysql.sh](../../scripts/common/01-install-mysql.sh) với demo 01. Lưu ý: package `mysql-shell` và `mysql-router` cũng được cài sẵn → không cần bước cài bổ sung cho InnoDB Cluster.

## Cách chạy

```bash
bash demo/02-innodb-cluster/03-install-mysql.sh
```

## Diễn giải

Gọi `vagrant provision install-mysql` trên `node1/2/3` (mgmt skip — sẽ cài riêng Router ở B6). Script:

1. Tải `mysql-apt-config_0.8.29-1_all.deb` (mặc định MySQL 8.0).
2. `debconf-set-selections` cài silent với `root` password = `$MYSQL_ROOT_PWD` (`ChangeMe!Root#2026`).
3. Map hostname → `server_id`: node1=1, node2=2, node3=3.
4. Sinh config `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf` baseline cho GR:
   - `enforce_gtid_consistency = ON` — bắt buộc với GR.
   - `report_host = <hostname>` — GR dùng để identify member; nếu không set, member nhìn nhau qua IP của eth0 (NAT) → lỗi.
5. Restart MySQL.

> **Khác biệt quan trọng với demo 01**: ở demo 01 chúng ta chỉ cần `gtid_mode=ON`. Với InnoDB Cluster còn cần `enforce_gtid_consistency=ON` + `report_host` đúng — `01-install-mysql.sh` đã set sẵn.

## Verify

```bash
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh "$N" -c "sudo systemctl is-active mysql && \
    mysql -uroot -p'ChangeMe!Root#2026' -e \"
      SELECT @@hostname,@@server_id,@@gtid_mode,@@enforce_gtid_consistency,@@binlog_format,@@report_host;
      SELECT plugin_name,plugin_status FROM information_schema.plugins WHERE plugin_name='clone';\"
  echo 'mysqlsh:';     command -v mysqlsh && mysqlsh --version
  echo 'mysqlrouter:'; command -v mysqlrouter && mysqlrouter --version"
done
```

Kỳ vọng:
```
hostname=node1  server_id=1  gtid_mode=ON  enforce_gtid_consistency=ON  binlog_format=ROW  report_host=node1
clone | ACTIVE
mysqlsh    Ver 8.0.x for Linux on x86_64 - for MySQL 8.0.x
mysqlrouter Ver 8.0.x for Linux on x86_64
```

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `mysql-apt-config` ko cài được (404) | Sửa URL .deb mới trong [01-install-mysql.sh](../../scripts/common/01-install-mysql.sh) |
| `Plugin 'clone' not loaded` | MySQL < 8.0.17 → upgrade. `INSTALL PLUGIN clone SONAME 'mysql_clone.so';` |
| `report_host` rỗng | Re-edit `zz-mysql-ha.cnf`, restart MySQL. GR sẽ phàn nàn ở B4 nếu thiếu. |
| `Job for mysql.service failed` | `vagrant ssh nodeX -c "sudo journalctl -u mysql -n100"` |

## Lưu ý bảo mật

Giống demo 01: password `env.sh` chỉ phù hợp lab. Production phải đổi và quản lý qua secret manager.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/03-install-mysql.md`
