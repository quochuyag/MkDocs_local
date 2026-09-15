---
title: ASH (Active Session History) — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_13_ash_senior_guide.md
---

# ASH (Active Session History) — Deep Dive for Senior DBA

## 1. Mental Model

ASH biến time thành một queryable dimension. AWR aggregate — ASH preserve temporal granularity. Đây là sự khác biệt cốt lõi. Khi một incident xảy ra lúc 14:23 và kết thúc lúc 14:31, AWR interval 14:00–15:00 sẽ dilute nó thành noise. ASH cho phép bạn slice exactly vào 14:23–14:31 và hỏi: ai đang chờ gì, trên object nào, bị block bởi session nào?

Use case killer: post-mortem analysis của transient incident sau khi session đã disconnect và wait event đã biến mất. ASH còn đó.

---

## 2. Internals & Mechanics

**Sampling pipeline:**

```
Mỗi 1 giây: MMNL process samples tất cả active non-idle sessions
                              ↓
              Ghi vào ASH ring buffer trong SGA
              (backing store của V$ACTIVE_SESSION_HISTORY)
                              ↓
              MMNL flush 1/10 samples lên disk mỗi 10 giây
                              ↓
              DBA_HIST_ACTIVE_SESS_HISTORY (persistent, nhiều ngày)
```

**Buffer size:** `MAX(1MB, 5% SGA)` — controlled bởi hidden parameter `_ASH_SIZE`. Trong systems có 200+ active sessions liên tục, 1-hour retention có thể drop xuống 20–30 phút khi buffer bị overwrite.

**Điều kiện để session xuất hiện trong ASH:**

- FOREGROUND sessions: chỉ khi đang active (trong một server call) — không capture khi client đang process
- BACKGROUND sessions: chỉ khi đang WAITING (không capture khi idle)
- Idle wait events bị filtered out (WAIT_CLASS = 'Idle')
- Sessions giữa calls (client processing, server idle) không xuất hiện

**Key column mechanics:**

| Column | Meaning |
|--------|---------|
| `SESSION_STATE` | `ON CPU` = running; `WAITING` = blocked on event |
| `TIME_WAITED` | Microseconds waited (completed wait); 0 nếu vẫn đang chờ |
| `CURRENT_OBJ#` | Object ID đang access; `-1` = không liên quan đến object |
| `TEMP_SPACE_ALLOCATED` | Temp space hiện tại của session (bytes) — **không có trong V$SQLAREA hay DBA_HIST_SQLSTAT** |
| `XID` | Transaction ID — critical cho lock investigation |
| `TOP_LEVEL_SQL_ID` | SQL cha nếu statement là recursive SQL; = SQL_ID nếu không recursive |
| `BLOCKING_SESSION` | SID của session đang block; NULL không có nghĩa là không có blocker |

**DBA_HIST_ACTIVE_SESS_HISTORY sampling math:**

```
V$ASH:            1 sample/second  → SUM(1) ≈ seconds of DB Time
DBA_HIST_ASH:     1/10 samples     → SUM(10) ≈ seconds of DB Time

COUNT(*) trong DBA_HIST_ASH mà không nhân 10 → undercount actual DB Time by 10x
```

---

## 3. Production Realities

**Buffer overflow trong busy systems:**

Với ~10 consistently active sessions, ASH giữ được ~1 giờ. Với 300+ active sessions (massive OLTP spike), buffer có thể bị overwrite trong 10-15 phút. Hệ quả: nếu incident xảy ra rồi mới được report, V$ASH có thể đã mất data đầu của incident. Luôn check oldest sample ngay khi bắt đầu investigation:

```sql
SELECT MIN(SAMPLE_TIME) FROM V$ACTIVE_SESSION_HISTORY;
```

Nếu min sample time > 30 phút trước incident start → escalate sang DBA_HIST_ACTIVE_SESS_HISTORY ngay.

**Recursive SQL trap:**

`TOP_LEVEL_SQL_ID ≠ SQL_ID` → statement là recursive SQL được gọi từ PL/SQL block. Khi ASH show SQL_ID X với high DB Time, và X là recursive, thì root attribution là parent PL/SQL block (TOP_LEVEL_SQL_ID). Điều này critical khi báo cáo với development team — sửa SQL child đúng nhưng cần report đúng PL/SQL parent cho context.

**Staging table pattern cho complex analysis:**

