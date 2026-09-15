---
title: Section 27 — Index Defragmentation
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_27_index_defrag_guide.md
---

# Section 27 — Index Defragmentation

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 29  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 27

Section 27 so sánh hai phương pháp **chống phân mảnh index** trong Oracle: **Rebuild** và **Coalesce** — mỗi phương pháp có ưu/nhược điểm khác nhau, đặc biệt khi áp dụng trên production system.

---

## Kiến thức nền tảng

### Index Fragmentation xảy ra như thế nào?

Oracle B-tree index lưu data theo cấu trúc cây:

```
Root Block
    ├── Branch Block
    │       ├── Leaf Block  [R_ID: 1, 2, 3, 4, 5...]
    │       └── Leaf Block  [R_ID: 6, 7, 8, 9, 10...]
    └── Branch Block
            ├── Leaf Block  [R_ID: 11, 12, 13...]
            └── Leaf Block  [R_ID: 14, 15, 16...]
```

Khi rows bị **DELETE**:
- Index entries bị đánh dấu là **deleted** nhưng space **không được trả lại**
- Leaf blocks chứa nhiều deleted entries → lãng phí space
- Phải đọc nhiều blocks hơn cần thiết → I/O tăng

**Trường hợp phổ biến cần defragmentation:**
- Table nhận data tuần tự (theo ID hoặc timestamp) và liên tục DELETE data cũ
- Bulk DELETE xóa nhiều rows liên tiếp
- Nhiều UPDATE làm row migrated → index entries cũ bị deleted

### Xem xét khi nào CẦN defragmentation

> Không phải lúc nào cũng cần rebuild — Oracle có thể **tái sử dụng** deleted entries khi INSERT mới vào cùng key range. Chỉ defragment khi có bằng chứng cụ thể (DEL_LF_ROWS cao, PCT_USED thấp).

---

## Phân tích Index Statistics

### 1. USER_IND_STATISTICS — thông tin cơ bản

```sql
SELECT BLEVEL,
       LEAF_BLOCKS        AS "LEAFBLK",
       DISTINCT_KEYS      AS "DIST_KEY",
       AVG_LEAF_BLOCKS_PER_KEY AS "LEAFBLK_PER_KEY",
       AVG_DATA_BLOCKS_PER_KEY AS "DATABLK_PER_KEY"
FROM USER_IND_STATISTICS
WHERE INDEX_NAME = 'TTABLE_IDX';
```

**Hạn chế:** Không có cột `DEL_LF_ROWS` — không thấy số deleted entries.

### 2. ANALYZE INDEX ... VALIDATE STRUCTURE — chi tiết đầy đủ

```sql
ANALYZE INDEX ttable_idx VALIDATE STRUCTURE;

SELECT HEIGHT, BLOCKS, LF_BLKS, BR_BLKS, DEL_LF_ROWS, BTREE_SPACE, PCT_USED
FROM INDEX_STATS;
```

**Giải thích các cột:**

| Cột | Ý nghĩa |
|-----|---------|
| `HEIGHT` | Chiều cao cây B-tree (thường 2-3 là bình thường) |
| `BLOCKS` | Tổng số blocks được cấp phát cho index |
| `LF_BLKS` | Số leaf blocks thực tế có data |
| `BR_BLKS` | Số branch blocks |
| `DEL_LF_ROWS` | **Số deleted entries còn chiếm space** — key metric |
| `BTREE_SPACE` | Tổng bytes trong B-tree |
| `PCT_USED` | % space đang được sử dụng thực sự |

**Ngưỡng cảnh báo:**
- `DEL_LF_ROWS` >> 0 (đặc biệt nếu chiếm >20-30% tổng rows) → xem xét defragment
- `PCT_USED` thấp → index có nhiều wasted space

**Lưu ý quan trọng:** `ANALYZE INDEX ... VALIDATE STRUCTURE` yêu cầu **exclusive lock** trên index — tránh dùng trên production đang có workload. Document ID 989186.1 có alternative method không cần lock.

---

## Phương pháp 1: REBUILD INDEX

### Cú pháp

```sql
-- Offline rebuild (table không accessible trong lúc rebuild)
ALTER INDEX TTABLE_IDX REBUILD;

-- Online rebuild (table vẫn accessible, nhưng có thể bị block)
ALTER INDEX TTABLE_IDX REBUILD ONLINE;

-- Rebuild vào tablespace khác
ALTER INDEX TTABLE_IDX REBUILD TABLESPACE new_tbs;
```

### Kết quả sau REBUILD

| Metric | Trước | Sau |
|--------|-------|-----|
| `BLOCKS` | 1000 | ~600 (giảm đáng kể) |
| `LF_BLKS` | 900 | ~550 (giảm) |
| `DEL_LF_ROWS` | 200,000 | **0** |
| `PCT_USED` | 90% | ~95% |

**Space được TRẢ LẠI hoàn toàn** cho tablespace.

### Hạn chế của REBUILD trên Production

```
ALTER INDEX TTABLE_IDX REBUILD ONLINE;
```

→ Khi table đang được UPDATE concurrent, `REBUILD ONLINE` **chờ lock** trên các rows đang bị update.

- Wait event: `enq: TX - row lock contention` hoặc `blocking txn id for DDL`
- Dùng `V$SESSION` với `CLIENT_IDENTIFIER` để track trạng thái:

```sql
-- Gắn identifier trước khi rebuild
EXEC DBMS_SESSION.SET_IDENTIFIER('Index Rebuild');
ALTER INDEX TTABLE_IDX REBUILD ONLINE;

-- Từ session khác — theo dõi trạng thái
SELECT EVENT, SECONDS_IN_WAIT, WAIT_TIME
FROM V$SESSION
WHERE CLIENT_IDENTIFIER = 'Index Rebuild'
ORDER BY WAIT_TIME;
```

