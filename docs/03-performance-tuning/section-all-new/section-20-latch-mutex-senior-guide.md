---
title: 'Section 20 — Latch & Mutex Contention: Deep Dive for Senior DBA'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_20_latch_mutex_senior_guide.md
---

# Section 20 — Latch & Mutex Contention: Deep Dive for Senior DBA

---

## OUTPUT 1 — LECTURE NOTES

---

## 1. Mental Model

Latch và mutex là Oracle's **internal serialization primitives** — phân biệt rõ với enqueue (user-visible locking). Enqueue serializes user data access; latch/mutex serializes access to Oracle's own **SGA data structures**. Frame nó như: enqueue là traffic light cho xe của users; latch là traffic light cho xe của Oracle engine.

Critical distinction: enqueue là "polite wait" (FIFO queue, signal-based wake); latch là "aggressive spin" (process spin-loops trying to grab latch → consumes CPU even while waiting). Khi bạn thấy CPU utilization cao nhưng throughput thấp và latch waits elevated: **latch contention consumes CPU without doing useful work**. Đây là dấu hiệu đặc trưng nhất.

---

## 2. Internals & Mechanics

**Latch get protocol**: Get → spin (up to `_latch_spin_count` attempts, default 100 iterations) → nếu still unavailable → sleep (exponential backoff: 0.5ms, 1ms, 2ms, 4ms...) → V$LATCH.SLEEPS records mỗi lần phải sleep. SLEEPS >> 0 với rapidly increasing = severe contention. MISSES = failed first attempt (spin started); SLEEPS = escalated to sleep state. Tỷ lệ SLEEPS/MISSES: cao → sessions spend significant time sleeping → latch is hot.

**Mutex architecture**: Introduced in 10g, progressive replacement cho nhiều latches. Mutex là lighter-weight: pure spin-then-yield (không có exponential sleep). Protected bởi `V$MUTEX_SLEEP` và `V$MUTEX_SLEEP_HISTORY`. Library cache protection: pre-11g = "library cache latch"; 11g+ = "library cache: mutex X/S". Event name thay đổi theo version — diagnostic query cần handle cả hai.

**Library cache mutex X**: Write mutex. Acquired khi: hard parsing SQL (syntax check, semantic check, optimization, plan generation). Mỗi hard parse requires exclusive mutex để write new cursor into library cache. Concurrent hard parses → queue on this mutex. Signal: `library cache: mutex X` event tăng cùng lúc với hard parse rate tăng → literal SQL là nguyên nhân số 1.

**CBC (Cache Buffer Chain) latch architecture**: Buffer pool chia thành hash buckets. Mỗi bucket được protect bởi một child CBC latch. Hash function: block's DBA (Data Block Address) → bucket → CBC latch. Nhiều buffers trong cùng bucket share cùng latch. "Hot block" = block được nhiều sessions access simultaneously → hash vào cùng bucket → tranh chấp cùng CBC child latch.

`X$BH` (internal) chứa buffer headers: `HLADDR` = hash latch address, `TCH` = touch count (increments per access). Join `V$LATCH_CHILDREN.ADDR = X$BH.HLADDR` để map latch → buffers → objects. `DBA_OBJECTS` on `X$BH.OBJ` → table/index name. High TCH = hot block.

**Cursor pin waits**: `cursor: pin S` = shared pin (read/execute). `cursor: pin S wait on X` = session needs shared pin but one session holds exclusive pin (kompiling/invalidating cursor). Cascade effect: first session holds X pin → all subsequent executions of same cursor stack behind → wait queue grows. Immediate visual: `V$SESSION` nhiều sessions cùng `WAITING` với same SQL_ID.

**GETS vs IMMEDIATE_GETS in V$LATCH**:
- `GETS/MISSES`: Willing-to-wait requests — process will spin/sleep until get
- `IMMEDIATE_GETS/IMMEDIATE_MISSES`: No-wait requests — if unavailable, process moves on (tries different approach)
- Library cache: primarily uses GETS. Some internal structures: IMMEDIATE. High `IMMEDIATE_MISSES` = internal Oracle processes cannot get latch even on first try → rare, usually more serious.

---

## 3. Production Realities

