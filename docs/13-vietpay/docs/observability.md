---
title: 📊 Observability — VietPay Fintech Database
course: 13-vietpay
source: vietpay/docs/observability.md
---

# 📊 Observability — VietPay Fintech Database
## Grafana Dashboard & SLO Specification

---

## 1. Tổng quan (Overview)

Tài liệu này định nghĩa **key metrics, SLOs, và alerting rules** cho hệ thống database của nền tảng thanh toán VietPay. Mục tiêu là cung cấp **full visibility** vào hiệu suất, độ tin cậy, và sức khỏe của PostgreSQL cluster phục vụ workload fintech.

### Stack Công nghệ Giám sát

| Thành phần | Công cụ | Vai trò |
|---|---|---|
| **Metrics Collection** | Prometheus + `postgres_exporter` | Thu thập metrics từ PostgreSQL |
| **Visualization** | Grafana | Dashboard hiển thị real-time |
| **Alerting** | Grafana Alerting / Alertmanager | Cảnh báo khi vượt ngưỡng |
| **Log Aggregation** | Loki + `promtail` | Centralized query logs |
| **Tracing** | Tempo / Jaeger | Distributed tracing cho transactions |

### Nguồn Metrics chính

```yaml
# postgres_exporter config
postgres_exporter:
  data_source_name: "postgresql://monitor:***@primary:5432/vietpay?sslmode=require"
  
  # Custom queries cho business metrics
  custom_queries:
    - settlement_lag
    - transaction_throughput
    - ledger_balance_check
```

---

## 2. Dashboard Panels

### 2.1 Query Latency (Độ trễ truy vấn)

**Mục đích**: Theo dõi thời gian phản hồi của các OLTP queries — chỉ số quan trọng nhất cho trải nghiệm người dùng.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_stat_statements_mean_time_seconds`, `pg_stat_statements_calls_total` |
| **Panel Type** | Time Series Graph (multi-line: p50, p95, p99) |
| **SLO Target** | p99 < 100ms cho OLTP, p99 < 5s cho reporting |
| **Warning** | p99 > 80ms |
| **Critical** | p99 > 150ms |

**PromQL Queries:**

```promql
# P50 latency (median)
histogram_quantile(0.50,
  rate(pg_stat_statements_seconds_bucket{datname="vietpay"}[5m])
)

# P95 latency
histogram_quantile(0.95,
  rate(pg_stat_statements_seconds_bucket{datname="vietpay"}[5m])
)

# P99 latency
histogram_quantile(0.99,
  rate(pg_stat_statements_seconds_bucket{datname="vietpay"}[5m])
)
```

**Tại sao chọn ngưỡng này:**
- **100ms p99**: Fintech payment flows cần phản hồi nhanh. Người dùng chờ quá 200ms sẽ cảm nhận delay. API gateway timeout thường 500ms-1s, nên DB cần < 100ms để chừa overhead cho app logic.
- **80ms warning**: Cảnh báo sớm trước khi vi phạm SLO, cho team ~20% headroom để phản ứng.

---

### 2.2 Transaction Throughput (Thông lượng giao dịch)

**Mục đích**: Đo lường số giao dịch tài chính xử lý mỗi giây — capacity indicator chính.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `vietpay_transactions_total`, `pg_stat_user_tables_n_tup_ins` |
| **Panel Type** | Stat Panel (current TPS) + Time Series (trend) |
| **SLO Target** | ≥ 500 TPS sustained, ≥ 2,000 TPS peak |
| **Warning** | < 400 TPS sustained (possible degradation) |
| **Critical** | < 200 TPS sustained (service impact) |

**PromQL Queries:**

```promql
# Current TPS (transactions per second)
rate(vietpay_transactions_total{status="SETTLED"}[1m])

# TPS từ PostgreSQL insert rate trên bảng transactions
rate(pg_stat_user_tables_n_tup_ins{relname="transactions"}[5m])

