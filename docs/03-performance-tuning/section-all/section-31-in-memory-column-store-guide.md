---
title: Section 31 — In-Memory Column Store
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_31_in_memory_column_store_guide.md
---

# Section 31 — In-Memory Column Store

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 33  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 31

Section 31 giới thiệu **Oracle In-Memory Column Store (IM Column Store / IMCS)** — tính năng lưu dữ liệu vào memory theo định dạng **columnar** (cột) thay vì row format truyền thống, giúp **analytic queries** chạy nhanh hơn nhiều lần.

> **Lưu ý:** In-Memory Column Store yêu cầu **license riêng** (Oracle Database In-Memory Option).

---

## Kiến thức nền tảng

### Row Store vs Column Store

```
ROW STORE (Buffer Cache — truyền thống):
Block 1:  [ID=1, Name='Alice', Dept='HR',  Salary=5000]
Block 2:  [ID=2, Name='Bob',   Dept='IT',  Salary=7000]
Block 3:  [ID=3, Name='Carol', Dept='HR',  Salary=6000]

Query: SELECT SUM(Salary) FROM employees WHERE Dept='HR'
→ Phải đọc TOÀN BỘ row của mỗi block, kể cả Name (không cần)
→ I/O đọc nhiều dữ liệu thừa
```

```
COLUMN STORE (In-Memory Area — columnar):
Col Dept:   ['HR', 'IT', 'HR', ...]   ← chỉ đọc cột này
Col Salary: [5000, 7000, 6000, ...]   ← chỉ đọc cột này
(Name, ID: không đọc vì không cần)

Query: SELECT SUM(Salary) FROM employees WHERE Dept='HR'
→ Chỉ scan 2 columns → ít I/O hơn, SIMD operations, cực nhanh
```

**Ưu điểm columnar format:**
- Chỉ đọc các columns cần thiết
- Dữ liệu cùng column có kiểu dữ liệu giống nhau → **nén tốt hơn**
- CPU SIMD (Single Instruction Multiple Data) xử lý nhiều giá trị cùng lúc
- Không cần indexes cho analytic queries

### Dual-Format Architecture

Oracle lưu dữ liệu **đồng thời ở hai nơi**:

```
                    Disk (Datafiles)
                          |
          ┌───────────────┴────────────────┐
          ▼                                ▼
  Buffer Cache (SGA)              IM Column Store (SGA)
  ROW FORMAT                      COLUMNAR FORMAT
  [Row1][Row2][Row3]...            [Col1_vals][Col2_vals]...
          |                                |
  OLTP queries                     Analytic queries
  (INDEX RANGE SCAN,               (FULL TABLE SCAN,
   point lookups, DML)              aggregations, GROUP BY)
```

**Đặc điểm quan trọng:** Oracle tự động chọn đọc từ nguồn nào phù hợp nhất cho từng query.

---

## Cấu hình In-Memory Column Store

### Bước 1: Kiểm tra cấu hình hiện tại

```sql
-- Xem memory management mode
SELECT NAME, VALUE/1024/1024/1024 GB
FROM V$PARAMETER
WHERE NAME IN ('sga_max_size', 'sga_target', 'memory_target');

-- Tổng SGA hiện tại
SELECT ROUND(SUM(VALUE)/1024/1024/1024, 1) TOTAL_SIZE_GB
FROM V$SGA;

-- Free memory trong SGA
SELECT ROUND(SUM(BYTES/1024/1024), 1) FREE_MEMORY_MB
FROM V$SGASTAT
WHERE NAME LIKE '%free memory%';
```

### Bước 2: Mở rộng SGA để chứa IM Area

```sql
-- Tăng SGA lên 2.5GB (cần đủ chỗ cho IM_SIZE + phần SGA hiện tại)
ALTER SYSTEM SET SGA_MAX_SIZE = 2684354560 SCOPE = SPFILE;  -- 2.5 GB
ALTER SYSTEM SET SGA_TARGET   = 2684354560 SCOPE = SPFILE;
```

### Bước 3: Đặt kích thước In-Memory Area

```sql
-- Bật In-Memory và đặt kích thước 300MB
ALTER SYSTEM SET INMEMORY_SIZE = 314572800 SCOPE = SPFILE;  -- 300 MB
-- SCOPE=SPFILE vì INMEMORY_SIZE là static parameter → cần restart
```

