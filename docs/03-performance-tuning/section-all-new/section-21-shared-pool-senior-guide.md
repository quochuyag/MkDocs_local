---
title: 'Section 21 — Shared Pool Tuning: Deep Dive for Senior DBA'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_21_shared_pool_senior_guide.md
---

# Section 21 — Shared Pool Tuning: Deep Dive for Senior DBA

---

## OUTPUT 1 — LECTURE NOTES

---

## 1. Mental Model

Shared Pool là Oracle's **code and metadata cache** — phân biệt rõ với Buffer Cache (data cache). Mọi SQL/PL/SQL phải được parsed trước khi execute. Parsed result (cursor + execution plan) lưu trong Library Cache (một phần của Shared Pool). Nếu cursor tìm thấy → soft parse (reuse plan); không tìm thấy → hard parse (full parse pipeline: syntax check → semantic check → optimization → plan generation → store).

Frame three-tier parse hierarchy như: **Hard Parse** = toàn bộ quá trình (expensive); **Soft Parse** = find cursor in Library Cache (moderate — phải acquire mutex); **Soft-Soft Parse** = find cursor in Session Cursor Cache (cheapest — bypass Library Cache entirely). Senior optimization: minimize hard → minimize soft → maximize soft-soft.

Result Cache là extension concept: cache không chỉ execution plan mà cả **result set** — bypass parse, execute, AND I/O.

---

## 2. Internals & Mechanics

**Library Cache structure**: Organized by namespace (SQL AREA, TABLE/PROCEDURE, BODY, TRIGGER, INDEX...). SQL AREA namespace holds cursors. Each SQL text → hash → Library Cache bucket. Parent cursor = unique SQL text. Child cursor = per execution context (schema, optimizer settings, NLS env, optimizer_mode). `V$SQL.CHILD_NUMBER` increments per child. Too many children per parent → cursor proliferation → library cache pressure.

**Child cursor invalidation conditions**: Stats gathered (DBMS_STATS), DDL on referenced object, optimizer param change, NLS setting mismatch, partition pruning difference, security policy. Each invalidation event → existing child marked invalid → next execution = hard parse for that session.

**Session Cursor Cache mechanics**: After a cursor is executed `SESSION_CACHED_CURSORS`-threshold times (Oracle internal: approximately 3 executions), pointer stored in session's UGA (User Global Area). `V$OPEN_CURSOR.CURSOR_TYPE = 'SESSION CURSOR CACHED'`. Subsequent access: soft-soft parse — no Library Cache latch/mutex required. Session cache is per-session, lost on session termination.

**Library Cache Pin types**:
- Shared pin (S): read access during execution. Multiple concurrent S pins allowed.
- Exclusive pin (X): write access during compile/recompile. Exclusive — blocks all S pins.
- `library cache pin` wait event = session waiting for X pin (compile in progress by another session)
- `cursor: pin S wait on X` = session waiting for S pin because another session holds X pin (compiling same object)
- `X$KGLOB`: internal table — KGLHDADR = handle address. P1RAW in V$SESSION for library cache waits = handle address → lookup object name via X$KGLOB.KGLNAOBJ.

**Shared Pool Advisory**: `V$SHARED_POOL_ADVICE` samples current workload → models how Library Cache would behave at different pool sizes → `ESTD_LC_TIME_SAVED` = estimated parse time saved at that size. Read-when-healthy rule: **advisory is only meaningful during representative normal workload**. Reading during hard parse storm → skewed recommendations (inflated benefit of larger pool). Key metric: find pool size where `ESTD_LC_TIME_SAVED_FACTOR` plateaus (diminishing returns beyond this point).

**AMM/ASMM interaction**: With AMM (MEMORY_TARGET > 0): Oracle can auto-shrink Shared Pool to feed Buffer Cache during heavy scan workloads — dangerous if heavy PL/SQL workload present. Set `SHARED_POOL_SIZE` as lower bound (minimum floor). With ASMM (SGA_TARGET > 0, MEMORY_TARGET = 0): Oracle manages SGA component ratios but respects explicit SHARED_POOL_SIZE floor.

