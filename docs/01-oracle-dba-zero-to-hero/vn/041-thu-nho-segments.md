---
title: 'Bài 41: Thu nhỏ Segments (Shrinking Segments)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/41-thu-nho-segments.md
---

# Bài 41: Thu nhỏ Segments (Shrinking Segments)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Mô tả ROWID pseudocolumn
- Mô tả hiện tượng phân mảnh segment (segment defragmentation)
- Thu nhỏ database segments
- Giải phóng không gian chưa sử dụng (deallocate unused space)
- Di chuyển bảng sang vị trí khác

---

## 1. ROWID Pseudocolumn

### 1.1 ROWID là gì?
Oracle Database sử dụng **ROWID** để định danh duy nhất từng row trong database. ROWID chứa đủ thông tin để Oracle truy cập **trực tiếp** đến row đó.

### 1.2 Cấu trúc ROWID

```
AAAPvh  AAL   AAAAFO  AAA
  |      |       |     |
  |      |       |     └── Row Number (số thứ tự row trong block)
  |      |       └──────── Block Number (số block trong file)
  |      └──────────────── Relative File Number (số thứ tự file)
  └─────────────────────── Data Object Number (số đối tượng)
```

### 1.3 Đặc điểm của ROWID
- **Tính ổn định**: ROWID không thay đổi trừ khi segment bị tổ chức lại, shrink, di chuyển, hoặc rebuild
- **Được dùng bởi Index**: Index Oracle lưu ROWID để tham chiếu đến row trong bảng
- **Có thể query**:

```sql
-- Xem ROWID của một row
SELECT ROWID FROM employees WHERE employee_id = 100;
-- Kết quả: AAAPvhAALAAAAFOAAA

-- Truy cập row bằng ROWID (nhanh nhất)
SELECT employee_id FROM employees WHERE ROWID = 'AAAPvhAALAAAAFOAAA';
```

---

## 2. Phân mảnh Segment (Segment Defragmentation)

### 2.1 High Water Mark (HWM) là gì?

**HWM** là ranh giới cao nhất mà dữ liệu từng chiếm trong segment. Khi thực hiện **Full Table Scan (FTS)**, Oracle phải đọc **tất cả blocks dưới HWM**, kể cả các block trống.

### 2.2 Quá trình tạo ra phân mảnh

| Thao tác | Tác động |
|----------|----------|
| INSERT | HWM tăng lên, blocks mới được sử dụng |
| DELETE | Rows bị xóa nhưng HWM **không giảm**, block vẫn nằm dưới HWM |
| UPDATE (giảm kích thước row) | Không gian dư thừa trong block |

**Kết quả**: Sau nhiều DELETE và UPDATE, segment có nhiều **empty space** (không gian trống) bên trong các blocks dưới HWM → **Full Table Scan chậm** dù bảng ít dữ liệu.

### 2.3 Minh họa phân mảnh

```
Trước khi INSERT:
[HWM]
[....] [....] [....] (unused blocks)

Sau khi INSERT 100,000 rows:
                                  [HWM]
[XXXX] [XXXX] [XXXX] ... [XXXX] (used blocks)

Sau DELETE 40% rows và UPDATE 30% rows:
                                  [HWM] ← không đổi!
[XX..] [.X..] [XXX.] ... [X.X.] (mixed blocks with empty space)
```

---

## 3. Giải pháp chống phân mảnh bảng

| Phương pháp | Mô tả |
|-------------|-------|
| **Shrinking** | Thu nhỏ segment, hạ HWM |
| **Deallocate Unused Space** | Giải phóng không gian trên HWM |
| **Move Table** | Di chuyển bảng → defragment tự động |
| **Online Redefinition** | Tái cấu trúc online |
| **Data Pump Export/Import** | Export → xóa → Import |

---

## 4. Thu nhỏ Segment (Shrinking)

### 4.1 Cách hoạt động

**Shrink không có COMPACT**:
1. Oracle di chuyển rows từ các block dưới HWM lên các block có không gian trống (gần đầu segment)
2. HWM được **hạ xuống** → không gian thừa được giải phóng về tablespace

**Shrink với COMPACT**:
1. Oracle chỉ **nén dữ liệu** (di chuyển rows) nhưng **không hạ HWM**
2. Không gian chưa được giải phóng ngay
3. Phù hợp khi có DML đang chạy song song

### 4.2 Lưu ý quan trọng

> **ROWID thay đổi!** Khi shrink, rows được di chuyển → ROWID của chúng thay đổi. Điều này ảnh hưởng đến:
> - **Indexes**: có thể trở nên unusable → thường Oracle tự cập nhật
> - **ROWID-based Triggers**: phải disable trước khi shrink

### 4.3 Yêu cầu

- Tablespace phải dùng **Automatic Segment Space Management (ASSM)**
- Phải bật **Row Movement** trước khi shrink

### 4.4 Cú pháp