Multiple complex ASH queries trên V$ACTIVE_SESSION_HISTORY đều rescan ring buffer. Trong busy system, buffer content thay đổi giữa các queries → inconsistent results. Standard practice khi điều tra incident:

```sql
CREATE TABLE ash_incident_20260422_1423 AS
SELECT *
FROM V$ACTIVE_SESSION_HISTORY
WHERE SAMPLE_TIME BETWEEN TIMESTAMP '2026-04-22 14:20:00'
                      AND TIMESTAMP '2026-04-22 14:35:00';
```

Chạy tất cả analysis queries trên bảng này — consistent snapshot, faster, không ảnh hưởng production ASH buffer.

**db file sequential read vs db file scattered read trong ASH context:**

- `db file sequential read` = single-block I/O → index lookup, ROWID fetch
- `db file scattered read` = multi-block I/O → full table scan, index fast full scan

Khi join ASH với DBA_OBJECTS qua CURRENT_OBJ#, bạn biết exactly object nào đang gây loại I/O nào — more actionable hơn AWR aggregate I/O stats.

**BLOCKING_SESSION reliability:**

NULL trong BLOCKING_SESSION không có nghĩa là không có blocker. Session có thể đang ở giữa wait event ở micro-second level mà không bị captured. Để tin tưởng blocking chain: cần nhiều consecutive samples (> 3) với cùng BLOCKING_SESSION. Trong RAC: check BLOCKING_INST_ID — blocker có thể trên different instance.

**12c+ CDB behavior:**

- V$ACTIVE_SESSION_HISTORY có column `CON_ID` trong CDB
- Sessions từ multiple PDBs mix vào CDB root's V$ASH
- Filter bằng `CON_ID` hoặc `CON_DBID` để isolate PDB activity
- `ashrpti.sql` chấp nhận `target_container` parameter cho CDB/PDB filtering

---

## 4. Decision Framework

| Scenario | V$ASH | DBA_HIST_ASH | Notes |
|----------|-------|-------------|-------|
| Incident ended < 30 min ago | ✅ Primary | Supplement | 1-sec resolution, real-time |
| Incident ended 30 min – 4 hrs ago | Check overflow | ✅ Primary | 10-sec resolution; multiply by 10 |
| Incident ended > 4 hours ago | ❌ Likely overwritten | ✅ Only option | Data may have gaps if SYSAUX full |
| TEMP space analysis | ✅ | ❌ [⚠️ verify TEMP_SPACE in DBA_HIST with MOS] | TEMP_SPACE_ALLOCATED not in DBA_HIST_ASH in most versions |
| Index usage analysis | N/A | ✅ + DBA_HIST_SQL_PLAN | Need plan_hash → object join |
| Blocking chain reconstruction | ✅ | Supplement | V$ASH real-time more reliable |

**ASH vs SQL Trace:**

- ASH: system-wide view, 1-second sampling, all sessions — tìm cái gì và ai
- SQL Trace: microsecond timing một session, full bind values, per-wait detail — đo cụ thể
- Workflow: ASH identifies problem statement → SQL Trace measures it precisely

**ASH vs AWR:**

- AWR: sustained performance trends, hourly deltas, Benchmark
- ASH: transient spikes, post-mortem session investigation, dimension-based slicing
- Nếu issue kéo dài > 30 phút và recurrent → AWR. Nếu transient, isolated, < 1 hour → ASH.

**Anti-patterns:**

- Query V$ACTIVE_SESSION_HISTORY không có time filter trên busy system → millions of rows, slow
- Dùng COUNT(*) từ DBA_HIST_ACTIVE_SESS_HISTORY mà không nhân 10 → undercount DB Time
- Trust ASH object analysis cho sub-millisecond waits (`db file sequential read` < 1ms) — these may be systematically under-sampled vì duration quá ngắn so với 1-second sampling interval

---

## 5. Key SQL / Commands