**CURSOR_SHARING = FORCE as double-edged sword**: Oracle rewrite SQL literals to bind variables at parse time. Short-term: reduces hard parse rate, reduces library cache mutex. Long-term problems: (1) histogram-aware queries suddenly use bind peeking on rewritten binds → single plan for all parameter values → plan regression for non-representative values; (2) SQL Text in V$SQL no longer matches application SQL → V$SQL analysis breaks; (3) parse overhead không biến mất, chỉ thay đổi. Senior recommendation: fix application code, không dùng CURSOR_SHARING = FORCE as permanent solution.

**FLUSH SHARED POOL as emergency response**: Clears library cache → forces hard parse storm → **briefly makes things worse before better**. CPU spike post-flush là expected. Use only when: library cache fragmentation severe (ORA-04031), không phải khi chỉ là high parse rate. Quan trọng: flush DOES NOT help with `cursor: pin S wait on X` — nếu root cause là DDL compiling, flush makes it worse.

**CBC latch on single-row hot table**: Classic pattern — config table có một row được SELECT hàng nghìn lần/giây (e.g., "get current exchange rate"). Block address constant → same CBC latch → contention. Solutions theo priority: (1) Application-level caching (best); (2) Row Cache (V$ROWCACHE) nếu là dictionary object; (3) SEQUENCE object thay vì manual counter row.

**Swingbench và latch baseline**: Practice dùng Swingbench để tạo realistic load. Trong production, latch contention baseline varies drastically by workload type. OLTP (many small SQL, bind variables) → low latch contention. Analytical (few complex SQL) → low parse contention nhưng possible CBC từ large scan buffer reuse. Batch literal SQL → high library cache mutex. Understanding workload type informs which latch to watch.

**Version-specific behavior**: 12c multitenancy context — latches are SGA-wide (not per-PDB). Heavy hard parsing in one PDB's workload affects library cache latches cho all PDBs sharing same SGA. In CDB environment, library cache pressure is shared resource → cross-PDB contention possible.

---

## 4. Decision Framework

| Event | Root Cause | Diagnostic | Fix |
|-------|-----------|-----------|-----|
| `library cache: mutex X` | High hard parse rate (literal SQL) | `V$SQL.FORCE_MATCHING_SIGNATURE` count; `V$SQLAREA` cursor count rate | Bind variables; CURSOR_SHARING = FORCE (temporary) |
| `cache buffers chains` | Hot block (many sessions same block) | `V$LATCH_CHILDREN` + `X$BH` → object; TCH value | Application caching; distribute data; fewer hot rows |
| `cursor: pin S wait on X` | DDL compiling cursor while sessions executing | `V$SESSION` with same SQL_ID waiting; check for DDL in progress | Schedule compile in maintenance window; kill blocking DDL session |
| `cursor: pin S wait on X` (mass) | Hard parse storm causing exclusive mutex waits | Correlate with V$SYS_TIME_MODEL hard parse spike | Same as library cache mutex fix |
| `row cache lock` | Dictionary cache contention | `V$ROWCACHE_PARENT` | Usually resolves with Shared Pool sizing |

**Anti-patterns**:
- Increasing `_latch_spin_count` để reduce sleeps → consumes MORE CPU (more spinning) → worse throughput
- FLUSH SHARED POOL in response to `cursor: pin S wait on X` → root cause unchanged, temporary relief, adds parse storm
- Monitoring V$LATCH total statistics (non-child) để diagnose CBC latch → must use V$LATCH_CHILDREN for CBC

---

## 5. Key SQL / Commands

