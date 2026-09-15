---
title: Section 30 — Table Compression
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_30_table_compression_guide.md
---

# Section 30 — Table Compression

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 32  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 30

Section 30 giới thiệu **Table Compression** trong Oracle — kỹ thuật giảm kích thước table bằng cách loại bỏ dữ liệu trùng lặp trong các blocks. Compression không chỉ tiết kiệm storage mà còn **cải thiện hiệu năng FTS** vì Oracle đọc ít blocks hơn.

---

## Kiến thức nền tảng

### Compression hoạt động như thế nào?

Oracle compression hoạt động ở **block level**: tạo một **symbol table** ở đầu mỗi block chứa các giá trị lặp lại, sau đó thay thế các giá trị đó bằng con trỏ ngắn hơn.

```
Không compress:
Block: [Alice][Alice][Alice][Bob][Bob][Carol][Carol]
        7B      7B     7B   4B    4B    6B     6B  = 39 bytes

Sau compress (symbol table ở đầu block):
Block header: [Alice=1][Bob=2][Carol=3]
Data:         [1]  [1]  [1]  [2] [2]  [3] [3]  = ~10 bytes
```

**Tác động hiệu năng:**
- Ít blocks hơn → FTS đọc ít I/O hơn
- Buffer Cache chứa được nhiều data hơn
- INSERT nhanh hơn (với direct path loading) — ít blocks để ghi

**Trade-off:** Tăng CPU overhead khi compress/decompress — đáng giá khi I/O là bottleneck.

---

## Hai loại Compression

### So sánh tổng quan

| Tiêu chí | Basic Compression | Advanced Compression |
|---------|------------------|---------------------|
| **Syntax** | `ROW STORE COMPRESS BASIC` | `ROW STORE COMPRESS ADVANCED` |
| **Normal INSERT** | ❌ Không compress | ✅ Compress |
| **Direct path loading** | ✅ Compress | ✅ Compress |
| **PCTFREE mặc định** | **0** (tự động) | 10 (phải set 0 thủ công) |
| **License** | Included | ⚠️ Separate license required |
| **Phù hợp** | Data warehouse, batch load | OLTP, mixed workload |

---

## Basic Compression

### Đặc điểm quan trọng

> **Basic Compression CHỈ compress data được load bằng direct path loading.**  
> Normal INSERT (`INSERT INTO ... VALUES` hoặc `INSERT INTO ... SELECT` thông thường) **không compress**.

### Direct Path Loading là gì?

| Phương thức | Direct Path? |
|------------|-------------|
| `INSERT /*+ APPEND */ INTO t SELECT ...` | ✅ Có |
| `CREATE TABLE t COMPRESS AS SELECT ...` | ✅ Có |
| `SQL*Loader với DIRECT=Y` | ✅ Có |
| `INSERT INTO t VALUES (...)` | ❌ Không |
| `INSERT INTO t SELECT ...` (không có APPEND) | ❌ Không |

**Tại sao direct path không compress với normal INSERT?**  
Direct path loading ghi data trực tiếp vào blocks mới ở trên High Water Mark, cho phép Oracle tối ưu và nén toàn bộ block. Normal INSERT ghi vào các blocks hiện có trong free list — Oracle không thể reorganize lại toàn bộ block để nén.

### Tạo Basic Compressed Table

```sql
-- Tạo table với basic compression
CREATE TABLE CUST_BCOMPRESSED
( CUSTOMER_NO NUMBER(6),
  FIRST_NAME  VARCHAR2(20),
  LAST_NAME   VARCHAR2(20),
  NOTE1       VARCHAR2(100),
  NOTE2       VARCHAR2(100)
) ROW STORE COMPRESS BASIC NOLOGGING TABLESPACE SOETBS;
-- Lưu ý: PCTFREE tự động = 0 với COMPRESS BASIC
```

### Compression ratio phụ thuộc vào repeated data

