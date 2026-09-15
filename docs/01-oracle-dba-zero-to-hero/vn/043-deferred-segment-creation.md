---
title: 'Bài 43: Deferred Segment Creation (Tạo Segment Trì hoãn)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/43-deferred-segment-creation.md
---

# Bài 43: Deferred Segment Creation (Tạo Segment Trì hoãn)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu và sử dụng tính năng Deferred Segment Creation
- Materialize (cụ thể hóa) các database segments

---

## 1. Vấn đề trước Oracle 11g

### Trước 11g: Không gian bị lãng phí bởi bảng rỗng

Trong các phiên bản Oracle trước 11g, khi tạo một bảng, Oracle **ngay lập tức** phân bổ ít nhất 1 extent (thường 1 MB trong tablespace locally managed) — kể cả khi bảng hoàn toàn **rỗng**.

**Ví dụ thực tế:**
Khi triển khai một ứng dụng mới với 1,000 bảng, Oracle sẽ phân bổ ngay:
```
1,000 bảng × 1 MB = 1,000 MB = ~1 GB
```
...dù tất cả các bảng đều trống!

---

## 2. Deferred Segment Creation là gì?

Tính năng được giới thiệu từ **Oracle 11g R2**: Khi tạo bảng, Oracle **không** phân bổ segment ngay. Segment chỉ được tạo khi có **row đầu tiên được INSERT** vào bảng.

### Cơ chế hoạt động:
```
CREATE TABLE → Chỉ tạo object metadata trong Data Dictionary
                 (không phân bổ segment/extent)
                          ↓
Bảng xuất hiện trong *_TABLES nhưng KHÔNG có trong *_SEGMENTS

                          ↓
INSERT row đầu tiên → Oracle mới phân bổ segment thực tế
```

### Lợi ích:
- **Tiết kiệm đĩa**: Không tốn không gian cho các bảng rỗng
- **Giảm thời gian cài đặt**: Triển khai ứng dụng nhanh hơn vì không cần phân bổ không gian

---

## 3. Khi nào Segment Creation bị trì hoãn?

### 3.1 Tham số DEFERRED_SEGMENT_CREATION

```sql
-- Xem giá trị hiện tại (mặc định = TRUE)
SHOW PARAMETER DEFERRED_SEGMENT_CREATION;

-- Tắt ở cấp system
ALTER SYSTEM SET DEFERRED_SEGMENT_CREATION = FALSE;

-- Tắt ở cấp session
ALTER SESSION SET DEFERRED_SEGMENT_CREATION = FALSE;
```

| Giá trị | Hành vi |
|---------|---------|
| `TRUE` (mặc định) | Tạo bảng với Deferred Segment Creation |
| `FALSE` | Tạo bảng với segment ngay lập tức |

### 3.2 Kiểm soát ở cấp từng bảng

```sql
-- Tạo bảng với segment NGAY LẬP TỨC (dù tham số system = TRUE)
CREATE TABLE my_table (...) SEGMENT CREATION IMMEDIATE;

-- Tạo bảng với DEFERRED segment (dù tham số system = FALSE)
CREATE TABLE my_table (...) SEGMENT CREATION DEFERRED;
```

---

## 4. Kiểm tra trạng thái Segment

Khi Deferred Segment Creation được kích hoạt, cột `SEGMENT_CREATED` trong các view Dictionary sẽ cho biết segment đã được tạo hay chưa:

```sql
-- Kiểm tra bảng đã có segment chưa
SELECT TABLE_NAME, SEGMENT_CREATED
FROM USER_TABLES
WHERE TABLE_NAME IN ('TABLE_A', 'TABLE_B');
```

| `SEGMENT_CREATED` | Ý nghĩa |
|------------------|---------|
| `YES` | Segment đã được tạo (bảng có ít nhất 1 row) |
| `NO` | Segment chưa được tạo (bảng đang rỗng) |

