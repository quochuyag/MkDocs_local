---
title: 'Section 16 — Real-time Database Operation Monitoring: Deep Dive for Senior DBA'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_16_realtime_monitoring_senior_guide.md
---

# Section 16 — Real-time Database Operation Monitoring: Deep Dive for Senior DBA

---

## OUTPUT 1 — LECTURE NOTES

---

## 1. Mental Model

Real-time SQL Monitoring là live telemetry — không phải audit trail như SQL Trace. SQL Trace (10046) capture mọi execution step post-hoc với synchronous write overhead; V$SQL_MONITOR là in-memory, sub-second sampled, cập nhật bởi chính foreground process đang thực thi SQL — designed for zero-impact production diagnosis. Frame nó như "live HUD on an actively executing SQL": bạn thấy execution plan đang unfold, output rows đang accumulate per plan line, CPU time đang tick — trong khi SQL vẫn đang chạy.

Hai tầng quan trọng: **simple monitoring** (auto-trigger: SQL > 5s CPU+I/O hoặc parallel) và **composite operation monitoring** (DBMS_SQL_MONITOR — gom nhiều SQL thành một named business operation để đo end-to-end throughput). Simple là reactive, zero-config; composite là deliberate instrumentation cho business-level SLA analysis.

---

## 2. Internals & Mechanics

**Auto-trigger threshold**: Oracle đo **cumulative CPU + I/O time**, không phải wall clock. Một query chạy 60 giây nhưng phần lớn là latch waits hoặc enqueue waits sẽ không auto-trigger — CPU+I/O chỉ có 0.5s. Parallel queries bypass threshold hoàn toàn: mọi parallel query đều được monitor bất kể duration vì PX coordinator phải track P_N slaves.

**Pool architecture**: V$SQL_MONITOR là in-memory structure, controlled bởi hidden parameter `_sql_monitor_pool_size` (default ~10% Shared Pool, thường 10–40MB trên standard systems). Eviction policy: LRU — khi pool đầy, oldest DONE/FAILED entry bị overwrite. Critical production implication: incident xảy ra 30 phút trước, DBA investigate sau → entry đã có thể bị evict.

**Composite operation mechanics**: `DBMS_SQL_MONITOR.BEGIN_OPERATION` associate một DBOP_NAME với session bằng cách set session-level attribute. Mọi SQL subsequent trong session đó được tagged `IN_DBOP_NAME`. `FORCED_TRACKING => 'Y'` lower threshold xuống ~0.1s cho individual statements trong operation — nhưng extremely short SQL (< ~100ms như `SELECT SYSDATE FROM DUAL`) vẫn không xuất hiện. [⚠️ verify with MOS: exact minimum threshold with FORCED_TRACKING]

**Status lifecycle**: EXECUTING → DONE/DONE(ERROR). DONE **không** được set ngay khi `END_OPERATION` được gọi — Oracle cần một **round-trip từ client session** để flush session state vào shared memory. Pattern chuẩn: call `SELECT SYSDATE FROM DUAL` trong client session sau `END_OPERATION` để force status update.

**V$SQL_PLAN_MONITOR**: populated per execution plan line, cập nhật mỗi ~1 giây khi SQL đang run. Cột `OUTPUT_ROWS` tăng dần real-time → identify chính xác plan operation nào đang slow. Join với V$SQL_PLAN (static plan metadata) để decode operation names, cardinality estimates, và cost. Cardinality estimate vs actual output rows là diagnostic signal quan trọng nhất.

**Portable report**: `DBMS_SQLTUNE.REPORT_SQL_MONITOR(sql_id => '...', type => 'HTML', report_level => 'ALL')` generate HTML report equivalent với EM Express Save button — accessible via SQL*Plus, critical cho incident documentation trước khi entry bị evict.

---

## 3. Production Realities

**License blocker thường bị bỏ qua**: `CONTROL_MANAGEMENT_PACK_ACCESS = DIAGNOSTIC+TUNING` là licensed option. Oracle **không** throw error nếu bạn query V$SQL_MONITOR mà không có license — bạn nhận data nhưng in compliance violation. Audit trước khi build monitoring dashboards.

**5-second CPU+I/O misunderstanding**: Developer hỏi "tại sao query 8 giây của tôi không có trong V$SQL_MONITOR?" — nếu 7.5s là Concurrency/Application wait events, CPU+I/O chỉ có 0.5s → không trigger. Phân biệt wait class trước khi kết luận monitoring gap.

**Pool eviction race condition**: Trong high-throughput environment với nhiều concurrent long-running queries, pool có thể fill nhanh. Investigation arrives sau khi entry đã bị evict → supplement với `DBA_HIST_ACTIVE_SESS_HISTORY` (AWR SQL Report) cho historical coverage.

