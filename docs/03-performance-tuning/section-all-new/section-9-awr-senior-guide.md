---
title: Section 9 — AWR (Automatic Workload Repository) — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_9_awr_senior_guide.md
---

# Section 9 — AWR (Automatic Workload Repository) — Deep Dive for Senior DBA

---

# OUTPUT 1 — LECTURE NOTES

## 1. Mental Model

AWR giải quyết đúng limitation mà Section 8 để lộ: V$ views là volatile, cumulative từ startup, không có time dimension. AWR là một **performance data warehouse nhúng trong Oracle** — không phải "logging" thêm vào, mà là sampling có kiến trúc riêng với persistence, retention policy, và indexing. Cách frame đúng: khi bạn nhìn `DBA_HIST_*`, bạn đang query các delta snapshot của V$ views, được MMON chụp định kỳ và flush vào SYSAUX. Hiểu cơ chế này là hiểu tại sao AWR data có độ trễ, tại sao nó bỏ sót sự kiện ngắn, và tại sao interval setting là một trong những quyết định quan trọng nhất trong AWR management.

---

## 2. Internals & Mechanics

### MMON — The AWR Engine

AWR không phải một feature bật/tắt — nó chạy qua background process **MMON** (Manageability Monitor) và slave process **MMNL** (MMON Lite):

- **MMON** wakes mỗi `INTERVAL` phút, kiểm tra xem có cần chụp snapshot không
- **MMNL** thực sự thực hiện snapshot capture — flush data từ X$ fixed tables vào WRH$_* tables trong SYSAUX
- MMON cũng chạy ADDM tự động sau mỗi snapshot pair (Section 12)
- Khi MMNL đang chạy, có thể thấy trong `V$SESSION` với `PROGRAM = 'oracle@host (MMNL)'`

### Data Path: V$ → DBA_HIST_*

```
SGA (in-memory)
    │
    ├── X$ fixed tables (kernel memory structures)
    │       │
    │       └── V$ views (virtual views over X$)
    │                   │ (snapshot at interval)
    │                   ▼
    └── MMNL process flushes delta to:
            WRH$_SYSTEM_EVENT     → DBA_HIST_SYSTEM_EVENT
            WRH$_SYSSTAT          → DBA_HIST_SYSSTAT
            WRH$_SQL_PLAN         → DBA_HIST_SQL_PLAN
            WRH$_SQLSTAT          → DBA_HIST_SQLSTAT
            WRH$_ACTIVE_SESS_HISTORY → DBA_HIST_ACTIVE_SESS_HISTORY
            ...
            WRM$_SNAPSHOT         → DBA_HIST_SNAPSHOT (metadata)
```

Naming convention: `WRH$_*` = historical data tables, `WRM$_*` = repository metadata, `WRI$_*` = internal AWR infrastructure.

### SNAP_LEVEL: TYPICAL vs ALL

| Level | Trigger | Thêm so với TYPICAL |
|-------|---------|---------------------|
| 1 (TYPICAL) | Default / STATISTICS_LEVEL=TYPICAL | Standard statistics set |
| 2 (ALL) | `FLUSH_LEVEL=>'ALL'` / STATISTICS_LEVEL=ALL | OS timed statistics + **row source execution stats** từ `V$SQL_PLAN_STATISTICS_ALL` |

Level 2 quan trọng vì cho phép AWR SQL Report hiển thị per-row-source execution statistics — cần thiết khi debugging execution plan regressions. Cost: snapshot chạy lâu hơn, data volume lớn hơn.

### TOPNSQL — Ít người để ý, hay gây vấn đề

TOPNSQL xác định **số lượng top SQL statements** được capture vào `DBA_HIST_SQLSTAT` mỗi snapshot, ranked theo 5 criteria: elapsed time, CPU time, buffer gets, disk reads, parse calls. Default = 30 (per criteria, per snapshot).