```sql
-- 1. System-level latch/mutex share của total wait time
WITH SYS_EVENT AS (
    SELECT CASE WHEN (EVENT LIKE '%latch%' OR EVENT LIKE '%mutex%' OR EVENT LIKE 'cursor:%')
                THEN EVENT ELSE WAIT_CLASS END WAIT_TYPE, E.*
    FROM V$SYSTEM_EVENT E
)
SELECT WAIT_TYPE,
       SUM(TOTAL_WAITS)                                          TOTAL_WAITS,
       ROUND(SUM(TIME_WAITED_MICRO)/1e6)                        TIME_WAITED_S,
       ROUND(SUM(TIME_WAITED_MICRO)*100 / SUM(SUM(TIME_WAITED_MICRO)) OVER(), 2) PCT
FROM (SELECT E.WAIT_TYPE, E.EVENT, E.TOTAL_WAITS, E.TIME_WAITED_MICRO FROM SYS_EVENT E
      UNION
      SELECT 'CPU', M.STAT_NAME, NULL, M.VALUE
      FROM V$SYS_TIME_MODEL M WHERE M.STAT_NAME IN ('background cpu time', 'DB CPU')
     ) L
WHERE WAIT_TYPE <> 'Idle'
GROUP BY WAIT_TYPE
HAVING ROUND(SUM(TIME_WAITED_MICRO)/1e6) > 0
ORDER BY 4 DESC;

-- 2. Top latches by wait time
SELECT C.NAME,
       SUM(A.GETS) GETS, SUM(A.MISSES) MISSES, SUM(A.SLEEPS) SLEEPS,
       ROUND(SUM(A.SLEEPS)/NULLIF(SUM(A.MISSES),0)*100,2) SLEEP_PCT,
       SUM(A.WAIT_TIME) WAIT_TIME_US
FROM V$LATCH A, V$LATCHNAME C
WHERE A.LATCH# = C.LATCH#
  AND (A.SLEEPS > 0 OR A.IMMEDIATE_MISSES > 0)
GROUP BY C.NAME
ORDER BY WAIT_TIME_US DESC
FETCH FIRST 15 ROWS ONLY;

-- 3. Library cache mutex diagnostic (literal SQL proliferation)
SELECT TO_CHAR(FORCE_MATCHING_SIGNATURE) FMS,
       SUBSTR(SQL_TEXT, 1, 60) SQL_TEXT,
       COUNT(*) CURSOR_COUNT       -- high count = same SQL, different literals
FROM V$SQL
WHERE FORCE_MATCHING_SIGNATURE <> 0
  AND PARSING_SCHEMA_NAME <> 'SYS'
GROUP BY TO_CHAR(FORCE_MATCHING_SIGNATURE), SUBSTR(SQL_TEXT, 1, 60)
HAVING COUNT(*) > 50               -- threshold; > 100 = significant issue
ORDER BY CURSOR_COUNT DESC;

-- 4. Sessions currently waiting on latch/mutex
SELECT S.SID, S.USERNAME, E.EVENT,
       E.TIME_WAITED TIME_CS,
       SUBSTR(Q.SQL_TEXT, 1, 80) SQL_TEXT
FROM V$SESSION S
JOIN V$SESSION_EVENT E ON E.SID = S.SID
LEFT JOIN V$SQLAREA Q ON S.SQL_ID = Q.SQL_ID
WHERE (E.EVENT LIKE '%latch%' OR E.EVENT LIKE '%mutex%' OR E.EVENT LIKE 'cursor:%')
  AND E.TIME_WAITED > 0
ORDER BY E.TIME_WAITED DESC;

-- 5. CBC latch: identify hot block → object
-- First: get LATCH_ADDRESS from V$SESSION_EVENT P1RAW for 'cache buffers chains' event
SELECT L.ADDR, OWNER, OBJECT_NAME, OBJECT_TYPE,
       COUNT(DISTINCT L.ADDR) LATCHES,
       SUM(B.TCH) TOUCHES          -- high TCH = hot block
FROM V$LATCH_CHILDREN L
JOIN X$BH B ON L.ADDR = B.HLADDR
JOIN DBA_OBJECTS O ON B.OBJ = O.OBJECT_ID
WHERE L.NAME = 'cache buffers chains'
  AND L.SLEEPS > 0                 -- only hot latches
  AND OWNER NOT IN ('SYS','SYSTEM')
GROUP BY L.ADDR, OWNER, OBJECT_NAME, OBJECT_TYPE
ORDER BY TOUCHES DESC
FETCH FIRST 10 ROWS ONLY;

-- 6. Monitor CBC latch statistics in real-time (repeat for delta)
SELECT ADDR, LATCH#, CHILD#, GETS, MISSES, SLEEPS,
       ROUND(SLEEPS/NULLIF(GETS,0)*1000, 2) SLEEPS_PER_1000_GETS
FROM V$LATCH_CHILDREN
WHERE ADDR = '&LATCH_ADDRESS'
ORDER BY SLEEPS DESC;

-- 7. Cursor pin wait analysis: sessions waiting on same SQL
SELECT S.SID, S.USERNAME, S.SQL_ID, S.EVENT,
       S.SECONDS_IN_WAIT, S.P1RAW
FROM V$SESSION S
WHERE S.EVENT LIKE 'cursor: pin%'
ORDER BY S.SQL_ID, S.SECONDS_IN_WAIT DESC;
```

