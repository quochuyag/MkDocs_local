---
title: Section 26 — Disk I/O Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_26_disk_io_guide.md
---

# Section 26 — Disk I/O Tuning

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 28  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 26

Section 26 tập trung vào **chẩn đoán và xử lý I/O bottleneck** trong Oracle Database, và **I/O Calibration** — đo năng lực thực tế của hệ thống lưu trữ từ bên trong database.

---

## Kiến thức nền tảng

### Các loại I/O trong Oracle

```
SQL Query → Buffer Cache?
    ├── HIT  → Không cần đọc disk
    └── MISS → Đọc từ disk
            ├── db file sequential read   (single block I/O — index access)
            ├── db file scattered read    (multiblock I/O — Full Table Scan)
            └── direct path read          (bypass buffer cache — large FTS, parallel)
```

### Wait Events I/O chính

| Wait Event | Loại I/O | Nguyên nhân phổ biến |
|-----------|---------|---------------------|
| `db file sequential read` | Single-block | Index lookup, row fetch by rowid |
| `db file scattered read` | Multi-block | Full Table Scan (qua Buffer Cache) |
| `direct path read` | Bypass buffer | Large FTS, parallel query, temp segment reads |
| `db file parallel read` | Parallel | Recovery, parallel query |
| `log file sync` | Redo log | COMMIT — LGWR chưa flush |
| `log file parallel write` | Redo log | LGWR ghi nhiều members |

**Ngưỡng cảnh báo:** Các event trên xuất hiện trong **Top 5 Wait Events** của session/system → cần điều tra.

---

## Chẩn đoán I/O Issue

### Bước 1: Phát hiện I/O wait events của session

```sql
-- Wait events của sessions có action = 'UPDATE_VAT' (non-idle)
SELECT E.EVENT, E.WAIT_CLASS, SUM(E.TIME_WAITED) TIME_CSEC
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID
  AND S.ACTION = 'UPDATE_VAT'
  AND E.WAIT_CLASS <> 'Idle'
GROUP BY E.EVENT, E.WAIT_CLASS
HAVING SUM(E.TIME_WAITED) > 0
ORDER BY SUM(TIME_WAITED) ASC;
```

**Phân tích kết quả:**
- `db file scattered read` cao → FTS qua buffer cache
- `direct path read` cao → FTS bypass buffer cache (large table hoặc parallel)

### Bước 2: Dùng ASH Report tìm culprit SQL

Khi phát hiện I/O wait events cao → generate **ASH Report** lọc theo module/action:

```sql
-- Trong SQL*Plus
define target_module_name = 'SALES';
define target_action_name = 'UPDATE_VAT';
@ $ORACLE_HOME/rdbms/admin/ashrpti.sql
```

**Đọc ASH Report:**
- Section **"Top SQL"** → SQL nào gây ra I/O nhiều nhất
- Nếu query dùng equality operator (`WHERE ORDER_ID = X`) nhưng **lại Full Table Scan** → khả năng cao index bị UNUSABLE hoặc bị drop

### Bước 3: Kiểm tra trạng thái Indexes

```sql
-- Kiểm tra index status của table
SELECT INDEX_NAME, STATUS
FROM DBA_INDEXES
WHERE OWNER = 'SOE' AND TABLE_NAME = 'ORDER_ITEMS';
```

**STATUS:**

| STATUS | Ý nghĩa | Hành động |
|--------|---------|---------|
| `VALID` | Index bình thường | Không cần làm gì |
| `UNUSABLE` | Index không dùng được — optimizer bỏ qua | **Rebuild index** |
| `N/A` | Partitioned index (xem DBA_IND_PARTITIONS) | — |

### Bước 4: Rebuild Index bị UNUSABLE

```sql
-- Generate câu lệnh rebuild
SELECT 'ALTER INDEX SOE.' || INDEX_NAME || ' REBUILD;'
FROM DBA_INDEXES
WHERE OWNER='SOE' AND TABLE_NAME='ORDER_ITEMS';

-- Chạy từng câu rebuild
ALTER INDEX SOE.ORDER_ITEMS_PK REBUILD;
ALTER INDEX SOE.ORDER_ITEMS_IDX1 REBUILD;
-- ...
```

**Nguyên nhân index trở thành UNUSABLE:**
- `ALTER TABLE ... MOVE TABLESPACE` → tất cả indexes trên bảng đó trở thành UNUSABLE
- `ALTER TABLE ... SPLIT PARTITION`, `MERGE PARTITION`
- Import không rebuild indexes

---

## Kịch bản thực tế: Diagnose I/O Issue

### Vấn đề