# TPS trend (smoothed)
rate(vietpay_transactions_total[5m])
```

**Custom SQL metric cho `postgres_exporter`:**

```sql
-- Custom query: vietpay_transaction_throughput
SELECT 
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '1 minute') AS tps_1m,
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '5 minutes') / 5.0 AS tps_5m_avg,
    COUNT(*) FILTER (WHERE status = 'SETTLED' AND created_at >= NOW() - INTERVAL '1 minute') AS settled_tps_1m
FROM transactions
WHERE created_at >= NOW() - INTERVAL '5 minutes';
```

**Tại sao chọn ngưỡng này:**
- **500 TPS sustained**: Với ~2M giao dịch/tháng = ~0.77 TPS trung bình. Nhưng traffic distribution không đều — peak hours (11h-14h, 18h-21h) có thể gấp 10-50x. 500 TPS đảm bảo hệ thống handle peak bình thường.
- **< 200 TPS critical**: Dưới mức này, queue backlog sẽ tích lũy, gây cascade failure.

---

### 2.3 Replication Lag (Độ trễ replica)

**Mục đích**: Giám sát streaming replication giữa primary và standby — critical cho DR và read scaling.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_replication_lag_seconds`, `pg_stat_replication_replay_lag` |
| **Panel Type** | Gauge (current lag) + Time Series (trend) |
| **SLO Target** | < 1 giây |
| **Warning** | > 3 giây |
| **Critical** | > 10 giây |

**PromQL Queries:**

```promql
# Replication lag in seconds
pg_replication_lag_seconds{instance=~"replica.*"}

# Lag in bytes (WAL)
pg_stat_replication_pg_wal_lsn_diff{state="streaming"}

# Write lag vs Replay lag (chi tiết hơn)
pg_stat_replication_write_lag_seconds
pg_stat_replication_replay_lag_seconds
```

**Tại sao chọn ngưỡng này:**
- **< 1s**: Read replicas phục vụ balance queries. Nếu lag > 1s, user có thể thấy stale balance — unacceptable cho fintech.
- **> 10s critical**: Tại mức này, failover sẽ mất data. WAL backlog có thể tràn `wal_keep_size`, gây replica disconnect.

---

### 2.4 Lock Contention (Tranh chấp khóa)

**Mục đích**: Phát hiện lock waits và deadlocks — dấu hiệu của bottleneck concurrency.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_locks_count`, `pg_stat_activity_max_wait_seconds`, `pg_stat_database_deadlocks_total` |
| **Panel Type** | Time Series (lock waits) + Stat (deadlocks counter) |
| **SLO Target** | < 0.1% queries bị block > 100ms; 0 deadlocks/giờ |
| **Warning** | > 5 lock waits > 1s / phút |
| **Critical** | > 20 lock waits > 1s / phút HOẶC > 3 deadlocks / giờ |

**PromQL Queries:**

```promql
# Số lượng locks hiện tại theo mode
pg_locks_count{datname="vietpay"}

# Lock waits kéo dài > 1 giây
count(pg_stat_activity_wait_event_type{wait_event_type="Lock", datname="vietpay"})

# Deadlock rate
rate(pg_stat_database_deadlocks_total{datname="vietpay"}[1h])

# Longest current wait
max(pg_stat_activity_seconds_since_last_msg{state="active", wait_event_type="Lock"})
```

**Custom SQL metric:**

```sql
-- Lock contention monitoring
SELECT 
    COUNT(*) AS total_lock_waits,
    COUNT(*) FILTER (WHERE wait_time > INTERVAL '1 second') AS long_waits,
    MAX(EXTRACT(EPOCH FROM (NOW() - query_start))) AS max_wait_seconds