---

## 6. Senior Checklist

1. Quantify latch/mutex as % of total DB time (V$SYSTEM_EVENT analysis) trước khi conclude có latch problem — < 5% thường acceptable
2. Distinguish library cache mutex (hard parse driven) vs cursor pin (DDL driven): time model hard parse spike → former; ALTER/CREATE DDL trong flight → latter
3. CBC latch hot block: always identify the **object** (via X$BH join) không chỉ latch address — object identity determines fix strategy
4. `SLEEPS/MISSES` ratio trong V$LATCH: high ratio (> 10%) → sessions regularly cannot get latch on first try → severe contention; low ratio → occasional miss, self-correcting
5. Sau fix (bind variables deployed): verify `V$SQLAREA` cursor count cho FORCE_MATCHING_SIGNATURE đang giảm — evidence fix working
6. Monitor `_latch_spin_count` (hidden param) — default thường fine; nếu có pressure to change này, fix root cause instead
7. Trong RAC: CBC latch contention có thể manifest as inter-node block shipping overhead (`gc buffer busy acquire/release`) — latch analysis trên single instance không capture cross-node pattern

---

## OUTPUT 2 — LAB EXERCISES

---

# Lab: Section 20 — Latch & Mutex Contention

## Lab Overview

- **Mục tiêu:** Diagnose library cache latch (hard parse) và CBC latch (hot block) contention, understand cursor mutex cascade
- **Môi trường:** Oracle 12c–19c / non-CDB với SOE schema và Swingbench (hoặc manual session simulation)
- **Thời gian ước tính:** 50 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Library Cache Mutex Diagnosis and Fix

### Scenario
Production OLTP system. DBA notice CPU utilization 80%+ nhưng throughput (transactions/sec) thấp hơn 30% so với normal. V$SYSTEM_EVENT cho thấy `library cache: mutex X` trong top 3 waits. Application developer vừa deploy một "performance improvement" — họ thêm ORDER_ID vào WHERE clause của một frequently-called query.

### Tasks
1. Identify hard parse rate hiện tại qua `V$SYS_TIME_MODEL` — `hard parse elapsed time` tỷ lệ so với `DB CPU`
2. Query `V$SQL` với `FORCE_MATCHING_SIGNATURE` để confirm có nhiều cursors cùng statement, khác literals
3. Tìm SESSION đang wait `library cache: mutex X` và SQL đang gây ra
4. Deploy fix (bind variable version) trong test session; verify `library cache: mutex X` rate giảm

### Expected Findings
- Hard parse elapsed time / DB CPU > 20% → excessive hard parsing
- FORCE_MATCHING_SIGNATURE count > 1000 cho cùng statement base = confirmed literal proliferation
- After bind variable fix: cursor count giảm; mutex wait rate giảm; throughput recovers

### Debrief Questions
- Tại sao hard parse tốn CPU ngay cả khi execution plan đơn giản (index range scan)?
- `CURSOR_SHARING = FORCE` có thể deployed ngay không? Trade-offs là gì so với fixing application code?

---

## Exercise 2 — CBC Latch Hot Block Root Cause Analysis

### Scenario
DBA nhận alert: `cache buffers chains` chiếm 15% total DB time trong giờ vừa rồi. System là inventory management app. DBA cần identify object(s) gây hot block và propose fix mà không require application downtime.

### Tasks
1. Query `V$SESSION_EVENT` WHERE EVENT = 'cache buffers chains' → collect `P1RAW` (latch address)
2. Join `V$LATCH_CHILDREN` → `X$BH` → `DBA_OBJECTS` để identify object và block numbers
3. Query `V$BH` (buffer cache view, public) để confirm block access pattern
4. Based on object type (table/index) và access pattern, propose fix