**Dangling composite operations**: `BEGIN_OPERATION` không có matching `END_OPERATION` → status = EXECUTING indefinitely. EM Express Monitored SQL hiển thị stale entries gây nhầm lẫn. Pattern này phổ biến khi ứng dụng exception trước khi reach `END_OPERATION` call. Build audit query vào daily monitoring routine.

**RAC complexity**: V$SQL_MONITOR là instance-local. GV$SQL_MONITOR spans instances nhưng composite operation chỉ tracked trên instance của monitored session. Trong RAC, cross-instance GV$ joins cần care về performance overhead.

**11g vs 12c behavioral difference**: Trong 12c+/CDB, V$SQL_MONITOR aggregates across all PDBs. CON_ID column available để filter. In 11g, monitoring pool smaller by default.

---

## 4. Decision Framework

| Công cụ | Dùng khi | Không dùng khi |
|---------|---------|----------------|
| V$SQL_MONITOR | SQL đang chạy > 5s CPU+I/O hoặc parallel; recent completion (< pool retention) | SQL < 5s, bind values cần capture, sub-statement granularity |
| V$SQL_PLAN_MONITOR | Cần biết plan step nào đang slow real-time | Post-hoc plan analysis (dùng AWR SQL Plan) |
| DBMS_SQL_MONITOR composite | Multi-statement business operation, end-to-end SLA measurement | Single SQL; short-lived sessions; pooled connections (session boundary problem) |
| SQL Trace 10046 | Sub-5s SQL, bind value capture, recursive SQL, microsecond timing | Long-running SQL (trace file size), production overhead concern |
| ASH | Historical wait patterns, trendlines, sampling adequate | Real-time plan progress; < 1s granularity needed |

**Anti-patterns**:
- `FORCED_TRACKING => 'Y'` trên production session dài mà không có `END_OPERATION` → pool pressure, stale entries
- Build V$SQL_MONITOR dashboard mà không verify license compliance trước
- Composite monitoring mà không specify `SESSION_ID` + `SESSION_SERIAL` → gom SQL từ wrong sessions trong connection-pooled environments
- Đọc EM Express SQL Monitor và screenshot, quên save HTML report → evidence lost sau eviction

---

## 5. Key SQL / Commands

```sql
-- 1. Verify prerequisites
SHOW PARAMETER STATISTICS_LEVEL              -- phải TYPICAL hoặc ALL
SHOW PARAMETER CONTROL_MANAGEMENT_PACK_ACCESS  -- phải DIAGNOSTIC+TUNING

-- 2. Pool size (hidden param)
SELECT KSPPINM, KSPPSTVL
FROM SYS.X$KSPPI X, SYS.X$KSPPSV Y
WHERE X.INDX = Y.INDX AND KSPPINM = '_sql_monitor_pool_size';

-- 3. Top currently executing SQL by elapsed
SELECT SQL_ID, STATUS, USERNAME,
       ROUND(ELAPSED_TIME/1e6, 1)            ELAPSED_S,
       ROUND(CPU_TIME/1e6, 1)                CPU_S,
       ROUND(PHYSICAL_READ_BYTES/1024/1024)  PHYRD_MB,
       SUBSTR(SQL_TEXT, 1, 60)               SQL_TEXT
FROM V$SQL_MONITOR
WHERE STATUS = 'EXECUTING'
ORDER BY ELAPSED_TIME DESC;

-- 4. Real-time execution plan progress (repeat để observe OUTPUT_ROWS tăng)
SELECT P.ID,
       RPAD(' ', P.DEPTH*2, ' ') || P.OPERATION || ' ' || P.OPTIONS  OPERATION,
       P.OBJECT_NAME  OBJECT,
       P.CARDINALITY  CARD_EST,   -- optimizer estimate
       M.OUTPUT_ROWS  ACTUAL_OUT, -- actual so far (real-time)
       SUBSTR(M.STATUS, 1, 6)     STATUS,
       ROUND(M.ELAPSED_TIME/1e6, 2) ELAPSED_S
FROM V$SQL_PLAN P, V$SQL_PLAN_MONITOR M
WHERE P.SQL_ID          = M.SQL_ID
  AND P.CHILD_ADDRESS   = M.SQL_CHILD_ADDRESS
  AND P.PLAN_HASH_VALUE = M.SQL_PLAN_HASH_VALUE
  AND P.ID              = M.PLAN_LINE_ID
  AND M.SQL_ID          = '&V_SQL_ID'
ORDER BY P.ID;

-- 5. Audit dangling composite operations
SELECT DBOP_NAME, STATUS, SID, SESSION_SERIAL#,
       ROUND((SYSDATE - LAST_REFRESH_TIME)*24*60) MINS_STALE
FROM V$SQL_MONITOR
WHERE DBOP_NAME IS NOT NULL
  AND STATUS = 'EXECUTING'
ORDER BY LAST_REFRESH_TIME;

-- 6. Portable HTML report (save as incident evidence)
SET LONG 1000000 LONGCHUNKSIZE 100000 PAGESIZE 0 LINESIZE 1000
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id       => '&SQL_ID',
    type         => 'HTML',
    report_level => 'ALL'
) FROM DUAL;

-- 7. Composite operation begin/end template (production-ready)
VARIABLE OP_ID NUMBER;
BEGIN
    :OP_ID := DBMS_SQL_MONITOR.BEGIN_OPERATION(
        DBOP_NAME       => 'BILLING.MONTHLY_CLOSE',
        SESSION_ID      => &SID,
        SESSION_SERIAL  => &SERIAL,
        FORCED_TRACKING => 'Y'
    );
END;
/
-- ... workload ...
BEGIN
    DBMS_SQL_MONITOR.END_OPERATION(
        DBOP_NAME => 'BILLING.MONTHLY_CLOSE',
        DBOP_EID  => :OP_ID
    );
END;
/
SELECT SYSDATE FROM DUAL;  -- client round-trip → force STATUS = DONE
```

