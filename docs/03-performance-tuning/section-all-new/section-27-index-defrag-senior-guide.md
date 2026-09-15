---
title: 'Section 27 — Index Defragmentation: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_27_index_defrag_senior_guide.md
---

# Section 27 — Index Defragmentation: Senior DBA Guide

**Nguồn:** Practice 29 (PDF gốc) + section_all guide + Oracle internals  
**Cập nhật:** 2026-04-25  
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Phần lớn Oracle DBAs từng bị dạy "rebuild indexes định kỳ để giữ hiệu năng". Đây là **một trong những myth phổ biến nhất trong Oracle DBA world** — và Oracle Corp đã nhiều lần phát biểu chính thức rằng nó không đúng.

B-tree index trong Oracle là **self-balancing**: tree không bao giờ mất cân bằng dù bạn insert/delete bao nhiêu rows. Vấn đề thực sự của index fragmentation chỉ xuất hiện trong một pattern cụ thể:

```
Fragmentation THỰC SỰ gây hại:
    Table nhận data tuần tự (sequence, timestamp)
         + Bulk DELETE data cũ thường xuyên
         = Deleted entries tập trung ở LEFT side của index
         = Oracle KHÔNG thể reuse vì key range đó không bao giờ có inserts mới
         = Leaf blocks "rỗng" nhưng vẫn trong index tree
         = Query phải traverse nhiều leaf blocks hơn cần thiết

Fragmentation KHÔNG gây hại (Oracle tự handle):
    Random inserts + random deletes
         = Deleted entries được reuse khi có insert mới vào cùng key range
         = BLEVEL và LEAF_BLOCKS tự cân bằng theo thời gian
```

Trước khi quyết định defragment, câu hỏi đúng là: **"Index này có pattern tuần tự + bulk delete không?"** — không phải "DEL_LF_ROWS có lớn không?"

---

## 2. Internals & Mechanics

### B-tree Index Structure

```
Level 0 (Root):    [Branch block — pointers to branch level]
Level 1 (Branch):  [Branch blocks — pointers to leaf level]
Level 2 (Leaf):    [Leaf block 1] ↔ [Leaf block 2] ↔ [Leaf block 3] ...
                   (doubly-linked list)
```

- **BLEVEL** = số branch levels (không tính leaf và root). BLEVEL=2 nghĩa là 3 levels total (root + 1 branch + leaf).
- Với 500K rows, BLEVEL thường là 1-2. BLEVEL=4 trên bảng nhỏ → anomaly cần check. BLEVEL=4 trên bảng 100M rows → hoàn toàn bình thường.
- **Leaf blocks** được linked thành doubly-linked list → range scan chỉ cần traverse level count lần để tìm start, sau đó scan left-to-right theo linked list.

### "Deleted Entry" — Mechanics

Khi một row bị DELETE:
1. Oracle tìm leaf block chứa index entry của row đó
2. Đánh dấu entry là **logically deleted** (flag bit set, space chưa trả lại)
3. Block vẫn trong index, space vẫn chiếm

Oracle **có thể reuse** một deleted entry khi:
- Có INSERT mới với key value nằm trong cùng key range của block chứa entry đó
- Block đó còn "active" trong tree path

Oracle **không thể reuse** khi:
- Key range đó không có inserts mới (ví dụ: orders từ năm 2020 bị delete, nhưng không có orders mới với ORDER_ID < 500000)
- Đây chính xác là pattern của sequential-insert + bulk-delete-old

### ANALYZE INDEX VALIDATE STRUCTURE — What Actually Happens

```sql
ANALYZE INDEX idx_name VALIDATE STRUCTURE;
SELECT * FROM INDEX_STATS;
```

**Mechanics:**
1. Oracle acquire **Share DML lock** (S mode) trên table — không phải exclusive, nhưng block DDL operations
2. Scan **toàn bộ** index từ root đến mọi leaf block → heavy I/O trên large indexes
3. Populate session-local `INDEX_STATS` view (single row, overwritten mỗi lần ANALYZE)
4. Lock release

**Quan trọng:** `INDEX_STATS` không phải một table — nó là một **virtual view** trong memory, chỉ hold kết quả của lần ANALYZE gần nhất trong session hiện tại. Nếu bạn ANALYZE index A rồi ANALYZE index B → kết quả của A bị mất.

**MOS Doc 989186.1** — alternative không cần lock: sử dụng `DBMS_SPACE` package hoặc indirect methods để estimate fragmentation từ dictionary views mà không phải VALIDATE STRUCTURE.