**Lưu ý:** `INMEMORY_SIZE` là **static parameter** — phải restart database sau khi thay đổi.

### Bước 4: Restart database

```sql
SHUTDOWN IMMEDIATE
STARTUP
```

### Verify sau restart

```sql
-- Kiểm tra INMEMORY_SIZE đã active
SELECT NAME, VALUE FROM V$PARAMETER WHERE NAME = 'inmemory_size';

-- Xem các In-Memory pools
SELECT POOL, ALLOC_BYTES/1024/1024 ALLOC_MB, USED_BYTES/1024/1024 USED_MB,
       POPULATE_STATUS
FROM V$INMEMORY_AREA;
```

**V$INMEMORY_AREA pools:**

| POOL | Dùng để |
|------|---------|
| `1MB POOL` | Lưu compressed columnar data |
| `64KB POOL` | Lưu metadata, bitmaps, indexes |

---

## Enable In-Memory trên Objects

### Bật IM cho một table

```sql
-- Enable với tất cả mặc định (PRIORITY=NONE, COMPRESSION=FOR QUERY HIGH)
ALTER TABLE orders2 INMEMORY;

-- Với tùy chọn cụ thể
ALTER TABLE orders2 INMEMORY
  PRIORITY HIGH
  MEMCOMPRESS FOR QUERY HIGH;
```

### Tắt IM cho một table

```sql
ALTER TABLE orders2 NO INMEMORY;
```

### Xem trạng thái IM của table

```sql
SELECT TABLE_NAME,
       INMEMORY,
       INMEMORY_PRIORITY,
       INMEMORY_DISTRIBUTE,
       INMEMORY_COMPRESSION,
       INMEMORY_DUPLICATE
FROM USER_TABLES
WHERE TABLE_NAME = 'ORDERS2';
```

**Giải thích các cột:**

| Cột | Ý nghĩa | Giá trị |
|-----|---------|---------|
| `INMEMORY` | IM có bật không | `ENABLED` / `DISABLED` |
| `INMEMORY_PRIORITY` | Mức độ ưu tiên populate | `NONE` / `LOW` / `MEDIUM` / `HIGH` / `CRITICAL` |
| `INMEMORY_COMPRESSION` | Kiểu nén trong IM | Xem bên dưới |
| `INMEMORY_DISTRIBUTE` | Phân phối trong RAC | `AUTO` / `BY ROWID RANGE` / ... |
| `INMEMORY_DUPLICATE` | Duplicate trong RAC | `NO DUPLICATE` / `DUPLICATE` / `DUPLICATE ALL` |

---

## INMEMORY_PRIORITY — Kiểm soát khi nào data được populate

| Priority | Hành vi |
|----------|---------|
| `NONE` (default) | Lazy — populate khi lần đầu được query |
| `LOW` | Background populate sau database startup |
| `MEDIUM` | Background populate, ưu tiên cao hơn LOW |
| `HIGH` | Background populate, ưu tiên cao |
| `CRITICAL` | Populate ngay khi startup, trước LOW/MEDIUM/HIGH |

**Thực tế:** Priority `NONE` là phổ biến nhất — data tự động vào IM khi được access lần đầu.

---

## INMEMORY_COMPRESSION — Nén trong IM Column Store

| Loại | Tradeoff | Dùng khi |
|------|---------|---------|
| `NO MEMCOMPRESS` | Không nén, tốc độ DML tốt nhất | Bảng có DML rất cao |
| `MEMCOMPRESS FOR DML` | Nén nhẹ, tối ưu DML | OLTP mixed |
| `MEMCOMPRESS FOR QUERY LOW` | Cân bằng nén và tốc độ query | General purpose |
| `MEMCOMPRESS FOR QUERY HIGH` | Nén cao, query nhanh (default) | Analytic, reporting |
| `MEMCOMPRESS FOR CAPACITY LOW` | Nén rất cao, ưu tiên space | Large tables ít query |
| `MEMCOMPRESS FOR CAPACITY HIGH` | Nén tối đa | Archive/cold data |

---

## Quá trình Population (Lazy Loading)