---

## 6. Senior Checklist

1. Verify `CONTROL_MANAGEMENT_PACK_ACCESS = DIAGNOSTIC+TUNING` trước khi build monitoring solution — license compliance trước tiên
2. Nắm rõ pool eviction risk: save `DBMS_SQLTUNE.REPORT_SQL_MONITOR` HTML **trong khi SQL đang EXECUTING**, không chờ DONE
3. SQL > 5s wall clock mà không có trong V$SQL_MONITOR → check CPU+I/O time thực tế (V$SQL.ELAPSED_TIME vs CPU_TIME) — query có thể đang wait-heavy
4. Audit dangling `BEGIN_OPERATION` entries định kỳ — orphaned EXECUTING entries mislead capacity và SLA analysis
5. Composite monitoring trong connection-pooled environment: luôn specify `SESSION_ID` + `SESSION_SERIAL` chính xác; không track by username
6. Trong RAC incident, GV$SQL_MONITOR spans instances nhưng filter by INST_ID trước khi join với GV$SQL_PLAN
7. V$SQL_PLAN_MONITOR CARDINALITY_ESTIMATE vs OUTPUT_ROWS divergence là số một signal của plan instability — hữu ích cho cả real-time diagnosis và post-hoc optimizer analysis

---

## OUTPUT 2 — LAB EXERCISES

---

# Lab: Section 16 — Real-time Database Operation Monitoring

## Lab Overview

- **Mục tiêu:** Validate understanding of SQL Monitor auto-trigger conditions, composite operation tracking, và incident evidence capture
- **Môi trường:** Oracle 12c–19c / non-CDB với Diagnostic+Tuning Pack
- **Thời gian ước tính:** 50 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Profiling a Running Parallel Query Without Interruption

### Scenario
14:07 thứ Tư. DBA được escalate: `GV$SESSION` có 12 PX slave processes cho một query của `ANALYTICS_USER` đã chạy 11 phút. User báo "vẫn đang chạy." Business requirement: không được cancel query, không được tạo trace. Bạn phải identify bottleneck trong khi query đang executing.

### Tasks
1. Locate query trong `V$SQL_MONITOR` dựa vào USERNAME và parallel indicator (PX_SERVERS_REQUESTED > 0)
2. Join `V$SQL_PLAN_MONITOR` với `V$SQL_PLAN` để xem OUTPUT_ROWS vs CARDINALITY per plan step
3. Identify plan step có OUTPUT_ROWS diverge nhiều nhất so với CARDINALITY estimate
4. Cross-check với `V$SESSION_WAIT` cho PX slaves: xác định I/O-bound vs CPU-bound

### Expected Findings
- Plan step với OUTPUT_ROWS >> CARDINALITY estimate → optimizer underestimate → wrong join method (NL thay vì hash join) hoặc hash join với insufficient PGA → disk spill
- PX slaves `ON CPU` với CPU_TIME cao → cardinality-driven computation overhead, không phải I/O
- PX slaves `db file scattered read` → full scan, I/O bottleneck → khác hướng xử lý

### Debrief Questions
- Nếu HASH JOIN estimate 1000 rows nhưng actual output 8 million rows: điều này ảnh hưởng gì đến memory allocation (PGA) và likelihood of spill to temp?
- Tại sao parallel queries always auto-trigger monitoring bất kể 5-second threshold?

---

## Exercise 2 — End-to-End Business Operation SLA Instrumentation

### Scenario
E-commerce team muốn biết SQL nào trong `CHECKOUT.ORDER_SUBMIT` pipeline (5 SQL statements trong một stored procedure) chiếm nhiều thời gian nhất. SLA = 300ms. 20% transactions exceed 1 second. DBA quyết định instrument bằng composite monitoring trên một test session để tái hiện pattern.