```sql
-- Bước 1: Bật row movement
ALTER TABLE my_table ENABLE ROW MOVEMENT;

-- Bước 2: Shrink
ALTER TABLE my_table SHRINK SPACE;              -- shrink + hạ HWM
ALTER TABLE my_table SHRINK SPACE COMPACT;      -- chỉ nén, không hạ HWM
ALTER TABLE my_table SHRINK SPACE CASCADE;      -- shrink cả indexes liên quan
ALTER TABLE my_table SHRINK SPACE COMPACT CASCADE;  -- nén + cascade

-- (Tùy chọn) Bước 3: Tắt row movement
ALTER TABLE my_table DISABLE ROW MOVEMENT;
```

### 4.5 Áp dụng được cho

- Tables và partitions/sub-partitions
- Index và Index-Organized Tables (IOT)
- LOB segments
- Materialized Views và Materialized View Logs

---

## 5. Đo lường không gian đã xóa

```sql
-- Cập nhật thống kê bảng
ANALYZE TABLE my_table COMPUTE STATISTICS;

-- Xem thông tin không gian
SELECT BLOCKS,
       BLOCKS * 8192 / 1024    TOTAL_SIZE_KB,
       AVG_SPACE,
       ROUND(BLOCKS * AVG_SPACE / 1024, 2)  FREE_SPACE_KB
FROM USER_TABLES
WHERE TABLE_NAME = 'MY_TABLE';
```

| Cột | Mô tả |
|-----|-------|
| `BLOCKS` | Tổng số blocks dưới HWM |
| `TOTAL_SIZE_KB` | Tổng kích thước (KB) |
| `AVG_SPACE` | Không gian trống trung bình mỗi block (bytes) |
| `FREE_SPACE_KB` | Tổng không gian trống (KB) |

---

## 6. Best Practice khi Shrink Tables

- **Khi nào nên shrink?** Khi > **20%** không gian của bảng là không gian trống (deleted space)
- **Full Table Scan**: Shrink chủ yếu có lợi cho các query dùng FTS
- **Giờ cao điểm**: Dùng `COMPACT` trong giờ cao điểm khi có nhiều DML đồng thời, sau đó hạ HWM vào giờ thấp điểm
- **Indexes**: Rebuild thường tốt hơn shrink cho indexes

```sql
-- Rebuild index (thường hiệu quả hơn shrink)
ALTER INDEX my_index REBUILD;
```

---

## 7. Giải phóng không gian chưa sử dụng (Deallocate Unused Space)

Khác với Shrink, **Deallocate** chỉ giải phóng không gian **trên HWM** (phần chưa bao giờ dùng):

```sql
-- Giải phóng tất cả không gian trên HWM
ALTER TABLE my_table DEALLOCATE UNUSED;

-- Giữ lại ít nhất n bytes trên HWM
ALTER TABLE my_table DEALLOCATE UNUSED KEEP 1M;
```

> **Lưu ý**: Deallocate **không** giảm HWM như Shrink. Nó chỉ giải phóng phần **unused** nằm trên HWM. Trong hầu hết trường hợp, **Shrink hữu ích hơn** Deallocate.

---

## 8. Di chuyển bảng (Moving a Table)

Khi bảng được di chuyển sang vị trí mới (trong cùng hoặc khác tablespace), nó tự động được **defragment** trong quá trình di chuyển:

```sql
-- Di chuyển bảng (offline — table bị lock trong quá trình)
ALTER TABLE my_table MOVE TABLESPACE users;

-- Di chuyển online (không lock, từ Oracle 12c)
ALTER TABLE my_table MOVE ONLINE TABLESPACE users UPDATE INDEXES;
```

| Option | Mô tả |
|--------|-------|
| `ONLINE` | Cho phép DML trong quá trình di chuyển (12c+) |
| `UPDATE INDEXES` | Tự động cập nhật indexes sau khi di chuyển |

> **Lưu ý**: Nếu không dùng `UPDATE INDEXES`, tất cả indexes sẽ ở trạng thái UNUSABLE sau khi di chuyển và phải rebuild thủ công.

---

## Tổng kết

| Phương pháp | Thao tác | Hạ HWM? | Cần Row Movement? |
|-------------|----------|---------|-----------------|
| `SHRINK SPACE` | Nén data + hạ HWM | ✅ Có | ✅ Cần |
| `SHRINK SPACE COMPACT` | Chỉ nén data | ❌ Không | ✅ Cần |
| `DEALLOCATE UNUSED` | Giải phóng không gian trên HWM | ❌ Không | ❌ Không cần |
| `MOVE` | Di chuyển + defragment | ✅ Có (reset) | ✅ Cần |

> **Lưu ý chung**: Sau khi Shrink hoặc Move mà không dùng `UPDATE INDEXES`, hãy kiểm tra trạng thái indexes và rebuild nếu cần.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/41-thu-nho-segments.md`