**Production reality:** Hệ thống OLTP với 5000+ distinct SQL statements chạy mỗi giờ → top 30 per criteria theo một snapshot có thể bỏ sót SQL quan trọng. Trong incident window, set `TOPNSQL = MAXIMUM` (capture tất cả eligible SQL) rồi reset về sau.

### SYSTEM_MOVING_WINDOW Baseline

Đây là baseline tự động Oracle duy trì, luôn cover đúng `RETENTION` days từ thời điểm hiện tại. Không thể manually modify. Mục đích chính: cung cấp dữ liệu cho **Adaptive Threshold** trong Server-generated Alerts (Section 10). Oracle dùng statistics trong moving window để tự động tính ngưỡng cảnh báo thay vì hardcode.

### CDB/PDB Consideration (12c+)

Trên Oracle 12c–18c: AWR chỉ tồn tại ở **CDB root level**. PDB statistics được aggregate vào root. Senior DBA không thể generate PDB-specific AWR report riêng.

Từ Oracle **19c**: có `AWR_PDB_AUTOFLUSH_ENABLED` parameter — khi set TRUE ở PDB level, Oracle capture AWR data riêng cho PDB. `@?/rdbms/admin/awrrpt.sql` khi connected vào PDB sẽ generate PDB-scoped report.

---

## 3. Production Realities

**Interval 60 phút là quá thô cho OLTP troubleshooting.** Một performance incident kéo dài 20 phút trong interval 60 phút sẽ bị diluted: data bị trộn với 40 phút trước và sau issue. Standard practice: 15 phút cho critical OLTP, 30 phút cho hầu hết systems. Trade-off: SYSAUX growth ~2–4x so với 60-minute default.

**SYSAUX sizing — rough formula:**

```
Daily AWR growth (MB) ≈ (Active Sessions) × (Metrics per session) × (24 × 60 / INTERVAL) × row_size / 1024
```

Thực tế đơn giản hơn: chạy `@?/rdbms/admin/awrinfo.sql` sau khi hệ thống đã chạy 1 tuần, xem "Estimated Weekly Growth". Nhân với 4 để ước tính tháng, đặt SYSAUX datafile với autoextend đủ cho RETENTION × monthly_growth.

**Optimizer statistics retention (SM/OPTSTAT) thường chiếm nhiều hơn AWR (SM/AWR)** trên hệ thống già. Default 31 ngày optstat retention là quá dài — không có use case thực tế nào cần flash back optimizer stats về hơn 7 ngày trước. Giảm xuống 7 ngày trước khi lo về AWR data.

**Baseline templates unreliable — author nói thẳng trong Practice 7.** Dùng Oracle Scheduler job thay thế:

```sql
-- Thay baseline template bằng scheduler job
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'CAPTURE_OLTP_BASELINE',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
      DECLARE
        l_begin  NUMBER := (SELECT MAX(SNAP_ID)-1 FROM DBA_HIST_SNAPSHOT);
        l_end    NUMBER := (SELECT MAX(SNAP_ID) FROM DBA_HIST_SNAPSHOT);
      BEGIN
        DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(
          start_snap_id => l_begin,
          end_snap_id   => l_end,
          baseline_name => 'OLTP_' || TO_CHAR(SYSDATE,'YYYYMMDD_HH24MI'),
          expiration    => 365);
      END;]',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=WEEKLY;BYDAY=MON;BYHOUR=8;BYMINUTE=0',
    enabled         => TRUE);
END;
/
```

**AWR report reading order — không phải top-to-bottom.** Senior DBA đọc theo priority:
1. **Top 10 Foreground Events** — xác định wait class chủ đạo
2. **Wait Classes by Total Wait Time** — confirm distribution
3. **Load Profile** — DB Time/sec, Hard Parses/sec, Logical Reads/sec
4. **Instance Efficiency** — nếu top events gợi ý library cache issue
5. **Top SQL by...** section tương ứng với wait class đã xác định

