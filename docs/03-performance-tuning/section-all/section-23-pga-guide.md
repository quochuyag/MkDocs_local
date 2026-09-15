---
title: Section 23 — PGA Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_23_pga_guide.md
---

# Section 23 — PGA Tuning

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 25  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 23

Section 23 tập trung vào **PGA (Program Global Area)** — vùng nhớ riêng của từng server process, ảnh hưởng trực tiếp đến hiệu năng các thao tác **sort, hash join, bitmap merge**.

---

## Kiến thức nền tảng

### PGA là gì?

```
SGA (chia sẻ giữa tất cả sessions)
    ├── Buffer Cache
    ├── Shared Pool
    └── ...

PGA (riêng biệt cho từng server process)
    ├── Work Area (Sort Area, Hash Area, Bitmap Merge Area)
    ├── Session Memory (session variables, logon info)
    └── Private SQL Area (cursors, bind variables)
```

**PGA không chia sẻ** — mỗi server process có PGA riêng. Khi process kết thúc, PGA được trả lại cho OS.

### Work Area — vùng nhớ quan trọng nhất trong PGA

Work Area được dùng cho các thao tác **memory-intensive**:

| Operation | Work Area type | Ví dụ SQL |
|-----------|---------------|-----------|
| **Sort** | Sort Area | `ORDER BY`, `GROUP BY`, `CREATE INDEX` |
| **Hash Join** | Hash Area | `SELECT ... FROM A JOIN B` (large tables) |
| **Bitmap Merge** | Bitmap Area | Queries dùng bitmap indexes |

### 3 chế độ thực thi Work Area

| Chế độ | Mô tả | Tác động |
|--------|-------|---------|
| **Optimal** | Toàn bộ data sort/hash trong RAM | Tốt nhất — không đụng đến disk |
| **One-pass** | RAM không đủ → ghi ra temp tablespace 1 lần | Chậm hơn optimal |
| **Multi-pass** | RAM quá nhỏ → ghi ra temp tablespace nhiều lần | Tệ nhất — rất chậm |

```
Optimal:   [DATA] → [SORT in RAM] → [RESULT]          (nhanh)
One-pass:  [DATA] → [partial sort RAM] → [TEMP] → [merge] → [RESULT]
Multi-pass:[DATA] → [tiny RAM] → [TEMP] × N → [merge N lần] → [RESULT]  (chậm)
```

---

## Chế độ quản lý PGA

### Automatic PGA Management (mặc định và khuyến nghị)

```sql
-- Kiểm tra
SHOW PARAMETER PGA_AGGREGATE_TARGET;
-- > 0 → Automatic PGA đang bật

-- Oracle tự điều chỉnh work area của từng session
-- PGA_AGGREGATE_TARGET là target tổng PGA cho toàn instance
```

**Lưu ý quan trọng:** Oracle **không** giới hạn cứng tổng PGA ở giá trị `PGA_AGGREGATE_TARGET`. Nếu workload cần nhiều hơn, Oracle có thể cấp thêm. Tham số này chỉ là **target** để Oracle tối ưu hóa phân bổ.

### Manual PGA Management (không khuyến nghị)

```sql
-- Tắt automatic, dùng thủ công
ALTER SESSION SET WORKAREA_SIZE_POLICY = MANUAL;
ALTER SESSION SET SORT_AREA_SIZE = 160204;  -- bytes
-- Nguy hiểm: nếu set quá nhỏ → multi-pass → performance tệ
```

---

## Giám sát PGA

### 1. Thống kê Work Area ở cấp Instance

```sql
-- Xem workarea executions và sort statistics
SELECT NAME, VALUE
FROM V$SYSSTAT
WHERE (NAME LIKE 'workarea executions%') OR (NAME LIKE 'sorts%');
```

**Các metric và ngưỡng:**

