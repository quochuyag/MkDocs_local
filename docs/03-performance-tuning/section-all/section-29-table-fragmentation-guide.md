---
title: Section 29 — Table Fragmentation
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_29_table_fragmentation_guide.md
---

# Section 29 — Table Fragmentation

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 31  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 29

Section 29 tập trung vào **Table Fragmentation** — hiện tượng blocks trong table có quá nhiều wasted space sau DELETE/UPDATE, gây **Full Table Scan (FTS) chậm hơn** vì Oracle phải đọc nhiều blocks rỗng không cần thiết.

---

## Kiến thức nền tảng

### Table Fragmentation là gì?

```
Trước DELETE/UPDATE:
Block 1: [Row1][Row2][Row3][Row4][Row5]  ← đầy
Block 2: [Row6][Row7][Row8][Row9][Row10] ← đầy
Block 3: [Row11][Row12]...               ← đang dùng

Sau DELETE nhiều rows + UPDATE shrink rows:
Block 1: [Row1][ empty ][ empty ][Row4][ empty ]  ← 60% rỗng
Block 2: [ empty ][Row7][ empty ][ empty ][Row10]  ← 60% rỗng
Block 3: [Row11]...

FTS phải đọc TẤT CẢ blocks → nhiều I/O cho ít data thực tế
```

**Tác động chính:** FTS (Full Table Scan) đọc nhiều blocks hơn cần thiết → tăng `session logical reads`, tăng I/O, chậm hơn.

### Khi nào fragmentation xảy ra?

- **DELETE** nhiều rows → blocks còn lại có nhiều "holes"
- **UPDATE** làm rows nhỏ lại (VD: set cột VARCHAR2 về NULL hoặc giá trị ngắn hơn)
- Kết hợp INSERT/DELETE/UPDATE không đều → blocks có density thấp

### Fragmentation vs Row Migration/Chaining

| | Table Fragmentation | Row Migration | Row Chaining |
|-|--------------------|--------------|-|
| **Ảnh hưởng** | FTS phải đọc nhiều blocks rỗng | Index lookup tốn 2+ blocks | Row phân mảnh qua blocks |
| **Metric** | `AVG_SPACE` cao trong `USER_TABLES` | `table fetch continued row` cao | `table fetch continued row` cao |
| **Fix** | `SHRINK SPACE` | MOVE + PCTFREE | MOVE + larger block size |

---

## Phát hiện Table Fragmentation

### USER_TABLES — AVG_SPACE và BLOCKS

```sql
-- Phải ANALYZE trước để có AVG_SPACE chính xác
ANALYZE TABLE CUST COMPUTE STATISTICS;

SELECT BLOCKS,
       BLOCKS * 8192 / 1024          TOTAL_SIZE_KB,
       AVG_SPACE,
       ROUND(BLOCKS * AVG_SPACE / 1024, 2) FREE_SPACE_KB
FROM USER_TABLES
WHERE TABLE_NAME = 'CUST';
```

**Giải thích:**

| Cột | Ý nghĩa |
|-----|---------|
| `BLOCKS` | Tổng số blocks đã cấp phát cho table |
| `AVG_SPACE` | Trung bình bytes free trong mỗi block |
| `FREE_SPACE_KB` | Tổng estimated free space (KB) |

**Dấu hiệu fragmentation:**
- `FREE_SPACE_KB` chiếm nhiều % `TOTAL_SIZE_KB` → quá nhiều space lãng phí
- Thực nghiệm trong course: **gần 50% table là deleted space** sau workload DELETE/UPDATE

---

## Xử lý: SHRINK SPACE

### Cú pháp

```sql
-- Yêu cầu bật ROW MOVEMENT trước
ALTER TABLE CUST ENABLE ROW MOVEMENT;

-- Shrink table và tất cả dependent objects (indexes)
ALTER TABLE CUST SHRINK SPACE CASCADE;

-- Chỉ shrink table (không CASCADE đến indexes)
ALTER TABLE CUST SHRINK SPACE;

-- Chỉ compact (không release HWM — không trả space về tablespace)
ALTER TABLE CUST SHRINK SPACE COMPACT;
```

### Ba giai đoạn của SHRINK SPACE

```
Phase 1 (COMPACT): Di chuyển rows về đầu table, giải phóng space ở cuối
    ↓ (DML vẫn hoạt động bình thường)
Phase 2 (HWM adjustment): Hạ High Water Mark — trả space về tablespace
    ↓ (brief exclusive lock — rất nhanh)
Phase 3 (CASCADE): Rebuild indexes nếu có CASCADE
```

**SHRINK SPACE COMPACT** = chỉ Phase 1, không Phase 2 → space chưa được trả về tablespace.  
Dùng khi muốn tách Phase 1 (chạy giờ cao điểm) và Phase 2 (chạy off-peak).

### ROW MOVEMENT — tại sao cần?

`SHRINK SPACE` di chuyển rows giữa các blocks → ROWID của rows **thay đổi**.  
Oracle cần biết table cho phép di chuyển rows → phải `ENABLE ROW MOVEMENT`.

**Lưu ý:** `ALTER TABLE ... ENABLE ROW MOVEMENT` yêu cầu **không có uncommitted transactions** trên table → nếu table đang bị UPDATE, lệnh sẽ báo lỗi.