**DB Time / CPU Time ratio:** Nếu `DB Time ≈ num_cpus × Elapsed Time`, đây là CPU-saturated workload. Nếu `DB Time >> num_cpus × Elapsed Time`, workload bị dominated bởi waits. Công thức này từ AWR header giúp phân loại ngay lập tức.

**AWR data không tự di chuyển khi clone database.** Khi làm Data Guard failover test hay RMAN clone, DBA_HIST_* data của primary không có trong standby (nếu standby là physical) hoặc bị reset (logical standby). Cho post-mortem trên clone: phải dùng `DBMS_SWRF_INTERNAL.AWR_EXTRACT` / `AWR_LOAD` để transport AWR data.

---

## 4. Decision Framework

### Chọn AWR Tool theo use case

| Tình huống | Tool | Script |
|-----------|------|--------|
| System-wide performance window | AWR Report | `awrrpt.sql` |
| So sánh healthy vs faulty period | AWR Compare Report | `awrddrpt.sql` |
| SQL statement history + plan changes | AWR SQL Report | `awrsqrpt.sql` |
| SYSAUX space planning | AWR Info Report | `awrinfo.sql` |
| Query AWR data programmatically | DBA_HIST_* direct | Custom SQL |

### Interval Sizing

| Scenario | Recommended Interval | Reasoning |
|---------|---------------------|-----------|
| Critical OLTP (banking, telco) | 15 min | Issues often < 30 min duration |
| General OLTP | 30 min | Balances granularity vs space |
| Batch / warehouse | 60 min | Issues are longer-duration |
| Post-incident investigation | Manual snapshots | Supplement auto snapshots |

### Retention Sizing

| Need | Minimum Retention |
|------|------------------|
| Weekly pattern analysis | 10 days |
| Monthly trend analysis | 35 days |
| Quarterly capacity planning | 95 days |
| Regulatory / audit | Per policy (up to 1 year, use baselines) |

### Anti-patterns

- **❌ Tạo manual snapshot không label** — sau 3 ngày không nhớ snapshot đó capture cái gì; tạo baseline ngay nếu snapshot quan trọng
- **❌ TOPNSQL mặc định trong incident window** — top 30 SQL quá ít; set MAXIMUM rồi reset
- **❌ Dùng baseline templates** — unreliable; dùng Scheduler job
- **❌ Delete manual snapshot ngay sau dùng** — nếu cần re-analyze sau này phải recreate workload; giữ lại ít nhất 1 tuần
- **❌ Chỉ đọc AWR report top-to-bottom** — mất thời gian; đọc theo priority (Foreground Events trước)

---

## 5. Key SQL / Commands

### AWR Delta cho Wait Events — Điều V$SYSTEM_EVENT không làm được

```sql
-- Delta wait events giữa 2 snapshots cụ thể
-- Đây là core query mà AWR report dùng internally
SELECT
    e.EVENT_NAME,
    e.WAIT_CLASS,
    (e.TOTAL_WAITS     - b.TOTAL_WAITS)                    delta_waits,
    ROUND((e.TIME_WAITED_MICRO - b.TIME_WAITED_MICRO)/1e6, 2) delta_sec,
    ROUND(
        (e.TIME_WAITED_MICRO - b.TIME_WAITED_MICRO) /
        NULLIF((e.TOTAL_WAITS - b.TOTAL_WAITS), 0) / 1000, 2
    )                                                       avg_wait_ms
FROM DBA_HIST_SYSTEM_EVENT e
JOIN DBA_HIST_SYSTEM_EVENT b
    ON  e.EVENT_NAME  = b.EVENT_NAME
    AND e.DBID        = b.DBID
    AND e.INSTANCE_NUMBER = b.INSTANCE_NUMBER
    AND e.SNAP_ID     = &end_snap
    AND b.SNAP_ID     = &begin_snap
WHERE e.WAIT_CLASS <> 'Idle'
  AND e.TIME_WAITED_MICRO > b.TIME_WAITED_MICRO
ORDER BY delta_sec DESC
FETCH FIRST 15 ROWS ONLY;
```