| Metric | Ý nghĩa | Ngưỡng bình thường |
|--------|---------|-------------------|
| `workarea executions - optimal` | Số lần thực thi trong RAM | Càng cao càng tốt |
| `workarea executions - onepass` | Số lần ghi temp 1 lần | Thấp |
| `workarea executions - multipass` | Số lần ghi temp nhiều lần | **= 0 trong healthy system** |
| `sorts (memory)` | Sort hoàn toàn trong RAM | Cao |
| `sorts (disk)` | Sort phải dùng temp tablespace | **Thấp — gần 0 với OLTP** |
| `sorts (rows)` | Tổng số rows được sort | — |

### 2. Thống kê tổng quan PGA (V$PGASTAT)

```sql
-- Hiển thị PGA memory usage statistics
SELECT NAME,
       DECODE(UNIT,'bytes',TO_CHAR(ROUND(VALUE/1024/1024,2)),VALUE) VALUE,
       DECODE(UNIT,'bytes','MB',UNIT) UNIT
FROM V$PGASTAT;
```

**Các metric quan trọng:**

| Metric | Ý nghĩa | Ghi chú |
|--------|---------|---------|
| `aggregate PGA target parameter` | Giá trị `PGA_AGGREGATE_TARGET` | Set bởi DBA |
| `aggregate PGA auto target` | Phần PGA Oracle dùng để tự điều chỉnh work area | Luôn ≤ aggregate target |
| `total PGA allocated` | Tổng PGA đã cấp phát thực tế | Có thể > target nếu cần |
| `total PGA inuse` | PGA đang thực sự dùng | ≤ total allocated |
| `cache hit percentage` | % lần xử lý data không cần extra pass | **OLTP: gần 100%** |
| `maximum PGA allocated` | PGA tối đa từng cấp phát | Peak usage |

### 3. Histogram Work Area (V$SQL_WORKAREA_HISTOGRAM)

```sql
-- Phân phối executions theo kích thước work area (buckets)
SELECT LOW_OPTIMAL_SIZE/1024    LOW_KB,
       (HIGH_OPTIMAL_SIZE+1)/1024 HIGH_KB,
       OPTIMAL_EXECUTIONS,
       ONEPASS_EXECUTIONS,
       MULTIPASSES_EXECUTIONS
FROM V$SQL_WORKAREA_HISTOGRAM
WHERE TOTAL_EXECUTIONS != 0;
```

**Cách đọc:** Thấy `MULTIPASSES_EXECUTIONS > 0` trong bất kỳ bucket nào → cần tăng PGA.

### 4. Work Area đang Active (V$SQL_WORKAREA_ACTIVE)

```sql
-- Xem từng cursor đang chạy
SELECT A.SID, V.USERNAME,
       OPERATION_TYPE           OPERATION,
       TRUNC(EXPECTED_SIZE/1024)  ESIZE_KB,   -- Oracle ước tính cần bao nhiêu
       TRUNC(ACTUAL_MEM_USED/1024) MEM,        -- Đang dùng thực tế
       TRUNC(MAX_MEM_USED/1024)   MAX_MEM,     -- Peak đã dùng
       NUMBER_PASSES             PASS,          -- 0=optimal, 1=onepass, >1=multipass
       TRUNC(TEMPSEG_SIZE/1024)  TSIZE_KB      -- Bao nhiêu KB dùng temp tablespace
FROM V$SQL_WORKAREA_ACTIVE A, V$SESSION V
WHERE A.SID = V.SID AND V.USERNAME <> 'SYS'
ORDER BY MEM;

-- Dạng aggregated theo operation type
SELECT OPERATION_TYPE  OPERATION,
       NUMBER_PASSES   PASS,
       SUM(TRUNC(EXPECTED_SIZE/1024))   ESIZE_KB,
       SUM(TRUNC(ACTUAL_MEM_USED/1024)) MEM,
       SUM(TRUNC(MAX_MEM_USED/1024))    MAX_MEM,
       SUM(TRUNC(TEMPSEG_SIZE/1024))    TSIZE_KB
FROM V$SQL_WORKAREA_ACTIVE
GROUP BY OPERATION_TYPE, NUMBER_PASSES;
```