### REBUILD — Cơ chế bên trong

`ALTER INDEX idx REBUILD`:
1. Oracle scan **table** (không phải index) để collect tất cả key values + ROWIDs
2. Sort trong PGA (hoặc temp nếu PGA không đủ)
3. Build new B-tree từ sorted data → tạo mới toàn bộ extents
4. Drop extents cũ → space trả về tablespace
5. Update data dictionary

`ALTER INDEX idx REBUILD ONLINE`:
1. Create internal **"journal" IOT** để capture tất cả DML changes trên indexed table trong suốt quá trình rebuild
2. Build new index structure (parallel với DML activity)
3. Apply journal changes vào new index
4. Acquire **brief exclusive DDL lock** để cutover old→new index
5. Drop old index + journal IOT

**Tại sao REBUILD ONLINE vẫn bị block:** Bước 4 — brief exclusive DDL lock — phải chờ tất cả **active transactions** trên indexed table commit hoặc rollback. Nếu có long-running transaction (như `update_ttable.sql` trong practice chạy endless loop với `DBMS_LOCK.SLEEP(0.5)`), DDL lock acquisition chờ indefinitely. Wait event: `enq: TX - row lock contention` hoặc `blocking txn id for DDL`.

### COALESCE vs SHRINK SPACE — Phân biệt chi tiết

| Command | Merge leaf blocks | Trả space về tablespace | Lock |
|---------|------------------|------------------------|------|
| `ALTER INDEX idx COALESCE` | ✅ | ❌ | Không |
| `ALTER INDEX idx SHRINK SPACE COMPACT` | ✅ | ❌ | Không |
| `ALTER INDEX idx SHRINK SPACE` | ✅ | ✅ | Brief |

**`SHRINK SPACE` (không có COMPACT)** làm được cả compact + deallocate — nhưng yêu cầu tablespace có **ASSM** (Automatic Segment Space Management). Khác với table SHRINK SPACE, index SHRINK SPACE **không yêu cầu** `ENABLE ROW MOVEMENT` trên table.

Bộ ba này từ low risk đến high risk: COALESCE < SHRINK SPACE COMPACT < SHRINK SPACE < REBUILD.

---

## 3. Production Realities

### Khi Nào KHÔNG Cần Defragment (Myth Busting)

**Myth:** "Rebuild all indexes every weekend / monthly maintenance."

**Reality:** Oracle B-tree tự-balancing. Rebuild định kỳ không được khuyến nghị vì:
- Gây I/O và undo/redo overhead không cần thiết
- Risk locking issues nếu table đang có concurrent activity
- Oracle Support (MOS 122008.1, 989186.1) khuyến nghị **evidence-based** rebuild, không phải scheduled

**Evidence cần có trước khi rebuild:**
- `BLEVEL > 4` *kết hợp* với index không grow theo data (anomaly, không phải normal growth)
- `DEL_LF_ROWS / (LF_ROWS + DEL_LF_ROWS) > 20%` *kết hợp* với sequential pattern
- Confirmed query performance degradation correlating với index stats

### ANALYZE VALIDATE trên Production

`ANALYZE INDEX VALIDATE STRUCTURE` trên large index (1M+ leaf blocks) = **heavy sequential I/O** — có thể kéo dài hàng phút và buffer cache pressure. Không chạy trong business hours.

Thay thế nhẹ hơn:
```sql
-- Estimate fragmentation từ dictionary (no lock, no I/O)
SELECT i.index_name,
       i.blevel,
       i.leaf_blocks,
       i.distinct_keys,
       ROUND((i.leaf_blocks - i.distinct_keys / i.leaf_blocks) * 100, 1) est_frag_pct
FROM   user_ind_statistics i
WHERE  i.last_analyzed > SYSDATE - 7;  -- stats fresh enough?
```

### REBUILD ONLINE — Known Risks

- **12c+:** DDL lock acquisition window giảm đáng kể (Oracle cải tiến journal merge algorithm)
- **Partitioned indexes:** `REBUILD ONLINE` không support tất cả partition types — check trước
- **Large indexes:** PGA pressure khi sort; nếu PGA không đủ → sort spill to temp → disk I/O
- [⚠️ verify with MOS]: Một số 19c versions có bug với `REBUILD ONLINE` trên function-based indexes và compressed indexes

### Automatic Index Maintenance (12c+)