```sql
-- Trường hợp 1: Random data (ít lặp lại) → compression ratio thấp
INSERT INTO CUST_SOURCE
SELECT LEVEL,
       DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.VALUE(10,20))) FIRST_NAME,
       DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.VALUE(10,20))) LAST_NAME,
       DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.VALUE(0,100)))  NOTE1,
       DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.VALUE(0,100)))  NOTE2
FROM DUAL CONNECT BY LEVEL <= 100000;

-- Sau direct path load → table bị compressed nhưng chỉ nhỏ hơn một chút
-- vì dữ liệu random, ít giá trị trùng → symbol table không tiết kiệm nhiều

-- Trường hợp 2: Repeated data (nhiều lặp lại) → compression ratio cao
INSERT INTO CUST_SOURCE
SELECT LEVEL,
       DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.VALUE(10,20))) FIRST_NAME,
       DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.VALUE(10,20))) LAST_NAME,
       'XXXXXX' NOTE1,   -- giá trị cố định → lặp lại 100,000 lần
       'YYYYYY' NOTE2    -- giá trị cố định → lặp lại 100,000 lần
FROM DUAL CONNECT BY LEVEL <= 100000;

-- Sau direct path load → table compressed nhỏ HƠN NHIỀU
-- NOTE1 và NOTE2 đều được replace bằng 1 byte pointer
```

**Kết luận:** Basic compression hiệu quả nhất với data warehouse và reporting tables nơi nhiều cột có repeated values (product codes, categories, dates, region codes...).

---

## Advanced Compression (OLTP Compression)

### Đặc điểm

```sql
-- Tạo table với advanced compression
-- QUAN TRỌNG: Phải set PCTFREE 0 thủ công (mặc định là 10!)
CREATE TABLE CUST_ACOMPRESSED
( CUSTOMER_NO NUMBER(6),
  FIRST_NAME  VARCHAR2(20),
  LAST_NAME   VARCHAR2(20),
  NOTE1       VARCHAR2(100),
  NOTE2       VARCHAR2(100)
) ROW STORE COMPRESS ADVANCED NOLOGGING PCTFREE 0 TABLESPACE SOETBS;
```

**Tại sao PCTFREE 0 với Advanced Compression?**  
Advanced Compression quản lý space trong block khác — nó **tự động compress blocks** khi đầy, cho phép DML tiếp tục vào block sau khi đã được nén. Giữ PCTFREE 10 sẽ lãng phí space.

### So sánh kết quả với 100,000 rows có repeated data (NOTE1='XXXXXX', NOTE2='YYYYYY')

| Table | Load Method | COMPRESSION | BLOCKS (approx) |
|-------|-------------|-------------|-----------------|
| CUST_SOURCE | Normal INSERT | DISABLED | 1000 |
| CUST_BCOMPRESSED | Normal INSERT | ENABLED | ~1000 (KHÔNG compress!) |
| CUST_BCOMPRESSED | Direct Path (APPEND) | ENABLED | ~400 (compress) |
| CUST_ACOMPRESSED | Normal INSERT | ENABLED | ~800 (compress nhẹ) |
| CUST_ACOMPRESSED | Direct Path (APPEND) | ENABLED | ~400 (compress = basic) |

**Kết luận quan trọng:**
- Basic + Direct Path = Advanced + Direct Path (kết quả tương đương)
- Advanced + Normal INSERT = có compress, nhưng kém hơn direct path
- Basic + Normal INSERT = KHÔNG compress (giống table không compress)

---

## Giám sát Compression Status

```sql
-- Xem compression status và kích thước tables
SELECT TABLE_NAME,
       BLOCKS * 8 SIZE_KB,
       COMPRESSION,
       PCT_FREE
FROM USER_TABLES
WHERE TABLE_NAME IN ('CUST_SOURCE', 'CUST_BCOMPRESSED', 'CUST_ACOMPRESSED');
```

| Cột | Ý nghĩa |
|-----|---------|
| `COMPRESSION` | `ENABLED` / `DISABLED` — table có bật compress không |
| `COMPRESS_FOR` | `BASIC` / `ADVANCED` / `QUERY HIGH` / `ARCHIVE HIGH` |
| `BLOCKS` | Số blocks thực tế đang dùng (sau khi compress: ít hơn) |

