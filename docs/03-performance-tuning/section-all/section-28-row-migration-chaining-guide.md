---
title: Section 28 — Row Migration & Row Chaining
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_28_row_migration_chaining_guide.md
---

# Section 28 — Row Migration & Row Chaining

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 30  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 28

Section 28 phân tích **Row Migration** và **Row Chaining** — hai hiện tượng khiến Oracle phải đọc thêm blocks không cần thiết, gây tăng I/O và giảm hiệu năng query.

---

## Kiến thức nền tảng

### Row Migration là gì?

```
Block A (PCTFREE đã đầy)
┌─────────────────────┐
│ Row 1: [ID=1, NAME='Alice', NOTE=NULL]  ← small row
│ Row 2: [ID=2, NAME='Bob',  NOTE=NULL]
│ ...free space hết...
└─────────────────────┘

UPDATE Row 1 SET NOTE = 'very long text...' (1000 chars)
↓ Block A không còn chỗ!

Block A                    Block B (block mới)
┌──────────────────┐       ┌──────────────────────────┐
│ Row 1: POINTER ──┼──────►│ Row 1 (migrated): full data│
│ Row 2: [data]    │       │                            │
└──────────────────┘       └──────────────────────────┘
```

**Row Migration:** Row phải di chuyển sang block khác do UPDATE làm row lớn hơn free space trong block hiện tại. Block cũ giữ **pointer** để index vẫn trỏ đúng.

**Tác động:** Mỗi lần đọc row migrated = đọc **2 blocks** (block gốc + block đích) thay vì 1.

---

### Row Chaining là gì?

```
Block size = 8 KB
Row size   = 20 KB  ← KHÔNG THỂ fit trong 1 block

Block A        Block B        Block C
┌──────────┐   ┌──────────┐   ┌──────────┐
│ Row part1│──►│ Row part2│──►│ Row part3│
└──────────┘   └──────────┘   └──────────┘
```

**Row Chaining:** Row quá lớn so với block size → Oracle chia row thành nhiều phần, mỗi phần ở một block, nối với nhau bằng chain pointers.

**Khác biệt quan trọng:**

| | Row Migration | Row Chaining |
|-|--------------|-------------|
| **Nguyên nhân** | UPDATE làm row lớn hơn free space | Row lớn hơn block size ngay từ đầu |
| **Khi xảy ra** | Sau khi INSERT, khi UPDATE | Ngay khi INSERT |
| **Có thể tránh?** | ✅ Tăng PCTFREE | ⚠️ Dùng block size lớn hơn, hoặc thiết kế lại |
| **Fix bằng MOVE?** | ✅ Có (nếu PCTFREE đủ) | ❌ Không (nếu block size vẫn nhỏ) |

---

## Metric: `table fetch continued row`

Đây là **stat quan trọng nhất** để phát hiện row migration/chaining:

```sql
-- Xem stat của session
SELECT NAME, VALUE
FROM V$MYSTAT S, V$STATNAME N
WHERE S.STATISTIC# = N.STATISTIC#
  AND N.NAME = 'table fetch continued row';
```

**Ý nghĩa:** Mỗi lần Oracle phải đọc thêm block do row migrated/chained → counter tăng 1.  
**Ngưỡng:** Càng thấp càng tốt. Cao → có migration/chaining.

---

## Phát hiện Row Migration/Chaining

### USER_TABLES — CHAIN_CNT

```sql
-- Hiển thị % chaining trong bảng CUST
SELECT CHAIN_CNT,
       ROUND(CHAIN_CNT/NUM_ROWS*100,2) CHAIN_PCT,
       AVG_ROW_LEN, PCT_FREE, PCT_USED, BLOCKS
FROM USER_TABLES
WHERE TABLE_NAME = 'CUST';
```

**Lưu ý quan trọng:**

> `CHAIN_CNT` trong `USER_TABLES` chứa cả **migrated rows** lẫn **chained rows** — không phân biệt.

**Cách lấy CHAIN_CNT đúng:**

```sql
-- DBMS_STATS KHÔNG tính CHAIN_CNT
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CUST');  -- CHAIN_CNT = NULL!

-- Phải dùng ANALYZE TABLE để có CHAIN_CNT
ANALYZE TABLE CUST COMPUTE STATISTICS;             -- CHAIN_CNT được populate ✅
```

---

## Ba phương pháp xử lý