FROM pg_stat_activity
WHERE wait_event_type = 'Lock' AND state = 'active';
```

**Tại sao chọn ngưỡng này:**
- **0 deadlocks/giờ**: Double-entry ledger với ordered lock acquisition KHÔNG nên có deadlocks. Nếu có = bug trong lock ordering.
- **> 20 waits/phút**: Cho thấy hot-spot contention (ví dụ: cùng wallet bị update đồng thời), cần investigation ngay.

---

### 2.5 Settlement Processing Lag (Độ trễ settlement)

**Mục đích**: Đo thời gian từ khi transaction `PENDING` đến `SETTLED` — business-critical metric.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `vietpay_settlement_lag_seconds` (custom) |
| **Panel Type** | Heatmap + Stat (p95 lag) |
| **SLO Target** | p95 < 5 phút |
| **Warning** | p95 > 3 phút |
| **Critical** | p95 > 10 phút |

**PromQL Queries:**

```promql
# Settlement lag - p95
histogram_quantile(0.95,
  rate(vietpay_settlement_lag_seconds_bucket[5m])
)

# Average settlement lag
rate(vietpay_settlement_lag_seconds_sum[5m]) 
  / rate(vietpay_settlement_lag_seconds_count[5m])

# Pending transactions older than 5 minutes
vietpay_pending_transactions_count{age_bucket=">5m"}
```

**Custom SQL metric:**

```sql
-- Settlement lag monitoring
SELECT
    percentile_cont(0.50) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (settled_at - created_at))
    ) AS p50_settlement_seconds,
    percentile_cont(0.95) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (settled_at - created_at))
    ) AS p95_settlement_seconds,
    percentile_cont(0.99) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (settled_at - created_at))
    ) AS p99_settlement_seconds,
    COUNT(*) FILTER (WHERE status = 'PENDING' AND created_at < NOW() - INTERVAL '5 minutes') 
        AS stale_pending_count
FROM transactions
WHERE created_at >= NOW() - INTERVAL '1 hour';
```

**Tại sao chọn ngưỡng này:**
- **< 5 phút**: Quy định NHNN (Ngân hàng Nhà nước) yêu cầu giao dịch điện tử phải được xử lý trong thời gian hợp lý. 5 phút là tiêu chuẩn ngành cho real-time payments.
- **> 10 phút critical**: Ảnh hưởng trải nghiệm người dùng nghiêm trọng, có thể vi phạm SLA với merchants.

---

### 2.6 Connection Pool (Quản lý kết nối)

**Mục đích**: Giám sát utilization connection pool — exhaustion gây service outage ngay lập tức.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_stat_activity_count`, `pgbouncer_pools_*` |
| **Panel Type** | Stacked Bar (active/idle/waiting) + Gauge (utilization %) |
| **SLO Target** | Utilization < 70%; 0 waiting connections |
| **Warning** | Utilization > 70% HOẶC waiting > 0 |
| **Critical** | Utilization > 90% HOẶC waiting > 10 |

**PromQL Queries:**

```promql
# Connection utilization
pg_stat_activity_count{datname="vietpay"} / pg_settings_max_connections * 100

# Active vs Idle vs Idle-in-transaction
pg_stat_activity_count{datname="vietpay", state="active"}
pg_stat_activity_count{datname="vietpay", state="idle"}
pg_stat_activity_count{datname="vietpay", state="idle in transaction"}

# PgBouncer pool stats (nếu dùng PgBouncer)
pgbouncer_pools_server_active{database="vietpay"}
pgbouncer_pools_client_waiting{database="vietpay"}

# Idle-in-transaction timeout detection
count(pg_stat_activity{state="idle in transaction", 
  query_start < (now() - interval '5 minutes')})
```

**Tại sao chọn ngưỡng này:**
- **< 70%**: PostgreSQL default `max_connections = 100`. Mỗi connection chiếm ~5-10MB RAM. Cần headroom cho connection spikes (ví dụ: app deploy, batch jobs).
- **waiting > 0 warning**: Bất kỳ client nào phải chờ connection = dấu hiệu pool exhaustion sắp xảy ra.

---

### 2.7 Disk I/O (Hoạt động đọc/ghi)

