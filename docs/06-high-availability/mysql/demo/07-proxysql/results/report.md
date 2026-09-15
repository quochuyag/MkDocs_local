---
title: Báo cáo Demo 07 — ProxySQL
course: 06-high-availability
source: HA/Mysql/demo/07-proxysql/results/report.md
---

# Báo cáo Demo 07 — ProxySQL

## 1. Thông tin demo

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-20 (khoảng 19:30 → 19:38 host time) |
| Backend stack | Galera / PXC 8.0 (Demo 06) |
| ProxySQL version | 2.6.x (chuẩn package proxysql:2 từ ProxySQL Hub) |

## 2. Cấu hình

| Hostgroup | Vai trò | Backends (Galera) |
|-----------|---------|-------------------|
| HG10 (writer) | Nhận INSERT/UPDATE/DELETE — chỉ 1 writer để tránh write conflict | node3 ONLINE; node1/2 SHUNNED |
| HG11 (backup writer) | Auto-promote khi HG10 down | node1, node2 ONLINE |
| HG20 (reader) | Round-robin SELECT | node1, node2 ONLINE |
| HG30 (offline/Desynced) | Donor/Desynced → không nhận traffic | (rỗng lúc verify) |

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 precheck             | PASS | <15s | [01-precheck.log](01-precheck.log) |
| B2 install-proxysql     | PASS | ~120s | [02-install-proxysql.log](02-install-proxysql.log) |
| B3 configure-galera     | PASS | <30s | [03-configure-galera.log](03-configure-galera.log) |
| B4 verify               | PASS | ~86s | [04-verify.log](04-verify.log) |
| B5 smoke-test           | PASS | ~116s | [05-smoke-test.log](05-smoke-test.log) |
| B6 failover-demo        | PASS | ~118s | [06-failover.log](06-failover.log) |

## 4. Các chỉ số chính

| Metric | Giá trị thực tế | Mong đợi | Pass? |
|--------|-----------------|----------|-------|
| ProxySQL service active | yes | yes | ✓ |
| Port 6032 (admin) + 6033 (client) listening | yes | yes | ✓ |
| `runtime_mysql_servers`: 7 rows, 5 ONLINE | yes | ≥3 ONLINE | ✓ |
| Monitor ping probes / 60s | 21 | ≥10 | ✓ |
| Active query rules | 2 | ≥2 | ✓ |
| appuser connect :6033 → @@hostname | OK (`node2`) | OK | ✓ |
| Insert 100 rows qua :6033 | 8.258s | <10s | ✓ |
| 8× SELECT @@hostname distinct hosts | 2 (node1=5, node2=3) | ≥2 (round-robin) | ✓ |
| Failover: detect halt node3 → SHUNNED | **51s** | <60s | ✓ |
| 6× SELECT sau halt không hit node3 | yes (toàn bộ hit node1) | yes | ✓ |

## 5. Quan sát & nhận xét

### Điểm tốt
- R/W split bằng regex query rule rất đơn giản — app không cần code logic routing.
- Backend failover trong suốt: khi node3 (writer) chết, HG11 backup tự promote (verify qua `runtime_mysql_servers` snapshot sau halt).
- Connection pool giảm số TCP connections từ app xuống backend (1:1 → N:M).
- Query digest (`stats_mysql_query_digest`) cung cấp insight tốt: INSERT vào HG10, SELECT @@hostname vào HG20 đúng routing.

### Hạn chế
- ProxySQL không hỗ trợ `caching_sha2_password` (MySQL 8 default) — appuser phải dùng `mysql_native_password`. Demo đã ALTER USER trong setup script.
- Single ProxySQL instance = SPOF. Production cần ≥2 ProxySQL + Keepalived VIP hoặc ProxySQL native cluster (`proxysql_servers`).
- Admin port :6032 SQLite không có hàm `UNIX_TIMESTAMP/LEFT/NOW` — cần dùng `SUBSTR` + inject timestamp từ shell (memory: `bug_proxysql_admin_sqlite_funcs.md`).
- Setup ban đầu fail với root@localhost-only PXC — phải `BOOTSTRAP_USERS=false` + `vagrant ssh nodeN socket` (memory: `bug_proxysql_setup_needs_socket_user_create.md`).
- DETECT_RTO 51s phụ thuộc `mysql-monitor_ping_interval_server_msec` (default 10s) + 4 lần fail liên tiếp.

### Câu hỏi mở
- ProxySQL native cluster (2 ProxySQL với `proxysql_servers`) auto-sync config — overhead bao nhiêu?
- Tích hợp với Orchestrator/MHA PostFailover hook → tự update HG10 writer hostname → fully automated stack?
- Query rewrite: optimize `SELECT … FOR UPDATE` thành covering-index version — tăng throughput bao nhiêu %?

## 6. Bằng chứng (từ log)

### B4 — Verify
```
[ OK ] proxysql service active
[ OK ] port 6032 + 6033 listening
runtime_mysql_servers: 7 rows, 5 ONLINE
Recent ping probes (60s window): 21
[ OK ] appuser connect :6033 → @@hostname=node2
active query rules: 2
VERIFY_PASS=true
```

### B5 — Smoke (R/W split + digest)
```
INSERT 100 rows qua :6033 → 8.258s
8× SELECT @@hostname:
  node2=3, node1=5 (round-robin reader HG20)

stats_mysql_connection_pool:
  HG10 192.168.10.13 ONLINE   (writer)
  HG10 192.168.10.11/12 SHUNNED (writer-only routing)
  HG11 192.168.10.11/12 ONLINE  (backup writer)
  HG20 192.168.10.11/12 ONLINE  (reader)

Top digest:
  INSERT INTO t(val) VALUES(?)        HG10 ×200
  SELECT @@hostname                   HG20 ×17
SMOKE_PASS=true
```

### B6 — Failover (halt --force node3)
```
ProxySQL detected 192.168.10.13 = SHUNNED sau 51s
6× SELECT post-halt: tất cả hit node1 (không có node3)
runtime sau halt:
  HG10 192.168.10.12 ONLINE  (HG11 backup writer promoted)
  HG30 192.168.10.13 SHUNNED
FAILOVER_PASS=true DETECT_RTO=51s
```

## 7. Bước tiếp theo

- [ ] Deploy 2nd ProxySQL trên app host → Keepalived VIP `192.168.10.99` hoặc ProxySQL native cluster.
- [ ] Tăng tốc detect: giảm `mysql-monitor_ping_interval_server_msec` từ 10000 → 2000 ms (đánh đổi noise vs DETECT_RTO).
- [ ] Query rewrite rule: bắt SELECT mất nhiều thời gian thành covering-index hint.
- [ ] Integrate `proxysql_exporter` (Prometheus) → Grafana dashboard 12555.
- [ ] Ghép với Orchestrator (demo 05) PostFailover hook → update HG10 hostname tự động khi master failover.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/07-proxysql/results/report.md`
