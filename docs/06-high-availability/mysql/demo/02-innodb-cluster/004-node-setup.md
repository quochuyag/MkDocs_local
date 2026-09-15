---
title: Bước 4 — Configure instance trên 3 DB nodes
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/04-node-setup.md
---

# Bước 4 — Configure instance trên 3 DB nodes

## Mục tiêu
Trên `node1/2/3`: tạo user `clusteradmin` + chạy `mysqlsh dba.configureInstance(...)` để MySQL Shell tự sửa my.cnf cho Group Replication và (nếu cần) restart MySQL.

## Cách chạy

```bash
bash demo/02-innodb-cluster/04-node-setup.sh
```

## Diễn giải

Script chạy [scripts/innodb-cluster/node-setup.sh](../../scripts/innodb-cluster/node-setup.sh) **bên trong từng db node** qua `vagrant ssh`. Hành động cụ thể trên mỗi node:

1. Tạo user `clusteradmin` với mật khẩu từ `$ADMIN_PWD`:
   ```sql
   CREATE USER IF NOT EXISTS 'clusteradmin'@'%' IDENTIFIED BY '...';
   GRANT ALL PRIVILEGES ON *.* TO 'clusteradmin'@'%' WITH GRANT OPTION;
   ```
2. Chạy `mysqlsh dba.configureInstance(...)` với `clusterAdmin` option. Shell sẽ:
   - Kiểm tra GR pre-requisites (gtid, enforce_gtid_consistency, log_bin, binlog_format, log_slave_updates, …).
   - Ghi các option còn thiếu vào `mysqld-auto.cnf` qua `SET PERSIST`.
   - Bật `report_port`/`report_host` nếu thiếu.
   - **Tự restart MySQL** nếu config yêu cầu (`"restart": true`).
3. Đợi MySQL ping pong trở lại sau restart.
4. `dba.checkInstanceConfiguration(...)` — confirm instance đã ready.

### `clusteradmin` vs `root`?

Group Replication API (`dba.*`) cần một user có nhiều quyền hệ thống. Theo best practice của Oracle, **không** dùng `root` cho ops thường ngày — tách thành `clusteradmin` để:
- Có thể `revoke` khi thay đội ngũ DBA mà không đụng đến `root`.
- Audit log rõ ai làm gì.
- Set password policy/expiration riêng.

## Verify

```bash
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh "$N" -c "
    mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
      -e \"dba.checkInstanceConfiguration('clusteradmin@127.0.0.1:3306')\""
done
```

Kỳ vọng cuối output:
```
The instance '127.0.0.1:3306' is valid to be used in an InnoDB Cluster.
{
    "status": "ok"
}
```

Hoặc check qua SQL:
```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -N -e \"
  SELECT user,host FROM mysql.user WHERE user='clusteradmin';
  SELECT @@gtid_mode, @@enforce_gtid_consistency, @@log_slave_updates, @@master_info_repository;\""
```

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `RuntimeError: Loose option 'innodb_buffer_pool_size'` | Cảnh báo, không phải lỗi — Shell tự fix |
| `Instance check failed: persistent variables not supported` | MySQL ≥ 8.0 mới hỗ trợ `SET PERSIST` — kiểm tra version |
| `MySQL Error: Can't connect to MySQL on '127.0.0.1'` sau restart | Đợi thêm 5-10s; tăng vòng lặp `mysqladmin ping` trong script |
| `Public Key Retrieval is not allowed` khi mysqlsh connect | Bug 8.0.x — thêm `?get-server-public-key=true` vào URI |
| `report_host` rỗng | Sửa `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf` đảm bảo có `report_host=<hostname>`, restart |

## Idempotency

Có thể chạy lại `04-node-setup.sh` nhiều lần an toàn:
- `CREATE USER IF NOT EXISTS` không bắn lỗi nếu user đã tồn tại.
- `dba.configureInstance(...)` thấy config đã đúng → no-op (không restart).


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/04-node-setup.md`
