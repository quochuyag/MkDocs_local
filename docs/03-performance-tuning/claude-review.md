---
title: Oracle Database Performance Tuning — Tài liệu Ôn tập Tổng hợp
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/claude_review.md
---

# Oracle Database Performance Tuning — Tài liệu Ôn tập Tổng hợp

> **Khóa học:** Oracle Database Performance Tuning (Ahmed Baraka, Packt v2.3)  
> **Cập nhật:** 2026-04-21 | **Tiến độ:** 28/29 sections hoàn thành

---

## MỤC LỤC

1. [Cluster 1 — Chẩn đoán & Giám sát](#cluster-1)
2. [Cluster 2 — Contention](#cluster-2)
3. [Cluster 3 — Memory Tuning](#cluster-3)
4. [Cluster 4 — Storage & Object](#cluster-4)
5. [Cluster 5 — Advanced Tools & OS](#cluster-5)
6. [Tình huống thực tế tổng hợp](#scenarios)
7. [Quiz tổng hợp 50 câu](#quiz)
8. [Bảng tham chiếu nhanh Views & Tools](#reference)

---

<a name="cluster-1"></a>
## CLUSTER 1 — CHẨN ĐOÁN & GIÁM SÁT
### (Section 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17)

---

### Section 6 — Time Model Views

#### Khái niệm cốt lõi
- `V$SYS_TIME_MODEL`: Thời gian tiêu thụ toàn hệ thống theo từng thành phần (DB time, CPU time, parse time, ...)
- `V$SESS_TIME_MODEL`: Tương tự nhưng theo từng session
- **DB Time** = tổng thời gian Oracle xử lý yêu cầu của user (bao gồm CPU + wait)
- **DB CPU** = phần CPU thuần túy trong DB Time

#### SQL tham chiếu
```sql
-- Top time consumers toàn hệ thống
SELECT stat_name, value/1e6 seconds
FROM   v$sys_time_model
ORDER  BY value DESC;

-- So sánh DB CPU vs DB Time (% CPU efficiency)
SELECT a.value db_cpu, b.value db_time,
       ROUND(a.value/b.value*100,2) pct_cpu
FROM   v$sys_time_model a, v$sys_time_model b
WHERE  a.stat_name = 'DB CPU'
AND    b.stat_name = 'DB time';
```

#### Câu hỏi ôn tập
1. DB Time khác DB CPU ở điểm gì?
2. Khi `parse time elapsed` chiếm > 20% DB Time, bạn nghi ngờ vấn đề gì?
3. `V$SYS_TIME_MODEL` vs `V$SESS_TIME_MODEL` — dùng cái nào khi nào?

#### Tình huống
> **Triệu chứng:** DBA thấy DB Time rất cao nhưng CPU load thấp.  
> **Phân tích:** DB Time = CPU + Wait. Nếu CPU thấp mà DB Time cao → phần lớn thời gian là **wait events**.  
> **Hướng xử lý:** Chuyển sang phân tích `V$SYSTEM_EVENT` / ASH để tìm wait event chiếm nhiều nhất.

---

### Section 8 — Instance Activity & Wait Events

#### Khái niệm cốt lõi
- **Wait Event**: Sự kiện Oracle phải chờ (I/O, lock, latch, network, ...)
- **Idle Wait**: Chờ bình thường (SQL*Net message from client) — không phải bottleneck
- **Non-idle Wait**: Chờ do vấn đề thực sự cần điều tra

| View | Phạm vi | Mục đích |
|------|---------|---------|
| `V$SYSTEM_EVENT` | Instance | Tổng hợp toàn hệ thống từ startup |
| `V$SESSION_EVENT` | Session | Wait events của từng session hiện tại |
| `V$SESSION_WAIT` | Session | Wait event đang diễn ra ngay lúc này |
| `V$ACTIVE_SESSION_HISTORY` | Session | Lịch sử 1 giây/lần cho active sessions |

#### SQL tham chiếu
```sql
-- Top non-idle wait events
SELECT event, total_waits, time_waited, average_wait
FROM   v$system_event
WHERE  wait_class != 'Idle'
ORDER  BY time_waited DESC
FETCH  FIRST 10 ROWS ONLY;

-- Session đang chờ gì ngay lúc này
SELECT sid, event, state, seconds_in_wait
FROM   v$session_wait
WHERE  wait_class != 'Idle';
```

#### Câu hỏi ôn tập
1. Tại sao phải lọc `wait_class != 'Idle'` khi phân tích wait events?
2. Khác nhau giữa `V$SESSION_WAIT` và `V$SESSION_EVENT`?
3. Wait class "Concurrency" và "Configuration" báo hiệu vấn đề gì?

#### Tình huống
> **Triệu chứng:** Users than DB chậm vào buổi sáng, bình thường buổi chiều.  
> **Phân tích:** Kiểm tra `V$SYSTEM_EVENT` trong khoảng thời gian đó (dùng AWR snapshot). Nếu thấy `log file sync` cao → redo I/O bottleneck.  
> **Hướng xử lý:** Kiểm tra I/O trên redo log destination (Section 24).

---

### Section 9 — AWR (Automatic Workload Repository)

#### Khái niệm cốt lõi
- AWR chụp ảnh (snapshot) hệ thống mỗi 60 phút (mặc định), lưu 8 ngày
- **AWR Report**: So sánh 2 snapshot → tổng hợp load, top SQL, top wait events
- **AWR SQL Report**: Chi tiết một SQL cụ thể qua nhiều snapshot
- **AWR Baseline**: Đóng băng dữ liệu tốt để so sánh trong tương lai

#### Các lệnh quan trọng
```sql
-- Tạo snapshot thủ công
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT();

-- Danh sách snapshots
SELECT snap_id, begin_interval_time, end_interval_time
FROM   dba_hist_snapshot
ORDER  BY snap_id DESC;

-- Tạo AWR Report (text)
@$ORACLE_HOME/rdbms/admin/awrrpt.sql

-- Tạo Baseline
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(
    start_snap_id => 100, end_snap_id => 105,
    baseline_name => 'MORNING_PEAK');

-- Xem top SQL từ AWR
SELECT sql_id, executions_delta, elapsed_time_delta/1e6 elapsed_sec
FROM   dba_hist_sqlstat
WHERE  snap_id BETWEEN 100 AND 105
ORDER  BY elapsed_time_delta DESC
FETCH  FIRST 10 ROWS ONLY;
```

#### Cấu trúc AWR Report — Các section quan trọng
1. **Load Profile**: Logical reads, physical reads, redo size/sec
2. **Top 5 Timed Events**: Wait events tốn nhiều thời gian nhất
3. **SQL Statistics**: Top SQL theo elapsed time, CPU, gets, reads
4. **Instance Activity Stats**: Buffer cache hit ratio, parse ratio
5. **I/O Stats**: Đọc/ghi theo datafile

#### Tình huống
> **Triệu chứng:** Performance tốt tuần trước, tuần này chậm hơn rõ rệt.  
> **Phân tích:** So sánh AWR report tuần này vs baseline tuần trước. Tìm điểm khác biệt trong Top 5 Events và Top SQL.  
> **Hướng xử lý:** Nếu xuất hiện SQL mới trong top → review execution plan của SQL đó (Section 35). Nếu I/O tăng → kiểm tra tablespace fragmentation (Section 29).

---

### Section 10 — Server-generated Alerts

#### Khái niệm cốt lõi
- Oracle tự động gửi alert khi metrics vượt ngưỡng
- Hai loại: **Stateful** (tồn tại đến khi metric trở về bình thường) và **Stateless**
- Ngưỡng: **Warning** (cảnh báo) và **Critical** (nghiêm trọng)

```sql
-- Xem alerts hiện tại
SELECT reason, metric_name, alert_level
FROM   dba_outstanding_alerts
ORDER  BY creation_time DESC;

-- Lịch sử alerts
SELECT reason, metric_name, creation_time
FROM   dba_alert_history
WHERE  creation_time > SYSDATE - 7;

-- Đặt ngưỡng cảnh báo
EXEC DBMS_SERVER_ALERT.SET_THRESHOLD(
    metrics_id    => DBMS_SERVER_ALERT.TABLESPACE_PCT_FULL,
    warning_value => '80', critical_value => '95',
    observation_period => 1, consecutive_occurrences => 1,
    instance_name => NULL, object_type => DBMS_SERVER_ALERT.OBJECT_TYPE_TABLESPACE,
    object_name => 'USERS');
```

#### Tình huống
> **Triệu chứng:** Tablespace USERS gần đầy, không ai biết trước.  
> **Hướng xử lý:** Đặt threshold `TABLESPACE_PCT_FULL` warning=80%, critical=90%. Kết hợp với OEM hoặc script email để thông báo tự động.

---

### Section 11 — Statspack

#### Khi nào dùng Statspack thay AWR?
- Database **Standard Edition** (không có AWR)
- Môi trường không có **Diagnostics Pack** license
- Statspack là công cụ **miễn phí**, chạy trên mọi edition

```sql
-- Cài Statspack
@$ORACLE_HOME/rdbms/admin/spcreate.sql

-- Chụp snapshot
EXEC STATSPACK.SNAP;

-- Tạo report
@$ORACLE_HOME/rdbms/admin/spreport.sql

-- Tự động chụp mỗi 1 giờ (dùng DBMS_JOB)
EXEC STATSPACK.SNAP_LEVEL(5);
```

#### So sánh AWR vs Statspack

| Tiêu chí | AWR | Statspack |
|---------|-----|----------|
| License | Diagnostics Pack | Miễn phí |
| Edition | EE | SE + EE |
| ADDM tích hợp | Có | Không |
| ASH data | Có | Không |
| Real-time | OEM | Không |

---

### Section 12 — ADDM (Automatic Database Diagnostic Monitor)

#### Khái niệm cốt lõi
- ADDM tự động chạy sau mỗi AWR snapshot
- Phân tích nguyên nhân gốc rễ (root cause) → đề xuất giải pháp
- Kết quả lưu trong `DBA_ADVISOR_*` views

```sql
-- Xem kết quả ADDM gần nhất
SELECT task_name, description, status
FROM   dba_advisor_tasks
WHERE  advisor_name = 'ADDM'
ORDER  BY created DESC;

-- Chi tiết findings
SELECT f.type, f.message, f.benefit
FROM   dba_advisor_findings f
       JOIN dba_advisor_tasks t ON f.task_id = t.task_id
WHERE  t.advisor_name = 'ADDM'
ORDER  BY f.benefit DESC;

-- Chạy ADDM thủ công cho khoảng thời gian cụ thể
EXEC DBMS_ADDM.ANALYZE_DB('MY_ADDM', start_snap_id, end_snap_id);
```

#### Tình huống
> **Triệu chứng:** DBA muốn biết bottleneck chính trong giờ cao điểm 8–9 sáng.  
> **Hướng xử lý:** Lấy snapshot IDs của khoảng 8–9 giờ từ `DBA_HIST_SNAPSHOT`, chạy `DBMS_ADDM.ANALYZE_DB`, đọc findings theo `benefit` giảm dần.

---

### Section 13 — ASH (Active Session History)

#### Khái niệm cốt lõi
- ASH mẫu 1 giây/lần, lưu active sessions vào circular buffer trong SGA
- `V$ACTIVE_SESSION_HISTORY`: dữ liệu in-memory (vài giờ gần nhất)
- `DBA_HIST_ACTIVE_SESS_HISTORY`: dữ liệu lịch sử trong AWR (flush 10 giây/lần, 1/10 mẫu)

```sql
-- Top wait events 30 phút gần nhất
SELECT event, COUNT(*) samples,
       ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,1) pct
FROM   v$active_session_history
WHERE  sample_time > SYSDATE - 30/1440
AND    session_state = 'WAITING'
GROUP  BY event
ORDER  BY samples DESC;

-- Top SQL đang gây tải
SELECT sql_id, COUNT(*) samples
FROM   v$active_session_history
WHERE  sample_time > SYSDATE - 1/24
GROUP  BY sql_id
ORDER  BY samples DESC;

-- Liên kết ASH với dimension views
SELECT ash.sql_id, u.username, o.object_name, ash.event
FROM   v$active_session_history ash
       LEFT JOIN dba_users u ON ash.user_id = u.user_id
       LEFT JOIN dba_objects o ON ash.current_obj# = o.object_id
WHERE  ash.sample_time > SYSDATE - 1/24;
```

#### Tình huống
> **Triệu chứng:** Spike performance 5 phút trước, không bắt được kịp bằng real-time tools.  
> **Hướng xử lý:** Query `V$ACTIVE_SESSION_HISTORY` với `sample_time` trong khoảng 5 phút đó. ASH đã ghi lại mọi thứ 1 giây/lần.

---

### Section 14 — Database Service Statistics

#### Khái niệm cốt lõi
- **Service**: Nhóm logic của workload (OLTP, batch, reporting)
- **Module/Action**: Phân loại chi tiết hơn trong application code
- **Client Identifier**: Tracking end-user qua connection pool

```sql
-- Set module/action từ application
EXEC DBMS_APPLICATION_INFO.SET_MODULE('ORDER_APP', 'INSERT_ORDER');

-- Set client identifier
EXEC DBMS_SESSION.SET_IDENTIFIER('USER_12345');

-- Xem service statistics
SELECT service_name, physical_reads, logical_reads, elapsed_time
FROM   v$service_stats
ORDER  BY elapsed_time DESC;

-- ASH theo service
SELECT service_name, event, COUNT(*)
FROM   v$active_session_history
WHERE  sample_time > SYSDATE - 1/24
GROUP  BY service_name, event
ORDER  BY COUNT(*) DESC;
```

---

### Section 15 — SQL Tracing với DBMS_MONITOR

#### Khái niệm cốt lõi
- **10046 trace**: Chi tiết từng SQL, parse/execute/fetch, wait events
- **TKPROF**: Tool đọc raw trace file → output dễ đọc
- Có thể trace theo: session, service+module, client_id

```sql
-- Trace session hiện tại
EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(
    session_id => 42, serial_num => 1234,
    waits => TRUE, binds => FALSE);

-- Trace theo module
EXEC DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE(
    service_name => 'ORCL',
    module_name  => 'ORDER_APP',
    action_name  => DBMS_MONITOR.ALL_ACTIONS);

-- Trace theo client_id
EXEC DBMS_MONITOR.CLIENT_ID_TRACE_ENABLE('USER_12345');

-- Tắt trace
EXEC DBMS_MONITOR.SESSION_TRACE_DISABLE(42, 1234);

-- Đọc trace file bằng TKPROF
-- tkprof /u01/diag/.../*.trc output.txt sys=no sort=exeela
```

#### Tình huống
> **Triệu chứng:** Một user cụ thể báo ứng dụng chậm, user khác bình thường.  
> **Hướng xử lý:** Dùng `DBMS_SESSION.SET_IDENTIFIER` ở tầng app, sau đó `CLIENT_ID_TRACE_ENABLE` để trace đúng user đó. Phân tích TKPROF output → tìm SQL chậm.

---

### Section 16 — Real-time Database Operation Monitoring

#### Khái niệm cốt lõi
- Monitor SQL đang chạy trong real-time (không cần đợi kết thúc)
- `V$SQL_MONITOR`: Theo dõi SQL chạy > 5 giây hoặc parallel
- `V$SQL_PLAN_MONITOR`: Chi tiết từng bước trong execution plan

```sql
-- SQL đang chạy và tiến độ
SELECT sql_id, status, elapsed_time/1e6 elapsed_sec,
       cpu_time/1e6 cpu_sec, buffer_gets, disk_reads
FROM   v$sql_monitor
WHERE  status = 'EXECUTING'
ORDER  BY elapsed_time DESC;

-- Báo cáo HTML real-time
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id     => 'abc123xyz',
    type       => 'HTML',
    report_level => 'ALL') report
FROM dual;
```

---

### Section 17 — Automated Maintenance Tasks

#### Khái niệm cốt lõi
- Oracle tự động chạy 3 task bảo trì:
  1. **Auto Optimizer Stats Collection**: Thu thập thống kê cho optimizer
  2. **Auto Segment Advisor**: Phát hiện segment cần shrink/reorganize
  3. **Auto SQL Tuning Advisor**: Đề xuất SQL Profile cho SQL chậm

```sql
-- Xem maintenance windows
SELECT window_name, enabled, next_start_date
FROM   dba_scheduler_windows;

-- Xem trạng thái tasks
SELECT client_name, status, attributes
FROM   dba_autotask_client;

-- Tắt/bật một task
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(
    client_name => 'auto optimizer stats collection',
    operation   => NULL, window_name => NULL);
```

---

<a name="cluster-2"></a>
## CLUSTER 2 — CONTENTION
### (Section 19, 20)

---

### Section 19 — Enqueue Waits (Lock Contention)

#### Khái niệm cốt lõi
- **Enqueue** = Lock trong Oracle (TX lock, TM lock, ...)
- **TX lock**: Row-level lock khi transaction chưa commit
- **TM lock**: DML lock bảo vệ table structure
- Wait event: `enq: TX - row lock contention`

```sql
-- Tìm sessions đang block/bị block
SELECT l1.sid blocking_session, l2.sid waiting_session,
       l1.type lock_type
FROM   v$lock l1, v$lock l2
WHERE  l1.block = 1
AND    l2.request > 0
AND    l1.id1 = l2.id1
AND    l1.id2 = l2.id2;

-- Thông tin chi tiết session blocking
SELECT s.sid, s.username, s.status, s.sql_id, s.blocking_session
FROM   v$session s
WHERE  s.blocking_session IS NOT NULL;

-- Kill session blocking
ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE;
```

#### Tình huống
> **Triệu chứng:** Nhiều sessions bị treo, ứng dụng không response.  
> **Phân tích:** Kiểm tra `V$SESSION` với `blocking_session IS NOT NULL`. Tìm root blocker (session block nhưng không bị block).  
> **Hướng xử lý:**  
> 1. Ngắn hạn: Kill root blocker nếu cần thiết  
> 2. Dài hạn: Review application logic — đảm bảo COMMIT/ROLLBACK kịp thời, tránh lock escalation

---

### Section 20 — Latch & Mutex Contention

#### Khái niệm cốt lõi
- **Latch**: Serialization mechanism cấp thấp (in-memory structures)
  - Ví dụ: `cache buffers chains` (buffer cache), `shared pool` (library cache)
- **Mutex**: Thay thế latch ở nhiều nơi trong Oracle 10g+ (nhẹ hơn latch)
- Wait events: `latch: cache buffers chains`, `cursor: pin S wait on X`

```sql
-- Top latch contention
SELECT name, gets, misses, sleeps,
       ROUND(misses/NULLIF(gets,0)*100,2) miss_ratio
FROM   v$latch
WHERE  gets > 0
ORDER  BY sleeps DESC
FETCH  FIRST 10 ROWS ONLY;

-- Mutex wait events
SELECT event, total_waits, time_waited
FROM   v$system_event
WHERE  event LIKE 'cursor%'
OR     event LIKE 'library cache%'
ORDER  BY time_waited DESC;
```

#### Tình huống — Library Cache Latch
> **Triệu chứng:** `latch: library cache` hoặc `library cache lock` cao bất thường.  
> **Phân tích:** Thường do **hard parse** quá nhiều (SQL không dùng bind variables).  
> **Hướng xử lý:**  
> 1. Buộc dùng bind variables trong code  
> 2. Tăng `cursor_sharing = FORCE` (giải pháp tạm, có side effects)  
> 3. Tăng `shared_pool_size` nếu thực sự thiếu memory

#### Tình huống — Cache Buffers Chains Latch
> **Triệu chứng:** `latch: cache buffers chains` cao, thường đi kèm với hot blocks.  
> **Phân tích:** Một block được đọc quá nhiều đồng thời (small table full scan, index root block).  
> **Hướng xử lý:** Tăng `db_block_size`, partitioning, hoặc reverse key index.

---

<a name="cluster-3"></a>
## CLUSTER 3 — MEMORY TUNING
### (Section 21, 22, 23, 24)

---

### Section 21 — Shared Pool Tuning

#### Khái niệm cốt lõi
- **Shared Pool** = Library Cache + Dictionary Cache + Result Cache + ...
- **Library Cache**: Lưu parsed SQL, execution plans
- **Hard Parse**: Parse lần đầu (tốn CPU, cần latch)
- **Soft Parse**: Tìm thấy SQL đã parse trong cache (nhanh hơn)
- **Pin hit ratio**: % lần find trong library cache

```sql
-- Library cache hit ratio
SELECT SUM(pins) pins, SUM(reloads) reloads,
       ROUND((1 - SUM(reloads)/SUM(pins))*100,2) hit_ratio
FROM   v$librarycache;

-- Hard parse ratio
SELECT s1.value hard_parses, s2.value total_parses,
       ROUND(s1.value/NULLIF(s2.value,0)*100,2) hard_pct
FROM   v$sysstat s1, v$sysstat s2
WHERE  s1.name = 'parse count (hard)'
AND    s2.name = 'parse count (total)';

-- Free memory trong shared pool
SELECT name, bytes/1024/1024 mb_free
FROM   v$sgastat
WHERE  pool = 'shared pool'
AND    name = 'free memory';

-- Xem cache cursor parameters
SHOW PARAMETER session_cached_cursors;
SHOW PARAMETER open_cursors;

-- Server Result Cache usage
SELECT name, value FROM v$result_cache_statistics;
```

#### Tình huống — Shared Pool Fragmentation
> **Triệu chứng:** `ORA-04031: unable to allocate X bytes of shared memory`  
> **Phân tích:** Shared pool bị fragmented dù tổng free memory còn đủ.  
> **Hướng xử lý:**  
> 1. `ALTER SYSTEM FLUSH SHARED_POOL` (tạm thời, ảnh hưởng performance)  
> 2. Dùng `DBMS_SHARED_POOL.KEEP` để pin các objects quan trọng  
> 3. Tăng `shared_pool_size` hoặc bật AMM/ASMM  
> 4. Sử dụng bind variables để giảm unique SQL

---

### Section 22 — Buffer Cache & Smart Flash Cache

#### Khái niệm cốt lõi
- **Buffer Cache**: Lưu data blocks đọc từ disk vào memory
- **LRU List**: Quản lý block nào bị đẩy ra khi đầy
- **Buffer Cache Hit Ratio** = 1 - (physical reads / logical reads)
- **Smart Flash Cache** (Oracle 11g): Dùng SSD làm Level 2 cache

```sql
-- Buffer cache hit ratio
SELECT 1 - (phy.value / (cur.value + con.value)) hit_ratio
FROM   v$sysstat phy, v$sysstat cur, v$sysstat con
WHERE  phy.name = 'physical reads'
AND    cur.name = 'db block gets'
AND    con.name = 'consistent gets';

-- DB Cache Advice
SELECT size_for_estimate mb, estd_physical_reads,
       ROUND(estd_physical_reads/
             (SELECT value FROM v$sysstat WHERE name='physical reads')
             * 100, 1) pct_of_current
FROM   v$db_cache_advice
WHERE  block_size = (SELECT value FROM v$parameter WHERE name='db_block_size')
AND    advice_status = 'ON'
ORDER  BY size_for_estimate;

-- Hot objects trong buffer cache
SELECT o.object_name, o.object_type, COUNT(*) blocks_in_cache
FROM   v$bh b, dba_objects o
WHERE  b.objd = o.data_object_id
GROUP  BY o.object_name, o.object_type
ORDER  BY COUNT(*) DESC
FETCH  FIRST 20 ROWS ONLY;
```

#### Tình huống
> **Triệu chứng:** Buffer cache hit ratio thấp (< 90%), physical reads cao.  
> **Phân tích:** Dùng `V$DB_CACHE_ADVICE` xem nếu tăng cache size thì physical reads giảm bao nhiêu %.  
> **Hướng xử lý:** Nếu curve trong cache advice còn dốc → tăng `db_cache_size`. Nếu đã phẳng → vấn đề là query design (full scans không cần thiết).

---

### Section 23 — PGA Tuning

#### Khái niệm cốt lõi
- **PGA** (Program Global Area): Memory riêng của mỗi server process
- Dùng cho: Sort, Hash Join, Bitmap operations
- **One-pass**: Xử lý trong 1 lần đọc disk (chấp nhận được)
- **Multi-pass**: Phải đọc disk nhiều lần (rất tệ)

```sql
-- PGA aggregate stats
SELECT name, value/1024/1024 mb
FROM   v$pgastat
WHERE  name IN ('aggregate PGA target parameter',
                'aggregate PGA auto target',
                'total PGA allocated',
                'cache hit percentage');

-- Workarea performance
SELECT operation_type, policy,
       estd_optimal_executions,
       estd_onepass_executions,
       estd_multipasses_executions
FROM   v$sql_workarea_histogram;

-- PGA Advice
SELECT pga_target_for_estimate/1024/1024 mb_estimate,
       estd_pga_cache_hit_percentage hit_pct,
       estd_overalloc_count
FROM   v$pga_target_advice
ORDER  BY pga_target_for_estimate;
```

#### Tình huống
> **Triệu chứng:** Queries dùng sort/hash join chậm, temp tablespace I/O cao.  
> **Phân tích:** Kiểm tra `V$PGASTAT` — nếu `cache hit percentage` < 90% và có multi-pass executions → PGA thiếu.  
> **Hướng xử lý:** Tăng `pga_aggregate_target` hoặc `pga_aggregate_limit`. Dùng `V$PGA_TARGET_ADVICE` để estimate giá trị tối ưu.

---

### Section 24 — Redo Path Tuning

#### Khái niệm cốt lõi
- **Redo Log Buffer** → **Log Writer (LGWR)** → **Online Redo Log Files**
- **Log File Sync**: User commit phải chờ LGWR flush buffer ra disk
- **Log File Parallel Write**: LGWR ghi ra nhiều members đồng thời

```sql
-- Redo-related wait events
SELECT event, total_waits, time_waited/100 seconds
FROM   v$system_event
WHERE  event IN ('log file sync', 'log file parallel write',
                 'log buffer space')
ORDER  BY time_waited DESC;

-- Redo log configuration
SELECT l.group#, l.members, l.bytes/1024/1024 mb, l.status,
       lf.member
FROM   v$log l JOIN v$logfile lf ON l.group# = lf.group#;

-- Redo generation rate
SELECT name, value
FROM   v$sysstat
WHERE  name LIKE 'redo%';
```

#### Tình huống
> **Triệu chứng:** `log file sync` wait cao, commits chậm.  
> **Phân tích:** LGWR không flush kịp khi nhiều commits đồng thời.  
> **Hướng xử lý:**  
> 1. Chuyển redo logs sang SSD (hoặc dedicated disk)  
> 2. Tăng kích thước redo log groups  
> 3. Sử dụng **COMMIT WRITE BATCH NOWAIT** cho batch operations  
> 4. Nhóm nhiều DML vào một transaction (giảm số commits)

---

<a name="cluster-4"></a>
## CLUSTER 4 — STORAGE & OBJECT TUNING
### (Section 25, 26, 27, 28, 29, 30, 31)

---

### Section 25 — CPU Bottleneck Detection

```sql
-- CPU-heavy SQLs
SELECT sql_id, executions, cpu_time/1e6 cpu_sec,
       ROUND(cpu_time/elapsed_time*100,1) cpu_pct
FROM   v$sql
WHERE  cpu_time > 0
ORDER  BY cpu_time DESC
FETCH  FIRST 10 ROWS ONLY;

-- OS CPU từ AWR
SELECT snap_id, value
FROM   dba_hist_osstat
WHERE  stat_name = 'BUSY_TIME'
ORDER  BY snap_id;
```

#### Tình huống
> **Triệu chứng:** CPU 100%, DB bình thường về waits.  
> **Phân tích:** Khi waits thấp nhưng CPU cao → **CPU-bound workload**. Tìm SQL có high CPU time.  
> **Hướng xử lý:** Optimize execution plans (indexes, rewrites), giảm hard parses, kiểm tra parallel query settings.

---

### Section 26 — Disk I/O Tuning

```sql
-- I/O per datafile
SELECT f.name, s.phyrds, s.phywrts,
       s.readtim/NULLIF(s.phyrds,0) avg_read_ms
FROM   v$filestat s JOIN v$datafile f ON s.file# = f.file#
ORDER  BY s.readtim DESC;

-- I/O wait events
SELECT event, total_waits, time_waited
FROM   v$system_event
WHERE  wait_class = 'User I/O'
ORDER  BY time_waited DESC;
```

#### Tình huống
> **Triệu chứng:** `db file sequential read` hoặc `db file scattered read` cao.  
> **Sequential read** → single block reads → index scans → kiểm tra index quality  
> **Scattered read** → multiblock reads → full table scans → cân nhắc thêm indexes hoặc partitioning

---

### Section 27 — Index Defragmentation

#### Khái niệm cốt lõi
- Index bị fragmented do DELETE, UPDATE → nhiều empty blocks
- **Blevel** (Branch Level): Chiều sâu B-tree, nên ≤ 4
- **Del_lf_rows_len**: Số bytes deleted nhưng chưa reuse

```sql
-- Phân tích tình trạng index
ANALYZE INDEX idx_orders VALIDATE STRUCTURE;

SELECT name, height, blocks, lf_rows, del_lf_rows,
       ROUND(del_lf_rows/NULLIF(lf_rows,0)*100,2) pct_deleted
FROM   index_stats;

-- Rebuild index
ALTER INDEX idx_orders REBUILD ONLINE;

-- Coalesce (nhẹ hơn, không lock)
ALTER INDEX idx_orders COALESCE;
```

#### Tình huống
> **Triệu chứng:** Index scans chậm dù index tồn tại và đúng columns.  
> **Phân tích:** `del_lf_rows` > 20% → index fragmented.  
> **Hướng xử lý:** `ALTER INDEX ... REBUILD ONLINE` (không downtime). Lên kế hoạch rebuild định kỳ cho bảng có nhiều DML.

---

### Section 28 — Row Migration & Row Chaining

#### Khái niệm cốt lõi
- **Row Migration**: Row bị dịch chuyển sang block khác khi UPDATE làm tăng kích thước, để lại pointer ở block cũ
- **Row Chaining**: Row quá lớn (> 1 block), bị tách qua nhiều blocks
- Cả hai đều gây thêm I/O

```sql
-- Detect migrated/chained rows
ANALYZE TABLE orders LIST CHAINED ROWS INTO chained_rows;

SELECT COUNT(*) FROM chained_rows WHERE table_name = 'ORDERS';

-- Fix migration: Export/Import hoặc MOVE TABLE
ALTER TABLE orders MOVE;
-- Sau khi MOVE phải rebuild indexes
ALTER INDEX idx_orders REBUILD;

-- Phòng ngừa: tuning PCTFREE
-- PCTFREE=20 để lại 20% không gian trong block cho UPDATEs
ALTER TABLE orders PCTFREE 20;
```

---

### Section 29 — Table Fragmentation

```sql
-- Phân tích fragmentation
ANALYZE TABLE orders COMPUTE STATISTICS;

SELECT table_name, blocks, empty_blocks,
       ROUND(empty_blocks/(blocks+empty_blocks)*100,2) pct_empty
FROM   dba_tables
WHERE  table_name = 'ORDERS';

-- Segment Advisor
EXEC DBMS_ADVISOR.QUICK_TUNE(
    DBMS_ADVISOR.SQLACCESS_ADVISOR, 'SEG_ADVISOR_TASK',
    'SELECT * FROM orders');

-- Shrink (online, không lock lâu)
ALTER TABLE orders ENABLE ROW MOVEMENT;
ALTER TABLE orders SHRINK SPACE;
ALTER TABLE orders DISABLE ROW MOVEMENT;
```

---

### Section 30 — Table Compression

#### Các loại compression

| Loại | Mô tả | License |
|------|-------|---------|
| **Basic Compression** | Nén khi Direct Load | Standard |
| **OLTP Compression** | Nén cả DML thông thường | Advanced Compression |
| **Hybrid Columnar** | Nén + In-Memory | In-Memory option |

```sql
-- Tạo bảng với OLTP compression
CREATE TABLE orders_compressed
  COMPRESS FOR OLTP
AS SELECT * FROM orders;

-- Đánh giá tỷ lệ nén
SELECT table_name, blocks, num_rows,
       ROUND(blocks*8192/NULLIF(num_rows,0)) avg_bytes_per_row
FROM   dba_tables
WHERE  table_name IN ('ORDERS', 'ORDERS_COMPRESSED');

-- Compression Advisor
EXEC DBMS_COMPRESSION.GET_COMPRESSION_RATIO(
    scratchtbsname => 'USERS', ownname => 'SOE',
    tabname => 'ORDERS', partname => NULL,
    comptype => DBMS_COMPRESSION.COMP_FOR_OLTP,
    blkcnt_cmp => :blkcnt_cmp, blkcnt_uncmp => :blkcnt_uncmp,
    row_cmp => :row_cmp, row_uncmp => :row_uncmp,
    cmp_ratio => :cmp_ratio, comptype_str => :comptype_str);
```

---

### Section 31 — In-Memory Column Store

#### Khái niệm cốt lõi
- **IM Column Store**: Lưu data theo cột trong SGA → cực nhanh cho analytics
- Không thay thế buffer cache (row format) — song song tồn tại
- **IMCU** (In-Memory Compression Unit): Đơn vị lưu trữ columnar

```sql
-- Bật In-Memory
ALTER SYSTEM SET inmemory_size = 2G SCOPE=SPFILE;

-- Load table vào In-Memory
ALTER TABLE orders INMEMORY;
ALTER TABLE orders INMEMORY PRIORITY CRITICAL; -- tự động populate

-- Kiểm tra trạng thái
SELECT segment_name, inmemory_size, bytes, populate_status
FROM   v$im_segments;

-- Force populate
EXEC DBMS_INMEMORY.POPULATE('SOE', 'ORDERS');
```

#### Tình huống
> **Triệu chứng:** Analytics queries (aggregations, full scans) chậm dù đã tune indexes.  
> **Hướng xử lý:** Load table vào IM Column Store. Columnar format + SIMD vectorization → tốc độ analytics tăng 10-100x.

---

<a name="cluster-5"></a>
## CLUSTER 5 — ADVANCED TOOLS & OS
### (Section 32, 34, 35, 36)

---

### Section 32 — Database Connection Optimization

#### Connection Pooling Strategies

| Loại | Mô tả | Khi dùng |
|------|-------|---------|
| **Dedicated** | 1 process/connection | Ít connections, batch jobs |
| **Shared Server** | Nhiều users share processes | Nhiều idle connections |
| **Connection Pool** (DRCP) | Pool tại database tier | Middle-tier apps |
| **Application Pool** | Pool tại app tier | Web applications |

```sql
-- Kiểm tra connection stats
SELECT server, COUNT(*) sessions
FROM   v$session
WHERE  type = 'USER'
GROUP  BY server;

-- DRCP (Database Resident Connection Pooling)
EXEC DBMS_CONNECTION_POOL.START_POOL();
EXEC DBMS_CONNECTION_POOL.CONFIGURE_POOL(
    pool_name => 'SYS_DEFAULT_CONNECTION_POOL',
    minsize => 4, maxsize => 40, incrsize => 2,
    session_cached_cursors => 20, inactivity_timeout => 300);

-- Xem pool stats
SELECT num_open_servers, num_busy_servers, num_requests
FROM   v$cpool_stats;
```

---

### Section 34 — OS Performance (Linux, OSWatcher)

#### Tools quan trọng

| Tool | Mục đích |
|------|---------|
| `top` / `htop` | CPU và memory real-time |
| `vmstat` | CPU, memory, swap, I/O tổng quan |
| `iostat` | Disk I/O per device |
| `sar` | Historical OS stats |
| `OSWatcher` | Oracle tool collect OS stats liên tục |

```bash
# CPU và Memory
vmstat 5 10        # 10 lần, mỗi 5 giây

# Disk I/O
iostat -x 5 10     # extended stats

# OSWatcher start
$ORACLE_BASE/oswatcher/startOSWbb.sh 30 48  # interval=30s, retain=48h
```

#### Tình huống
> **Triệu chứng:** DB slow nhưng không tìm thấy vấn đề bên trong Oracle.  
> **Hướng xử lý:** Kiểm tra OS level — swap usage, CPU steal time (virtualization), disk await time. OSWatcher lưu lịch sử để phân tích sau incident.

---

### Section 35 — SQL Performance Analyzer (SPA)

#### Khái niệm cốt lõi
- SPA test impact của thay đổi (patch, parameter, upgrade) lên SQL workload
- Workflow: Capture SQL Tuning Set → Test Before → Apply Change → Test After → Compare

```sql
-- Bước 1: Tạo SQL Tuning Set
EXEC DBMS_SQLTUNE.CREATE_SQLSET('MY_STS');
EXEC DBMS_SQLTUNE.LOAD_SQLSET(
    sqlset_name => 'MY_STS',
    populate_cursor => dbms_sqltune.select_workload_repository(100, 120));

-- Bước 2: Tạo SPA Task
VAR task_name VARCHAR2(30);
EXEC :task_name := DBMS_SQLPA.CREATE_ANALYSIS_TASK(
    sqlset_name => 'MY_STS', task_name => 'SPA_TASK');

-- Bước 3: Execute trial TRƯỚC thay đổi
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
    task_name => 'SPA_TASK',
    execution_type => 'TEST EXECUTE',
    execution_name => 'BEFORE_CHANGE');

-- (Apply change here)

-- Bước 4: Execute trial SAU thay đổi
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
    task_name => 'SPA_TASK',
    execution_type => 'TEST EXECUTE',
    execution_name => 'AFTER_CHANGE');

-- Bước 5: Compare
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
    task_name => 'SPA_TASK',
    execution_type => 'COMPARE PERFORMANCE',
    execution_name => 'COMPARISON');

-- Xem kết quả
SELECT * FROM TABLE(DBMS_SQLPA.REPORT_ANALYSIS_TASK('SPA_TASK'));
```

#### Tình huống
> **Kịch bản:** Sắp upgrade Oracle từ 19c lên 21c, lo ngại SQL regression.  
> **Hướng xử lý:**  
> 1. Capture production SQL Tuning Set  
> 2. Test trên DB 21c với SPA  
> 3. Identify SQLs bị regression  
> 4. Tạo SQL Plan Baseline cho các SQLs đó trước khi upgrade

---

### Section 36 — Database Replay

#### Khái niệm cốt lõi
- Capture toàn bộ workload production → Replay trên test environment
- Mục đích: Test upgrade, patch, hardware change với workload thực
- Khác SPA: Replay toàn bộ concurrency, timing, dependencies

```sql
-- Capture (trên Production)
EXEC DBMS_WORKLOAD_CAPTURE.START_CAPTURE(
    name => 'PROD_CAPTURE_01',
    dir  => 'CAPTURE_DIR',
    duration => 3600);  -- 1 giờ

EXEC DBMS_WORKLOAD_CAPTURE.FINISH_CAPTURE();

-- Preprocessing (trên Test)
EXEC DBMS_WORKLOAD_REPLAY.PROCESS_CAPTURE('CAPTURE_DIR');

-- Replay (trên Test)
EXEC DBMS_WORKLOAD_REPLAY.INITIALIZE_REPLAY(
    replay_name => 'REPLAY_01', replay_dir => 'CAPTURE_DIR');

EXEC DBMS_WORKLOAD_REPLAY.START_REPLAY();

-- Phân tích kết quả
SELECT * FROM dba_workload_replays ORDER BY id DESC;
SELECT * FROM dba_workload_replay_divergence;
```

---

<a name="scenarios"></a>
## TÌNH HUỐNG THỰC TẾ TỔNG HỢP

---

### Scenario 1: "DB chậm đột ngột" — Quy trình chẩn đoán từ đầu

```
Bước 1: Thu thập thông tin ban đầu
  ├── Hỏi: Khi nào bắt đầu? Tất cả users hay một số?
  ├── Check V$SESSION → có blocking sessions không?
  └── Check OS: CPU, memory, disk I/O

Bước 2: Top-level diagnosis
  ├── V$SYS_TIME_MODEL → DB Time có tăng bất thường không?
  ├── V$SYSTEM_EVENT → Top wait events là gì?
  └── V$ACTIVE_SESSION_HISTORY → SQL nào đang gây tải?

Bước 3: Drill down theo wait event
  ├── Lock waits (enq: TX) → V$LOCK → tìm blocking session
  ├── I/O waits (db file * read) → V$FILESTAT → datafile nào?
  ├── Latch waits → V$LATCH → hard parse hay hot block?
  └── Log waits (log file sync) → redo log I/O performance

Bước 4: Xác nhận và fix
  └── AWR report (nếu sự cố đã qua) → so sánh với baseline
```

---

### Scenario 2: Chuẩn bị cho maintenance window

```
Trước maintenance:
  1. Tạo AWR snapshot thủ công (baseline "before")
  2. Capture SQL Tuning Set (cho SPA)
  3. Ghi lại top 10 SQLs theo elapsed time

Sau maintenance:
  1. Tạo AWR snapshot thủ công (baseline "after")
  2. Chạy SPA compare
  3. So sánh AWR report before/after
  4. Monitor V$ACTIVE_SESSION_HISTORY 30 phút đầu
```

---

### Scenario 3: Tối ưu hóa query đặc thù

```
Triệu chứng: Query report chạy 30 phút, trước đây 5 phút

Điều tra:
  1. V$SQL → tìm sql_id của query
  2. DBMS_SQLTUNE.REPORT_SQL_MONITOR → xem execution plan hiện tại
  3. V$SQL_PLAN → so sánh plan với lịch sử trong AWR
  4. Kiểm tra statistics: DBA_TAB_STATS_HISTORY → thay đổi khi nào?

Xử lý:
  Option A: Statistics stale → DBMS_STATS.GATHER_TABLE_STATS
  Option B: Plan regression → tạo SQL Plan Baseline với plan cũ
  Option C: Index fragmented → ALTER INDEX REBUILD
  Option D: Data skew → histogram collection
```

---

### Scenario 4: Memory pressure

```
Triệu chứng: Paging/swapping trên OS, DB chậm, ORA-04031

Điều tra:
  1. OS: vmstat → si/so (swap in/out) > 0 là vấn đề
  2. V$SGASTAT → shared pool free memory
  3. V$PGASTAT → total PGA allocated vs target
  4. V$PARAMETER → SGA_MAX_SIZE, PGA_AGGREGATE_TARGET

Xử lý theo nguyên nhân:
  A. Shared Pool ORA-04031:
     - Flush (tạm): ALTER SYSTEM FLUSH SHARED_POOL
     - Dài hạn: enforce bind variables, tăng shared_pool_size

  B. PGA over-allocation:
     - Giảm pga_aggregate_target hoặc limit sessions
     - Tìm sessions dùng PGA nhiều: V$PROCESS → PGA_USED_MEM

  C. Buffer Cache thiếu:
     - DB Cache Advice: V$DB_CACHE_ADVICE
     - Xem curve còn dốc không → tăng db_cache_size
```

---

### Scenario 5: Trước khi upgrade Oracle Database

```
Chuẩn bị (4-8 tuần trước):
  1. Capture AWR Baselines cho peak hours
  2. Build SQL Tuning Set từ production workload
  3. Capture Database Replay workload

Test trên môi trường mới:
  1. Chạy SPA với SQL Tuning Set → identify regressions
  2. Replay Database Capture → compare divergence
  3. Fix regressions: SQL Plan Baselines, hints

Sau upgrade:
  1. Monitor ASH chặt chẽ 48h đầu
  2. So sánh AWR với pre-upgrade baselines
  3. Sẵn sàng rollback nếu critical regression
```

---

<a name="quiz"></a>
## QUIZ TỔNG HỢP — 50 CÂU HỎI

### Phần A — Chẩn đoán & Giám sát (15 câu)

**1.** `V$SYS_TIME_MODEL.DB_TIME` bao gồm những gì?  
*(a) Chỉ CPU time của Oracle processes*  
*(b) CPU time + Wait time của user calls*  
*(c) Tất cả CPU time trên server*  
*(d) Chỉ foreground process time*  
**→ Đáp án: (b)**

**2.** AWR snapshot mặc định chụp mỗi bao lâu và giữ trong bao lâu?  
*(a) 30 phút / 7 ngày*  
*(b) 60 phút / 8 ngày*  
*(c) 15 phút / 30 ngày*  
*(d) 60 phút / 30 ngày*  
**→ Đáp án: (b)**

**3.** View nào cho phép truy vấn lịch sử wait events của sessions đã kết thúc?  
*(a) V$SESSION_WAIT*  
*(b) V$SESSION_EVENT*  
*(c) DBA_HIST_ACTIVE_SESS_HISTORY*  
*(d) V$ACTIVE_SESSION_HISTORY*  
**→ Đáp án: (c)** — V$ASH chỉ có in-memory, DBA_HIST_ASH có historical data

**4.** Sự khác biệt chính giữa AWR và Statspack là gì?  
**→ Đáp án:** AWR yêu cầu Diagnostics Pack license (EE), có ASH và ADDM tích hợp. Statspack miễn phí, chạy trên Standard Edition nhưng không có ASH/ADDM.

**5.** ADDM tự động chạy vào thời điểm nào?  
*(a) Mỗi giờ theo DBMS_JOB*  
*(b) Sau mỗi AWR snapshot*  
*(c) Khi CPU > 80%*  
*(d) Mỗi đêm lúc 22:00*  
**→ Đáp án: (b)**

**6.** Để trace SQL của một end-user cụ thể qua connection pool, bạn dùng gì?  
**→ Đáp án:** `DBMS_SESSION.SET_IDENTIFIER` để set client_id, sau đó `DBMS_MONITOR.CLIENT_ID_TRACE_ENABLE`.

**7.** `V$ACTIVE_SESSION_HISTORY` sample dữ liệu theo tần suất nào?  
*(a) Mỗi 10 giây*  
*(b) Mỗi 1 giây*  
*(c) Mỗi 5 giây*  
*(d) Mỗi phút*  
**→ Đáp án: (b)**

**8.** Khi nào nên dùng `V$SQL_MONITOR` thay vì xem explain plan thông thường?  
**→ Đáp án:** Khi cần xem execution plan đang chạy trong real-time với số liệu thực tế (actual rows, actual time) — đặc biệt hữu ích cho long-running queries và parallel execution.

**9.** Automated Maintenance Task nào có thể đề xuất SQL Profile?  
*(a) Auto Optimizer Stats Collection*  
*(b) Auto Segment Advisor*  
*(c) Auto SQL Tuning Advisor*  
*(d) ADDM*  
**→ Đáp án: (c)**

**10.** View nào dùng để xem danh sách alerts đang active (chưa resolved)?  
**→ Đáp án:** `DBA_OUTSTANDING_ALERTS`

**11.** `DBMS_APPLICATION_INFO.SET_MODULE` vs `DBMS_SESSION.SET_IDENTIFIER` — khác nhau gì?  
**→ Đáp án:** SET_MODULE đặt tên module/action cho toàn application tier (nhóm workload). SET_IDENTIFIER đặt client identifier để track end-user cụ thể qua connection pool.

**12.** Hard parse khác soft parse như thế nào? Vấn đề của hard parse nhiều là gì?  
**→ Đáp án:** Hard parse = parse lần đầu, phải build execution plan, tốn CPU, cần exclusive latch. Soft parse = tìm thấy SQL đã parse trong library cache. Hard parse nhiều → library cache latch contention, CPU spike, ORA-04031.

**13.** Bạn muốn xem top SQL đã chạy trong khoảng 8-9 giờ sáng qua. View/table nào bạn query?  
**→ Đáp án:** `DBA_HIST_SQLSTAT` (join với `DBA_HIST_SNAPSHOT` để lọc theo thời gian).

**14.** `log file sync` wait event cho biết điều gì?  
**→ Đáp án:** User sessions đang chờ LGWR flush redo log buffer ra disk khi COMMIT. Cao khi redo log I/O chậm hoặc quá nhiều commits nhỏ.

**15.** Để compare performance trước và sau khi tăng `sga_target`, bạn dùng công cụ nào?  
**→ Đáp án:** AWR baselines — tạo baseline trước thay đổi, so sánh AWR report sau thay đổi với baseline.

---

### Phần B — Contention (5 câu)

**16.** Câu lệnh nào tìm root blocker trong một blocking chain?  
**→ Đáp án:**
```sql
SELECT sid, blocking_session FROM v$session
WHERE blocking_session IS NULL
AND sid IN (
    SELECT blocking_session FROM v$session
    WHERE blocking_session IS NOT NULL);
```

**17.** `latch: cache buffers chains` thường do nguyên nhân gì?  
**→ Đáp án:** Hot blocks — một số blocks được nhiều sessions đọc đồng thời (small lookup tables full scan, index root/branch blocks trên high-DML tables).

**18.** Sự khác biệt giữa Latch và Mutex trong Oracle là gì?  
**→ Đáp án:** Latch là low-level serialization cơ chế cũ, sử dụng spin lock và sleep. Mutex (Oracle 10g+) nhẹ hơn, granular hơn (per-object thay vì per-cache), giảm contention. Mutex đã thay thế latch cho library cache operations.

**19.** Khi thấy `enq: TX - row lock contention` cao, bước đầu tiên là gì?  
**→ Đáp án:** Query `V$SESSION` với `blocking_session IS NOT NULL` và `V$LOCK` để identify root blocker. Tìm SQL đang chạy của blocking session.

**20.** Nếu không thể dùng bind variables (legacy code), có thể set parameter nào để giảm hard parse?  
**→ Đáp án:** `CURSOR_SHARING = FORCE` — Oracle tự động thay thế literals bằng system-generated bind variables. Có thể ảnh hưởng plan quality trong một số trường hợp.

---

### Phần C — Memory Tuning (10 câu)

**21.** Library cache hit ratio bao nhiêu là chấp nhận được?  
*(a) > 80%*  
*(b) > 90%*  
*(c) > 95%*  
*(d) > 99%*  
**→ Đáp án: (c)** — < 95% cần điều tra

**22.** `ORA-04031` xảy ra khi nào? Nguyên nhân thường gặp?  
**→ Đáp án:** Khi Oracle không thể cấp phát memory trong shared pool. Thường do: shared pool fragmentation (nhiều unique SQL), shared pool quá nhỏ, không dùng bind variables.

**23.** `DBMS_SHARED_POOL.KEEP` dùng để làm gì?  
**→ Đáp án:** Pin (giữ) một object (package, procedure, cursor) trong shared pool để không bị aged out, giảm reloads và hard parse khi object được gọi thường xuyên.

**24.** Buffer cache hit ratio < 90% luôn có nghĩa là cần tăng buffer cache không?  
**→ Đáp án:** Không. Cần kiểm tra `V$DB_CACHE_ADVICE` — nếu curve đã phẳng thì tăng cache không giúp được. Vấn đề có thể là unnecessary full table scans cần được giải quyết ở query level.

**25.** Khi nào nên dùng Multiple Buffer Pools (KEEP, RECYCLE)?  
**→ Đáp án:** KEEP pool: cho small, frequently accessed tables/indexes để pin chúng, không bị LRU aging. RECYCLE pool: cho large objects chỉ dùng một lần (full scans) để không ảnh hưởng main pool.

**26.** Sự khác biệt giữa `ONE-PASS` và `MULTI-PASS` trong PGA workarea là gì?  
**→ Đáp án:** ONE-PASS: dữ liệu vừa không fit memory nhưng chỉ cần 1 lần đọc từ temp (chấp nhận được). MULTI-PASS: phải đọc temp nhiều lần (rất tệ, cần tăng PGA). Target: tất cả operations là OPTIMAL hoặc tối thiểu ONE-PASS.

**27.** Tham số nào kiểm soát tổng PGA tự động trong Oracle?  
*(a) PGA_MAX_SIZE*  
*(b) PGA_AGGREGATE_TARGET*  
*(c) WORKAREA_SIZE_POLICY*  
*(d) SORT_AREA_SIZE*  
**→ Đáp án: (b)** — cùng với WORKAREA_SIZE_POLICY = AUTO

**28.** `session_cached_cursors` vs `open_cursors` — khác nhau thế nào?  
**→ Đáp án:** `open_cursors`: số cursor tối đa một session có thể mở cùng lúc. `session_cached_cursors`: số parsed cursor được cache trong session memory (soft close) để soft parse lần sau — giảm cả số parse call vào shared pool.

**29.** Khi `log file sync` cao, một giải pháp application-level là gì?  
**→ Đáp án:** Gom nhiều DML vào một transaction trước khi COMMIT (batch commits), hoặc dùng `COMMIT WRITE BATCH NOWAIT` cho operations không cần synchronous durability.

**30.** Server Result Cache khác Client Query Cache thế nào?  
**→ Đáp án:** Server Result Cache lưu kết quả query trong shared pool, tất cả sessions dùng chung. Client Query Cache lưu ở OCI client tier cho một ứng dụng cụ thể. Server Result Cache tốt cho deterministic queries, invalidated tự động khi underlying data thay đổi.

---

### Phần D — Storage & Object (10 câu)

**31.** Blevel của index bao nhiêu là cần rebuild?  
*(a) > 3*  
*(b) > 4*  
*(c) > 5*  
*(d) > 2*  
**→ Đáp án: (b)** — Blevel > 4 thường là dấu hiệu cần rebuild

**32.** Khác nhau giữa `ALTER INDEX REBUILD` và `ALTER INDEX COALESCE`?  
**→ Đáp án:** REBUILD tạo lại index hoàn toàn (có thể ONLINE), giải quyết cả height và fragmentation. COALESCE chỉ merge adjacent leaf blocks, không giảm height, không yêu cầu thêm space, ít resource hơn.

**33.** Row migration xảy ra khi nào? Ảnh hưởng gì đến performance?  
**→ Đáp án:** Xảy ra khi UPDATE làm row lớn hơn không fit block hiện tại, Oracle di chuyển row sang block khác nhưng giữ pointer ở vị trí cũ. Ảnh hưởng: mỗi lần đọc row cần thêm 1 I/O để follow pointer → tăng `db file sequential read`.

**34.** Sau khi chạy `ALTER TABLE orders MOVE`, tại sao phải rebuild indexes?  
**→ Đáp án:** MOVE thay đổi physical ROWIDs của tất cả rows. Index entries vẫn trỏ đến ROWIDs cũ → indexes bị unusable (UNUSABLE status). Phải `ALTER INDEX ... REBUILD` để update ROWIDs.

**35.** `SHRINK SPACE` vs `MOVE` — khi nào dùng cái nào?  
**→ Đáp án:** SHRINK: online, ít downtime, giữ indexes valid (cần ROW MOVEMENT). MOVE: offline (hoặc online 12c+), gom contiguous space, cần rebuild indexes. Dùng SHRINK cho production OLTP, MOVE cho maintenance window.

**36.** Compression Advisor (`DBMS_COMPRESSION`) cho biết gì?  
**→ Đáp án:** Ước tính tỷ lệ nén đạt được (`cmp_ratio`) cho các compression types khác nhau mà không cần thực sự compress toàn bộ bảng. Giúp quyết định có nên compress và chọn loại compression phù hợp.

**37.** In-Memory Column Store có thay thế Buffer Cache không?  
**→ Đáp án:** Không. Cả hai song song tồn tại. Buffer Cache lưu row format cho OLTP. IM Column Store lưu columnar format cho analytics. Oracle tự chọn format phù hợp theo loại query.

**38.** Khi nào nên dùng Basic Compression vs OLTP Compression?  
**→ Đáp án:** Basic: chỉ nén khi direct path load (INSERT /*+ APPEND */, SQL*Loader direct). Tốt cho data warehouse load. OLTP: nén cả conventional DML (INSERT, UPDATE). Tốt cho transactional tables nhưng tốn thêm CPU.

**39.** Phân biệt Row Chaining vs Row Migration?  
**→ Đáp án:** Row Chaining: row quá lớn (> 1 block size) → span nhiều blocks ngay từ đầu, không thể tránh. Row Migration: row lớn dần do UPDATE → di chuyển sang block khác, có thể phòng tránh bằng PCTFREE phù hợp.

**40.** `INMEMORY PRIORITY CRITICAL` khác gì `INMEMORY PRIORITY NONE`?  
**→ Đáp án:** CRITICAL: Oracle tự động populate vào IM Column Store ngay sau database open (background). NONE: chỉ populate khi object được access lần đầu (on-demand).

---

### Phần E — Advanced Tools (10 câu)

**41.** Database Replay khác SQL Performance Analyzer ở điểm gì?  
**→ Đáp án:** SPA test impact lên SQL statements riêng lẻ. DB Replay replay toàn bộ workload với đúng concurrency, timing, và dependencies giữa các sessions — cho kết quả realistic hơn khi test upgrade/migration.

**42.** Khi chạy SPA, `execution_type => 'EXPLAIN PLAN'` vs `'TEST EXECUTE'` khác gì?  
**→ Đáp án:** EXPLAIN PLAN chỉ generate execution plans (nhanh, không cần chạy SQL). TEST EXECUTE thực sự chạy SQLs và thu thập runtime statistics (chính xác hơn nhưng tốn tài nguyên).

**43.** DRCP (Database Resident Connection Pooling) giải quyết vấn đề gì?  
**→ Đáp án:** Cho phép nhiều mid-tier clients dùng chung pool of database server processes, giảm số dedicated processes khi có nhiều connections idle (web apps có nhiều connections nhưng ít concurrent activity).

**44.** OSWatcher thu thập dữ liệu gì? Lưu ở đâu?  
**→ Đáp án:** CPU (mpstat, top), memory (vmstat), disk I/O (iostat), network (netstat). Lưu dạng compressed files theo thời gian trong `$ORACLE_BASE/oswatcher/archive/`. Dùng OSwatcher Analyzer (OSWbba) để visualize.

**45.** Khi Database Replay divergence cao, điều đó nghĩa là gì?  
**→ Đáp án:** Nhiều replay calls trả về kết quả khác với capture (data divergence) hoặc gặp errors không có trong capture (error divergence). Cần investigate divergence report để xác định impact.

**46.** Một DBA sắp thay đổi `optimizer_features_enable` parameter. Cần làm gì TRƯỚC khi thay đổi?  
**→ Đáp án:**  
1. Capture SQL Tuning Set từ production workload  
2. Chạy SPA trial với setting hiện tại (BEFORE)  
3. Apply thay đổi parameter  
4. Chạy SPA trial với setting mới (AFTER)  
5. Compare và review regressions

**47.** Shared Server (MTS) giải quyết vấn đề gì? Khi nào KHÔNG nên dùng?  
**→ Đáp án:** Shared Server giảm memory footprint khi có nhiều idle connections (nhiều dedicated processes tốn memory). Không nên dùng cho: batch jobs dài, operations cần dedicated PGA lớn (sort/hash join lớn), DDL operations.

**48.** Sau khi chụp Database Replay capture, tại sao cần chạy `PROCESS_CAPTURE` trước khi replay?  
**→ Đáp án:** PROCESS_CAPTURE tiền xử lý raw capture files — chuẩn hóa external references (SCNs, timestamps, user IDs) để phù hợp với target environment, tạo replay metadata mà Replay Clients cần.

**49.** SQL Tuning Set (STS) là gì? Khác gì với AWR?  
**→ Đáp án:** STS là tập hợp SQL statements cùng execution context (plans, statistics, bind variables) được lưu trữ explicitly. AWR lưu toàn bộ historical database data. STS có thể được export/import để di chuyển giữa DBs, dùng làm input cho SPA, SQL Tuning Advisor.

**50.** Trong tình huống production đang gặp vấn đề, bạn muốn identify top 5 SQL đang gây tải nhất ngay lúc này. Query nào nhanh nhất?  
**→ Đáp án:**
```sql
SELECT sql_id, COUNT(*) active_samples
FROM   v$active_session_history
WHERE  sample_time > SYSDATE - 5/1440   -- 5 phút gần nhất
AND    sql_id IS NOT NULL
GROUP  BY sql_id
ORDER  BY active_samples DESC
FETCH  FIRST 5 ROWS ONLY;
```

---

<a name="reference"></a>
## BẢNG THAM CHIẾU NHANH

### Views & Tables theo chủ đề

| Chủ đề | View / Table | Mô tả |
|--------|-------------|-------|
| **Time Model** | `V$SYS_TIME_MODEL` | DB Time, CPU, parse time (system) |
| | `V$SESS_TIME_MODEL` | Theo từng session |
| **Wait Events** | `V$SYSTEM_EVENT` | Tổng hợp từ startup |
| | `V$SESSION_EVENT` | Theo session hiện tại |
| | `V$SESSION_WAIT` | Đang wait ngay lúc này |
| **ASH** | `V$ACTIVE_SESSION_HISTORY` | In-memory (vài giờ) |
| | `DBA_HIST_ACTIVE_SESS_HISTORY` | Historical (AWR) |
| **AWR** | `DBA_HIST_SNAPSHOT` | Danh sách snapshots |
| | `DBA_HIST_SQLSTAT` | Historical SQL stats |
| | `DBA_HIST_OSSTAT` | OS statistics history |
| **ADDM** | `DBA_ADVISOR_TASKS` | ADDM task list |
| | `DBA_ADVISOR_FINDINGS` | ADDM findings |
| **Alerts** | `DBA_OUTSTANDING_ALERTS` | Active alerts |
| | `DBA_ALERT_HISTORY` | Alert history |
| **Locks** | `V$LOCK` | Lock information |
| | `V$SESSION` | Session blocking info |
| **Latches** | `V$LATCH` | Latch stats |
| | `V$LATCH_CHILDREN` | Child latch stats |
| **Shared Pool** | `V$SGASTAT` | SGA component sizes |
| | `V$LIBRARYCACHE` | Library cache hits |
| | `V$SQL` | SQL in library cache |
| **Buffer Cache** | `V$BH` | Buffer header details |
| | `V$DB_CACHE_ADVICE` | Cache size advice |
| **PGA** | `V$PGASTAT` | PGA aggregate stats |
| | `V$SQL_WORKAREA` | Workarea per SQL |
| | `V$PGA_TARGET_ADVICE` | PGA sizing advice |
| **I/O** | `V$FILESTAT` | I/O per datafile |
| | `V$TEMPSTAT` | I/O per temp file |
| **SQL Monitor** | `V$SQL_MONITOR` | Real-time SQL monitor |
| | `V$SQL_PLAN_MONITOR` | Plan step monitor |
| **Maintenance** | `DBA_AUTOTASK_CLIENT` | Auto task status |
| | `DBA_SCHEDULER_WINDOWS` | Maintenance windows |
| **Indexes** | `INDEX_STATS` | After ANALYZE INDEX |
| | `DBA_INDEXES` | Index metadata |
| **Tables** | `DBA_TABLES` | Table stats (blocks, rows) |
| | `CHAINED_ROWS` | Row migration/chaining |
| **In-Memory** | `V$IM_SEGMENTS` | IM population status |
| **Connection** | `V$SESSION` | Session details |
| | `V$CPOOL_STATS` | DRCP pool stats |

### DBMS Packages quan trọng

| Package | Chức năng chính |
|---------|----------------|
| `DBMS_WORKLOAD_REPOSITORY` | Quản lý AWR (snapshot, baseline, report) |
| `DBMS_ADDM` | Chạy ADDM thủ công |
| `DBMS_MONITOR` | Enable/disable SQL tracing |
| `DBMS_APPLICATION_INFO` | Set module/action cho instrumentation |
| `DBMS_SESSION` | Set client identifier, session properties |
| `DBMS_SQLTUNE` | SQL Tuning Advisor, SQL Monitor report |
| `DBMS_SQLPA` | SQL Performance Analyzer |
| `DBMS_WORKLOAD_CAPTURE` | Database Replay capture |
| `DBMS_WORKLOAD_REPLAY` | Database Replay replay |
| `DBMS_STATS` | Thu thập optimizer statistics |
| `DBMS_COMPRESSION` | Compression Advisor |
| `DBMS_INMEMORY` | In-Memory population control |
| `DBMS_SHARED_POOL` | Pin objects trong shared pool |
| `DBMS_AUTO_TASK_ADMIN` | Bật/tắt automated maintenance tasks |
| `DBMS_SERVER_ALERT` | Set thresholds cho server alerts |
| `DBMS_CONNECTION_POOL` | Configure DRCP |

---

*Tài liệu này được tổng hợp từ 28/29 sections của khóa học Oracle Database Performance Tuning — Packt Publishing.*  
*Cập nhật lần cuối: 2026-04-21*


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/claude_review.md`