**Lưu ý:** `V$SQL_WORKAREA_ACTIVE` chỉ có data khi statement đang chạy. Khi query xong → biến mất.

### 5. Work Area của các Cursor đã hoàn thành (V$SQL_WORKAREA)

```sql
-- Top 10 cursors theo memory used (sau khi chúng hoàn thành)
SELECT Q.PARSING_SCHEMA_NAME             USERNAME,
       SUBSTR(Q.SQL_TEXT,1,20)           SQL_TEXT,
       W.OPERATION_TYPE,
       TRUNC(W.ESTIMATED_OPTIMAL_SIZE/1024,2) EST_OPTIMAL_SIZE,
       TRUNC(LAST_MEMORY_USED/1024,2)    MEM_USED,
       TRUNC(MAX_TEMPSEG_SIZE/1024,2)    MAX_TEMP_SIZE
FROM V$SQL_WORKAREA W, V$SQL Q
WHERE W.ADDRESS = Q.ADDRESS
  AND Q.PARSING_SCHEMA_NAME NOT IN ('SYS','ORACLE_OCM','GSMADMIN_INTERNAL')
ORDER BY LAST_MEMORY_USED DESC
FETCH FIRST 10 ROWS ONLY;
```

### 6. Statistics cấp Session

```sql
-- Sort/workarea stats của sessions đang chạy với action='my action'
SELECT N.NAME, T.VALUE
FROM V$SESSTAT T, V$SESSION S, V$STATNAME N
WHERE T.STATISTIC# = N.STATISTIC#
  AND T.SID = S.SID
  AND S.ACTION = 'my action'
  AND ((N.NAME LIKE 'workarea executions%') OR (N.NAME LIKE 'sorts%'));
```

---

## PGA Memory Advisory — Xác định kích thước tối ưu

### V$PGA_TARGET_ADVICE

```sql
-- Ước tính cache hit % ở các kích thước PGA khác nhau
SELECT ROUND(PGA_TARGET_FOR_ESTIMATE/1024/1024) TARGET_MB,
       ESTD_PGA_CACHE_HIT_PERCENTAGE           CACHE_HIT_PERC,
       ESTD_OVERALLOC_COUNT
FROM V$PGA_TARGET_ADVICE;
```

**Cách đọc:**

```
TARGET_MB | CACHE_HIT_PERC | ESTD_OVERALLOC_COUNT
       50 |          62    |  1500   ← quá nhỏ, nhiều overalloc
      100 |          78    |   800
      200 |          91    |   100
      400 |          98    |     0   ← plateau, đạt tốt
      800 |          99    |     0   ← không cải thiện nhiều
     1600 |          99    |     0
```

- **`CACHE_HIT_PERC`:** % lần xử lý không cần đến temp disk. Mục tiêu OLTP: ≥ 95-100%
- **`ESTD_OVERALLOC_COUNT`:** Số lần Oracle phải cấp phát vượt target. = 0 là tốt
- **Tìm điểm:** `CACHE_HIT_PERC` plateau + `ESTD_OVERALLOC_COUNT = 0` → đó là kích thước tối ưu

**AWR Report** cũng có section **"PGA Memory Advisory"** — dùng khi cần data historical.

### Điều chỉnh PGA_AGGREGATE_TARGET

```sql
-- Tham số động — không cần restart
ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 400M;

-- Verify
SHOW PARAMETER PGA_AGGREGATE_TARGET;
```

---

## Thực nghiệm: Optimal vs One-pass vs Multi-pass

### Trường hợp 1: Query nhỏ → Optimal

```sql
-- 100 rows → work area nhỏ → fit trong RAM
SELECT /*+ SQLID: 1 */ ORDER_ID, ORDER_TOTAL
FROM ORDERS
WHERE ORDER_ID BETWEEN 10000 AND 10100
ORDER BY 2;
-- Kết quả: workarea executions - optimal tăng, sorts (disk) = 0
```