### Tasks
1. Implement `BEGIN_OPERATION` / `END_OPERATION` wrapper cho test session chạy 5 SQLs tuần tự
2. Query `V$SQL_MONITOR` phân biệt: operation row (DBOP_NAME có value) vs task rows (IN_DBOP_NAME có value)
3. Calculate `ELAPSED_TIME` per SQL và % contribution to total operation elapsed
4. Identify SQL nào không xuất hiện trong monitoring (< 5s threshold) dù có FORCED_TRACKING

### Expected Findings
- Inventory availability check (full scan thiếu index) chiếm 70%+ elapsed nếu bảng lớn
- Short SQL như UPDATE trên indexed column (< 0.1s) không xuất hiện dù FORCED_TRACKING = 'Y'
- Status của operation row vẫn EXECUTING sau END_OPERATION → cần client round-trip để flip to DONE

### Debrief Questions
- `FORCED_TRACKING => 'Y'` không guarantee rằng mọi SQL trong operation đều monitored — threshold tối thiểu vẫn tồn tại. Implications gì cho SLA analysis khi short queries bị miss?
- Trong production với connection pooling (session tái sử dụng), `BEGIN_OPERATION` / `END_OPERATION` phải được placed ở đâu trong application code?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
14:23 thứ Hai. DBA nhận call: "Batch `DAILY_BILLING_CALC` đang chạy 47 phút, SLA = 20 phút." Job là stored procedure với 6 SQL statements sequential. Được trigger bởi DBMS_SCHEDULER.

### Evidence Provided

```
V$SQL_MONITOR (14:31):
SQL_ID        STATUS     ELAPSED_S  CPU_S  PHYRD_MB  SQL_TEXT (first 60 chars)
------------  ---------  ---------  -----  --------  ----------------------------------------
2yxq9fd3mw1r  EXECUTING    487.3    412.1      0.0   SELECT B.ACCOUNT_ID, SUM(C.USAGE_AMOUNT)
3kx7tm8np4a2  DONE          28.4      1.2    324.5   UPDATE BILLING_SUMMARY SET PROCESSED_FLAG
fjw2kbhq9r5p  DONE           2.1      1.9      0.0   SELECT COUNT(*) FROM BILLING_PERIODS ...

V$SESSION for SID running 2yxq9fd3mw1r:
  EVENT           : cursor: pin S wait on X
  WAIT_CLASS      : Concurrency
  SECONDS_IN_WAIT : 2

V$SYS_TIME_MODEL (delta last 30 min):
  hard parse elapsed time   : 1,847 s
  soft parse elapsed time   :   312 s
  DB CPU                    : 3,200 s
```

### Your Mission
1. Identify root cause của `2yxq9fd3mw1r`: 487s CPU + 0 physical reads
2. Explain tại sao `cursor: pin S wait on X` xuất hiện và connect với time model data
3. List missing evidence cần để confirm root cause
4. Propose immediate mitigation (không restart instance) và permanent fix

### Evaluation Criteria
- **Nhận ra pattern**: 487s CPU + 0 physical reads → pure in-memory computation, không phải I/O → likely cartesian product hoặc bad nested loop trên in-memory dataset; NOT a "database I/O issue"
- **Correlate time model**: hard parse 1847s trong 30 phút là bất thường cực kỳ → high literal SQL rate → library cache mutex pressure → `cursor: pin S wait on X` là downstream symptom của hard parse storm, không phải nguyên nhân gốc
- **Missing evidence**: V$SQL cho SQL_ID 2yxq9fd3mw1r (ROWS_PROCESSED, EXECUTIONS, PLAN_HASH_VALUE changes), V$SQL_PLAN để check plan cho 2yxq9fd3mw1r, V$SQLSTAT.FORCE_MATCHING_SIGNATURE count, V$SQLAREA WHERE SQL_TEXT LIKE... để confirm literal pattern
- **Ambiguity recognized**: "cursor: pin S wait on X" có thể do (a) hard parse storm OR (b) DDL/recompile của package. Hard parse 1847s strongly suggests (a) nhưng alert.log cần check cho ORA-04031 (Shared Pool pressure) để rule out (b)
- **Mitigation**: Flush Shared Pool là last resort (makes parse storm worse temporarily) → correct approach: identify offending SQL via `SELECT SQL_TEXT, COUNT(*) FROM V$SQLAREA GROUP BY SQL_TEXT HAVING COUNT(*) > 100` → find literal-heavy query, replace with bind var
- **Business decision**: kill running job (47 min in, unknown % complete) vs let run to completion — answer depends on whether job is idempotent and what "fix" is

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_16_realtime_monitoring_senior_guide.md`