**Result Cache internals**: Stored in Shared Pool (not Buffer Cache). Block size = 1KB (vs Buffer Cache 8KB). Cache coherency = dependency tracking: `V$RESULT_CACHE_DEPENDENCY` maps RC object → base tables. When dependency table receives DML+COMMIT → RC entry immediately marked INVALID. `RESULT_CACHE_MODE = FORCE`: cache ALL result sets — performance disaster in OLTP (constant invalidation overhead > execution benefit). `STATUS = 'Invalid'` in `V$RESULT_CACHE_OBJECTS` = either (a) data changed (invalidated), or (b) result set exceeded `RESULT_CACHE_MAX_RESULT` size limit.

---

## 3. Production Realities

**Library cache pin storm after schema migration**: ALTER TABLE ADD COLUMN trên referenced table → invalidates ALL cursors referencing that table → next execution for every session = hard parse. In large PL/SQL codebases: hundreds of packages, thousands of SQL statements simultaneously hard-parsing → library cache pin cascade. Pattern: `cursor: pin S wait on X` spikes immediately after DDL. Mitigation: `UTL_RECOMP.RECOMP_SERIAL` or `DBMS_UTILITY.COMPILE_SCHEMA` scheduled in maintenance window before releasing DDL.

**Shared Pool Advisory read timing**: DBA sees `ESTD_LC_TIME_SAVED_FACTOR = 1.2` at current size → interprets as "20% time savings with more pool." Actually means "if pool were this size normally, parse time would save 20%." If currently under load, reading advisory mid-stress = overstating benefit. Correct procedure: AWR Report "Shared Pool Advisory" section dari normal workload window.

**RESULT_CACHE_MODE = FORCE in OLTP**: Customer case — DBA enabled FORCE to "automatically cache all queries." Every DML operation on base tables invalidated related RC entries → invalidation overhead > query execution saved → throughput degraded 40%. Rollback required `ALTER SYSTEM SET RESULT_CACHE_MODE = MANUAL`.

**SESSION_CACHED_CURSORS saturation**: If many sessions reach `session cursor cache count = SESSION_CACHED_CURSORS value`, new cursors evict older ones. Churn: frequently used cursors compete with rarely used → net effect = less soft-soft parse benefit. Signal: `V$SESSTAT` for `session cursor cache count` = MAX at many sessions → increase parameter.

**Large Pool vs Shared Pool confusion**: `PARALLEL_EXECUTION_MESSAGE_SIZE` buffers, `DBMS_JOB`/DBMS_SCHEDULER private area, some RMAN buffers → Large Pool, not Shared Pool. Heavy parallel DML causing Large Pool ORA-04031 is NOT a Shared Pool issue. Check `V$SGASTAT` WHERE POOL = 'large pool' để distinguish.

---

## 4. Decision Framework

| Triệu chứng | Diagnosis | Fix |
|------------|----------|-----|
| `cursor: pin S wait on X` + hard parse high | Literal SQL → hard parse storm → mutex cascade | Bind variables; CURSOR_SHARING = FORCE (temp) |
| `library cache pin` tăng sau DDL/COMPILE | Cursor recompilation blocking executions | Schedule recompile in maintenance window; UTL_RECOMP |
| ORA-04031 (Shared Pool out of memory) | Shared Pool fragmented or too small | `ALTER SYSTEM FLUSH SHARED_POOL`; increase SHARED_POOL_SIZE; investigate fragmentation |
| SESSION_CACHED_CURSORS near max | Session cache saturated | Increase SESSION_CACHED_CURSORS; profile cursor reuse |
| Result Cache miss rate high | RC too small or high DML invalidation rate | Increase RESULT_CACHE_MAX_SIZE; evaluate DML rate on dependency tables |
| `RESULT_CACHE_OBJECTS.STATUS = Invalid` (consistently) | Result set too large or base table high DML | Increase RESULT_CACHE_MAX_RESULT; remove RESULT_CACHE hint from volatile data queries |

**Anti-patterns**:
- Setting RESULT_CACHE_MODE = FORCE without analyzing DML rate on dependency tables
- Reading V$SHARED_POOL_ADVICE during peak stress period → oversized pool recommendation
- Keeping SESSION_CACHED_CURSORS = 0 (disabled) in OLTP → forces Library Cache lookup every execution
- FLUSH SHARED_POOL as regular scheduled maintenance → equivalent to self-inflicted hard parse storm

---

## 5. Key SQL / Commands