Oracle 12c+ tích hợp **Auto Space Advisor** trong Automated Maintenance Tasks:
- Monitors `DBA_OBJECT_USAGE` (12c replacement của `V$OBJECT_USAGE`)
- Recommends coalesce/rebuild khi threshold vượt
- Findings trong `DBA_ADVISOR_FINDINGS` / `DBA_ADVISOR_RECOMMENDATIONS`

Senior DBA nên biết mechanism này trước khi setup manual maintenance job — có thể Oracle đã tự handle.

### Index Monitoring — Detect Unused Indexes

Trước khi rebuild, check xem index có được dùng không. Không có lý do rebuild một index mà optimizer không bao giờ pick:

```sql
-- 12c+: Enable monitoring
ALTER INDEX schema.idx_name MONITORING USAGE;

-- Sau 1-2 tuần, check:
SELECT index_name, table_name, monitoring, used, start_monitoring, end_monitoring
FROM   dba_object_usage
WHERE  table_owner = 'SOE';

-- Unused index? Consider DROP trước khi rebuild.
```

---

## 4. Decision Framework

### Index Defragmentation Decision Tree

```
Observed performance issue: query chậm hơn trước
        │
        ▼
Check execution plan: có đang dùng index này không?
        │
        ├── KHÔNG dùng index → vấn đề khác (CBO, stats, hints)
        │
        └── CÓ dùng index → check index stats
                │
                ▼
        BLEVEL > 4?
                │
                ├── YES → Abnormal height → REBUILD (với maintenance window)
                │
                └── NO → check DEL_LF_ROWS
                            │
                            ▼
                    DEL_LF_ROWS / Total rows > 20%?
                            │
                            ├── YES → Check insert pattern
                            │         ├── Sequential (ID/timestamp) + bulk delete old
                            │         │   → Deleted entries WON'T be reused
                            │         │   → COALESCE (no window) hoặc REBUILD (with window)
                            │         │
                            │         └── Random inserts/deletes
                            │             → Oracle WILL reuse entries
                            │             → Defragment KHÔNG cần thiết
                            │
                            └── NO → Index healthy, không cần defragment
```

### Rebuild vs Coalesce — Khi Nào Dùng Gì

| Situation | Khuyến nghị |
|-----------|------------|
| Maintenance window available | `REBUILD ONLINE NOLOGGING PARALLEL n` |
| No maintenance window, table under DML | `COALESCE` hoặc `SHRINK SPACE COMPACT` |
| BLEVEL anomaly (height too high for size) | `REBUILD` — coalesce không giảm height |
| STATUS = UNUSABLE | `REBUILD` — coalesce không fix UNUSABLE |
| Just need to remove deleted entries, tablespace space not critical | `COALESCE` |
| Need to reclaim tablespace space + ASSM tablespace | `SHRINK SPACE` |
| Need to move index to different tablespace | `REBUILD TABLESPACE new_tbs` |

**Coalesce KHÔNG fix:** BLEVEL anomaly, UNUSABLE status, wrong tablespace placement.

---

## 5. Key SQL / Commands

### 5.1 — Index Health Assessment (No Lock)

```sql
-- Overview: all indexes, ordered by potential fragmentation risk
SELECT i.index_name,
       i.table_name,
       i.blevel,
       i.leaf_blocks,
       i.distinct_keys,
       i.clustering_factor,
       i.status,
       TO_CHAR(i.last_analyzed, 'YYYY-MM-DD') last_analyzed
FROM   user_ind_statistics i
WHERE  i.table_name = 'TTABLE'  -- or remove filter for all
ORDER  BY i.leaf_blocks DESC;
```

### 5.2 — Detailed Index Stats (Requires Lock — Use in Maintenance)

```sql
-- Analyze one index and read results
ANALYZE INDEX schema_name.index_name VALIDATE STRUCTURE;

SELECT height,
       blocks,
       lf_blks,
       br_blks,
       del_lf_rows,
       lf_rows,
       ROUND(del_lf_rows / DECODE(lf_rows + del_lf_rows, 0, 1,
             lf_rows + del_lf_rows) * 100, 1)  pct_deleted,
       btree_space,
       pct_used
FROM   index_stats;
-- pct_deleted > 20% + sequential pattern → consider defrag
```

### 5.3 — Batch Fragmentation Check (Script Multiple Indexes)