**Mục đích**: Theo dõi I/O để phát hiện bottleneck storage — đặc biệt quan trọng cho OLTP workload.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `node_disk_io_time_seconds_total`, `pg_stat_bgwriter_*` |
| **Panel Type** | Time Series (IOPS, throughput, latency) |
| **SLO Target** | Disk latency p99 < 5ms (NVMe SSD) |
| **Warning** | Disk latency p99 > 5ms |
| **Critical** | Disk latency p99 > 20ms |

**PromQL Queries:**

```promql
# Disk IOPS
rate(node_disk_reads_completed_total{device="nvme0n1"}[5m])
rate(node_disk_writes_completed_total{device="nvme0n1"}[5m])

# Disk throughput (MB/s)
rate(node_disk_read_bytes_total{device="nvme0n1"}[5m]) / 1024 / 1024
rate(node_disk_written_bytes_total{device="nvme0n1"}[5m]) / 1024 / 1024

# Average disk latency
rate(node_disk_io_time_seconds_total{device="nvme0n1"}[5m])
  / rate(node_disk_io_now{device="nvme0n1"}[5m])

# PostgreSQL checkpoint I/O
rate(pg_stat_bgwriter_buffers_checkpoint_total[5m])
rate(pg_stat_bgwriter_checkpoint_write_time_total[5m])
```

---

### 2.8 Cache Hit Ratio (Tỷ lệ cache hit)

**Mục đích**: Buffer cache hit ratio thấp = đọc từ disk quá nhiều = latency tăng.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_stat_database_blks_hit`, `pg_stat_database_blks_read` |
| **Panel Type** | Gauge (percentage) + Time Series (trend) |
| **SLO Target** | > 99% cho OLTP database |
| **Warning** | < 98% |
| **Critical** | < 95% |

**PromQL Queries:**

```promql
# Buffer cache hit ratio
pg_stat_database_blks_hit{datname="vietpay"} 
  / (pg_stat_database_blks_hit{datname="vietpay"} 
     + pg_stat_database_blks_read{datname="vietpay"}) * 100

# Index hit ratio (nên > 99%)
pg_stat_user_indexes_idx_blks_hit 
  / (pg_stat_user_indexes_idx_blks_hit + pg_stat_user_indexes_idx_blks_read) * 100

# Table hit ratio per table
pg_statio_user_tables_heap_blks_hit{relname=~"transactions|ledger_entries"}
  / (pg_statio_user_tables_heap_blks_hit{relname=~"transactions|ledger_entries"} 
     + pg_statio_user_tables_heap_blks_read{relname=~"transactions|ledger_entries"}) * 100
```

**Tại sao chọn ngưỡng này:**
- **> 99%**: PostgreSQL OLTP workload với `shared_buffers` đúng cấu hình phải đạt 99%+. Dưới 98% cho thấy `shared_buffers` quá nhỏ hoặc có full table scan query.

---

### 2.9 WAL Generation Rate (Tốc độ sinh WAL)

**Mục đích**: WAL (Write-Ahead Log) volume ảnh hưởng trực tiếp đến disk space, replication lag, và backup time.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_stat_wal_wal_bytes_total` (PG14+) |
| **Panel Type** | Time Series (MB/s) + Stat (daily total) |
| **SLO Target** | < 500 MB/giờ sustained |
| **Warning** | > 1 GB/giờ sustained |
| **Critical** | > 5 GB/giờ sustained (possible runaway backfill/migration) |

**PromQL Queries:**

```promql
# WAL generation rate (bytes/sec)
rate(pg_stat_wal_wal_bytes_total[5m])

# WAL generation rate (MB/hour)
rate(pg_stat_wal_wal_bytes_total[1h]) / 1024 / 1024 * 3600

# WAL records per second
rate(pg_stat_wal_wal_records_total[5m])
```

---

### 2.10 Table Bloat & Autovacuum (Phình bảng)

**Mục đích**: Dead tuples tích lũy gây bloat → index scan chậm, disk waste. Autovacuum health = database health.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `pg_stat_user_tables_n_dead_tup`, `pg_stat_user_tables_last_autovacuum` |
| **Panel Type** | Table (top 10 bloated tables) + Time Series (dead tuples trend) |
| **SLO Target** | Dead tuple ratio < 10% cho bất kỳ bảng nào |
| **Warning** | Dead tuple ratio > 10% |
| **Critical** | Dead tuple ratio > 25% HOẶC autovacuum chưa chạy > 24h trên bảng active |