```
ALTER TABLE orders2 INMEMORY;     ← chỉ đánh dấu, chưa load
         ↓
ALTER SYSTEM FLUSH BUFFER_CACHE;  ← xóa buffer cache để test thuần túy
         ↓
Lần 1: SELECT SUM(ORDER_TOTAL) FROM orders2  
       → Plan: TABLE ACCESS INMEMORY FULL
       → Statistics: vẫn cao (đang load dữ liệu vào IM)
       → IMCO (background process) bắt đầu populate
         ↓
Lần 2: SELECT SUM(ORDER_TOTAL) FROM orders2
       → consistent gets giảm ~50%
       → physical reads giảm ~50%  (IM đang được populate dần)
         ↓
Lần 3+: SELECT SUM(ORDER_TOTAL) FROM orders2
       → consistent gets rất thấp
       → physical reads = 0  ← tất cả data đã trong IM!
       → Significant improvement!
```

**Execution plan phân biệt:**

| Operation | Nguồn |
|-----------|-------|
| `TABLE ACCESS FULL` | Đọc từ Buffer Cache (row format) |
| `TABLE ACCESS INMEMORY FULL` | Đọc từ IM Column Store (columnar) |

---

## Monitoring In-Memory

### V$INMEMORY_AREA — Tổng quan IM pools

```sql
SELECT POOL,
       ALLOC_BYTES/1024/1024  ALLOC_MB,
       USED_BYTES/1024/1024   USED_MB,
       POPULATE_STATUS
FROM V$INMEMORY_AREA;
```

### V$IM_SEGMENTS — Segments đã populate vào IM

```sql
COL SEGMENT_NAME FORMAT A30
SELECT SEGMENT_NAME,
       INMEMORY_SIZE/1024/1024   INMEMORY_SIZE_MB,
       BYTES/1024/1024           SEGMENT_SIZE_MB,
       POPULATE_STATUS,
       BYTES_NOT_POPULATED/1024/1024 NOT_YET_MB
FROM V$IM_SEGMENTS;
```

**Cột quan trọng:**

| Cột | Ý nghĩa |
|-----|---------|
| `INMEMORY_SIZE_MB` | Kích thước segment sau khi nén trong IM |
| `SEGMENT_SIZE_MB` | Kích thước gốc trên disk |
| `POPULATE_STATUS` | `STARTED` / `POPULATING` / `COMPLETED` |
| `BYTES_NOT_POPULATED` | Bytes chưa load vào IM (populate chưa xong) |

**Quan sát điển hình:** `INMEMORY_SIZE_MB` thường **nhỏ hơn nhiều** so với `SEGMENT_SIZE_MB` vì columnar compression.

### So sánh kích thước compression

```
SEGMENT_SIZE_MB (disk): 500 MB
INMEMORY_SIZE_MB (IM):   80 MB   ← ~6x compression ratio
```

---

## Thí nghiệm so sánh Performance

### Kịch bản

```sql
-- Tạo testing table (~200,000 orders)
CREATE TABLE ORDERS2 NOLOGGING AS
SELECT * FROM ORDERS WHERE ORDER_ID <= 2000000;

ANALYZE TABLE ORDERS2 COMPUTE STATISTICS;

-- Xem kích thước
SELECT BYTES/1024/1024 MB
FROM USER_SEGMENTS
WHERE SEGMENT_NAME = 'ORDERS2';
```

### Test không có IM

```sql
ALTER TABLE ORDERS2 NO INMEMORY;  -- đảm bảo IM tắt

ALTER SYSTEM FLUSH SHARED_POOL;
ALTER SYSTEM FLUSH BUFFER_CACHE;

SET LINESIZE 180
SET TIMING ON
SET AUTOT TRACE EXP STAT

-- Query analytic điển hình
SELECT SUM(ORDER_TOTAL), TO_CHAR(ORDER_DATE, 'YYYY-MM') ODATE
FROM ORDERS2
GROUP BY TO_CHAR(ORDER_DATE, 'YYYY-MM')
ORDER BY TO_CHAR(ORDER_DATE, 'YYYY-MM');
-- → Plan: TABLE ACCESS FULL (từ buffer cache)
-- → consistent gets: cao
-- → Elapsed time: baseline
```

### Enable IM và test