```sql
-- Generate ANALYZE commands + collect results
-- Run each ANALYZE separately then union INDEX_STATS result
-- This is a workaround since INDEX_STATS is single-row

-- Simple version: check BLEVEL across all indexes for a table
SELECT index_name, blevel, leaf_blocks,
       CASE
         WHEN blevel > 4                THEN 'HIGH - Consider Rebuild'
         WHEN leaf_blocks > 10000       THEN 'LARGE - Monitor'
         ELSE                                'OK'
       END  recommendation
FROM   dba_indexes
WHERE  owner      = 'SOE'
  AND  table_name = 'ORDER_ITEMS'
ORDER  BY blevel DESC, leaf_blocks DESC;
```

### 5.4 — REBUILD with Monitoring

```sql
-- Tag the session for monitoring from another window
EXEC dbms_session.set_identifier('IDX_REBUILD_' || TO_CHAR(SYSDATE,'HH24MISS'));

-- Rebuild with performance options
ALTER INDEX soe.ttable_idx
  REBUILD ONLINE
  NOLOGGING          -- less redo (not archive-safe, re-enable logging after)
  PARALLEL 4         -- use 4 parallel slaves
  COMPUTE STATISTICS;

-- After rebuild, reset parallel degree
ALTER INDEX soe.ttable_idx NOPARALLEL;

-- If NOLOGGING was used, force a backup or mark for re-logging
ALTER INDEX soe.ttable_idx LOGGING;
```

```sql
-- From a monitoring window: watch rebuild session
SELECT s.sid, s.serial#, s.event, s.seconds_in_wait,
       s.client_identifier, s.state
FROM   v$session s
WHERE  s.client_identifier LIKE 'IDX_REBUILD%';
```

### 5.5 — COALESCE (Production-Safe)

```sql
-- No lock, works during DML
ALTER INDEX soe.ttable_idx COALESCE;

-- If ASSM tablespace and want to also return space:
ALTER INDEX soe.ttable_idx SHRINK SPACE;
-- Does not require ENABLE ROW MOVEMENT on table (unlike table shrink)
```

### 5.6 — Generate Rebuild Script for All UNUSABLE Indexes

```sql
-- Consolidated rebuild script
SELECT 'ALTER INDEX ' || owner || '.' || index_name
       || CASE WHEN partitioned = 'NO'
               THEN ' REBUILD ONLINE NOLOGGING;'
               ELSE ' REBUILD;'  -- partitioned: check partition level
          END  rebuild_ddl,
       status,
       partitioned
FROM   dba_indexes
WHERE  owner  = 'SOE'
  AND  status = 'UNUSABLE'
ORDER  BY table_name, index_name;
```

### 5.7 — Index Usage Monitoring (12c+)

```sql
-- Enable monitoring for selected indexes
ALTER INDEX soe.order_items_pk          MONITORING USAGE;
ALTER INDEX soe.order_items_idx1        MONITORING USAGE;

-- Check after workload period
SELECT index_name, table_name, monitoring, used,
       start_monitoring, end_monitoring
FROM   dba_object_usage
WHERE  table_owner = 'SOE'
ORDER  BY used DESC, index_name;

-- Disable monitoring
ALTER INDEX soe.order_items_pk NOMONITORING USAGE;
```

### 5.8 — Check Automated Maintenance Recommendations

```sql
-- Did Auto Space Advisor already recommend defrag?
SELECT f.task_name, f.finding_name, f.impact_type,
       f.message, r.benefit
FROM   dba_advisor_findings f
       JOIN dba_advisor_recommendations r
         ON f.task_id = r.task_id AND f.finding_id = r.finding_id
WHERE  f.task_name LIKE '%AUTO_SPACE%'
  AND  f.object_type = 'INDEX'
ORDER  BY r.benefit DESC
FETCH FIRST 20 ROWS ONLY;
```

---

## 6. Senior Checklist

Trước khi thực hiện bất kỳ index defragmentation nào trên production:

- [ ] **Xác nhận fragmentation là root cause:** execution plan confirm index đang được dùng, query thực sự chậm hơn baseline — không defragment dựa trên assumption
- [ ] **Kiểm tra insert pattern của table:** sequential (ID/timestamp) + bulk delete old data → defrag worth it; random inserts/deletes → Oracle self-heals, không cần
- [ ] **Đo trước khi làm:** `ANALYZE INDEX VALIDATE STRUCTURE` + record `DEL_LF_ROWS`, `BLEVEL`, `LF_BLKS` để compare sau; nhớ chạy ngoài business hours vì I/O heavy
- [ ] **Chọn đúng method:** maintenance window → `REBUILD ONLINE NOLOGGING`; không có window → `COALESCE`; cần return space + ASSM → `SHRINK SPACE`; BLEVEL anomaly → chỉ REBUILD mới fix được
- [ ] **Với REBUILD ONLINE:** tag session bằng `DBMS_SESSION.SET_IDENTIFIER`, có monitoring window sẵn để check `V$SESSION` nếu rebuild bị block; có plan B (COALESCE) nếu blocking kéo dài
- [ ] **Check index có thực sự được dùng không** (`DBA_OBJECT_USAGE` sau monitoring period): rebuilding một index mà optimizer không bao giờ chọn là pure waste
- [ ] **Verify sau khi xong:** re-run `ANALYZE INDEX VALIDATE STRUCTURE`, confirm `DEL_LF_ROWS = 0`; nếu dùng `NOLOGGING` → re-enable `LOGGING` + note cho next backup cycle

---

# LAB EXERCISES

## Exercise 1 — Determine Whether an Index Actually Needs Defragmentation

**Scenario:** An index on `ORDER_ITEMS(ORDER_DATE)` has been flagged by a junior DBA as "heavily fragmented — needs rebuild." The justification is that `DEL_LF_ROWS = 180,000` which is 36% of total leaf rows. Before scheduling the maintenance window, you're asked to validate the recommendation.

**Tasks:**

1. Run `ANALYZE INDEX soe.order_items_idx_date VALIDATE STRUCTURE` and record all columns from `INDEX_STATS`. Also query `DBA_INDEXES` for the same index — specifically `BLEVEL`, `CLUSTERING_FACTOR`, and `LAST_ANALYZED`.

2. Profile the table's DML pattern over the past 30 days: query `DBA_HIST_SQLSTAT` filtered by `TABLE_NAME = 'ORDER_ITEMS'` and look at the ratio of inserts vs deletes. Are rows inserted with monotonically increasing `ORDER_DATE`? Are old orders regularly deleted?

3. Enable `MONITORING USAGE` on the index for one business day. Check `DBA_OBJECT_USAGE`: is the index actually being picked by the optimizer?

4. Based on findings from steps 1–3, write a one-paragraph recommendation: rebuild, coalesce, or do nothing — with justification referencing the actual metrics.

**Expected Findings:**
- If ORDER_DATE is used as a sequential key (older orders deleted regularly) + DEL_LF_ROWS high + index IS used → defragmentation justified (COALESCE since no maintenance window)
- If DELETE pattern is random, not left-skewed → Oracle will naturally reuse entries → no action needed
- If index is NOT used (MONITORING USAGE shows `USED=NO`) → consider DROP, not rebuild

**Debrief Questions:**
- Một DBA khác argue rằng "DEL_LF_ROWS=36% là trên threshold, phải rebuild". Bạn phản biện điểm nào?
- Sau khi COALESCE, `BLOCKS` vẫn như cũ. Business muốn "reclaim disk space". Làm thế nào để thực sự trả space về tablespace mà không cần maintenance window?

---

## Exercise 2 — Rebuild Online Under Concurrent DML Load

**Scenario:** Table `PROMOTIONS` (200K rows, one B-tree index on `PROMO_ID`) shows confirmed fragmentation (BLEVEL=4, DEL_LF_ROWS=45% of leaf rows, sequential insert/delete pattern confirmed). You need to rebuild the index tonight without a full maintenance window — application continues running with updates.

**Tasks:**