### Phương pháp 1: Online Redefinition (DBMS_REDEFINITION)

**Dùng khi:** Table đang được DML liên tục, cần zero-downtime.

```sql
-- Rebuild toàn bộ table online
BEGIN
  DBMS_REDEFINITION.REDEF_TABLE(
    UNAME               => 'SOE',
    TNAME               => 'CUST',
    TABLE_PART_TABLESPACE => 'SOETBS',
    INDEX_TABLESPACE    => 'SOETBS'
  );
END;
/
```

**Hành vi với concurrent DML:**
- Chạy được khi table đang bị UPDATE
- Sẽ **chờ** cho đến khi tất cả uncommitted transactions hoàn thành (COMMIT/ROLLBACK)
- Sau khi xong → **phải rebuild indexes** (indexes trở thành UNUSABLE)

**Lựa chọn nhanh hơn (Oracle 12c+):**
```sql
-- MOVE ONLINE — nhanh hơn DBMS_REDEFINITION, cũng không block DML
ALTER TABLE cust MOVE TABLESPACE SOETBS ONLINE;
```

**Ưu/nhược:**

| | DBMS_REDEFINITION | ALTER TABLE MOVE ONLINE |
|-|-------------------|------------------------|
| Không block DML | ✅ | ✅ |
| Tốc độ | Chậm hơn | Nhanh hơn |
| Space cần | 2× table size | < 2× |
| Indexes sau đó | UNUSABLE → phải rebuild | Tự động valid (Oracle 12c+) |

---

### Phương pháp 2: Tăng PCTFREE

**Dùng khi:** Row migration do UPDATE làm row lớn hơn → ngăn chặn tái phát.

**PCTFREE là gì:**
```
Block = [DATA][DATA][DATA]...[FREE SPACE (PCTFREE%)]
                                    ↑
                    Oracle giữ lại % này cho UPDATE
```

- `PCTFREE 10` (mặc định) → Oracle giữ lại 10% block space cho UPDATE
- Nếu rows thường xuyên được UPDATE tăng kích thước → tăng PCTFREE

```sql
-- Tăng PCTFREE rồi rebuild
ALTER TABLE CUST PCTFREE 20;
ALTER TABLE cust MOVE TABLESPACE SOETBS ONLINE;

-- Verify
ANALYZE TABLE CUST COMPUTE STATISTICS;
SELECT CHAIN_CNT, CHAIN_PCT, PCT_FREE, BLOCKS FROM USER_TABLES WHERE TABLE_NAME='CUST';
```

**Trade-off:** PCTFREE cao hơn → **table dùng nhiều blocks hơn** (BLOCKS tăng) vì mỗi block chứa ít data hơn.

---

### Phương pháp 3: Tablespace với Block Size lớn hơn

**Dùng khi:** Row Chaining — row thực sự lớn hơn block size hiện tại.

**Chỉ giải quyết được Row Chaining** (không phải Migration), vì row quá lớn so với block size.

```sql
-- Bước 1: Cấu hình buffer cache cho block size mới (phải làm trước)
ALTER SYSTEM SET DB_32K_CACHE_SIZE = 160M;

-- Bước 2: Tạo tablespace với block size 32K
CREATE TABLESPACE TBS32K
DATAFILE '/u01/app/oracle/oradata/ORADB/datafile/tbs32k.dbf'
SIZE 160M AUTOEXTEND ON MAXSIZE 1000M BLOCKSIZE 32K;

ALTER USER SOE QUOTA UNLIMITED ON TBS32K;

-- Bước 3: Move table sang tablespace 32K
ALTER TABLE CUST MOVE TABLESPACE tbs32k;
ALTER INDEX CUST_NO_IDX REBUILD;

-- Bước 4: Verify
ANALYZE TABLE CUST COMPUTE STATISTICS;
SELECT CHAIN_CNT, CHAIN_PCT FROM USER_TABLES WHERE TABLE_NAME = 'CUST';
-- CHAIN_CNT = 0 ✅
```

**Điều kiện tiên quyết cho non-standard block size:**
- Phải set `DB_nK_CACHE_SIZE` trước khi tạo tablespace đó
- Oracle hỗ trợ: 2K, 4K, 8K (default), 16K, 32K

---

## Đo impact của Row Migration/Chaining