```sql
-- Bật IM trên table
ALTER TABLE ORDERS2 INMEMORY;
ALTER SYSTEM FLUSH BUFFER_CACHE;

-- Chạy lần 1 (loading phase)
SELECT SUM(ORDER_TOTAL), TO_CHAR(ORDER_DATE, 'YYYY-MM') ODATE
FROM ORDERS2
GROUP BY TO_CHAR(ORDER_DATE, 'YYYY-MM')
ORDER BY TO_CHAR(ORDER_DATE, 'YYYY-MM');
-- → Plan: TABLE ACCESS INMEMORY FULL  ← đã dùng IM!
-- → consistent gets: tương đương (data đang populate)

-- Chạy lần 2
-- → consistent gets: giảm ~50%

-- Chạy lần 3+
-- → consistent gets: rất thấp
-- → physical reads: 0
-- → Significant improvement!
```

---

## Quy trình triển khai IM cho Production

```
1. Xác định objects phù hợp
   - Large tables được query analytic/aggregation thường xuyên
   - Ít DML (hoặc DML không phải critical path)
       ↓
2. Estimate IM size cần thiết
   SELECT INMEMORY_SIZE/1024/1024 ESTIMATED_MB
   FROM V$IM_SEGMENTS; (sau test)
   -- Hoặc ước lượng: ~15-30% kích thước table on-disk với QUERY HIGH
       ↓
3. Cấu hình INMEMORY_SIZE
   ALTER SYSTEM SET INMEMORY_SIZE = <size> SCOPE=SPFILE;
   SHUTDOWN IMMEDIATE; STARTUP;
       ↓
4. Enable IM trên objects
   ALTER TABLE big_table INMEMORY PRIORITY HIGH
     MEMCOMPRESS FOR QUERY HIGH;
       ↓
5. Monitor
   SELECT SEGMENT_NAME, POPULATE_STATUS, INMEMORY_SIZE_MB
   FROM V$IM_SEGMENTS;
```

---

## Khi nào nên/không nên dùng IM

| Phù hợp | Không phù hợp |
|---------|--------------|
| ✅ Analytic queries: SUM, COUNT, AVG, GROUP BY | ❌ OLTP point lookups (index vẫn tốt hơn) |
| ✅ Reporting trên large tables | ❌ Bảng rất nhỏ (overhead không đáng) |
| ✅ Range scans nhiều columns | ❌ Bảng có UPDATE liên tục và nhiều (overhead DML) |
| ✅ Mixed workload (OLTP + analytics) | ❌ Không có IM license |
| ✅ Query chọn ít columns từ bảng rộng | |

---

## Tóm tắt Parameters, Views & Commands

| Parameter/View/Command | Dùng để |
|-----------------------|---------|
| `INMEMORY_SIZE` | Đặt kích thước IM Column Store (static, cần restart) |
| `SGA_MAX_SIZE`, `SGA_TARGET` | Mở rộng SGA để chứa IM area |
| `ALTER TABLE t INMEMORY` | Enable IM cho table (lazy populate) |
| `ALTER TABLE t NO INMEMORY` | Disable IM cho table |
| `USER_TABLES` — `INMEMORY`, `INMEMORY_PRIORITY` | Xem trạng thái IM của table |
| `V$INMEMORY_AREA` | Xem IM pools: allocated, used, populate status |
| `V$IM_SEGMENTS` | Xem segments đã populate: kích thước, trạng thái |
| `V$PARAMETER` — `inmemory_size` | Kiểm tra giá trị INMEMORY_SIZE hiện tại |
| `TABLE ACCESS INMEMORY FULL` | Execution plan khi query dùng IM Column Store |

---

## Câu hỏi ôn tập

1. In-Memory Column Store khác Buffer Cache ở điểm gì về cách lưu trữ dữ liệu?
2. Tại sao columnar format giúp analytic queries nhanh hơn? Cơ chế nào (ít nhất 2 cơ chế)?
3. `INMEMORY_SIZE` là static hay dynamic parameter? Cần làm gì sau khi thay đổi?
4. `INMEMORY_PRIORITY = NONE` có nghĩa là gì? Data được load vào IM khi nào?
5. Tại sao kích thước segment trong `V$IM_SEGMENTS.INMEMORY_SIZE_MB` thường nhỏ hơn nhiều so với kích thước trên disk?
6. Khi chạy lần đầu sau `ALTER TABLE t INMEMORY`, execution plan đã hiện `TABLE ACCESS INMEMORY FULL` nhưng performance chưa cải thiện. Tại sao?
7. Trong execution plan, làm thế nào để phân biệt query đang đọc từ Buffer Cache hay từ IM Column Store?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_31_in_memory_column_store_guide.md`