```sql
-- Xem chi tiết compression type
SELECT TABLE_NAME, COMPRESSION, COMPRESS_FOR
FROM USER_TABLES
WHERE TABLE_NAME LIKE 'CUST%';
```

---

## Compression + Direct Path Loading = Performance Gain

### Thí nghiệm so sánh INSERT performance

```sql
-- T1: Không compress
CREATE TABLE T1 AS SELECT * FROM USER_OBJECTS WHERE 1=2;

-- T2: Basic compress, normal INSERT
CREATE TABLE T2 ROW STORE COMPRESS BASIC AS SELECT * FROM USER_OBJECTS WHERE 1=2;

-- T3: Basic compress, direct path INSERT
CREATE TABLE T3 ROW STORE COMPRESS BASIC AS SELECT * FROM USER_OBJECTS WHERE 1=2;

-- Populate T1 — normal INSERT
SET TIMING ON
INSERT INTO T1
SELECT A.* FROM USER_OBJECTS A, USER_OBJECTS B, USER_OBJECTS C,
               (SELECT 1 FROM DUAL CONNECT BY LEVEL <= 20) D;
SET TIMING OFF
COMMIT;

-- Populate T2 — normal INSERT vào compressed table
SET TIMING ON
INSERT INTO T2
SELECT A.* FROM USER_OBJECTS A, USER_OBJECTS B, USER_OBJECTS C,
               (SELECT 1 FROM DUAL CONNECT BY LEVEL <= 20) D;
SET TIMING OFF
COMMIT;

-- Populate T3 — DIRECT PATH INSERT vào compressed table ← NHANH NHẤT
SET TIMING ON
INSERT /*+ APPEND */ INTO T3
SELECT A.* FROM USER_OBJECTS A, USER_OBJECTS B, USER_OBJECTS C,
               (SELECT 1 FROM DUAL CONNECT BY LEVEL <= 20) D;
SET TIMING OFF
COMMIT;
```

**Kết quả điển hình:** T3 nhanh hơn T1 và T2 khoảng **70%** khi INSERT.

### Thí nghiệm so sánh SELECT performance

```sql
-- Flush cache để test khách quan
ALTER SYSTEM FLUSH SHARED_POOL;
ALTER SYSTEM FLUSH BUFFER_CACHE;

SET TIMING ON
SET AUTOT TRACE STAT
SELECT COUNT(*) FROM T1;  -- nhiều consistent gets, nhiều physical reads
SET AUTOT OFF
SET TIMING OFF

ALTER SYSTEM FLUSH SHARED_POOL;
ALTER SYSTEM FLUSH BUFFER_CACHE;

SET TIMING ON
SET AUTOT TRACE STAT
SELECT COUNT(*) FROM T3;  -- ít consistent gets hơn, ít physical reads hơn
SET AUTOT OFF
SET TIMING OFF
```

**Kết quả:** T3 (compressed + direct path) có:
- Ít **consistent gets** hơn (ít blocks logical reads)
- Ít **physical reads** hơn (ít blocks cần đọc từ disk)
- **Elapsed time** thấp hơn

**Tại sao FTS nhanh hơn trên compressed table?**  
Compressed table chứa nhiều rows hơn trong mỗi block → Oracle đọc **ít blocks hơn** để scan toàn bộ table → ít I/O → nhanh hơn.

---

## Compression Types tổng hợp (Oracle Reference)

| Type | Syntax | DML Support | Use Case |
|------|--------|-------------|---------|
| **Basic** | `ROW STORE COMPRESS BASIC` | Direct path only | Data warehouse, bulk load |
| **Advanced (OLTP)** | `ROW STORE COMPRESS ADVANCED` | All DML ⚠️ Licensed | OLTP mixed workload |
| **Query Low** | `COLUMN STORE COMPRESS FOR QUERY LOW` | Direct path only (Exadata) | Data warehouse queries |
| **Query High** | `COLUMN STORE COMPRESS FOR QUERY HIGH` | Direct path only (Exadata) | Best ratio for queries |
| **Archive Low/High** | `COLUMN STORE COMPRESS FOR ARCHIVE` | Direct path only (Exadata) | Long-term archival |