```sql
-- 1. Verify memory management mode
SHOW PARAMETER MEMORY_TARGET    -- AMM if > 0
SHOW PARAMETER SGA_TARGET       -- ASMM if > 0

-- 2. SGA component sizes
SELECT NAME, ROUND(BYTES/1024/1024, 2) MB
FROM V$SGAINFO
ORDER BY BYTES DESC;

-- 3. Library Cache memory by namespace
SELECT LC_NAMESPACE                  NAMESPACE,
       LC_INUSE_MEMORY_OBJECTS       OBJECTS_IN_USE,
       ROUND(LC_INUSE_MEMORY_SIZE/1e6, 2)     USED_MB,
       ROUND(LC_FREEABLE_MEMORY_SIZE/1e6, 2)  FREEABLE_MB
FROM V$LIBRARY_CACHE_MEMORY
ORDER BY LC_INUSE_MEMORY_OBJECTS DESC;

-- 4. Shared Pool Advisory (read during normal workload!)
SELECT SHARED_POOL_SIZE_FOR_ESTIMATE C1,
       SHARED_POOL_SIZE_FACTOR        C2,  -- 1.0 = current size
       ESTD_LC_SIZE                   C3,
       ESTD_LC_TIME_SAVED             C4,
       ESTD_LC_TIME_SAVED_FACTOR      C5,  -- plateau here = optimal
       ESTD_LC_MEMORY_OBJECT_HITS     C6
FROM V$SHARED_POOL_ADVICE
ORDER BY 1;

-- 5. Session cursor cache statistics per session
SELECT S.SID, S.USERNAME,
       B.NAME                     STATISTIC,
       A.VALUE
FROM V$SESSTAT A
JOIN V$STATNAME B ON A.STATISTIC# = B.STATISTIC#
JOIN V$SESSION S ON S.SID = A.SID
WHERE S.USERNAME = 'SOE'
  AND B.NAME IN ('session cursor cache count',
                 'session cursor cache hits',
                 'parse count (total)',
                 'parse count (hard)')
ORDER BY S.SID, B.NAME;

-- 6. Session cursor cache hit rate
SELECT C.SID,
       C.VALUE                              CACHE_HITS,
       P.VALUE                              TOTAL_PARSES,
       ROUND(C.VALUE/NULLIF(P.VALUE,0)*100, 1) HIT_PCT
FROM V$SESSTAT C
JOIN V$STATNAME N1 ON C.STATISTIC# = N1.STATISTIC# AND N1.NAME = 'session cursor cache hits'
JOIN V$SESSTAT P  ON C.SID = P.SID
JOIN V$STATNAME N2 ON P.STATISTIC# = N2.STATISTIC# AND N2.NAME = 'parse count (total)'
JOIN V$SESSION S  ON S.SID = C.SID
WHERE S.USERNAME = 'SOE'
ORDER BY HIT_PCT DESC;

-- 7. Library cache pin diagnosis: find object being compiled
SELECT EVENT, P1TEXT, P1RAW, WAIT_TIME_MICRO
FROM V$SESSION WHERE SID = &WAITING_SID;

SELECT KGLNAOWN OWNER, KGLNAOBJ OBJECT_NAME, KGLHDNSP NAMESPACE
FROM SYS.X$KGLOB
WHERE KGLHDADR = '&P1RAW_VALUE';

-- 8. Result Cache status and statistics
SELECT NAME, VALUE
FROM V$RESULT_CACHE_STATISTICS
ORDER BY ID;

SELECT NAME, TYPE, STATUS,
       BLOCK_COUNT, INVALIDATIONS,
       SUBSTR(NAME, 1, 80) RC_OBJECT
FROM V$RESULT_CACHE_OBJECTS
WHERE TYPE = 'Result'
ORDER BY STATUS, BLOCK_COUNT DESC;

-- 9. Using Result Cache with named cache object
SELECT /*+ RESULT_CACHE(NAME=SALES_BY_REP_2025) */
       SALES_REP_ID,
       TO_CHAR(SUM(ORDER_TOTAL), '999,999,999') TOTAL
FROM ORDERS
WHERE EXTRACT(YEAR FROM ORDER_DATE) = 2025
GROUP BY SALES_REP_ID
ORDER BY SUM(ORDER_TOTAL) DESC;
```

---

## 6. Senior Checklist