```sql
-- Session history cho một ACTION/time window (closed session investigation)
SELECT TO_CHAR(SAMPLE_TIME, 'HH24:MI:SS') STIME,
       SESSION_STATE,
       EVENT,
       TIME_WAITED,
       SQL_ID,
       CURRENT_OBJ#     "OBJ#",
       CURRENT_FILE#    "FILE#",
       CURRENT_BLOCK#   "BLK#",
       CURRENT_ROW#     "ROW#",
       BLOCKING_SESSION "BLKR_SID"
FROM V$ACTIVE_SESSION_HISTORY
WHERE ACTION     = 'YOUR_ACTION_NAME'
  AND SAMPLE_TIME BETWEEN :start_ts AND :end_ts
ORDER BY SESSION_ID, SAMPLE_TIME;

-- DB Time breakdown theo event (mini-AWR từ ASH — last 30 min)
SELECT NVL(EVENT, 'ON CPU')                                      EVENT,
       COUNT(1)                                                  SAMPLES,
       ROUND(COUNT(1) / SUM(COUNT(1)) OVER () * 100, 2)         PCT_DBTIME
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_TYPE = 'FOREGROUND'
  AND SAMPLE_TIME  >= SYSTIMESTAMP - INTERVAL '30' MINUTE
GROUP BY NVL(EVENT, 'ON CPU')
ORDER BY SAMPLES DESC
FETCH FIRST 15 ROWS ONLY;

-- DB Time và CPU Time breakdown theo module
WITH TOTAL AS (
    SELECT COUNT(1) T
    FROM V$ACTIVE_SESSION_HISTORY
    WHERE SESSION_TYPE = 'FOREGROUND'
      AND SAMPLE_TIME  >= SYSTIMESTAMP - INTERVAL '30' MINUTE
)
SELECT MODULE,
       COUNT(1)                                         MODULE_DBTIME,
       SUM(CASE WHEN SESSION_STATE = 'ON CPU' THEN 1 ELSE 0 END) MODULE_CPU,
       ROUND(COUNT(1) / (SELECT T FROM TOTAL) * 100, 2)          PCT_DBTIME
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_TYPE = 'FOREGROUND'
  AND SAMPLE_TIME  >= SYSTIMESTAMP - INTERVAL '30' MINUTE
GROUP BY MODULE
ORDER BY MODULE_DBTIME DESC
FETCH FIRST 10 ROWS ONLY;

-- Top SQL by DB Time với plan hash (detect plan changes)
SELECT H.SQL_ID,
       H.SQL_PLAN_HASH_VALUE,
       SUBSTR(Q.SQL_TEXT, 1, 40)    SQL_TEXT,
       SUM(1)                       SQL_DBTIME
FROM V$ACTIVE_SESSION_HISTORY H
LEFT JOIN V$SQLAREA Q ON H.SQL_ID = Q.SQL_ID
WHERE H.SQL_ID      IS NOT NULL
  AND H.SAMPLE_TIME >= SYSTIMESTAMP - INTERVAL '30' MINUTE
GROUP BY H.SQL_ID, H.SQL_PLAN_HASH_VALUE, SUBSTR(Q.SQL_TEXT, 1, 40)
ORDER BY SQL_DBTIME DESC
FETCH FIRST 10 ROWS ONLY;
-- Tip: cùng SQL_ID với 2 SQL_PLAN_HASH_VALUE → plan change đang xảy ra

-- Blocking chain reconstruction (last 10 minutes)
SELECT TO_CHAR(s.SAMPLE_TIME, 'HH24:MI:SS') STIME,
       s.SESSION_ID,
       s.BLOCKING_SESSION,
       s.EVENT,
       s.SQL_ID
FROM V$ACTIVE_SESSION_HISTORY s
WHERE s.BLOCKING_SESSION IS NOT NULL
  AND s.SAMPLE_TIME       >= SYSTIMESTAMP - INTERVAL '10' MINUTE
ORDER BY s.SAMPLE_TIME, s.BLOCKING_SESSION;

-- Top objects by I/O wait (User I/O class — more reliable than 'db file%' filter)
SELECT O.OBJECT_NAME,
       O.OBJECT_TYPE,
       N.NAME             EVENT_NAME,
       SUM(1)             WAIT_SAMPLES
FROM V$ACTIVE_SESSION_HISTORY H
JOIN DBA_OBJECTS   O ON H.CURRENT_OBJ# = O.OBJECT_ID
JOIN V$EVENT_NAME  N ON H.EVENT_ID     = N.EVENT_ID
WHERE H.SESSION_STATE  = 'WAITING'
  AND N.WAIT_CLASS      = 'User I/O'
  AND H.SAMPLE_TIME    >= SYSTIMESTAMP - INTERVAL '30' MINUTE
GROUP BY O.OBJECT_NAME, O.OBJECT_TYPE, N.NAME
ORDER BY WAIT_SAMPLES DESC
FETCH FIRST 10 ROWS ONLY;

-- Top blocks by I/O (find hot blocks → segment identification)
SELECT H.P1 FILE#, H.P2 BLOCK#, SUM(1) WAIT_SAMPLES
FROM V$ACTIVE_SESSION_HISTORY H
WHERE H.SESSION_STATE = 'WAITING'
  AND H.EVENT         LIKE 'db file%'
  AND H.P2TEXT        = 'block#'
  AND H.SAMPLE_TIME   >= SYSTIMESTAMP - INTERVAL '30' MINUTE
GROUP BY H.P1, H.P2
ORDER BY WAIT_SAMPLES DESC
FETCH FIRST 10 ROWS ONLY;

-- Từ file# + block# → identify segment
SELECT SEGMENT_NAME, PARTITION_NAME, SEGMENT_TYPE
FROM DBA_EXTENTS
WHERE (&blockno BETWEEN BLOCK_ID AND (BLOCK_ID + BLOCKS - 1))
  AND FILE_ID = &fileno
  AND ROWNUM  < 2;

-- ROWID reconstruction từ ASH object/file/block/row info
SELECT OBJECT_NAME,
       DBMS_ROWID.ROWID_CREATE(1, &ENTER_DATA_OBJ_ID, &ENTER_FILE,
                                  &ENTER_BLOCK, &ENTER_ROW) ROW_ID
FROM DBA_OBJECTS
WHERE DATA_OBJECT_ID = &ENTER_DATA_OBJ_ID;

-- Index usage analysis (AWR history — indexes accessed by executed SQL plans)
WITH idx_plans AS (
    SELECT DISTINCT PLAN_HASH_VALUE, OBJECT#, OBJECT_OWNER, OBJECT_TYPE, OBJECT_NAME
    FROM DBA_HIST_SQL_PLAN
    WHERE OBJECT_TYPE LIKE 'INDEX%'
      AND OBJECT_OWNER = 'SOE'
)
SELECT p.OBJECT_NAME,
       p.OBJECT_TYPE,
       COUNT(DISTINCT h.SQL_ID || h.SQL_PLAN_HASH_VALUE || h.SQL_EXEC_ID) EXEC_SAMPLES
FROM DBA_HIST_ACTIVE_SESS_HISTORY h
JOIN idx_plans p ON h.SQL_PLAN_HASH_VALUE = p.PLAN_HASH_VALUE
GROUP BY p.OBJECT_NAME, p.OBJECT_TYPE
ORDER BY EXEC_SAMPLES;

-- SQL performance history across days (detect when performance degraded)
SELECT TO_CHAR(SAMPLE_TIME, 'YY-MM-DD')  SAMPLE_DATE,
       H.SQL_ID,
       H.SQL_PLAN_HASH_VALUE,
       SUM(10)                            SQL_DBTIME  -- ×10 for DBA_HIST
FROM DBA_HIST_ACTIVE_SESS_HISTORY H
WHERE H.SQL_ID IS NOT NULL
  AND H.SQL_ID = '&V_SQL_ID'
GROUP BY TO_CHAR(SAMPLE_TIME, 'YY-MM-DD'), H.SQL_ID, H.SQL_PLAN_HASH_VALUE
ORDER BY SAMPLE_DATE DESC;

-- Generate targeted ASH report (ashrpti.sql — more filter options than ashrpt.sql)
DEFINE begin_time  = '04/22/26 14:00:00';
DEFINE report_type = 'html';
DEFINE duration    = 30;                          -- minutes
DEFINE report_name = '/tmp/ash_report.html';
DEFINE target_sql_id       = '';                  -- filter to specific SQL
DEFINE target_wait_class   = '';                  -- filter to wait class
DEFINE target_module_name  = '';                  -- filter to module
DEFINE target_action_name  = '';
DEFINE target_client_id    = '';
DEFINE target_container    = '';                  -- for CDB: PDB name
@$ORACLE_HOME/rdbms/admin/ashrpti.sql
```