```sql
-- Script test_queries.sql — so sánh trước và sau fix
-- Flush cache để test khách quan
ALTER SYSTEM FLUSH SHARED_POOL;
ALTER SYSTEM FLUSH BUFFER_CACHE;

-- Snapshot stats trước
CREATE TABLE T1 AS
SELECT N.NAME, S.VALUE
FROM V$MYSTAT S, V$STATNAME N
WHERE S.STATISTIC# = N.STATISTIC#;

-- Chạy workload queries
DECLARE V_FIRST_NAME VARCHAR2(40);
BEGIN
  FOR I IN 1..100000 LOOP
    IF MOD(I,2)=0 OR MOD(I,3)=0 THEN
      SELECT FIRST_NAME INTO V_FIRST_NAME FROM CUST WHERE CUSTOMER_NO=I;
    END IF;
  END LOOP;
END;
/

-- Snapshot stats sau
CREATE TABLE T2 AS SELECT N.NAME, S.VALUE FROM V$MYSTAT S, V$STATNAME N
WHERE S.STATISTIC# = N.STATISTIC#;

-- So sánh
SELECT T1.NAME || ': ' || TO_CHAR(T2.VALUE - T1.VALUE) MYSTAT
FROM T1, T2
WHERE T1.NAME = T2.NAME
  AND T1.NAME IN ('DB time', 'CPU used by this session',
                  'session logical reads', 'table fetch continued row')
ORDER BY T1.NAME;
```

**Kết quả mong đợi sau khi fix:**
- `session logical reads` giảm (ít blocks cần đọc hơn)
- `table fetch continued row` = 0 (không còn migration/chaining)
- `DB time` và `CPU used` giảm tương ứng

---

## Checklist xử lý Row Migration & Chaining

| Bước | Hành động | Command |
|------|----------|---------|
| 1 | Lấy CHAIN_CNT đúng | `ANALYZE TABLE t COMPUTE STATISTICS` |
| 2 | Kiểm tra % | `SELECT CHAIN_PCT FROM USER_TABLES` |
| 3 | Xác định loại | Migration (UPDATE) hay Chaining (INSERT)? |
| 4a | Fix Migration (24/7) | `DBMS_REDEFINITION.REDEF_TABLE` hoặc `MOVE ONLINE` |
| 4b | Fix Migration + ngăn tái phát | `ALTER TABLE t PCTFREE 20` + `MOVE ONLINE` |
| 4c | Fix Chaining | Tạo tablespace block size lớn hơn + `MOVE` |
| 5 | Verify | `ANALYZE TABLE` → `CHAIN_CNT = 0` |

---

## Tóm tắt Views & Commands

| View/Command | Dùng để |
|-------------|---------|
| `USER_TABLES` — `CHAIN_CNT`, `PCT_FREE` | Xem % migrated+chained rows |
| `ANALYZE TABLE t COMPUTE STATISTICS` | Populate CHAIN_CNT (DBMS_STATS không làm được) |
| `V$MYSTAT` + `table fetch continued row` | Đo impact trực tiếp |
| `DBMS_REDEFINITION.REDEF_TABLE` | Online rebuild, không block DML |
| `ALTER TABLE t MOVE TABLESPACE x ONLINE` | Nhanh hơn, online (Oracle 12c+) |
| `ALTER TABLE t PCTFREE n` | Tăng free space dành cho UPDATE |
| `DB_32K_CACHE_SIZE` | Bật buffer cache cho 32K blocks |
| `CREATE TABLESPACE ... BLOCKSIZE 32K` | Tablespace với block size lớn hơn |

---

## Câu hỏi ôn tập

1. Phân biệt Row Migration và Row Chaining — nguyên nhân khác nhau như thế nào?
2. Tại sao `DBMS_STATS.GATHER_TABLE_STATS` không tính `CHAIN_CNT`? Phải dùng lệnh nào?
3. Stat `table fetch continued row` đo lường gì? Giá trị cao có nghĩa là gì?
4. `PCTFREE` là gì? Tăng PCTFREE giải quyết được loại vấn đề nào (Migration hay Chaining)?
5. Tại sao `ALTER TABLE ... MOVE` không giải quyết được Row Chaining nếu không thay đổi block size?
6. Điều kiện tiên quyết để tạo tablespace 32K là gì? Tại sao?
7. `DBMS_REDEFINITION.REDEF_TABLE` có thể chạy khi table đang bị UPDATE không? Có điều kiện gì?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_28_row_migration_chaining_guide.md`
