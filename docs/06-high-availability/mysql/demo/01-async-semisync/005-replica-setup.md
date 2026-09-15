---
title: Bước 5 — Bật Semi-Sync Replica trên node2, node3
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/05-replica-setup.md
---

# Bước 5 — Bật Semi-Sync Replica trên node2, node3

## Mục tiêu
Trên node2 và node3: cài plugin `rpl_semi_sync_replica`, point replication về node1 với GTID auto-position, set `super_read_only=ON`.

## Cách chạy

```bash
bash demo/01-async-semisync/05-replica-setup.sh
```

## Diễn giải

Script chạy [scripts/async-semisync/replica-setup.sh](../../scripts/async-semisync/replica-setup.sh) trên node2/node3. Các hành động trên mỗi replica:

1. `INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so';`
2. `SET GLOBAL rpl_semi_sync_replica_enabled = 1;`
3. `STOP REPLICA; RESET REPLICA ALL;` — clear state cũ (nếu có).
4. `CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;`
5. `START REPLICA;`
6. `SET GLOBAL read_only=ON; SET GLOBAL super_read_only=ON;` — chống ghi nhầm.

> **Vì sao `SOURCE_AUTO_POSITION=1`?** Với GTID, replica tự yêu cầu các GTID còn thiếu từ master, không cần biết file/pos cụ thể. Đây là điều kiện tiên quyết để failover dễ dàng.

## Verify

```bash
# Trên mỗi replica
for N in node2 node3; do
  echo "--- $N ---"
  vagrant ssh "$N" -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SHOW REPLICA STATUS\G\" | egrep \
    'Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_IO_Error|Last_SQL_Error|Auto_Position'"
done

# Trên master — kiểm tra đã có 2 clients
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  SHOW STATUS LIKE 'Rpl_semi_sync_source%';\""
```

Kết quả mong đợi:
```
# node2 / node3:
Source_Host: node1
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Seconds_Behind_Source: 0
Auto_Position: 1
Last_IO_Error:
Last_SQL_Error:

# node1:
Rpl_semi_sync_source_status   | ON
Rpl_semi_sync_source_clients  | 2
Rpl_semi_sync_source_yes_tx   | 0  (chưa có ghi gì sau khi bật)
Rpl_semi_sync_source_no_tx    | 0
```

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `Last_IO_Error: Authentication plugin 'caching_sha2_password' reported error` | Đảm bảo user `repl` tạo với `mysql_native_password` (đã có trong master-setup) HOẶC dùng `GET_SOURCE_PUBLIC_KEY=1` (đã set). |
| `Last_IO_Error: error connecting to source 'repl@node1'... Errno=2002 Connection refused` | `vagrant ssh node1 -c "sudo ss -tlnp \| grep 3306"` — đảm bảo MySQL listen 0.0.0.0; `sudo ufw status` mở port. |
| `Replica_SQL_Running: No`, `Last_SQL_Error: ... GTID consistency` | `STOP REPLICA; SET GTID_NEXT='<uuid:N>'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC'; START REPLICA;` — skip transaction lỗi (xem runbook 01 §4.2). |
| `Seconds_Behind_Source: NULL` | IO thread fail; xem `Last_IO_Error`. |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/05-replica-setup.md`