> Đây chính xác là bài toán Section 8 không giải được: TWO thời điểm cụ thể, không phải cumulative từ startup.

### SQL Performance Regression Detection

```sql
-- SQL statements có elapsed time tăng đột ngột giữa 2 snapshot windows
-- Useful để detect plan regression sau stats gathering hoặc patch
SELECT
    s1.SQL_ID,
    s1.PLAN_HASH_VALUE,
    ROUND(s1.ELAPSED_TIME_TOTAL/1e6 / NULLIF(s1.EXECUTIONS_TOTAL, 0), 3) avg_sec_current,
    ROUND(s0.ELAPSED_TIME_TOTAL/1e6 / NULLIF(s0.EXECUTIONS_TOTAL, 0), 3) avg_sec_baseline,
    ROUND(
        (s1.ELAPSED_TIME_TOTAL/NULLIF(s1.EXECUTIONS_TOTAL,0)) /
        NULLIF(s0.ELAPSED_TIME_TOTAL/NULLIF(s0.EXECUTIONS_TOTAL,0), 0), 2
    )                                                                       regression_ratio,
    s1.EXECUTIONS_TOTAL                                                     exec_count
FROM DBA_HIST_SQLSTAT s1
JOIN DBA_HIST_SQLSTAT s0
    ON s1.SQL_ID = s0.SQL_ID
    AND s1.DBID = s0.DBID
WHERE s1.SNAP_ID BETWEEN &issue_begin AND &issue_end
  AND s0.SNAP_ID BETWEEN &normal_begin AND &normal_end
  AND s1.EXECUTIONS_TOTAL >= 10
  AND s1.ELAPSED_TIME_TOTAL/NULLIF(s1.EXECUTIONS_TOTAL,0) >
      s0.ELAPSED_TIME_TOTAL/NULLIF(s0.EXECUTIONS_TOTAL,0) * 2  -- 2x regression threshold
ORDER BY regression_ratio DESC
FETCH FIRST 20 ROWS ONLY;
```

### AWR Settings Audit + Space Projection

```sql
-- Settings hiện tại + SYSAUX usage by component
SELECT
    w.SNAP_INTERVAL,
    w.RETENTION,
    w.TOPNSQL,
    ROUND(a.SPACE_USAGE_KBYTES/1024, 1)  awr_mb,
    ROUND(o.SPACE_USAGE_KBYTES/1024, 1)  optstat_mb,
    (SELECT COUNT(*) FROM DBA_HIST_SNAPSHOT)  total_snapshots
FROM DBA_HIST_WR_CONTROL w
CROSS JOIN (SELECT SPACE_USAGE_KBYTES FROM V$SYSAUX_OCCUPANTS WHERE OCCUPANT_NAME='SM/AWR') a
CROSS JOIN (SELECT SPACE_USAGE_KBYTES FROM V$SYSAUX_OCCUPANTS WHERE OCCUPANT_NAME='SM/OPTSTAT') o;
```

### Snapshot Inventory — Xem khoảng trống hoặc restart

```sql
-- Phát hiện gap trong AWR snapshots (restart hoặc snapshot failure)
SELECT
    s1.SNAP_ID,
    s1.END_INTERVAL_TIME,
    s2.BEGIN_INTERVAL_TIME,
    ROUND((s2.BEGIN_INTERVAL_TIME - s1.END_INTERVAL_TIME) * 24 * 60, 1) gap_minutes,
    s2.STARTUP_TIME  -- restart nếu khác s1
FROM DBA_HIST_SNAPSHOT s1
JOIN DBA_HIST_SNAPSHOT s2 ON s2.SNAP_ID = s1.SNAP_ID + 1
                          AND s2.DBID = s1.DBID
                          AND s2.INSTANCE_NUMBER = s1.INSTANCE_NUMBER
WHERE (s2.BEGIN_INTERVAL_TIME - s1.END_INTERVAL_TIME) * 24 * 60 > 90  -- gap > 1.5x interval
ORDER BY s1.SNAP_ID;
```

