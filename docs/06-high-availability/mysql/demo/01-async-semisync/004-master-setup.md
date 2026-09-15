---
title: Bước 4 — Bật Semi-Sync Source trên node1 (master)
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/04-master-setup.md
---

# Bước 4 — Bật Semi-Sync Source trên node1 (master)

## Mục tiêu
Trên node1: bật plugin `rpl_semi_sync_source`, tạo user `repl`, ghi config bền vững.

## Cách chạy

```bash
bash demo/01-async-semisync/04-master-setup.sh
```

## Diễn giải

Script chạy [scripts/async-semisync/master-setup.sh](../../scripts/async-semisync/master-setup.sh) **bên trong node1** qua `vagrant ssh`. Các hành động:

1. `INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so';` — load plugin runtime.
2. `SET GLOBAL rpl_semi_sync_source_enabled = 1;` — bật semi-sync ngay.
3. `SET GLOBAL rpl_semi_sync_source_timeout = 10000;` — chờ ack 10s rồi fallback async.
4. Ghi `/etc/mysql/mysql.conf.d/zz-semisync.cnf` để bền vững sau restart:
   ```ini
   [mysqld]
   plugin_load_add                = "semisync_source.so;semisync_replica.so"
   rpl_semi_sync_source_enabled   = 1
   rpl_semi_sync_source_timeout   = 10000
   rpl_semi_sync_replica_enabled  = 1
   ```
5. `CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY '...';`
6. `GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'%';`
7. Hiển thị `SHOW MASTER STATUS\G` + `gtid_executed`.

> **Vì sao `mysql_native_password`?** Để `SOURCE_AUTO_POSITION=1` không cần lo `caching_sha2_password` + RSA public key transfer trong giai đoạn đầu. Production khuyến nghị TLS bắt buộc với `caching_sha2_password`.

## Verify

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  SHOW PLUGINS;
  SHOW VARIABLES LIKE 'rpl_semi_sync_source%';
  SHOW STATUS  LIKE 'Rpl_semi_sync_source%';
  SELECT user,host,plugin FROM mysql.user WHERE user='repl';\""
```

Kết quả mong đợi (master ngay sau setup, chưa có replica):
```
rpl_semi_sync_source        | ACTIVE
rpl_semi_sync_source_enabled | ON
rpl_semi_sync_source_timeout | 10000
Rpl_semi_sync_source_clients | 0          <- 0 vì chưa có replica
Rpl_semi_sync_source_status  | OFF        <- OFF khi 0 client
user=repl, host=%, plugin=mysql_native_password
```

`status=OFF` ở giai đoạn này là **bình thường** — sẽ chuyển `ON` ngay khi replica đầu tiên connect ở bước 5.

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `ERROR 1126 Can't open shared library 'semisync_source.so'` | MySQL < 8.0.26 dùng tên cũ `semisync_master.so`. Repo này nhắm 8.0.30+ |
| `Duplicate entry 'repl'@'%' for key 'PRIMARY'` | Đã có user — script dùng `IF NOT EXISTS` nên bỏ qua. |
| `Access denied with --connect-expired-password` | `mysql_secure_installation` hoặc xem `~/.mysql_history` trên node1 |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/04-master-setup.md`