### Trường hợp 2: Query lớn với PGA đủ → Optimal

```sql
-- 39,000 rows → work area lớn nhưng PGA đủ RAM
SELECT /*+ SQLID: 2 */ ORDER_ID, ORDER_TOTAL
FROM ORDERS
WHERE ORDER_ID BETWEEN 10000 AND 400000
ORDER BY 2;
-- Kết quả: vẫn optimal, sorts (disk) = 0
-- V$SQL_WORKAREA: ESTIMATED_OPTIMAL_SIZE rất lớn, nhưng MEM_USED đủ đáp ứng
```

### Trường hợp 3: Query lớn với sort area nhỏ → Multi-pass

```sql
-- Tắt automatic, set sort area nhỏ
ALTER SESSION SET WORKAREA_SIZE_POLICY = MANUAL;
ALTER SESSION SET SORT_AREA_SIZE = 160204;  -- chỉ ~157 KB

-- Cùng query nhưng sort area quá nhỏ
SELECT /*+ SQLID: 3 */ ORDER_ID, ORDER_TOTAL
FROM ORDERS
WHERE ORDER_ID BETWEEN 10000 AND 400000
ORDER BY 2;
-- Kết quả: sorts (disk) tăng, TEMPSEG_SIZE > 0
-- V$SQL_WORKAREA: ESTIMATED_OPTIMAL_SIZE >> LAST_MEMORY_USED, MAX_TEMP_SIZE > 0
```

---

## Checklist đánh giá sức khỏe PGA

| Kiểm tra | Query/View | Ngưỡng bình thường |
|---------|-----------|-------------------|
| Multipass executions | `V$SYSSTAT` — `workarea executions - multipass` | **= 0** |
| Sorts on disk | `V$SYSSTAT` — `sorts (disk)` | **Thấp, gần 0 (OLTP)** |
| Cache hit % | `V$PGASTAT` — `cache hit percentage` | **≥ 95% (OLTP)** |
| Overalloc count | `V$PGA_TARGET_ADVICE` — `ESTD_OVERALLOC_COUNT` | **= 0 tại target hiện tại** |
| Active passes | `V$SQL_WORKAREA_ACTIVE` — `NUMBER_PASSES` | **= 0 (optimal)** |

---

## Tóm tắt Views quan trọng

| View | Mô tả |
|------|-------|
| `V$PGASTAT` | Tổng quan PGA usage + cache hit % |
| `V$SYSSTAT` | Workarea execution counters + sort statistics |
| `V$SQL_WORKAREA_HISTOGRAM` | Phân phối optimal/onepass/multipass theo bucket size |
| `V$SQL_WORKAREA_ACTIVE` | Work areas đang hoạt động (real-time) |
| `V$SQL_WORKAREA` | Work areas của cursors đã hoàn thành |
| `V$PGA_TARGET_ADVICE` | Advisory kích thước PGA tối ưu |

---

## Câu hỏi ôn tập

1. PGA khác SGA ở điểm nào cơ bản nhất? Tại sao điều đó quan trọng khi tuning?
2. Ba chế độ thực thi work area là gì? Chế độ nào tệ nhất và tại sao?
3. Metric nào trong `V$PGASTAT` quan trọng nhất để đánh giá sức khỏe PGA? Ngưỡng bao nhiêu là tốt?
4. Sự khác biệt giữa `V$SQL_WORKAREA_ACTIVE` và `V$SQL_WORKAREA` là gì?
5. Đọc kết quả `V$PGA_TARGET_ADVICE` như thế nào để chọn kích thước tối ưu?
6. Tại sao Oracle có thể cấp phát PGA nhiều hơn giá trị `PGA_AGGREGATE_TARGET`?
7. `WORKAREA_SIZE_POLICY = MANUAL` gây nguy hiểm gì nếu set `SORT_AREA_SIZE` quá nhỏ?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_23_pga_guide.md`
