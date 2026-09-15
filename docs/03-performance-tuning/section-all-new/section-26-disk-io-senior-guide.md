---
title: 'Section 26 — Disk I/O Tuning: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_26_disk_io_senior_guide.md
---

# Section 26 — Disk I/O Tuning: Senior DBA Guide

**Nguồn:** Practice 28 (PDF gốc) + section_all guide + Oracle internals  
**Cập nhật:** 2026-04-25  
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Khi gặp I/O wait events trong top waits, câu hỏi đầu tiên không phải là "storage của tôi chậm không?" mà là: **"Query này đang làm quá nhiều physical I/O, hay storage thực sự không đáp ứng được?"**

Đây là hai bài toán hoàn toàn khác nhau:

```
I/O wait events cao
        │
        ├── Logic problem (query làm quá nhiều I/O)
        │       → FTS thay vì index, UNUSABLE indexes, bad execution plan
        │       → Fix: fix query / fix indexes / fix stats
        │
        └── Capacity problem (storage không đủ bandwidth)
                → Nhiều sessions cùng chờ, wait time per request cao
                → Fix: FILESYSTEMIO_OPTIONS, ASM striping, thêm disk
```

**90% "I/O bottleneck" trên production thực ra là logic problem** — query đang đọc nhiều block hơn nó cần phải đọc. Practice 28 minh họa case điển hình nhất: một `ALTER TABLE MOVE` thầm lặng biến tất cả indexes thành UNUSABLE, đẩy query equality predicate từ index lookup thành Full Table Scan. Không phải storage chậm — là query làm việc sai.

Capacity problem thực sự chỉ xuất hiện khi: throughput yêu cầu vượt hardware limit, I/O per-request latency vượt baseline (>10ms mechanical, >2ms SSD), nhiều sessions song song cùng chờ. Để confirm capacity problem, bạn cần cả hai phía: Oracle wait time *và* OS `iostat`/`sar`.

---

## 2. Internals & Mechanics

### I/O Path trong Oracle

```
SQL executes
    │
    ▼
Buffer Cache lookup (LRU scan)
    ├── HIT → return block (no physical I/O)
    └── MISS → physical read required
                │
                ├── Single-block request  → db file sequential read
                │   (index block, single row fetch by rowid)
                │
                ├── Multiblock request    → db file scattered read
                │   (FTS, index range scan large range)
                │   blocks go to non-contiguous buffer cache slots ("scattered")
                │
                └── Direct path read      → bypass buffer cache entirely
                    (large FTS, parallel query, temp segment)
                    reads go directly into PGA
```

**"Scattered" không phải về disk layout** — tên này mô tả cách blocks được đặt vào buffer cache: chúng không cần vào các slot liền kề. Multiblock read đọc `DB_FILE_MULTIBLOCK_READ_COUNT` blocks mỗi request (default thường 8–128 tùy platform/version).

### Khi nào Oracle chọn Direct Path Read?

Oracle chuyển FTS sang `direct path read` khi table size > `_small_table_threshold` (hidden parameter, default ~2% buffer cache size). Cụ thể:
- Oracle 11g+: threshold tính theo số cache buffers; nếu table > threshold → direct path
- Parallel FTS *luôn* dùng direct path (PQ slaves không dùng buffer cache)
- Temp segment reads (sort, hash join spill) → luôn direct path

**Implication:** với large FTS, bạn sẽ thấy `direct path read` chứ không phải `db file scattered read`. Cả hai đều là I/O wait — nhưng direct path không làm ấm buffer cache.

### FILESYSTEMIO_OPTIONS — Mechanics

| Value | ASYNCH | DIRECTIO | Giải thích |
|-------|--------|----------|-----------|
| `NONE` | ✗ | ✗ | Oracle block chờ từng I/O call hoàn thành; OS cache datafiles |
| `ASYNCH` | ✓ | ✗ | Oracle submit I/O và tiếp tục, OS notify khi xong; OS vẫn cache |
| `DIRECTIO` | ✗ | ✓ | Bypass OS page cache; block on each I/O |
| `SETALL` | ✓ | ✓ | Async + bypass OS cache — **recommended cho non-ASM** |