---

## 6. Senior Checklist

- [ ] **STATISTICS_LEVEL**: verify TYPICAL minimum; nếu cần row source execution stats cho SQL plan analysis → set ALL (SCOPE=BOTH, không chỉ MEMORY)
- [ ] **Interval ≤ 30 phút**: 60-minute default quá coarse cho OLTP; tính SYSAUX growth trước khi commit
- [ ] **TOPNSQL**: tăng lên MAXIMUM trong incident window; reset về 30 sau; script này nên trong runbook
- [ ] **SYSAUX monitoring**: đặt alert ở 80% full; kiểm tra SM/OPTSTAT trước SM/AWR — thường optstat lớn hơn và dễ thu nhỏ hơn
- [ ] **Baseline creation**: create baseline ngay sau khi confirm "normal period" — đừng đợi; một khi snapshot bị purge thì mất
- [ ] **CDB/PDB**: trên 19c+ confirm `AWR_PDB_AUTOFLUSH_ENABLED` = TRUE nếu cần PDB-level AWR report
- [ ] **Snapshot gaps**: query inventory sau restart hoặc MMON issue — gap trong AWR data làm AWR compare report vô nghĩa nếu không biết

---
---

# OUTPUT 2 — LAB EXERCISES

# Lab: AWR — Hands-on for Senior DBA

## Lab Overview
- **Mục tiêu:** Build production-grade AWR management workflow; implement delta analysis mà V$ views không làm được; develop AWR report reading strategy
- **Môi trường:** Oracle 12c–19c / non-CDB hoặc CDB (note CDB considerations khi applicable)
- **Thời gian ước tính:** 60–90 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — AWR Configuration Audit & Right-sizing

### Scenario
Bạn vừa join một team mới. Database này đã chạy 3 năm, SYSAUX đang ở 87% full, monitoring đã trigger alert. DBA cũ không để lại runbook. `DBA_HIST_WR_CONTROL` shows: INTERVAL=60, RETENTION=35 days, TOPNSQL=30. `V$SYSAUX_OCCUPANTS` shows SM/AWR=42GB, SM/OPTSTAT=38GB.

### Tasks
1. Audit current AWR configuration: assess xem INTERVAL và RETENTION có phù hợp với workload pattern không (hint: check `DBA_HIST_SNAPSHOT` để xem có bao nhiêu snapshots/day và gap nào không)
2. Tính projected SYSAUX growth nếu giảm INTERVAL xuống 30 phút mà giữ RETENTION 35 days. Công thức: `new_size ≈ current_AWR_size × (60/new_interval)`
3. Propose và implement một configuration change plan: phải resolve SYSAUX issue mà không mất historical data quan trọng
4. Implement SM/OPTSTAT reduction: giảm retention từ default xuống 7 ngày, purge dữ liệu cũ. Ước tính space được giải phóng trước khi chạy purge

### Expected Findings
- Giảm OPTSTAT retention giải phóng 60–80% SM/OPTSTAT space ngay lập tức (38GB → ~8GB)
- Điều này thường giải quyết SYSAUX crisis mà không cần chạm vào AWR retention
- Nếu giảm INTERVAL: RETENTION phải giảm tương ứng để giữ footprint tương đương

### Debrief Questions
- Tại sao giảm AWR RETENTION trước khi giảm OPTSTAT retention là sai thứ tự ưu tiên?
- Hệ quả của SYSAUX 100% full là gì? (Hint: không chỉ ảnh hưởng AWR)

---

## Exercise 2 — Delta Analysis: Implementing What Section 8 Couldn't