**PromQL Queries:**

```promql
# Dead tuple ratio per table
pg_stat_user_tables_n_dead_tup{relname=~"transactions|ledger_entries|wallets"}
  / (pg_stat_user_tables_n_live_tup{relname=~"transactions|ledger_entries|wallets"} 
     + pg_stat_user_tables_n_dead_tup{relname=~"transactions|ledger_entries|wallets"}) * 100

# Time since last autovacuum (seconds)
time() - pg_stat_user_tables_last_autovacuum{relname=~"transactions|ledger_entries"}

# Autovacuum currently running
pg_stat_activity_count{query=~"autovacuum:.*", state="active"}
```

**Custom SQL metric:**

```sql
-- Table bloat estimation
SELECT
    schemaname || '.' || relname AS table_name,
    n_live_tup,
    n_dead_tup,
    ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
    last_autovacuum,
    last_autoanalyze,
    autovacuum_count,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE n_live_tup > 10000
ORDER BY n_dead_tup DESC
LIMIT 20;
```

---

### 2.11 Capacity Planning (Quy hoạch năng lực)

**Mục đích**: Dự đoán khi nào cần tăng tài nguyên — tránh outage do resource exhaustion.

| Thuộc tính | Chi tiết |
|---|---|
| **Metric Name** | `node_filesystem_avail_bytes`, `pg_database_size_bytes` |
| **Panel Type** | Gauge (current %) + Time Series (trend + linear prediction) |
| **SLO Target** | Disk usage < 70%, luôn có ≥ 60 ngày headroom |
| **Warning** | Disk usage > 70% HOẶC < 30 ngày headroom |
| **Critical** | Disk usage > 85% HOẶC < 7 ngày headroom |

**PromQL Queries:**

```promql
# Disk usage percentage
(1 - node_filesystem_avail_bytes{mountpoint="/data"} 
  / node_filesystem_size_bytes{mountpoint="/data"}) * 100

# Database size
pg_database_size_bytes{datname="vietpay"} / 1024 / 1024 / 1024  -- GB

# Growth rate prediction (linear regression, dự đoán khi nào full)
predict_linear(
  node_filesystem_avail_bytes{mountpoint="/data"}[30d], 
  86400 * 60  -- 60 ngày
)

# Bảng lớn nhất
topk(10, pg_total_relation_size_bytes{datname="vietpay"})
```

---

## 3. SLO Definitions (Định nghĩa SLO)

### 3.1 Bảng SLO tổng hợp

| # | SLI (Service Level Indicator) | SLO Target | Error Budget (30 ngày) | Measurement Window |
|---|---|---|---|---|
| 1 | **Query Latency** — p99 OLTP query time | < 100ms | 43.2 phút downtime (99.9%) | Rolling 30 days |
| 2 | **Availability** — Database uptime | 99.95% | 21.6 phút/tháng | Calendar month |
| 3 | **Transaction Throughput** — Min sustained TPS | ≥ 500 TPS | < 1% time below target | Rolling 7 days |
| 4 | **Replication Lag** — Streaming rep delay | < 1 giây | 99.9% of time within target | Rolling 30 days |
| 5 | **Settlement Lag** — PENDING → SETTLED | p95 < 5 phút | 99.5% settled within 5m | Rolling 7 days |
| 6 | **Data Integrity** — Ledger balance | 100% balanced | 0 tolerance | Continuous |
| 7 | **Cache Hit Ratio** — Buffer cache | > 99% | 99.5% of time within target | Rolling 30 days |
| 8 | **Durability** — Zero data loss | RPO = 0 (sync rep) | 0 tolerance | Continuous |

### 3.2 Error Budget Policy