**Tại sao DIRECTIO quan trọng:** Oracle đã có buffer cache để cache data blocks. Nếu OS cũng cache cùng blocks trong page cache → **double caching** — lãng phí RAM, giảm hiệu quả. DIRECTIO loại bỏ lớp cache OS.

**Lưu ý:** Trên ASM (Automatic Storage Management), Oracle I/O đi qua ASM kernel module (`kfk`/`asmlib`) → FILESYSTEMIO_OPTIONS thường bị ignore hoặc không applicable. ASM tự handle async I/O.

**Lưu ý v19c+:** Với Exadata và các storage appliance, cơ chế có thể khác — verify trước khi thay đổi.

### ALTER TABLE MOVE → UNUSABLE Indexes — Cơ chế

Khi `ALTER TABLE t MOVE TABLESPACE x`:
1. Oracle copy toàn bộ rows sang extent mới trong tablespace đích
2. **Mỗi row nhận ROWID mới** (vì ROWID encode physical location: file#, block#, row#)
3. B-tree indexes lưu `(key_value, rowid)` → tất cả ROWIDs đã thay đổi → index trỏ sai
4. Oracle mark tất cả **global indexes** là `UNUSABLE` thay vì để chúng trỏ sai
5. Optimizer *biết* về UNUSABLE status → skip index → dùng FTS

Trường hợp tương tự:
- `ALTER TABLE ... SPLIT/MERGE PARTITION` → partition-level indexes UNUSABLE
- `IMPORT` (không có `INDEXES=y`) → indexes không rebuild sau import
- `TRUNCATE TABLE` với `REUSE STORAGE DROP STORAGE` → thường giữ valid nhưng empty

**Fix nhanh (11g/12c):** Thêm `UPDATE INDEXES` vào MOVE clause:
```sql
ALTER TABLE order_items MOVE TABLESPACE soetbs UPDATE INDEXES;
```
Oracle tự maintain indexes trong suốt quá trình MOVE (online, chậm hơn, nhưng không gián đoạn).

**12c+ Online MOVE:**
```sql
ALTER TABLE order_items MOVE ONLINE;  -- không cần UNUSABLE handling
```

---

## 3. Production Realities

### The UNUSABLE Index Footgun

Đây là trap phổ biến nhất trên production. Junior DBA thực hiện table reorganization (MOVE, partition management), không biết về UNUSABLE index consequence, application vẫn chạy nhưng chậm hơn 50-100x.

**Detection pattern:** Query có equality/range predicate trên indexed column nhưng execution plan là FTS → kiểm tra `DBA_INDEXES.STATUS = 'UNUSABLE'` ngay.

**Pre-MOVE checklist:**
```sql
-- Đếm indexes sẽ bị ảnh hưởng
SELECT INDEX_NAME, INDEX_TYPE, UNIQUENESS
FROM DBA_INDEXES
WHERE OWNER = 'SOE' AND TABLE_NAME = 'ORDER_ITEMS';

-- Script rebuild sẵn trước khi MOVE
SELECT 'ALTER INDEX ' || OWNER || '.' || INDEX_NAME || ' REBUILD ONLINE NOLOGGING;'
FROM DBA_INDEXES
WHERE OWNER = 'SOE' AND TABLE_NAME = 'ORDER_ITEMS';
```

### Online Rebuild vs. Regular Rebuild

| | `REBUILD` | `REBUILD ONLINE` |
|--|-----------|-----------------|
| Table lock | Share lock (DML blocked) | No table lock |
| Undo/Redo generated | Less | More (journal concurrent DML) |
| Prerequisite | — | `DML_LOCKS > 0` |
| Duration | Faster | Slower |
| Use when | Maintenance window | 24/7 critical table |

[⚠️ verify with MOS]: `REBUILD ONLINE` trên large partitioned indexes trong 19c có một số known bugs — check MOS trước khi apply in production.

### I/O Calibration — Khi nào và Khi nào không

**Nên chạy:**
- Môi trường mới setup, cần baseline storage performance
- Trước khi configure parallel query (Resource Manager dùng kết quả)
- Sau storage hardware change (disk replacement, cache expansion)
- Khi nghi ngờ storage degraded (RAID rebuild, một disk chết)

**Không nên chạy:**
- Trên live production — QUIESCE RESTRICTED block tất cả non-DBA transactions
- Trong business hours — calibration làm maximum I/O stress test, 9+ phút
- Khi đã biết storage specs từ vendor — calibration chỉ measure Oracle-visible throughput

**Kết quả calibration ảnh hưởng gì:**
- Oracle Resource Manager dùng IOPS/MBPS để allocate I/O slaves cho parallel queries
- Exadata: Smart Scan offload decision dựa trên calibration results
- `DBA_RSRC_IO_CALIBRATE` là source of truth Oracle dùng — nếu numbers sai (e.g., chạy trên VM), parallel query performance bị miscalibrate

### V$IOSTAT_FILE vs V$FILESTAT

| | `V$IOSTAT_FILE` | `V$FILESTAT` |
|--|-----------------|-------------|
| Granularity | Small reads / Large reads separate | Total reads/writes |
| Filetype filter | Có (`FILETYPE_NAME`) | Không (chỉ datafiles) |
| Async I/O info | Có (`ASYNCH_IO` column) | Không |
| Covers | All file types (data, temp, log, control, archive) | Chỉ datafiles |
| Added in | 11g | Older |

Dùng `V$IOSTAT_FILE` cho analysis. Dùng `V$FILESTAT` chỉ khi query cũ cần backward compat.

---

## 4. Decision Framework

### I/O Diagnostic Decision Tree

```
Báo cáo: session/process chậm
    │
    ▼
V$SESSION_EVENT / ASH → I/O wait events trong top?
    │
    ├── NO  → Vấn đề ở chỗ khác (CPU, latch, lock)
    │
    └── YES → Xác định loại I/O wait:
                │
                ├── db file sequential read cao
                │   → Index access chậm
                │   → Check: index là local hay global? Block size? PCTFREE cao?
                │   → Check: storage latency per I/O (READTIM/PHYRDS từ V$FILESTAT)
                │
                ├── db file scattered read cao
                │   → FTS đang xảy ra
                │   → Check: có index phù hợp không? STATUS UNUSABLE?
                │   → Check: stats hiện tại? CBO quyết định FTS có đúng không?
                │
                ├── direct path read cao
                │   → Large FTS hoặc parallel query hoặc sort spill
                │   → Check: query có parallel hint không? PGA workarea đủ không?
                │   → Check: bảng có thực sự lớn đến mức cần FTS không?
                │
                └── Nhiều loại cùng cao (system-wide)
                    → Capacity problem
                    → Check: wait time per I/O (ms), OS iostat %util, await
                    → Run CALIBRATE_IO để confirm storage baseline
```

### Khi nào nên Rebuild Index?

**Phải rebuild:**
- `STATUS = 'UNUSABLE'` → không optional

**Nên rebuild (với evidence):**
```sql
ANALYZE INDEX schema.idx_name VALIDATE STRUCTURE;
SELECT NAME, HEIGHT, DEL_LF_ROWS, LF_ROWS,
       ROUND(DEL_LF_ROWS/DECODE(LF_ROWS,0,1,LF_ROWS)*100,1) PCT_DELETED
FROM INDEX_STATS;
-- Rebuild if: HEIGHT > 4 AND PCT_DELETED > 20%
```

**Đừng rebuild chỉ vì "index cũ":** Oracle B-tree indexes tự-balancing. Rebuild không cải thiện query performance trừ khi có evidence cụ thể (height cao, deletion heavy). Rebuilding tốn I/O + lock + undo/redo.

---

## 5. Key SQL / Commands

### 5.1 — Phát hiện I/O Wait Events của Session

```sql
-- Wait events theo session, lọc theo APPLICATION attribute
SELECT e.event,
       e.wait_class,
       e.time_waited       csec_waited,
       e.total_waits,
       ROUND(e.time_waited / DECODE(e.total_waits,0,1,e.total_waits), 2) avg_wait_csec
FROM   v$session_event e
       JOIN v$session s ON e.sid = s.sid
WHERE  s.module = 'SALES'          -- hoặc filter theo SID/USERNAME
  AND  s.action = 'UPDATE_VAT'
  AND  e.wait_class <> 'Idle'
ORDER  BY e.time_waited DESC;
```

### 5.2 — ASH: Top SQL đang gây I/O (real-time)

```sql
-- 5 phút qua, top SQL by I/O waits
SELECT ash.sql_id,
       ash.event,
       COUNT(*)                                            samples,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)  pct
FROM   v$active_session_history ash
WHERE  ash.session_state = 'WAITING'
  AND  ash.wait_class    = 'User I/O'
  AND  ash.sample_time   > SYSDATE - 5/1440
GROUP  BY ash.sql_id, ash.event
ORDER  BY samples DESC
FETCH FIRST 10 ROWS ONLY;
```

### 5.3 — Kiểm tra UNUSABLE Indexes

```sql
-- Tất cả UNUSABLE indexes của user/table
SELECT i.owner,
       i.index_name,
       i.table_name,
       i.index_type,
       i.status,
       i.partitioned
FROM   dba_indexes i
WHERE  i.status = 'UNUSABLE'
  AND  i.owner  = 'SOE'         -- thay schema
ORDER  BY i.table_name, i.index_name;

-- Nếu partitioned: check partition level
SELECT ip.index_name, ip.partition_name, ip.status
FROM   dba_ind_partitions ip
       JOIN dba_indexes i ON ip.index_name = i.index_name AND ip.index_owner = i.owner
WHERE  i.owner  = 'SOE'
  AND  ip.status = 'UNUSABLE';
```

### 5.4 — Generate Rebuild Script

```sql
-- Script cho tất cả UNUSABLE indexes (non-partitioned)
SELECT 'ALTER INDEX ' || owner || '.' || index_name
       || ' REBUILD ONLINE NOLOGGING PARALLEL 4;'   rebuild_cmd
FROM   dba_indexes
WHERE  owner  = 'SOE'
  AND  status = 'UNUSABLE'
ORDER  BY table_name, index_name;

-- Sau rebuild, reset parallel degree
-- ALTER INDEX soe.idx_name NOPARALLEL;
```

### 5.5 — V$IOSTAT_FILE: Async I/O Status + Hot Files

```sql
-- Datafiles: async I/O status + read/write volume
SELECT d.name                                   datafile,
       i.asynch_io,
       i.small_read_reqs,
       i.large_read_reqs,
       ROUND(i.small_read_servicetime
             / DECODE(i.small_read_reqs,0,1,i.small_read_reqs), 2)  avg_small_read_ms,
       ROUND(i.large_read_servicetime
             / DECODE(i.large_read_reqs,0,1,i.large_read_reqs), 2)  avg_large_read_ms
FROM   v$iostat_file i
       JOIN v$datafile d ON i.file_no = d.file#
WHERE  i.filetype_name = 'Data File'
ORDER  BY i.small_read_reqs + i.large_read_reqs DESC;
```

### 5.6 — V$FILESTAT: Average Read Latency per File

```sql
-- Average I/O latency per datafile (cumulative since instance start)
SELECT f.file#,
       d.name,
       f.phyrds,
       f.phywrts,
       ROUND(f.readtim  / DECODE(f.phyrds, 0,1,f.phyrds)  * 10, 2)  avg_read_ms,
       ROUND(f.writetim / DECODE(f.phywrts,0,1,f.phywrts) * 10, 2)  avg_write_ms
FROM   v$filestat f
       JOIN v$datafile d ON f.file# = d.file#
WHERE  f.phyrds > 0
ORDER  BY avg_read_ms DESC;
-- Latency unit in V$FILESTAT: centiseconds (x10 → ms)
```

### 5.7 — Enable Async I/O + Calibrate

```sql
-- Step 1: Check current setting
SHOW PARAMETER filesystemio_options;

-- Step 2: Enable SETALL (requires restart)
ALTER SYSTEM SET filesystemio_options = SETALL SCOPE = SPFILE;
SHUTDOWN IMMEDIATE;
STARTUP;

-- Step 3: Verify
SELECT DISTINCT asynch_io FROM v$iostat_file
WHERE filetype_name = 'Data File';

-- Step 4: Quiesce and calibrate
ALTER SYSTEM QUIESCE RESTRICTED;

DECLARE
  v_lat  INTEGER;
  v_iops INTEGER;
  v_mbps INTEGER;
BEGIN
  dbms_resource_manager.calibrate_io(
      num_physical_disks => 1         -- set correctly for your hardware
    , max_latency        => 20        -- tolerable latency ms
    , max_iops           => v_iops
    , max_mbps           => v_mbps
    , actual_latency     => v_lat
  );
  dbms_output.put_line('IOPS    = ' || v_iops);
  dbms_output.put_line('MBPS    = ' || v_mbps);
  dbms_output.put_line('Latency = ' || v_lat || ' ms');
END;
/

ALTER SYSTEM UNQUIESCE;

-- Step 5: View saved results
SELECT max_iops, max_mbps, max_pmbps, latency, num_physical_disks,
       last_calibrated
FROM   dba_rsrc_io_calibrate;
```

### 5.8 — AWR: SQL Ordered by Physical Reads

```sql
-- Top SQL by physical reads từ AWR snapshot range
SELECT s.sql_id,
       s.executions_delta                          execs,
       s.disk_reads_delta                          phys_reads,
       ROUND(s.disk_reads_delta
             / DECODE(s.executions_delta,0,1,s.executions_delta))  reads_per_exec,
       SUBSTR(t.sql_text, 1, 80)                   sql_text
FROM   dba_hist_sqlstat s
       JOIN dba_hist_sqltext t ON s.sql_id = t.sql_id AND s.dbid = t.dbid
WHERE  s.snap_id BETWEEN :begin_snap AND :end_snap
  AND  s.dbid      = :dbid
  AND  s.instance_number = :inst_num
ORDER  BY s.disk_reads_delta DESC
FETCH  FIRST 10 ROWS ONLY;
```

---

## 6. Senior Checklist

Khi I/O waits xuất hiện trong Top 5 và bạn cần triage nhanh:

- [ ] **Xác định loại I/O event:** sequential (index), scattered (FTS via buffer), direct path (FTS bypass / sort spill) — từ `V$SESSION_EVENT` hoặc ASH
- [ ] **Tìm culprit SQL:** ASH filter theo MODULE/ACTION hoặc SQL_ID → xem execution plan, đặc biệt chú ý FTS trên bảng có index
- [ ] **Kiểm tra UNUSABLE indexes ngay:** `DBA_INDEXES WHERE STATUS='UNUSABLE'` — đây là fix nhanh nhất nếu applicable; check cả `DBA_IND_PARTITIONS`
- [ ] **Xác nhận root cause của UNUSABLE:** ai làm MOVE/SPLIT/MERGE gần đây? `DBA_AUDIT_TRAIL` hoặc alert log / DDL trigger history
- [ ] **Cross-check với OS:** nếu waits high và indexes đều valid → lấy `iostat -x 5` trên Linux; `%util > 80%` hoặc `await > 10ms` → capacity problem thực sự
- [ ] **Verify async I/O đang bật:** `V$IOSTAT_FILE.ASYNCH_IO = 'ASYNC_ON'` — nếu tắt, `FILESYSTEMIO_OPTIONS=SETALL` có thể giảm I/O latency đáng kể (nhưng cần restart)
- [ ] **Calibration baseline tồn tại không?** `DBA_RSRC_IO_CALIBRATE` — nếu NULL, bạn không có baseline để so sánh khi storage degraded

---

# LAB EXERCISES

## Exercise 1 — Diagnose I/O Regression Caused by Silent Schema Change

**Scenario:** Một stored procedure `CALCULATE_VAT` xử lý `ORDER_ITEMS` theo từng `ORDER_ID` đã chạy ổn trong 6 tháng. Sáng nay sau maintenance window cuối tuần, DBA nhận report process này chậm gấp 50 lần. Không có code change, không có data growth đáng kể.

**Tasks:**

1. Query `V$SESSION_EVENT` (filter theo MODULE='SALES', ACTION='UPDATE_VAT') — ghi lại top wait events và `TIME_WAITED` của mỗi event.

2. Generate ASH report cho module/action đó trong 15 phút qua. Trong section "Top SQL Statements", tìm SQL có `disk_reads` cao nhất. Paste execution plan của SQL đó (`DBMS_XPLAN.DISPLAY_CURSOR`).

3. Query `DBA_INDEXES` cho bảng `ORDER_ITEMS` — có index nào UNUSABLE không? Nếu có, trace lại bằng `DBA_AUDIT_TRAIL` hoặc alert log xem DDL nào xảy ra trong maintenance window.

4. Rebuild tất cả UNUSABLE indexes với `REBUILD ONLINE`. Chạy lại process và so sánh `TIME_WAITED` từ `V$SESSION_EVENT`.

**Expected Findings:**
- Top wait event: `db file scattered read` hoặc `direct path read`
- Execution plan: `TABLE ACCESS FULL` trên `ORDER_ITEMS` dù query có `WHERE ORDER_ID = :b1`
- DBA_INDEXES: tất cả indexes trên `ORDER_ITEMS` STATUS = 'UNUSABLE'
- Sau rebuild: process hoàn thành ~50x nhanh hơn, I/O waits biến mất khỏi top events

**Debrief Questions:**
- Tại sao `ALTER TABLE MOVE` lại làm indexes UNUSABLE thay vì Oracle tự update ROWIDs trong index?
- Nếu table có 20 indexes và bạn cần rebuild online không downtime — thứ tự rebuild có quan trọng không? Unique index PK có nên rebuild trước không?
- `UPDATE INDEXES` clause trong MOVE statement có trade-off gì so với rebuild sau?

---

## Exercise 2 — Baseline Storage I/O Capacity via Calibration

**Scenario:** Bạn vừa nhận bàn giao một Oracle 19c database mới setup trên môi trường on-premise. Không có I/O baseline nào tồn tại. Team Storage nói storage system này "capable of 50,000 IOPS" — nhưng đó là vendor spec, không phải Oracle-visible IOPS. Bạn cần thiết lập baseline thực tế.

**Tasks:**

1. Kiểm tra `FILESYSTEMIO_OPTIONS` hiện tại. Nếu không phải `SETALL`, enable và restart database. Verify `V$IOSTAT_FILE.ASYNCH_IO` sau restart.

2. Schedule I/O Calibration trong maintenance window (yêu cầu QUIESCE RESTRICTED):
   - Xác định số physical disks thực tế (hỏi storage team hoặc `ls /dev/sd*` trên OS)
   - Chạy `DBMS_RESOURCE_MANAGER.CALIBRATE_IO` với `max_latency=10` (SSD) hoặc `20` (spinning)
   - Ghi lại thời gian chạy

3. Query `DBA_RSRC_IO_CALIBRATE` sau khi hoàn thành. Ghi lại `MAX_IOPS`, `MAX_MBPS`, `LATENCY`.

4. So sánh với vendor specs. Thường Oracle-visible IOPS thấp hơn vendor spec 40-60% — tại sao?

**Expected Findings:**
- `ASYNCH_IO = 'ASYNC_ON'` sau khi set SETALL
- Calibration duration: 5–15 phút tùy storage
- Oracle-visible IOPS thường < vendor spec (overhead của filesystem, volume manager, Oracle I/O layer)
- `DBA_RSRC_IO_CALIBRATE` có record với timestamp

**Debrief Questions:**
- Oracle dùng kết quả `DBA_RSRC_IO_CALIBRATE` để làm gì? Tìm trong `V$RSRC_PLAN_HISTORY` sau khi calibrate.
- Nếu `NUM_PHYSICAL_DISKS` trong `DBA_RSRC_IO_CALIBRATE` sai (ví dụ NULL hoặc 1), điều gì xảy ra với parallel query I/O slave allocation?
- Bạn có nên chạy calibration lại sau khi thêm disk vào storage group không?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**

03:47 sáng thứ Hai, batch job nightly `LOAD_SALES_DATA` timeout sau 4 giờ chạy. Job này thường hoàn thành trong 45 phút. On-call DBA restart job lúc 04:15, job vẫn chậm — hoàn thành lúc 07:30. Sáng ra bạn được assign investigate.

**Evidence Provided:**

*AWR Report (03:00–04:00, Top 5 Wait Events):*
```
Event                           Waits   Time(s)  Avg(ms)  % DB Time
------------------------------ ------- -------- -------- ----------
db file scattered read          847,293   18,240     21.5      61.2
direct path read                 23,441    4,102    175.0      13.7
log file sync                    12,890    1,204      9.3       4.0
db file sequential read          56,234      843      1.5       2.8
CPU time                              -    1,102        -       3.7
```

*AWR SQL Ordered by Physical Reads (same window):*
```
SQL_ID         Reads    Execs   Reads/Exec  Module
------------- -------- ------- ----------- ------------------
8f3kz9qpd2t1  2,341,890    1    2,341,890  LOAD_SALES_DATA
af7mn4xvq0p3    456,230   23       19,836  NIGHTLY_REPORTS
```

*DBA_INDEXES check (run at 08:00):*
```
INDEX_NAME                 STATUS
-------------------------- -------
SALES_PK                   VALID
SALES_IDX_DATE             VALID
SALES_IDX_CUST             VALID
ORDER_ITEMS_PK             VALID
ORDER_ITEMS_IDX1           VALID
```

*V$IOSTAT_FILE (queried at 08:00):*
```
NAME                              ASYNCH_IO   SMALL_READ_REQS  AVG_SMALL_READ_MS
--------------------------------- ----------- ---------------- -----------------
/u01/oradata/oradb/system01.dbf   ASYNC_ON              1,204               1.2
/u01/oradata/oradb/soetbs01.dbf   ASYNC_OFF         3,891,204              21.4
/u02/oradata/oradb/soetbs02.dbf   ASYNC_OFF           891,034              20.1
```

*Fragment từ LOAD_SALES_DATA procedure (được share bởi app team):*
```sql
-- Trong loop xử lý từng order
FOR rec IN (SELECT * FROM order_items WHERE order_id = v_order_id) LOOP
    -- process each item
    UPDATE sales_summary SET ...;
END LOOP;
```

**Your Mission:**

1. Identify **tất cả** contributing factors dẫn đến performance degradation. Không phải chỉ "I/O cao" — list cụ thể từng root cause.

2. Giải thích tại sao `avg_small_read_ms = 21.4ms` trên `soetbs01.dbf` là đáng ngại — ngưỡng reference của bạn là bao nhiêu?

3. Tại sao `direct path read avg 175ms` trong Top Events nhưng không xuất hiện trong `ASYNCH_IO` issue? Đây là I/O loại gì?

4. Đề xuất action plan với prioritization — cái gì fix trước, cái gì cần maintenance window.

5. Câu hỏi tranh luận: DBA khác đề xuất "tăng `DB_FILE_MULTIBLOCK_READ_COUNT` để batch job đọc nhanh hơn". Bạn đồng ý hay phản đối? Vì sao?

**Evaluation Criteria:**

- [ ] Identify được `ASYNC_OFF` trên `soetbs` tablespace là root cause của `db file scattered read` latency cao (21ms vs 1.2ms)
- [ ] Nhận ra `direct path read 175ms avg` là sort/hash spill vào temp (không phải FTS) — vì `order_items` lookup là single-row equality, không phải large FTS
- [ ] Nhận biết row-by-row processing pattern trong procedure (CURSOR FOR LOOP per order_id) là kiến trúc issue — N+1 query problem
- [ ] Đề xuất đúng: (1) Immediate: `ALTER SYSTEM SET FILESYSTEMIO_OPTIONS=SETALL` + restart để fix ASYNC; (2) Short-term: profile PGA usage để check temp spill; (3) Long-term: rewrite procedure dùng bulk operations
- [ ] Phản đối `DB_FILE_MULTIBLOCK_READ_COUNT` increase: tham số này ảnh hưởng CBO cost calculation → có thể push thêm queries sang FTS; không giải quyết root cause; ASYNCH là fix đúng


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_26_disk_io_senior_guide.md`