1. Baseline hard parse rate: `V$SYS_TIME_MODEL.hard parse elapsed time` / `DB CPU` < 10% = healthy; > 20% = investigate bind variable usage
2. Read Shared Pool Advisory ONLY during representative normal workload — not during incidents
3. After schema migration (ALTER TABLE, CREATE INDEX): expect cursor invalidation wave → monitor `cursor: pin S wait on X` trong 10 phút đầu sau DDL
4. SESSION_CACHED_CURSORS audit: `SELECT COUNT(*) FROM V$SESSTAT WHERE STATISTIC# = (SELECT STATISTIC# FROM V$STATNAME WHERE NAME = 'session cursor cache count') AND VALUE = (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'session_cached_cursors')` — nhiều sessions ở limit → increase parameter
5. Result Cache suitability check trước khi enable: query `DBA_HIST_SEG_STAT` cho DML frequency trên dependency tables — high DML rate → invalidation overhead outweighs benefit
6. Library Cache fragmentation indicator: `V$SGASTAT` WHERE POOL = 'shared pool' AND NAME = 'free memory' < 5% của Shared Pool → consider flush và/hoặc increase SHARED_POOL_SIZE
7. `X$KGLOB` requires SYS access — ensure diagnostic scripts available to on-call DBA; grant SELECT on X$KGLOB to DBA user if needed (note: X$ tables are undocumented)

---

## OUTPUT 2 — LAB EXERCISES

---

# Lab: Section 21 — Shared Pool Tuning

## Lab Overview

- **Mục tiêu:** Diagnose high parse situations, validate Session Cursor Cache behavior, evaluate Result Cache suitability
- **Môi trường:** Oracle 12c–19c / non-CDB với SOE schema
- **Thời gian ước tính:** 55 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Parse Rate Analysis and Optimization

### Scenario
OLTP application với 200 concurrent sessions. DBA nhận report: "response time degraded 2x trong giờ cao điểm." Check nhanh: DB CPU 85%, throughput normal. Hard parse time 35% của DB CPU. Không có DBA code change recent — application team just released new version sáng nay.

### Tasks
1. Query `V$SYS_TIME_MODEL` để baseline: DB CPU, hard parse, soft parse, sql execute breakdown
2. Identify top SQL by `VERSION_COUNT` trong `V$SQL` — high version count = same SQL, many cursors
3. Query `FORCE_MATCHING_SIGNATURE` để confirm literal vs bind variable pattern
4. For one offending SQL_ID: count children (`V$SQL WHERE SQL_ID = '...'`), check execution plan consistency across children

### Expected Findings
- VERSION_COUNT > 100 cho một SQL_ID = confirmed literal proliferation
- Same FORCE_MATCHING_SIGNATURE across many SQL_IDs = same logical query, different literal values
- Children may have different PLAN_HASH_VALUE if bind peeking produced different plans at different cardinalities

### Debrief Questions
- Application released new version "without changing SQL." Làm sao application release có thể introduce literal SQL? (e.g., ORM framework change, connection pool change clearing session cursor cache, new module without bind variable support)
- Nếu VERSION_COUNT = 50,000 cho một SQL_ID: memory implications gì trong Library Cache?

---

## Exercise 2 — Session Cursor Cache Tuning

### Scenario
DBA muốn quantify benefit của Session Cursor Cache cho SOE workload. Test: measure parse statistics với SESSION_CACHED_CURSORS = 0 (disabled) vs SESSION_CACHED_CURSORS = 50 (default) cho một single intensive session.

### Tasks
1. Baseline một session: run 1000 iterations của same bind-variable query, record `session cursor cache hits` và `parse count (total)` trước/sau
2. Set SESSION_CACHED_CURSORS = 0 cho test session: `ALTER SESSION SET SESSION_CACHED_CURSORS = 0`; repeat same test; compare parse metrics
3. Verify `V$OPEN_CURSOR.CURSOR_TYPE` — với cache enabled: 'SESSION CURSOR CACHED'; disabled: 'OPEN'
4. Estimate soft-soft parse savings: nếu 1000 parse/sec saved 50% overhead → throughput impact gì?

### Expected Findings
- Cache enabled: `session cursor cache hits / parse count (total)` > 95% sau warmup period (first ~3 executions per cursor = mandatory Library Cache fetch)
- Cache disabled: mỗi parse = Library Cache mutex acquisition → higher mutex contention under concurrent load
- CURSOR_TYPE change visible trong V$OPEN_CURSOR after threshold executions