```
Khi error budget còn:
  > 50%  → Normal operations, deploy bình thường
  25-50% → Tăng cường monitoring, giảm tần suất deploy
  10-25% → Freeze feature deployments, chỉ fix bugs
  < 10%  → Incident mode, toàn bộ team focus reliability
  0%     → Complete deployment freeze cho đến khi budget reset
```

---

## 4. Alerting Rules (Quy tắc cảnh báo)

### 4.1 Critical Alerts — PagerDuty (đánh thức on-call)

```yaml
# Alert 1: Database Down
- alert: PostgresDatabaseDown
  expr: pg_up{datname="vietpay"} == 0
  for: 30s
  labels:
    severity: critical
    team: dba
  annotations:
    summary: "PostgreSQL database vietpay is DOWN"
    runbook: |
      1. Kiểm tra pg_isready -h <host> -p 5432
      2. Check systemctl status postgresql
      3. Review /var/log/postgresql/postgresql-*.log
      4. Nếu primary down → trigger failover via Patroni
      5. Notify business team về potential transaction impact

# Alert 2: Replication Lag Critical
- alert: ReplicationLagCritical
  expr: pg_replication_lag_seconds > 10
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Replication lag {{ $value }}s exceeds 10s threshold"
    runbook: |
      1. Check pg_stat_replication on primary
      2. Verify network bandwidth between primary/replica
      3. Check if heavy write workload (backfill, migration)
      4. Nếu lag > 30s → consider pausing non-essential writes
      5. Nếu replica disconnect → re-create from pg_basebackup

# Alert 3: Connection Pool Exhaustion
- alert: ConnectionPoolExhaustion
  expr: pg_stat_activity_count{datname="vietpay"} / pg_settings_max_connections > 0.9
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Connection utilization at {{ $value | humanizePercentage }}"
    runbook: |
      1. Check for idle-in-transaction: SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction'
      2. Kill long-running idle connections: SELECT pg_terminate_backend(pid)
      3. Review PgBouncer pool settings
      4. Check application connection pool configuration
      5. Nếu cần ngay → ALTER SYSTEM SET max_connections = 200 (requires restart)

# Alert 4: Disk Space Critical
- alert: DiskSpaceCritical
  expr: (1 - node_filesystem_avail_bytes{mountpoint="/data"} / node_filesystem_size_bytes{mountpoint="/data"}) > 0.85
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Disk usage at {{ $value | humanizePercentage }} on /data"
    runbook: |
      1. Check largest tables: SELECT pg_size_pretty(pg_total_relation_size(oid)) FROM pg_class ORDER BY pg_total_relation_size(oid) DESC LIMIT 10
      2. Run VACUUM FULL on bloated tables (requires maintenance window)
      3. Archive old partitions to cold storage
      4. Drop unused indexes
      5. Emergency: expand volume (AWS EBS resize)

# Alert 5: Ledger Imbalance (CRITICAL — data integrity)
- alert: LedgerImbalance
  expr: vietpay_ledger_imbalance_count > 0
  for: 0s  # Immediately!
  labels:
    severity: critical
    escalation: executive
  annotations:
    summary: "CRITICAL: Ledger imbalance detected! {{ $value }} transactions with non-zero sum"
    runbook: |
      1. NGAY LẬP TỨC: Dừng mọi giao dịch mới (circuit breaker)
      2. Run: SELECT * FROM check_ledger_balance()
      3. Identify affected transactions
      4. Notify compliance team
      5. Begin forensic analysis — DO NOT modify any data
      6. File incident report per PCI-DSS requirements

# Alert 6: Settlement Lag Critical
- alert: SettlementLagCritical
  expr: histogram_quantile(0.95, rate(vietpay_settlement_lag_seconds_bucket[5m])) > 600
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Settlement p95 lag at {{ $value }}s (> 10 minutes)"
    runbook: |
      1. Check settlement batch processor status
      2. Verify payment provider API availability
      3. Check for lock contention on transactions table
      4. Review settlement_batches for stuck batches
      5. Manual intervention: re-trigger failed settlement batches
```