Tương tự cho:
- `*_TABLES` — bảng
- `*_INDEXES` — index
- `*_LOBS` — LOB columns
- `*_TAB_PARTITIONS` — partition của bảng
- `*_IND_PARTITIONS` — partition của index
- `*_LOB_PARTITIONS` — partition của LOB

### Ví dụ kiểm tra bảng rỗng

```sql
-- Tạo bảng (segment chưa được tạo)
CREATE TABLE test_deferred (id NUMBER, name VARCHAR2(50));

-- Kiểm tra trong *_TABLES: xuất hiện
SELECT TABLE_NAME FROM USER_TABLES WHERE TABLE_NAME = 'TEST_DEFERRED';
-- Kết quả: TEST_DEFERRED

-- Kiểm tra trong *_SEGMENTS: KHÔNG xuất hiện
SELECT SEGMENT_NAME FROM USER_SEGMENTS WHERE SEGMENT_NAME = 'TEST_DEFERRED';
-- Kết quả: không có dòng nào

-- Insert row đầu tiên
INSERT INTO test_deferred VALUES (1, 'Alice');
COMMIT;

-- Kiểm tra lại *_SEGMENTS: bây giờ xuất hiện!
SELECT SEGMENT_NAME FROM USER_SEGMENTS WHERE SEGMENT_NAME = 'TEST_DEFERRED';
-- Kết quả: TEST_DEFERRED
```

---

## 5. Materialize Deferred Segments (Cụ thể hóa Segment)

Trong một số trường hợp, bạn cần **tạo segment ngay** cho các bảng đang dùng Deferred Segment Creation mà chưa có dữ liệu (ví dụ: chuẩn bị cho data migration hoặc kiểm tra phân bổ không gian).

Dùng thủ tục `DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS`:

```sql
-- Materialize tất cả segments trong schema SOE
BEGIN
  DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS(
    SCHEMA_NAME => 'SOE');
END;
/

-- Materialize chỉ bảng ORDERS trong schema SOE
BEGIN
  DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS(
    SCHEMA_NAME    => 'SOE',
    TABLE_NAME     => 'ORDERS');
END;
/

-- Materialize một partition cụ thể
BEGIN
  DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS(
    SCHEMA_NAME    => 'SOE',
    TABLE_NAME     => 'ORDERS',
    PARTITION_NAME => 'ORDERS_Q1');
END;
/
```

---

## 6. Ví dụ thực tế

### Tình huống: Triển khai ứng dụng mới với 500 bảng

```sql
-- Trước Oracle 11g (hoặc khi DEFERRED_SEGMENT_CREATION = FALSE):
-- 500 bảng × 1 MB = 500 MB phân bổ ngay, dù tất cả rỗng

-- Với Deferred Segment Creation (mặc định từ 11g):
CREATE TABLE customers (id NUMBER, name VARCHAR2(100));
CREATE TABLE orders (id NUMBER, cust_id NUMBER, amount NUMBER);
-- ... 498 bảng khác ...
-- → Không tốn không gian đĩa cho đến khi có dữ liệu!

-- Chỉ khi ứng dụng bắt đầu nạp dữ liệu, segment mới được tạo
INSERT INTO customers VALUES (1, 'Nguyen Van A');
-- → Lúc này segment của bảng CUSTOMERS mới được phân bổ
```

---

## Tổng kết

| Khái niệm | Chi tiết |
|-----------|---------|
| Deferred Segment Creation | Segment chỉ được tạo khi có row đầu tiên |
| Tham số | `DEFERRED_SEGMENT_CREATION` = TRUE (mặc định từ 11g) |
| Kiểm soát từng bảng | `SEGMENT CREATION IMMEDIATE / DEFERRED` |
| Kiểm tra trạng thái | Cột `SEGMENT_CREATED` trong `*_TABLES` |
| *_TABLES | Bảng xuất hiện ngay sau CREATE TABLE |
| *_SEGMENTS | Bảng chỉ xuất hiện sau INSERT đầu tiên |
| Materialize | `DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS()` |
| Lợi ích | Tiết kiệm đĩa + giảm thời gian triển khai ứng dụng |


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/43-deferred-segment-creation.md`