### Expected Findings
- Hot block thường là: (a) small lookup table full-scanned repeatedly; (b) index root/branch block của heavily-used index; (c) single row with counters updated frequently
- `TCH` (touch count) rất cao trên specific block → confirms hot
- Fix depends: index root → consider reverse-key index; lookup table → application caching; counter row → SEQUENCE object

### Debrief Questions
- Tại sao index root block thường hot hơn leaf blocks trong CBC contention?
- Direct Memory Access (DMA) caching tier (e.g., Memcached) giải quyết hot block như thế nào so với Database In-Memory option?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Friday 16:45. Production database. CPU: 95%. Throughput: 20% of normal. DBA escalated. Alert team says "khởi động lại app server không giúp gì."

### Evidence Provided

```
V$SYS_TIME_MODEL (last 15 min delta):
  STAT_NAME                       VALUE_S
  DB CPU                          2,840
  hard parse elapsed time         2,110      ← 74% of DB CPU!
  parse time elapsed              2,390
  sql execute elapsed time          890

V$SYSTEM_EVENT (top 5, last 15 min delta):
  EVENT                           TIME_WAITED_S  TOTAL_WAITS
  cursor: pin S wait on X              1,247       892,441
  library cache: mutex X                 834       1,341,283
  DB CPU (on CPU)                        890           N/A
  db file sequential read                 23        18,422
  log file sync                            8         4,218

V$SQL (top by VERSION_COUNT, last snapshot):
  SQL_ID        FORCE_MATCHING_SIG  VERSION_COUNT  SQL_TEXT (first 50)
  8xm4kfq7n2p5  7293847561029384        18,294    SELECT P.PRICE, P.STOCK_QTY FR...
  3nq7xl2mp8k4  7293847561029384           248    SELECT P.PRICE, P.STOCK_QTY FR...
  (same FMS = same statement, different literals)

V$SESSION (sample at 16:47, 200 active sessions):
  Status WAITING:  178 sessions
  Top events:
    cursor: pin S wait on X  : 142 sessions
    library cache: mutex X   :  31 sessions
    ON CPU                   :   5 sessions
```

### Your Mission
1. Identify exact root cause và propagation chain từ first cause đến all symptoms
2. Explain tại sao `cursor: pin S wait on X` có nhiều waiters hơn `library cache: mutex X` (142 vs 31)
3. Immediate mitigation: propose action DBA có thể take right now (không restart)
4. Identify root trigger của hard parse storm: application bug hay deployment event?

### Evaluation Criteria
- **Propagation chain**: Hard parse storm (74% DB CPU) → library cache: mutex X (exclusive mutex per hard parse) → sessions waiting on mutex → some sessions holding mutex while others wait → cursor invalidation cascade → cursor: pin S wait on X (sessions waiting to execute same cursor that is being invalidated/reloaded)
- **142 vs 31**: `cursor: pin S wait on X` is the downstream effect: each hard parse that creates a new child cursor → invalidates/displaces existing child → all sessions executing that cursor hit pin wait. ONE library cache mutex creates MANY pin waiters — multiplier effect explains ratio
- **FMS analysis**: 18,294 versions of SAME statement (same FORCE_MATCHING_SIG) = 18,294 hard parses, each with different literals. VERSION_COUNT of 18,294 for one statement is catastrophic
- **Immediate mitigation options** (ordered by risk):
  - (a) Identify and kill sessions causing hard parses (if from batch job, kill job)
  - (b) `ALTER SYSTEM FLUSH SHARED_POOL` — nuclear option, causes brief parse storm, use with caution
  - (c) `ALTER SYSTEM SET CURSOR_SHARING = FORCE SCOPE = MEMORY` — immediate effect, rewrite literals → reduces hard parse; risks: histogram plans affected
- **Root trigger identification**: VERSION_COUNT 18,294 appearing suddenly → deployment event most likely. Check: (a) application deployment changelog; (b) `DBA_AUDIT_TRAIL` for recent DDL; (c) `V$SQL.FIRST_LOAD_TIME` distribution — if all recent = deployment triggered hard parse flush

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_20_latch_mutex_senior_guide.md`