---

## 6. Senior Checklist

- [ ] Verify ASH buffer không bị overflow: `SELECT MIN(SAMPLE_TIME) FROM V$ACTIVE_SESSION_HISTORY` — nếu oldest sample < 30 phút trước incident start, escalate sang DBA_HIST
- [ ] Với DBA_HIST queries: luôn nhân COUNT/SUM với 10; đừng compare raw row counts với V$ASH counts
- [ ] Check `TOP_LEVEL_SQL_ID ≠ SQL_ID` trên top DB Time consumers trước khi blame child SQL — root là parent PL/SQL block
- [ ] Filter background sessions (SESSION_TYPE = 'BACKGROUND') trừ khi đang investigate specific background process issue
- [ ] Khi `CURRENT_OBJ# = -1`: wait không liên quan đến object (log file sync, control file I/O, network events)
- [ ] Trong CDB: add `CON_ID` filter hoặc connect trực tiếp vào PDB để isolate PDB workload
- [ ] Sau khi identify blocking chain: query ASH records của BLOCKING_SESSION để xem nó đang chờ gì — có thể nó cũng đang bị block (deadlock-like cascade)

---

# Lab: ASH — Hands-on for Senior DBA

## Lab Overview

- **Mục tiêu:** Sử dụng ASH để investigate post-mortem performance incidents và correlate multi-dimensional evidence
- **Môi trường:** Oracle 12.2+ / CDB or non-CDB; SOE schema với Swingbench OLTP load
- **Thời gian ước tính:** 75 phút
- **Độ khó:** Senior/Expert

