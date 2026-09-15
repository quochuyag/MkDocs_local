---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp HA **Async + Semi-Synchronous Replication** cho MySQL 8.0:
1. Dựng được cụm 3 node + 1 mgmt host trong môi trường ảo hoá.
2. Đưa MySQL về trạng thái sẵn sàng replication (GTID, log_bin, server_id).
3. Cấu hình semi-sync plugin trên master và 2 replicas.
4. Chứng minh **data đồng bộ** trên cả 3 node (smoke test).
5. Chứng minh **failover thủ công** (promote replica thành master mới).

## Kiến trúc

- **Master (node1)**: nhận write, ghi binlog, phát sang replicas.
- **Semi-sync plugin**: master chờ **ít nhất 1 replica ACK** đã nhận binlog trước khi commit trả về client. Nếu không có ack trong 10s → fallback async.
- **GTID auto-position**: replicas dùng GTID set thay vì file+pos → dễ failover.
- **read_only + super_read_only**: replicas bị khoá ghi để chống nhầm.

## Phạm vi demo

| Có | Không |
|----|-------|
| Setup cluster, smoke test, manual failover | Auto failover (sẽ làm ở runbook 04/05 — MHA/Orchestrator) |
| Semi-sync plugin + GTID | Group Replication (runbook 02/03) |
| Vagrant + VirtualBox | Multi-cloud / production sizing |
| Mock data smoke test | Benchmark hiệu năng |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | 4 VM up, ping được nhau qua IP private | `vagrant status`, `ping node2` từ node1 |
| 2 | MySQL 8.0 chạy trên 3 DB nodes, port 3306 listen 0.0.0.0 | `ss -tlnp \| grep 3306` |
| 3 | `gtid_mode=ON`, `log_bin=ON`, `binlog_format=ROW` | `SELECT @@gtid_mode, @@log_bin, @@binlog_format;` |
| 4 | Master báo `Rpl_semi_sync_source_status=ON` và 2 clients | `SHOW STATUS LIKE 'Rpl_semi_sync_source%';` |
| 5 | 2 replicas: IO+SQL running = Yes, lag = 0 | `SHOW REPLICA STATUS\G` |
| 6 | INSERT trên master → SELECT trên cả 2 replica trong < 1s | smoke test |
| 7 | Sau khi `vagrant halt node1`, promote node2 thành master, node3 follow node2 | failover test |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| `vagrant up` (lần đầu, tải box) | 10–15 phút |
| Prepare OS | 2 phút |
| Install MySQL | 5–8 phút (tải gói APT) |
| Master + Replica setup | 1–2 phút |
| Verify + smoke test | 1 phút |
| Failover demo | 2 phút |
| **Tổng cộng** | **~25–30 phút** |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/00-overview.md`