> Column Store Compression (HCC — Hybrid Columnar Compression) chỉ có trên Exadata và một số Oracle Cloud platforms.

---

## Chuyển đổi Table hiện có sang Compression

### Cách 1: ALTER TABLE MOVE (offline)

```sql
-- Chuyển table hiện có sang basic compression (blocks DML!)
ALTER TABLE orders MOVE ROW STORE COMPRESS BASIC;

-- Phải rebuild indexes sau MOVE
ALTER INDEX orders_pk REBUILD;
```

### Cách 2: Online Redefinition (không block DML)

```sql
BEGIN
  DBMS_REDEFINITION.REDEF_TABLE(
    UNAME               => 'SOE',
    TNAME               => 'ORDERS',
    TABLE_COMPRESSION   => 'ROW STORE COMPRESS BASIC',
    TABLE_PART_TABLESPACE => 'SOETBS'
  );
END;
/
```

### Cách 3: ALTER TABLE MOVE ONLINE (Oracle 12c+)

```sql
-- Không block DML, indexes vẫn valid (Oracle 12c+)
ALTER TABLE orders MOVE ROW STORE COMPRESS BASIC ONLINE;
```

---

## Khi nào nên dùng Table Compression?

| Trường hợp | Khuyến nghị |
|-----------|-------------|
| Data warehouse, batch reports | ✅ Basic + Direct Path Loading |
| Archive tables (ít DML) | ✅ Basic Compression |
| OLTP với repeated column values | ✅ Advanced Compression (nếu có license) |
| Table có random unique data | ⚠️ Compression ratio thấp, cân nhắc |
| Table nhỏ (< vài MB) | ❌ Overhead không đáng |
| Table bị UPDATE thường xuyên làm row lớn hơn | ⚠️ Basic không hoạt động với normal DML |

---

## Tóm tắt Commands & Views

| Command/View | Dùng để |
|-------------|---------|
| `ROW STORE COMPRESS BASIC` | Tạo table basic compressed |
| `ROW STORE COMPRESS ADVANCED` | Tạo table advanced compressed (licensed) |
| `INSERT /*+ APPEND */ INTO t SELECT ...` | Direct path loading — bật compression |
| `USER_TABLES` — `COMPRESSION`, `COMPRESS_FOR`, `BLOCKS` | Xem trạng thái và kích thước sau compress |
| `DBMS_STATS.GATHER_TABLE_STATS` | Cập nhật statistics sau load |
| `SET AUTOT TRACE STAT` | Xem consistent gets, physical reads, elapsed time |
| `ALTER TABLE t MOVE ROW STORE COMPRESS BASIC` | Chuyển table hiện có sang compression |
| `ALTER TABLE t MOVE ... ONLINE` | Chuyển không block DML (Oracle 12c+) |

---

## Câu hỏi ôn tập

1. Tại sao Basic Compression không compress data được INSERT bằng normal INSERT statement?
2. `INSERT /*+ APPEND */` khác với `INSERT` thông thường như thế nào? Tại sao nó kích hoạt được Basic Compression?
3. Compressed table cải thiện FTS performance như thế nào? Cơ chế là gì?
4. Tại sao `PCTFREE` mặc định là 0 cho Basic Compression nhưng Advanced Compression phải set thủ công?
5. Nếu bạn có một reporting table được load mỗi đêm bằng batch job, bạn sẽ dùng loại compression nào và phương thức load nào?
6. Advanced Compression và Basic Compression cho kết quả kích thước tương đương trong trường hợp nào?
7. Khi chuyển một table OLTP hiện có sang compression, phương thức nào phù hợp nhất để không ảnh hưởng đến ứng dụng đang chạy?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_30_table_compression_guide.md`