### Debrief Questions
- Session Cursor Cache lưu trong UGA (User Global Area). Nếu SESSION_CACHED_CURSORS rất cao (ví dụ = 500) với 1000 sessions: memory implications gì cho PGA/UGA tổng thể?
- Cursor cache hit rate 98% nhưng hard parse rate vẫn cao: possible explanation?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Production database. Friday 18:30. DBA nhận ORA-04031: "unable to allocate 4096 bytes of shared memory" trong alert log, xuất hiện lần đầu 17:45 và tăng dần. Database vẫn running nhưng một số sessions nhận ORA-04031 và rollback. Business impact: 5% of transactions failing.

### Evidence Provided

```
V$SGASTAT (18:32):
  POOL         NAME                   BYTES
  shared pool  free memory            2,048,000      ← ~2MB (was 180MB an hour ago)
  shared pool  library cache          3,890,000,000
  shared pool  sql area               120,000,000
  shared pool  miscellaneous          580,000,000

V$SYS_TIME_MODEL (delta since 17:30):
  hard parse elapsed time   : 12,847 s
  soft parse elapsed time   :    287 s
  DB CPU                    :  8,200 s

V$SQL (top 5 by SHARABLE_MEM):
  SQL_ID        SHARABLE_MEM_MB  VERSION_COUNT  SQL_TEXT
  x9km2nf7pq4r       847            24,291    SELECT O.ORDER_ID, O.ORDER_DATE, C.CUST...
  7pq4nxk2fm9w       612            18,847    SELECT I.ITEM_ID, I.PRICE, I.STOCK_QT...
  3km8xq7fn2p4       445            12,233    SELECT C.CUSTOMER_ID, C.CUST_FIRST_NAM...
  (all three have same PREFIX pattern, different literal CUSTOMER_ID values)

DBA_REGISTRY (recent changes):
  No schema changes recorded

Application change log (manual check):
  17:30 — New release deployed: "connection pool configuration change — 
           switched from prepared statements to direct string concatenation 
           for dynamic filter support"
```

### Your Mission
1. Identify exact root cause: technical mechanism từ "connection pool config change" → ORA-04031
2. Quantify: nếu mỗi cursor VERSION_COUNT = 24,000 và SHARABLE_MEM = 847MB → Shared Pool consumption đang ở đâu?
3. Immediate actions: order by risk/impact (lowest risk first)
4. One action bạn KHÔNG nên làm mặc dù tempting, và tại sao?

### Evaluation Criteria
- **Root cause chain**: "direct string concatenation" = literal SQL (e.g., `WHERE CUSTOMER_ID = 12345` instead of `WHERE CUSTOMER_ID = :b1`) → each unique customer ID = new cursor → VERSION_COUNT explosion → Library Cache consumes all free Shared Pool memory → ORA-04031
- **Quantification**: 3 SQL statements × avg 635MB × VERSION_COUNT growing = Shared Pool capacity being exhausted. At 18:32: free memory = 2MB → critical state. Every new hard parse requires memory allocation → ORA-04031
- **Ordered actions (low to high risk)**:
  1. Rollback application to previous version (safest, resolves root cause) — requires deployment team approval
  2. `ALTER SYSTEM SET CURSOR_SHARING = FORCE SCOPE = MEMORY` (immediate, no restart, temporary) — stops literal proliferation; risk: histogram-based plans may change
  3. `ALTER SYSTEM FLUSH SHARED_POOL` — DO NOT DO THIS FIRST: with only 2MB free, flush forces ALL sessions to hard parse simultaneously → brief ORA-04031 storm worse than current, plus CPU spike
  4. Kill sessions creating highest-VERSION_COUNT SQL (if identifiable) — reduces symptom but not root cause
- **Anti-pattern**: FLUSH SHARED POOL when free memory < 10MB — classic mistake that escalates incident. Correct sequence: fix root cause (rollback/CURSOR_SHARING) first, then optional flush after free memory recovers
- **Bonus recognition**: SHARABLE_MEM of 847MB for ONE SQL_ID (24,291 versions × ~34KB per cursor) — this means Library Cache is holding 24,000 execution plans for effectively same query. Even after root cause fix, FLUSH SHARED_POOL is needed to reclaim this memory

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_21_shared_pool_senior_guide.md`