1. Set up a simulation: start a loop that randomly updates `PROMOTIONS.PROMO_STATUS` every 0.5 seconds (keep transactions open, don't commit immediately — simulate a realistic batch process).

2. From a second session, tag it with `DBMS_SESSION.SET_IDENTIFIER('REBUILD_TEST')` and execute `ALTER INDEX soe.promotions_idx REBUILD ONLINE`.

3. From a third monitoring session, query `V$SESSION` every 30 seconds to observe the wait event. Record: does the rebuild start progressing, does it block, how long does it wait?

4. Cancel the update loop. Observe: does the rebuild complete immediately? Record the time gap between loop cancellation and rebuild completion.

5. Post-rebuild: run `ANALYZE INDEX VALIDATE STRUCTURE` and confirm `DEL_LF_ROWS = 0`, `BLEVEL` back to normal.

**Expected Findings:**
- Rebuild starts and progresses (journal IOT capturing changes)
- At final cutover phase: blocks on `enq: TX - row lock contention` or `blocking txn id for DDL`
- After loop cancelled: rebuild completes within seconds (brief lock acquired, journal applied, cutover done)

**Debrief Questions:**
- Trong scenario thực tế production, bạn không thể cancel application DML. Cách nào để force rebuild hoàn thành mà không kill application sessions?
- Nếu rebuild bị block 30+ phút và bạn quyết định cancel (`Ctrl+C`): index bị để ở trạng thái nào? Valid, Unusable, hay còn ở trạng thái cũ?
- NOLOGGING REBUILD có nghĩa là gì cho disaster recovery? Nếu database crash ngay sau rebuild nologging, điều gì xảy ra với index?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**

Quarterly maintenance window (Saturday 02:00–06:00). DBA team chạy script maintenance tự động:

```sql
-- maintenance_script.sql (inherited script, nobody knows who wrote it)
BEGIN
  FOR r IN (SELECT index_name, owner FROM dba_indexes WHERE owner = 'SOE') LOOP
    EXECUTE IMMEDIATE 'ALTER INDEX ' || r.owner || '.' || r.index_name
                   || ' REBUILD ONLINE NOLOGGING';
  END LOOP;
END;
/
```

Script started at 02:15. At 04:45, it's still running. Window closes at 06:00. You are called in at 05:00.

**Evidence Provided:**

*V$SESSION at 05:00:*
```
SID  USERNAME  EVENT                              SECONDS_IN_WAIT  STATE
---  --------  ---------------------------------- ---------------  ----------
127  SYS       blocking txn id for DDL                      6,847  WAITING
```

*V$LOCK at 05:00:*
```
SID  TYPE  ID1   ID2  LMODE  REQUEST  BLOCK
---  ----  ----  ---  -----  -------  -----
127  TM    8821    0      4      0        0    ← SID 127 holds TM share lock on table
 89  TM    8821    0      3      4        1    ← SID 89 holds TM row-exclusive, blocking
```

*DBA_INDEXES (queried at 05:00, sample):*
```
INDEX_NAME                  STATUS     LAST_REBUILT
--------------------------- ---------  ------------
ORDER_ITEMS_PK              VALID      2026-04-26 02:18
ORDER_ITEMS_IDX_DATE        VALID      2026-04-26 02:23
ORDER_ITEMS_IDX_CUST        VALID      2026-04-26 02:31
PROMOTIONS_IDX              UNUSABLE   (never rebuilt tonight)
ORDER_HISTORY_IDX           VALID      2026-04-26 04:12
```

*V$SESSION SID 89:*
```
SID  USERNAME  MODULE              ACTION          STATUS   LAST_CALL_ET
---  --------  ------------------  --------------  -------  ------------
89   SOE       BATCH_LOADER        LOAD_PROMOS     ACTIVE          7,120
```

**Your Mission:**

1. Explain exactly what is happening at 05:00. Why is SID 127 blocked? Who/what is SID 89? What is the maintenance script currently trying to rebuild?

2. The window closes in 55 minutes. Which indexes are already safely rebuilt? Which is UNUSABLE? What is the risk of leaving the window without finishing?

3. Give a decision tree for the remaining 55 minutes: kill SID 89 or not? Complete remaining rebuilds or abort? What's the safest sequence of actions to take before 06:00?

4. Critique the maintenance script architecturally: list 3 design flaws and propose how each should have been done.

5. Post-incident: propose a proper index health monitoring + maintenance strategy that doesn't require scheduled full rebuilds.

**Evaluation Criteria:**

- [ ] Correctly identify: SID 127 is waiting at REBUILD ONLINE final DDL lock cutover; SID 89 is a batch job (`BATCH_LOADER/LOAD_PROMOS`) with an open transaction on the table being rebuilt — not a random user
- [ ] Identify that `PROMOTIONS_IDX` is UNUSABLE — this is the only truly critical issue; valid indexes from before the script are still fine
- [ ] Decision: killing SID 89 is necessary only if PROMOTIONS_IDX is on a critical query path; otherwise, abort this rebuild + schedule separately
- [ ] Script flaws: (1) no timeout/kill fallback mechanism; (2) rebuilding ALL indexes including healthy ones; (3) no pre-check for DML activity; (4) NOLOGGING without post-rebuild LOGGING reset; (5) no verification loop after each rebuild
- [ ] Proposed strategy: evidence-based maintenance (only rebuild when threshold met), COALESCE for production 24/7 tables, use `DBA_OBJECT_USAGE` for unused index detection, leverage Auto Space Advisor (12c+)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_27_index_defrag_senior_guide.md`