### 4.2 Warning Alerts — Slack notification

```yaml
# Alert 7: High Query Latency
- alert: HighQueryLatency
  expr: histogram_quantile(0.99, rate(pg_stat_statements_seconds_bucket{datname="vietpay"}[5m])) > 0.08
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Query p99 latency at {{ $value }}s approaching SLO threshold"
    runbook: |
      1. Check pg_stat_statements for slow queries
      2. Review EXPLAIN ANALYZE for top queries
      3. Check if missing indexes or stale statistics
      4. Run ANALYZE on affected tables

# Alert 8: Cache Hit Ratio Low
- alert: CacheHitRatioLow
  expr: |
    pg_stat_database_blks_hit{datname="vietpay"} 
    / (pg_stat_database_blks_hit{datname="vietpay"} + pg_stat_database_blks_read{datname="vietpay"}) < 0.98
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Buffer cache hit ratio at {{ $value | humanizePercentage }}"
    runbook: |
      1. Check for recent query pattern changes
      2. Consider increasing shared_buffers
      3. Look for sequential scan queries: SELECT * FROM pg_stat_user_tables WHERE seq_scan > 0

# Alert 9: Deadlock Detected
- alert: DeadlockDetected
  expr: rate(pg_stat_database_deadlocks_total{datname="vietpay"}[1h]) > 0
  for: 0s
  labels:
    severity: warning
  annotations:
    summary: "Deadlock detected in vietpay database"
    runbook: |
      1. Check PostgreSQL logs for deadlock details
      2. Review application lock ordering
      3. Verify double-entry ledger uses ordered wallet_id locking

# Alert 10: Table Bloat
- alert: TableBloat
  expr: |
    pg_stat_user_tables_n_dead_tup 
    / (pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup) > 0.1
  for: 30m
  labels:
    severity: warning
  annotations:
    summary: "Table {{ $labels.relname }} has {{ $value | humanizePercentage }} dead tuples"
    runbook: |
      1. Check autovacuum status for this table
      2. Consider manual VACUUM if autovacuum is behind
      3. Review autovacuum_vacuum_threshold settings

# Alert 11: WAL Generation Spike
- alert: WALGenerationSpike
  expr: rate(pg_stat_wal_wal_bytes_total[5m]) / 1024 / 1024 > 100  # > 100 MB/s
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "WAL generation at {{ $value }}MB/s — possible bulk operation"
    runbook: |
      1. Check for running migrations or backfill operations
      2. Verify replication can keep up
      3. Monitor WAL disk space
```

---

## 5. Dashboard Layout (Bố cục Dashboard)

### 5.1 Executive Overview Dashboard

```
┌─────────────────────────────────────────────────────────────┐
│  VietPay Database — Executive Overview                       │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│ DB Status│  TPS     │ Settled  │ Rep Lag  │ Disk Usage      │
│  🟢 UP   │  723/s   │  687/s   │  0.2s    │  52%            │
│  (Stat)  │ (Stat)   │ (Stat)   │ (Gauge)  │ (Gauge)         │
├──────────┴──────────┴──────────┴──────────┴─────────────────┤
│ Query Latency (p50/p95/p99)          │ Settlement Lag        │
│ ▂▃▂▃▂▁▂▃▅▃▂▁▂▃▂ (Time Series)       │ ▂▁▂▁▂▃▅▃▂▁ (Heatmap)│
├──────────────────────────────────────┼───────────────────────┤
│ Connection Pool                      │ Cache Hit Ratio       │
│ ████░░░░ 67% active (Stacked Bar)   │ 99.7% (Gauge)         │
├──────────────────────────────────────┴───────────────────────┤
│ Capacity Forecast (30d trend + linear prediction)            │
│ ▂▃▄▅▅▆▆▇▇ → 85% in 73 days (Time Series)                   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 DBA Deep-Dive Dashboard

```
┌─────────────────────────────────────────────────────────────┐
│  VietPay Database — DBA Deep Dive                            │
├──────────────────────────────────────────────────────────────┤
│ Row 1: Lock Analysis                                         │
│ Lock Waits │ Deadlocks (24h) │ Longest Wait │ Lock by Table  │
├──────────────────────────────────────────────────────────────┤
│ Row 2: I/O Analysis                                          │
│ IOPS Read/Write │ Throughput MB/s │ Checkpoint I/O │ WAL/s   │
├──────────────────────────────────────────────────────────────┤
│ Row 3: Vacuum & Bloat                                        │
│ Top 10 Dead Tuples │ Autovacuum Activity │ Table Sizes       │
├──────────────────────────────────────────────────────────────┤
│ Row 4: Replication                                           │
│ Write Lag │ Flush Lag │ Replay Lag │ WAL Send/Receive Gap    │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Custom Business Metrics (Metrics nghiệp vụ tùy chỉnh)