---

## Phương pháp 2: COALESCE INDEX

### Cú pháp

```sql
-- Coalesce (tương đương SHRINK SPACE COMPACT)
ALTER INDEX TTABLE_IDX COALESCE;

-- Hoặc dùng SHRINK SPACE COMPACT (Oracle 10g+)
ALTER INDEX TTABLE_IDX SHRINK SPACE COMPACT;
```

### Kết quả sau COALESCE

| Metric | Trước | Sau |
|--------|-------|-----|
| `BLOCKS` | 1000 | **1000 (KHÔNG thay đổi)** |
| `LF_BLKS` | 900 | ~550 (giảm) |
| `DEL_LF_ROWS` | 200,000 | **0** |
| `BTREE_SPACE` | lớn | nhỏ hơn |

**Space KHÔNG được trả lại** cho tablespace — chỉ được compact trong các blocks đã cấp phát.

### Ưu điểm của COALESCE

- **Không yêu cầu lock** — chạy được khi table đang bị UPDATE concurrent
- Phù hợp cho production 24/7 không có maintenance window
- Không gây blocking

---

## So sánh REBUILD vs COALESCE

| Tiêu chí | REBUILD | COALESCE |
|---------|---------|---------|
| **Xóa deleted entries** | ✅ Có | ✅ Có |
| **Trả space về tablespace** | ✅ Có (BLOCKS giảm) | ❌ Không (BLOCKS giữ nguyên) |
| **Yêu cầu lock** | ✅ Cần lock (ONLINE: ít hơn) | ❌ Không cần lock |
| **Blocking concurrent DML** | ✅ Có thể bị block | ❌ Không bị block |
| **Phù hợp production** | ⚠️ Có rủi ro | ✅ Khuyến nghị |
| **Overhead** | Cao (tạo lại toàn bộ) | Thấp (merge leaf blocks) |
| **Cần REBUILD sau không?** | Không | Không (chỉ compact) |

**Kết luận:**
> Trên production system, **COALESCE là phương pháp được khuyến nghị** khi cần defragmentation vì không yêu cầu lock và không block DML concurrent.

---

## Quy trình đánh giá và xử lý Index Fragmentation

```
1. Thu thập statistics
   ANALYZE INDEX idx_name VALIDATE STRUCTURE;
   SELECT DEL_LF_ROWS, PCT_USED FROM INDEX_STATS;
       ↓
2. Đánh giá mức độ fragmentation
   DEL_LF_ROWS / (LF_ROWS + DEL_LF_ROWS) > 20%? → cần xem xét
       ↓
3. Chọn phương pháp
   ├── Có maintenance window? → REBUILD (trả space, sạch hơn)
   └── Không có maintenance window? → COALESCE (an toàn, không block)
       ↓
4. Thực hiện và verify
   ANALYZE INDEX ... VALIDATE STRUCTURE;
   SELECT DEL_LF_ROWS FROM INDEX_STATS; -- phải = 0
```

---

## Monitoring Index Health — Views

```sql
-- Xem tất cả indexes của schema hiện tại
SELECT INDEX_NAME, TABLE_NAME, BLEVEL, LEAF_BLOCKS,
       DISTINCT_KEYS, STATUS, LAST_ANALYZED
FROM USER_IND_STATISTICS
ORDER BY LEAF_BLOCKS DESC;

-- Index với BLEVEL cao (cây quá sâu → cần rebuild)
SELECT INDEX_NAME, BLEVEL
FROM USER_IND_STATISTICS
WHERE BLEVEL >= 4;  -- BLEVEL >= 4 là dấu hiệu cần rebuild

-- Index UNUSABLE
SELECT INDEX_NAME, STATUS
FROM USER_INDEXES
WHERE STATUS = 'UNUSABLE';
```

---

## Tóm tắt Commands

| Command | Dùng để |
|---------|---------|
| `ANALYZE INDEX idx VALIDATE STRUCTURE` | Phân tích chi tiết, xem DEL_LF_ROWS |
| `SELECT ... FROM INDEX_STATS` | Đọc kết quả sau ANALYZE |
| `ALTER INDEX idx REBUILD` | Rebuild hoàn toàn (cần lock) |
| `ALTER INDEX idx REBUILD ONLINE` | Rebuild online (ít lock hơn, nhưng có thể bị block) |
| `ALTER INDEX idx COALESCE` | Compact leaf blocks (không cần lock) |
| `ALTER INDEX idx SHRINK SPACE COMPACT` | Tương đương COALESCE |
| `SELECT ... FROM USER_IND_STATISTICS` | Xem statistics cơ bản (không có DEL_LF_ROWS) |

---

## Câu hỏi ôn tập

1. Tại sao DELETE nhiều rows không trả space của index về cho tablespace?
2. Sự khác biệt chính giữa REBUILD và COALESCE là gì? Cái nào được khuyến nghị cho production?
3. `ANALYZE INDEX ... VALIDATE STRUCTURE` có hạn chế gì trên production? Tại sao?
4. Metric `DEL_LF_ROWS` trong `INDEX_STATS` đo lường gì? Ngưỡng bao nhiêu nên xem xét defragment?
5. Tại sao `ALTER INDEX ... REBUILD ONLINE` vẫn có thể bị hang khi table đang được UPDATE?
6. Sau khi COALESCE, `BLOCKS` không giảm — điều đó có nghĩa gì? Có phải vấn đề không?
7. Trường hợp nào trong thực tế thường gây ra index fragmentation nghiêm trọng nhất?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_27_index_defrag_guide.md`