1. Process `UPDATE_VAT` chạy SELECT trên `ORDER_ITEMS` với `WHERE ORDER_ID = X`
2. Bình thường rất nhanh, đột nhiên chậm nghiêm trọng
3. Junior DBA đã làm `ALTER TABLE ORDER_ITEMS MOVE TABLESPACE SOETBS` để chống fragmentation
4. DBA không biết rằng MOVE làm tất cả indexes trở thành UNUSABLE

### Chuỗi chẩn đoán

```
Báo cáo: process chậm
    ↓
V$SESSION_EVENT → top event: db file scattered read / direct path read
    ↓
ASH Report (filter by MODULE='SALES', ACTION='UPDATE_VAT')
    ↓
Top SQL: query dùng equality WHERE ORDER_ID = X nhưng lại FTS
    ↓
DBA_INDEXES: tất cả indexes STATUS = 'UNUSABLE'
    ↓
Root cause: ALTER TABLE MOVE không rebuild indexes
    ↓
Fix: ALTER INDEX ... REBUILD
    ↓
Kết quả: process chạy nhanh, I/O wait events biến mất
```

---

## I/O Calibration — Đo năng lực lưu trữ

### Mục đích

Oracle I/O Calibration đo **thông số thực tế** của hệ thống lưu trữ:
- **IOPS** (I/O Operations Per Second) — số lần read/write mỗi giây
- **MBPS** (Megabytes Per Second) — throughput
- **Latency** (ms) — độ trễ thực tế

### Điều kiện tiên quyết

```sql
-- 1. Phải bật Asynchronous I/O cho datafiles
-- Kiểm tra hiện tại
SELECT D.NAME, I.ASYNCH_IO
FROM V$DATAFILE D, V$IOSTAT_FILE I
WHERE D.FILE# = I.FILE_NO AND I.FILETYPE_NAME = 'Data File';

-- Bật async I/O (cần restart)
ALTER SYSTEM SET FILESYSTEMIO_OPTIONS = SETALL SCOPE = SPFILE;
SHUTDOWN IMMEDIATE;
STARTUP;

-- Verify
SELECT D.NAME, I.ASYNCH_IO
FROM V$DATAFILE D, V$IOSTAT_FILE I
WHERE D.FILE# = I.FILE_NO AND I.FILETYPE_NAME = 'Data File';
```

**`FILESYSTEMIO_OPTIONS` values:**

| Giá trị | Ý nghĩa |
|---------|---------|
| `NONE` | Không async, không direct I/O |
| `ASYNCH` | Chỉ async I/O |
| `DIRECTIO` | Chỉ direct I/O (bypass OS cache) |
| `SETALL` | Cả async và direct I/O (khuyến nghị) |

### Quiesced State — yêu cầu khi calibrate

```sql
-- Đưa database vào Quiesced state (chỉ DBA transactions)
ALTER SYSTEM QUIESCE RESTRICTED;

-- Sau khi calibrate xong
ALTER SYSTEM UNQUIESCE;
```

### Chạy I/O Calibration

```sql
SET TIMING ON
SET SERVEROUTPUT ON

DECLARE
  V_LAT  INTEGER;  -- actual latency (ms)
  V_IOPS INTEGER;  -- I/O rate per second
  V_MBPS INTEGER;  -- throughput MB/s
BEGIN
  DBMS_RESOURCE_MANAGER.CALIBRATE_IO(
      1    -- số physical disks
    , 20   -- maximum tolerable latency (ms)
    , V_IOPS
    , V_MBPS
    , V_LAT
  );
  DBMS_OUTPUT.PUT_LINE('Max IOPS = ' || V_IOPS);
  DBMS_OUTPUT.PUT_LINE('Actual Latency (ms) = ' || V_LAT);
  DBMS_OUTPUT.PUT_LINE('Max MBPS = ' || V_MBPS);
END;
/
SET TIMING OFF
```

**Tham số `CALIBRATE_IO`:**

| Tham số | Ý nghĩa |
|---------|---------|
| `num_physical_disks` | Số physical disks (Oracle dùng để tối ưu số I/O streams) |
| `max_latency` | Latency tối đa chấp nhận được (ms) |
| `max_iops` (OUT) | IOPS tối đa đo được |
| `max_mbps` (OUT) | Throughput MB/s tối đa |
| `actual_latency` (OUT) | Latency thực tế đo được |

### Xem kết quả calibration đã lưu

```sql
SELECT MAX_IOPS, MAX_MBPS, MAX_PMBPS, LATENCY, NUM_PHYSICAL_DISKS
FROM DBA_RSRC_IO_CALIBRATE;
```

**Giải thích cột:**