Ngoài infrastructure metrics, cần giám sát **business-level health**:

```sql
-- Expose via postgres_exporter custom queries

-- 1. Ledger balance verification (chạy mỗi phút)
-- Metric: vietpay_ledger_imbalance_count
SELECT COUNT(*) AS imbalance_count
FROM (
    SELECT transaction_id, SUM(CASE WHEN entry_type = 'DEBIT' THEN amount ELSE -amount END) AS net
    FROM ledger_entries
    WHERE created_at >= NOW() - INTERVAL '1 hour'
    GROUP BY transaction_id
    HAVING SUM(CASE WHEN entry_type = 'DEBIT' THEN amount ELSE -amount END) != 0
) imbalanced;

-- 2. Idempotency key hit rate (duplicate detection effectiveness)
-- Metric: vietpay_idempotency_duplicate_rate
SELECT 
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '5 minutes') AS total_keys,
    COUNT(*) FILTER (WHERE response_status IS NOT NULL 
                     AND created_at >= NOW() - INTERVAL '5 minutes') AS duplicate_hits
FROM idempotency_keys;

-- 3. Failed transaction rate
-- Metric: vietpay_failed_transaction_rate
SELECT
    COUNT(*) FILTER (WHERE status = 'FAILED') AS failed,
    COUNT(*) AS total,
    ROUND(COUNT(*) FILTER (WHERE status = 'FAILED')::numeric / NULLIF(COUNT(*), 0) * 100, 4) AS fail_pct
FROM transactions
WHERE created_at >= NOW() - INTERVAL '5 minutes';

-- 4. Wallet balance anomaly detection
-- Metric: vietpay_wallet_balance_anomaly_count  
SELECT COUNT(*) AS anomaly_count
FROM wallets w
WHERE w.balance != (
    SELECT COALESCE(SUM(CASE WHEN le.entry_type = 'CREDIT' THEN le.amount ELSE -le.amount END), 0)
    FROM ledger_entries le
    WHERE le.wallet_id = w.id
);
```

---

## 7. Monitoring During Operations (Giám sát trong vận hành)

### 7.1 Migration Monitoring Panel

Khi chạy migration (Task 3), thêm temporary panel:

```promql
# Lock waits during migration
count(pg_stat_activity{wait_event_type="Lock", query=~".*settlement_batch_id.*"})

# Backfill progress
vietpay_backfill_progress_rows / vietpay_backfill_total_rows * 100

# Replication lag spike during migration
deriv(pg_replication_lag_seconds[5m])
```

### 7.2 On-Call Runbook Quick Reference

| Alert | First Response (< 5 min) | Escalation (< 15 min) |
|---|---|---|
| DB Down | Check process, attempt restart | Failover to standby |
| Replication Lag > 10s | Check network, pause writes | Re-create replica |
| Connection Exhaustion | Kill idle connections | Increase max_connections |
| Disk > 85% | Archive old partitions | Expand volume |
| Ledger Imbalance | **STOP ALL TRANSACTIONS** | Executive escalation |
| Settlement > 10m | Check batch processor | Manual settlement trigger |


---

!!! info "Nguồn gốc"
    `vietpay/docs/observability.md`