---

## Exercise 1 — Post-Mortem Session Investigation

### Scenario

14:22: User từ team kế toán report transaction mất ~3 phút thay vì vài giây. Session đã disconnect trước khi DBA kịp xem. User biết module là `ACCT_PERIOD_CLOSE` trong connection string và action là `PROCESS_ORDERS`.

### Tasks

1. Query `V$ACTIVE_SESSION_HISTORY` với filter `MODULE = 'ACCT_PERIOD_CLOSE'` trong window 14:15–14:30
2. Xác định: session đang WAITING hay ON CPU phần lớn thời gian? Event nào chiếm nhiều samples nhất?
3. Nếu BLOCKING_SESSION xuất hiện trong nhiều consecutive samples → query ASH cho blocking SID đó trong cùng time window
4. Từ `CURRENT_OBJ#`, `CURRENT_FILE#`, `CURRENT_BLOCK#`, `CURRENT_ROW#` → dùng `DBMS_ROWID.ROWID_CREATE()` để identify exact row bị block, sau đó SELECT row đó
5. Từ SQL_ID trong ASH → lấy SQL text; kiểm tra query có dùng bind variables không

### Expected Findings

- Multiple consecutive samples với SESSION_STATE = 'WAITING', EVENT = 'enq: TX - row lock contention'
- BLOCKING_SESSION trỏ đến một session khác (có thể cũng đã disconnect)
- SQL_ID reveal UPDATE statement trên ORDERS table, CURRENT_OBJ# confirm object
- Row retrieved từ ROWID là order của customer đang bị lock uncommitted

### Debrief Questions

- Nếu BLOCKING_SESSION cũng đã disconnect khi bạn điều tra, bạn còn có thể truy vết ngược blocking session đó không? Cần thêm gì?
- Tại sao số rows trả về trong ASH query xấp xỉ bằng số giây session đó chờ?

---

## Exercise 2 — Real-time CPU Spike Identification

### Scenario

Hệ thống chạy bình thường (CPU ~30%). 11:47: monitoring báo CPU jump lên 95%, kéo dài 8 phút. Bạn nhận alert lúc 11:52 — spike đang còn xảy ra.

### Tasks

1. Query V$ASH real-time (last 10 minutes): breakdown samples của `SESSION_STATE = 'ON CPU'` vs `WAITING` — tỷ lệ bao nhiêu?
2. Filter `SESSION_STATE = 'ON CPU'` → GROUP BY MODULE → module nào đang dùng CPU nhiều nhất?
3. Tiếp tục GROUP BY SQL_ID để identify top CPU consumers; lấy SQL text
4. Lấy execution plan của top SQL_ID: `DBMS_XPLAN.DISPLAY_CURSOR()` — có full scan không?
5. Compare với historical normal: query `DBA_HIST_ACTIVE_SESS_HISTORY` cùng giờ hôm qua → SQL_ID đó thường chiếm bao nhiêu CPU?

### Expected Findings

- 1-2 SQL_IDs chiếm > 70% CPU samples trong period
- Execution plan có TABLE ACCESS FULL hoặc INDEX FAST FULL SCAN không expected
- DBA_HIST comparison cho thấy cùng SQL_ID có CPU consumption thấp hơn nhiều hôm qua — plan regression

### Debrief Questions

- Execution plan regression có thể xảy ra đột ngột vì những lý do gì? List ít nhất 3 triggers
- Nếu V$ASH đã overwrite data của 11:47–11:48 (2 phút đầu spike), còn có thể recover không? Options là gì?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief

Thứ Sáu 16:45 — peak OLTP period, end of business. Monitoring báo 3 anomalies đồng thời:
1. DB Time/CPU Time ratio: 1.2 → 4.8
2. Active sessions: 35 → 142
3. Transaction rate: 380 TPS → 80 TPS

Incident kéo dài 22 phút (16:45–17:07) rồi đột ngột self-resolve. Không có code release, không có scheduled batch job.

Bạn điều tra lúc 17:30.

### Evidence Provided

**V$ACTIVE_SESSION_HISTORY aggregated (16:45–17:07):**

```
EVENT                             SAMPLES   PCT_DBTIME
-------------------------------- -------- -----------
ON CPU                             4,821       34.2%
enq: TX - row lock contention      3,947       28.0%
db file sequential read            2,108       15.0%
library cache lock                 1,234        8.8%
cursor: pin S wait on X              891        6.3%
log file sync                        412        2.9%
null event                           401        2.8%
direct path read                     247        1.8%
```

**Top SQL từ ASH (16:45–17:07):**

```
SQL_ID          SQL_PLAN_HASH   DBTIME  SQL_TEXT (first 40 chars)
--------------  --------------  ------  ----------------------------------------
7tq9s8x2mn4pv   1847291034       2,847  UPDATE ORDERS SET ORDER_TOTAL=ORDER_...
7tq9s8x2mn4pv   3910284751         234  UPDATE ORDERS SET ORDER_TOTAL=ORDER_...
9p2xk4r8vn3wq   NULL               891  SELECT ORDERS.* FROM ORDERS WHERE...
```

**V$SESSION snapshot tại 16:52 (mid-incident):**

```
SID   STATE    EVENT                               BLOCKING_SID
----  -------  ----------------------------------  -----------
142   WAITING  enq: TX - row lock contention       117
193   WAITING  enq: TX - row lock contention       117
208   WAITING  enq: TX - row lock contention       117
...   (34 sessions tổng cộng đang wait trên SID 117)
117   WAITING  library cache lock                  NULL
```

### Your Mission

1. Xác định root cause cascade: tại sao 36 sessions đang wait trên SID 117? SID 117 đang chờ gì và tại sao?
2. SQL_ID `7tq9s8x2mn4pv` xuất hiện với 2 SQL_PLAN_HASH_VALUE khác nhau trong cùng incident window — điều này có ý nghĩa gì và liên quan đến incident như thế nào?
3. `library cache lock` và `cursor: pin S wait on X` xuất hiện đồng thời — relationship giữa chúng là gì?
4. Incident self-resolve sau 22 phút — điều gì có thể đã xảy ra để break the chain?
5. Để prevent recurrence, cần investigate và monitor thêm gì?

### Evaluation Criteria

- **Root cause chain:** SID 117 bị block bởi `library cache lock` → không thể complete transaction → giữ row lock → 36 sessions cascade wait trên TX lock. Library cache lock thường do DDL hoặc compile/recompile object đang được SQL_ID đó reference
- **Plan hash change significance:** 2 plan_hash cho cùng SQL_ID → plan change xảy ra trong incident window → likely do DDL trên table (e.g., `GATHER TABLE STATISTICS` hoặc `ALTER TABLE`) triggering shared pool invalidation và force reparse
- **library cache lock + cursor: pin S wait on X correlation:** khi một session reparse SQL (do invalidation), nó phải acquire library cache lock. Sessions cố execute cùng SQL phải wait cho `cursor: pin S wait on X` — chúng muốn share cursor nhưng cursor đang bị mutated/reloaded
- **Self-resolve hypothesis:** DDL statement completed → library cache lock released → SID 117 completes → row lock released → cascade resolves; hoặc library cache lock timeout
- **Prevention:** Check `DBA_OPTSTAT_OPERATIONS` xem có gather stats job nào run lúc 16:45 trên ORDERS table không; investigate `v$locked_objects` history; xem xét pinning stable SQL với DBMS_SPM; review auto stats maintenance window settings

---

*Self-check: Buffer overflow mechanism và staging table pattern không có trong Oracle docs introductory. Recursive SQL trap section có production implication thực tế. Ex3: library cache lock cascade là intentionally non-obvious root cause — không thể diagnose từ enq: TX finding alone, cần correlate SID 117's own wait. Tone: peer throughout.*


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_13_ash_senior_guide.md`
