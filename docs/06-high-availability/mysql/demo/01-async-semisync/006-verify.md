---
title: Bước 6 — Verify toàn cluster
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/06-verify.md
---

# Bước 6 — Verify toàn cluster

## Mục tiêu
Tổng hợp tất cả checkpoint vào 1 báo cáo `results/06-verify.log`. Đây là **"happy path verification"** chứng minh cluster đã sẵn sàng.

## Cách chạy

```bash
bash demo/01-async-semisync/06-verify.sh
```

## Checkpoints

| # | Item | Câu lệnh | Pass khi |
|---|------|----------|----------|
| 1 | Service mysql active trên node1/2/3 | `systemctl is-active mysql` | `active` |
| 2 | Port 3306 listen 0.0.0.0 | `ss -tlnp \| grep 3306` | có dòng `0.0.0.0:3306` |
| 3 | GTID, log_bin, binlog_format đúng | `SELECT @@gtid_mode,@@log_bin,@@binlog_format;` | `ON / 1 / ROW` |
| 4 | Plugin semi-sync ACTIVE | `SELECT plugin_name,plugin_status FROM IS.plugins WHERE plugin_name LIKE 'rpl_semi%';` | tất cả `ACTIVE` |
| 5 | Master: `Rpl_semi_sync_source_status=ON` | `SHOW STATUS LIKE ...;` | `ON` |
| 6 | Master: `Rpl_semi_sync_source_clients=2` | `SHOW STATUS LIKE ...;` | `2` |
| 7 | Replica IO/SQL thread running | `SHOW REPLICA STATUS\G` | cả 2 = `Yes` |
| 8 | `Seconds_Behind_Source` ≤ 1 | `SHOW REPLICA STATUS\G` | `0` hoặc `1` |
| 9 | `Last_IO_Error` & `Last_SQL_Error` rỗng | `SHOW REPLICA STATUS\G` | rỗng |
| 10 | Replica có `super_read_only=1` | `SELECT @@super_read_only;` | `1` |

## Output

Toàn bộ output lưu tại [results/06-verify.log](results/06-verify.log) — gồm các block cho từng node với prefix `[node1]`, `[node2]`, `[node3]`. Cuối log có dòng `VERIFY_PASS=true/false` dùng để gating bước sau.

## Đọc kết quả

- Nếu thấy `VERIFY_PASS=true` ở cuối log → an toàn chạy [07-smoke-test.sh](07-smoke-test.sh).
- Nếu `false` → grep log tìm dòng `[FAIL]` để xác định checkpoint nào fail.

## Lưu ý

Script này read-only — không thay đổi state DB. An toàn rerun nhiều lần để theo dõi liên tục.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/06-verify.md`
