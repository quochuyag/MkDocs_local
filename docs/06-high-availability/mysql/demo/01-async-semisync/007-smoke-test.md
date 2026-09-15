---
title: 'Bước 7 — Smoke test: ghi master → đọc replicas'
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/07-smoke-test.md
---

# Bước 7 — Smoke test: ghi master → đọc replicas

## Mục tiêu
Chứng minh **data flow end-to-end** và đo độ trễ replication:
1. Tạo DB `smoke_db`, table `t(id, val, ts)` trên node1.
2. Insert N rows lên node1.
3. Trên node2 + node3: poll `SELECT COUNT(*) FROM smoke_db.t` đến khi = N hoặc timeout.
4. Đo thời gian từ insert cuối → khi cả 2 replica thấy đủ N rows.
5. Kiểm tra `Rpl_semi_sync_source_yes_tx` đã tăng = N.

## Cách chạy

```bash
bash demo/01-async-semisync/07-smoke-test.sh
# hoặc với số row tuỳ chỉnh:
ROWS=500 bash demo/01-async-semisync/07-smoke-test.sh
```

## Diễn giải

| Pha | Action | Kỳ vọng |
|-----|--------|---------|
| Setup | `CREATE DATABASE smoke_db; CREATE TABLE t(...)` trên master | Replicate xuống cả 2 replica |
| Write | Loop 200 INSERT vào master | Master commit; `yes_tx` tăng 200 |
| Read replica2 | `SELECT COUNT(*) FROM t` | Đến 200 trong < 1s |
| Read replica3 | `SELECT COUNT(*) FROM t` | Đến 200 trong < 1s |
| GTID check | So sánh `gtid_executed` 3 node | Replica = Master (sau khi sync) |

> **Vì sao đo lag bằng counter thay vì `Seconds_Behind_Source`?** Counter chính xác đến row; `Seconds_Behind_Source` chỉ chính xác đến giây và có thể NULL/0 lừa.

## Output

File [results/07-smoke-test.log](results/07-smoke-test.log) gồm:
- Time elapsed cho master insert
- Time elapsed cho mỗi replica để đạt N rows
- Counter `Rpl_semi_sync_source_yes_tx` trước/sau
- 3 GTID set (mong đợi: bằng nhau)
- Bảng kết quả `SMOKE_PASS=true/false`

## Kết quả mong đợi (lab điển hình)

```
[node1] insert 200 rows: 0.45s
[node2] saw 200 rows after: 0.18s
[node3] saw 200 rows after: 0.22s
[node1] yes_tx: 0 -> 201 (200 INSERT + 1 CREATE TABLE statements counted)
[node1] gtid_executed: <uuid>:1-XXX
[node2] gtid_executed: <uuid>:1-XXX   <- KHỚP
[node3] gtid_executed: <uuid>:1-XXX   <- KHỚP
SMOKE_PASS=true
```

## Cleanup (optional)
Smoke test KHÔNG drop database tự động — để dùng lại cho bước 8 (failover sẽ insert tiếp). Nếu muốn dọn:
```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'DROP DATABASE smoke_db;'"
```

## Lỗi thường gặp

| Hiện tượng | Nguyên nhân | Khắc phục |
|------------|-------------|-----------|
| Replica đếm dừng < N | SQL thread bị lỗi | `SHOW REPLICA STATUS\G` xem `Last_SQL_Error` |
| `yes_tx` không tăng, `no_tx` tăng | Replica disconnect, master fallback async | `vagrant ssh node1 -c "mysql -e \"SHOW PROCESSLIST\"\\G"` xem có dump thread không |
| Replica có thừa rows | Có write vào replica (sai sao đó vẫn ghi được) | Đảm bảo `super_read_only=ON` |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/07-smoke-test.md`