| Cột | Ý nghĩa |
|-----|---------|
| `MAX_IOPS` | I/O operations/giây (random reads) |
| `MAX_MBPS` | MB/giây (sequential reads) |
| `MAX_PMBPS` | MB/giây với parallel I/O |
| `LATENCY` | Độ trễ trung bình (ms) |

---

## Giám sát I/O tổng thể

### V$IOSTAT_FILE — I/O stats theo file

```sql
-- I/O thống kê theo datafile
SELECT F.FILE_NO, D.NAME, F.SMALL_READ_REQS, F.LARGE_READ_REQS,
       F.SMALL_READ_SERVICETIME, F.LARGE_READ_SERVICETIME
FROM V$IOSTAT_FILE F, V$DATAFILE D
WHERE F.FILE_NO = D.FILE#
  AND F.FILETYPE_NAME = 'Data File'
ORDER BY F.SMALL_READ_REQS DESC;
```

### V$FILESTAT — tóm tắt I/O theo file

```sql
SELECT F.FILE#, D.NAME, F.PHYRDS, F.PHYWRTS,
       F.READTIM, F.WRITETIM,
       ROUND(F.READTIM/DECODE(F.PHYRDS,0,1,F.PHYRDS),2) AVG_READ_MS
FROM V$FILESTAT F, V$DATAFILE D
WHERE F.FILE# = D.FILE#
ORDER BY F.PHYRDS DESC;
```

### ASH — Real-time I/O analysis

```sql
-- Top SQL gây I/O hiện tại
SELECT SQL_ID, EVENT, COUNT(*) SAMPLES
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_STATE = 'WAITING'
  AND WAIT_CLASS = 'User I/O'
  AND SAMPLE_TIME > SYSDATE - 1/24/12  -- 5 phút qua
GROUP BY SQL_ID, EVENT
ORDER BY 3 DESC;
```

---

## Checklist chẩn đoán I/O Bottleneck

| Bước | Kiểm tra | View/Tool |
|------|---------|----------|
| 1 | I/O wait events trong top events? | `V$SESSION_EVENT` / AWR Top Events |
| 2 | SQL nào gây I/O cao nhất? | ASH Report / AWR SQL by Reads |
| 3 | Query dùng FTS thay vì index? | ASH Report — SQL Plan |
| 4 | Indexes có UNUSABLE? | `DBA_INDEXES` — STATUS |
| 5 | Async I/O đã bật chưa? | `V$IOSTAT_FILE` — ASYNCH_IO |
| 6 | Năng lực lưu trữ thực tế? | `DBMS_RESOURCE_MANAGER.CALIBRATE_IO` |

---

## Tóm tắt Views & Commands

| View/Command | Dùng để |
|-------------|---------|
| `V$SESSION_EVENT` | Wait events của session đang chạy |
| `V$ACTIVE_SESSION_HISTORY` | Real-time I/O analysis theo SQL/session |
| `DBA_INDEXES` — `STATUS` | Phát hiện UNUSABLE indexes |
| `V$IOSTAT_FILE` | I/O stats + async I/O status theo file |
| `V$FILESTAT` | Tổng I/O reads/writes theo datafile |
| `DBA_RSRC_IO_CALIBRATE` | Kết quả calibration đã lưu |
| `ALTER TABLE ... MOVE` | Gây UNUSABLE indexes — luôn rebuild sau đó |
| `ALTER INDEX ... REBUILD` | Rebuild index UNUSABLE về VALID |
| `FILESYSTEMIO_OPTIONS=SETALL` | Bật async + direct I/O |
| `DBMS_RESOURCE_MANAGER.CALIBRATE_IO` | Đo IOPS/MBPS/Latency thực tế |

---

## Câu hỏi ôn tập

1. Phân biệt `db file sequential read` và `db file scattered read` — loại query nào gây ra mỗi event?
2. Tại sao `ALTER TABLE ... MOVE TABLESPACE` lại làm indexes trở thành UNUSABLE?
3. Khi query có `WHERE ORDER_ID = X` (equality) mà lại dùng FTS — làm thế nào để xác nhận nguyên nhân?
4. `direct path read` khác `db file scattered read` ở điểm nào? Khi nào Oracle dùng direct path?
5. Để chạy `DBMS_RESOURCE_MANAGER.CALIBRATE_IO`, cần bật tham số nào và tại sao?
6. `ALTER SYSTEM QUIESCE RESTRICTED` làm gì? Tại sao cần trạng thái này khi calibrate I/O?
7. `FILESYSTEMIO_OPTIONS = SETALL` bật những gì? Tại sao đây là setting được khuyến nghị?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_26_disk_io_guide.md`
