---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/04-mha/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp HA **MHA (Master High Availability)** cho MySQL 8.0:
1. Cài mha4mysql-node trên 3 DB nodes, mha4mysql-manager trên mgmt host.
2. Cấu hình SSH passwordless từ mgmt → mọi DB nodes (tiền đề bắt buộc).
3. Verify topology hợp lệ qua `masterha_check_ssh` + `masterha_check_repl`.
4. Gắn VIP 192.168.10.100 lên master (node1).
5. Halt master → MHA tự failover (chọn replica mới, relay binlog còn sót, move VIP).
6. Rebuild master cũ thành replica của master mới.

## Kiến trúc

- **mha4mysql-manager (mgmt)**: Perl daemon, ping master mỗi `ping_interval=3s`, kích hoạt failover khi confirm master chết.
- **mha4mysql-node (3 DB nodes)**: chỉ là tập binary script Perl (`save_binary_logs`, `apply_diff_relay_logs`, ...) — manager SSH vào chạy.
- **master_ip_failover.sh**: hook do MHA gọi sau khi promote — dùng `ip addr add/del` để move VIP. Production nên dùng Keepalived/Pacemaker.

## Phạm vi demo

| Có | Không |
|----|-------|
| Auto-failover khi master chết, đo RTO | Multi-master (MHA chỉ 1 master + N replica) |
| VIP move qua hook | TLS/SSL channel |
| Rebuild master cũ qua GTID | High-availability cho bản thân manager (cần Keepalived/Pacemaker thêm) |
| Tích hợp với semi-sync (giảm data loss) | Group Replication / Galera (MHA không tương thích) |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | Demo 01 đã chạy thành công | `bash 01-precheck.sh` báo ALL OK |
| 2 | SSH passwordless mgmt → node1/2/3 hoạt động | `vagrant ssh mgmt -c "ssh root@node1 hostname"` |
| 3 | mha4mysql-manager service đã start | `masterha_check_status --conf=/etc/mha/myCluster.cnf` báo `PING_OK` |
| 4 | `masterha_check_repl` exit 0 | log có dòng `MySQL Replication Health is OK` |
| 5 | VIP `192.168.10.100` có trên node1 | `vagrant ssh node1 -c "ip -4 addr show eth1 \| grep 100"` |
| 6 | Halt node1 → master mới chọn trong ≤ 30s | log có dòng `Master failover to <new_master>... completed successfully` |
| 7 | VIP đã move sang master mới | `vagrant ssh <new_master> -c "ip -4 addr show eth1 \| grep 100"` |
| 8 | 2 replica còn lại đã `CHANGE REPLICATION SOURCE` về master mới | `SHOW REPLICA STATUS\G` |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| Precheck Demo 01 | 30s |
| SSH trust | 1 phút |
| Cài mha4mysql-node (3 nodes) | 2 phút |
| Cài + start manager (mgmt) | 1 phút |
| Verify | 30s |
| Failover demo | 2 phút |
| Rebuild master cũ | 1 phút |
| **Tổng** | **~7–10 phút** (chưa kể Demo 01) |

## Lưu ý quan trọng

- **MHA project ở chế độ maintenance** (yoshinorim không phát hành bản mới sau v0.58). Khuyến nghị production dùng **Orchestrator (Demo 05)**.
- MHA **chỉ hoạt động** với async/semi-sync — không dùng được với Group Replication/Galera.
- Cần `relay_log_purge=0` trên replicas (đã set trong Demo 01) để MHA có thể relay binlog còn sót khi failover.
- Sau khi failover xong, MHA **tự dừng**. Cần restart manager khi rebuild master cũ.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/04-mha/00-overview.md`