### Scenario
Operations team báo cáo: database chậm mỗi ngày thứ Hai 09:00–10:00 (batch job chạy). Bạn đã có AWR snapshots cho thứ Hai vừa rồi (snap_id 1240–1244, covering 08:00–10:00). Bạn cũng có snapshots cho thứ Năm bình thường (snap_id 1180–1184, cùng time window). Cần xác định wait event nào thay đổi nhiều nhất giữa thứ Năm và thứ Hai.

### Tasks
1. Implement delta query trên `DBA_HIST_SYSTEM_EVENT` cho 2 window snapshots trên. Calculate: delta_waits, delta_seconds, avg_wait_ms, percentage của DB Time
2. Implement delta query trên `DBA_HIST_SYSSTAT` cho cùng 2 windows: focus vào statistics liên quan đến top 3 wait events từ bước 1 (ví dụ: nếu top wait là `log file sync` → look at `user commits`, `redo writes`; nếu là `db file sequential read` → look at `physical reads`, `consistent gets`)
3. Dùng `DBA_HIST_SQLSTAT` để identify top 5 SQL statements trong window thứ Hai theo `ELAPSED_TIME_TOTAL`, cùng với `PLAN_HASH_VALUE` và execution count. So sánh với thứ Năm để xem có SQL nào mới xuất hiện không
4. Generate AWR Compare Report (`awrddrpt.sql`) cho cùng 2 windows. So sánh kết quả của script với kết quả query thủ công của bạn

### Expected Findings
- Direct query trên `DBA_HIST_*` và AWR report phải cho cùng top events (minor formatting differences)
- Batch job thường gây: tăng `db file sequential read` hoặc `direct path read` tùy plan, tăng `log file sync` nếu heavy DML
- SQL mới xuất hiện trong batch window thường là culprit

### Debrief Questions
- Tại sao AWR Compare Report đòi hỏi "cùng elapsed time" mới cho meaningful comparison?
- `DBA_HIST_SYSTEM_EVENT.TIME_WAITED_MICRO` có accuracy cao hơn `TIME_WAITED` (centiseconds) — khi nào điều này actually matters trong real analysis?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Production OLTP database, Oracle 19c, 24-CPU NUMA (2 sockets × 12 cores), 192GB RAM, AWR interval 30 minutes. Thứ Sáu 15:30: users bắt đầu báo cáo application timeout. Incident kéo dài 47 phút, tự recover lúc 16:17. On-call DBA chỉ kịp tạo manual snapshot lúc 15:45 (snap_id 8831), ngoài ra có auto snapshots tại 15:30 (8829) và 16:00 (8832). Không có deployment hay maintenance trong ngày.

### Evidence Provided

**AWR Report: snap 8829–8832 (15:30–16:00, 30 min)**

```
Load Profile                               Per Second     Per Transaction
~~~~~~~~~                                  ----------     ---------------
DB Time(s):                                     24.3              0.22
DB CPU(s):                                      21.8              0.20
Logical reads:                              84,234.1            762.4
Block changes:                               4,112.3             37.2
Physical reads:                                891.2              8.1
Executes:                                    3,892.1             35.2
Hard parses:                                     2.3
Transactions:                                  110.4

Instance Efficiency Percentages
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Buffer Nowait %:  99.97       Redo NoWait %:  100.00
Buffer  Hit   %:  98.94       In-memory Sort %:  100.00
Library Hit   %:  99.98       Soft Parse %:    99.94
Execute to Parse %: 84.21     Latch Hit %:     99.99
Parse CPU to Parse Elapsed %:  91.23

Top 10 Foreground Events by Total Wait Time
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Event                          Waits     Time(s)  Avg(ms)  % DB Time  Wait Class
------------------------------ --------- -------- -------- ---------- ----------
DB CPU                                    39,240             26.9%
read by other session          234,441    8,412    35.9      5.8%      User I/O
db file sequential read         89,221    2,341     26.2     1.6%      User I/O
log file sync                   44,112    1,892     42.9     1.3%      Commit
cursor: pin S wait on X             441      831  1,882.1    0.6%      Concurrency
```