---

## SHRINK SPACE vs ALTER TABLE MOVE

| Tiêu chí | SHRINK SPACE | ALTER TABLE MOVE |
|---------|-------------|----------------|
| **Blocking DML** | ❌ Online (Phase 1) | ✅ Blocks DML |
| **Trả space về tablespace** | ✅ Có | ✅ Có |
| **Indexes sau đó** | ✅ Valid (với CASCADE) | ❌ UNUSABLE → phải rebuild |
| **ROWID thay đổi** | ✅ Có (cần ENABLE ROW MOVEMENT) | ✅ Có |
| **Phù hợp production** | ✅ Tốt hơn | ⚠️ Cần maintenance window |
| **Cần thêm space?** | Ít hơn | ~2× table size |

---

## Đo impact của Fragmentation lên FTS

```sql
-- Flush cache để test khách quan
ALTER SYSTEM FLUSH SHARED_POOL;
ALTER SYSTEM FLUSH BUFFER_CACHE;

-- Snapshot stats trước
CREATE TABLE T1 AS
SELECT N.NAME, S.VALUE FROM V$MYSTAT S, V$STATNAME N
WHERE S.STATISTIC# = N.STATISTIC#;

-- Chạy FTS workload (query không dùng index)
DECLARE V_FIRST_NAME VARCHAR2(40);
BEGIN
  FOR I IN 1..1000 LOOP
    BEGIN
      SELECT FIRST_NAME INTO V_FIRST_NAME FROM CUST WHERE CUSTOMER_NO = I;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
  END LOOP;
END;
/

-- Snapshot stats sau
CREATE TABLE T2 AS
SELECT N.NAME, S.VALUE FROM V$MYSTAT S, V$STATNAME N
WHERE S.STATISTIC# = N.STATISTIC#;

-- So sánh
SELECT T1.NAME || ': ' || TO_CHAR(T2.VALUE - T1.VALUE) MYSTAT
FROM T1, T2
WHERE T1.NAME = T2.NAME
  AND T1.NAME IN ('DB time', 'CPU used by this session', 'session logical reads')
ORDER BY T1.NAME;
```

**Kết quả mong đợi sau SHRINK:**
- `session logical reads` **giảm đáng kể** (ít blocks cần đọc hơn)
- `DB time` và `CPU used` giảm tương ứng

---

## Quy trình chẩn đoán và xử lý

```
1. Thu thập statistics
   ANALYZE TABLE t COMPUTE STATISTICS;
   SELECT BLOCKS, TOTAL_SIZE_KB, FREE_SPACE_KB FROM USER_TABLES;
       ↓
2. Đánh giá mức độ
   FREE_SPACE_KB / TOTAL_SIZE_KB > 30%? → xem xét shrink
       ↓
3. Enable ROW MOVEMENT (khi không có uncommitted txn)
   ALTER TABLE t ENABLE ROW MOVEMENT;
       ↓
4. Shrink
   ALTER TABLE t SHRINK SPACE CASCADE;
       ↓
5. Verify
   ANALYZE TABLE t COMPUTE STATISTICS;
   SELECT BLOCKS, FREE_SPACE_KB FROM USER_TABLES; -- BLOCKS và FREE_SPACE_KB giảm
```

---

## Tóm tắt Commands & Views

| Command/View | Dùng để |
|-------------|---------|
| `ANALYZE TABLE t COMPUTE STATISTICS` | Populate AVG_SPACE, BLOCKS chính xác |
| `USER_TABLES` — `AVG_SPACE`, `BLOCKS` | Phát hiện fragmentation |
| `ALTER TABLE t ENABLE ROW MOVEMENT` | Cho phép SHRINK (rows có thể đổi ROWID) |
| `ALTER TABLE t SHRINK SPACE CASCADE` | Shrink table + tất cả indexes (online) |
| `ALTER TABLE t SHRINK SPACE COMPACT` | Chỉ compact, chưa hạ HWM |
| `ALTER TABLE t SHRINK SPACE` | Shrink table, không rebuild indexes |
| `V$MYSTAT` — `session logical reads` | Đo impact FTS trước/sau shrink |

---

## Câu hỏi ôn tập

1. Table fragmentation ảnh hưởng đến loại query nào nhiều nhất — Index Scan hay FTS? Tại sao?
2. `AVG_SPACE` trong `USER_TABLES` đo lường gì? Cần chạy lệnh nào trước để có giá trị chính xác?
3. Tại sao `ALTER TABLE ... ENABLE ROW MOVEMENT` cần thiết trước khi SHRINK SPACE?
4. Sự khác biệt giữa `SHRINK SPACE` và `SHRINK SPACE COMPACT` là gì?
5. `SHRINK SPACE CASCADE` làm gì với indexes? Tại sao đây là ưu điểm so với `ALTER TABLE MOVE`?
6. Khi nào nên tách Phase 1 (COMPACT) và Phase 2 (HWM adjustment) của SHRINK?
7. Tại sao `ALTER TABLE ... ENABLE ROW MOVEMENT` có thể thất bại khi table đang bị UPDATE?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_29_table_fragmentation_guide.md`