**Top SQL by CPU Time (trong snap 8829–8832):**
```
SQL_ID         CPU_TIME(s)  EXEC  ELAPSED(s)  PLAN_HASH
-------------- ------------ ----- ----------- ----------
3x4mnp7qq8w1a       31,441   122    31,892    2847291034
8f2kl9mnb3p2q       4,221    44     4,441     1923847102
vn9x2pq1r7t5w       2,112  8,441    2,341     3892014567
```

**SQL Text of 3x4mnp7qq8w1a:**
```sql
SELECT c.CUSTOMER_ID, c.CUSTOMER_NAME,
       SUM(o.ORDER_TOTAL) TOTAL_ORDERS,
       COUNT(DISTINCT p.PRODUCT_ID) DISTINCT_PRODUCTS
FROM CUSTOMERS c
JOIN ORDERS o ON c.CUSTOMER_ID = o.CUSTOMER_ID
JOIN ORDER_ITEMS oi ON o.ORDER_ID = oi.ORDER_ID
JOIN PRODUCTS p ON oi.PRODUCT_ID = p.PRODUCT_ID
WHERE c.REGION_CODE = :b1
GROUP BY c.CUSTOMER_ID, c.CUSTOMER_NAME
ORDER BY TOTAL_ORDERS DESC
```

**V$SQL (lúc 15:47, captured by on-call DBA):**
```
SQL_ID: 3x4mnp7qq8w1a
PLAN_HASH_VALUE: 2847291034
CHILD_NUMBER: 0
LOADS: 1
INVALIDATIONS: 0
EXECUTIONS: 89
ELAPSED_TIME: 23,441,221 microseconds
CPU_TIME: 23,112,441 microseconds
BUFFER_GETS: 4,234,112
ROWS_PROCESSED: 45,221
LAST_ACTIVE_TIME: 15:47:02
```

**DBA_HIST_SQLSTAT cho cùng SQL_ID, snapshot 2 tuần trước (normal Friday):**
```
SNAP_ID: 8571  (Friday same time window)
EXECUTIONS_TOTAL: 98
ELAPSED_TIME_TOTAL: 1,892,441 microseconds (total, not per exec)
CPU_TIME_TOTAL: 1,771,221 microseconds
BUFFER_GETS_TOTAL: 312,441
PLAN_HASH_VALUE: 3910284751   ← DIFFERENT
```

### Your Mission
1. Xác định root cause của incident — cụ thể đến level component/mechanism
2. Explain tại sao `read by other session` chiếm 5.8% DB Time đồng thời với top SQL chiếm 26.9% CPU — hai điều này có liên quan không?
3. `cursor: pin S wait on X` với average 1,882ms là signal gì? Liên quan đến root cause như thế nào?
4. Đề xuất immediate action (trong 15 phút khi incident đang diễn ra) và permanent fix — phải khác nhau rõ ràng
5. Xác định data nào còn thiếu để confirm root cause hoàn toàn — và làm thế nào để capture nó trong lần sau

### Evaluation Criteria
- Root cause phải chỉ đến cụ thể hơn "plan change" — senior sẽ explain tại sao plan thay đổi vào thứ Sáu 15:30 cụ thể (hint: Friday batch + stats gathering schedule là một hypothesis, nhưng không phải duy nhất)
- `read by other session` analysis: phải differentiate giữa "shared buffer pool hot blocks" vs "parallel query slaves racing" — AWR data có đủ để phân biệt không?
- `cursor: pin S wait on X` thường có 2 root causes khác nhau — senior phải name cả hai và assess which is more likely given this evidence
- Immediate action không được là "kill session" — phải có justification và risk assessment
- Missing data: senior checklist phải include ASH (Section 13) và execution plan history (`DBA_HIST_SQL_PLAN`) — hai thứ AWR report không cho thấy đủ

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_9_awr_senior_guide.md`
