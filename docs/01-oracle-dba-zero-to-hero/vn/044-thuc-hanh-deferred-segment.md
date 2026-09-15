---
title: 'Bài 44: Thực hành - Deferred Segment Creation'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/44-thuc-hanh-deferred-segment.md
---

# Bài 44: Thực hành - Deferred Segment Creation

## Mục tiêu thực hành
Khảo sát hành vi Deferred Segment Creation trong Oracle Database:
- So sánh không gian tiêu thụ khi tạo bảng với và không có Deferred Segment Creation
- Xác nhận segment chỉ được tạo sau khi có dữ liệu
- Materialize các segment còn trì hoãn

---

## Điều kiện tiên quyết
Máy ảo `srv1` với **CDB** database đang chạy.

---

## Các bước thực hành

### Bước 1: Kết nối srv1 qua Putty với user oracle

### Bước 2: Tạo script tạo 10 bảng test

```bash
cat > create_tables.sql <<EOL
-- Script tạo TABLE1 đến TABLE10; nếu bảng đã tồn tại thì xóa trước
DECLARE
  T VARCHAR2(10);
  N INTEGER;
BEGIN
  FOR I IN 1..10 LOOP
    T := 'TABLE' || TO_CHAR(I);
    SELECT COUNT(*) INTO N FROM USER_TABLES WHERE TABLE_NAME = T;
    IF N > 0 THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || T || ' PURGE';
    END IF;
    EXECUTE IMMEDIATE 'CREATE TABLE ' || T || ' (PERSON_ID NUMBER, PERSON_NAME VARCHAR2(20))';
  END LOOP;
END;
/
EOL
```

### Bước 3: Kết nối PDB1 với SYSTEM

```sql
sqlplus SYSTEM/ABcd##1234@//srv1/pdb1.localdomain
```

### Bước 4: Kiểm tra trạng thái DEFERRED_SEGMENT_CREATION

```sql
SHOW PARAMETER DEFERRED_SEGMENT_CREATION;
-- Kết quả mong đợi: TRUE (mặc định)
```

---

## Phần 1: Tạo bảng KHI TẮT Deferred Segment Creation

### Bước 5: Kết nối HR, tắt Deferred Segment Creation ở cấp session

```sql
conn hr/ABcd##1234@//srv1/pdb1.localdomain

ALTER SESSION SET DEFERRED_SEGMENT_CREATION = FALSE;
```

### Bước 6: Chạy script tạo 10 bảng rỗng

```sql
@ create_tables.sql
```

### Bước 7: Xác nhận bảng đã được tạo

```sql
SELECT COUNT(*) FROM USER_TABLES WHERE TABLE_NAME LIKE 'TABLE%';
-- Kết quả mong đợi: 10
```

### Bước 8: Kiểm tra không gian bị tiêu thụ

```sql
SELECT SUM(BYTES/1024) KB FROM USER_SEGMENTS WHERE SEGMENT_NAME LIKE 'TABLE%';
-- Kết quả mong đợi: 640 KB (10 bảng × 64 KB/bảng)
```

### Bước 9: Kiểm tra số extent của một bảng

```sql
SELECT EXTENT_ID, BYTES/1024 "SIZE(KB)", BLOCKS
FROM USER_EXTENTS
WHERE SEGMENT_NAME = 'TABLE1';
-- Kết quả: 1 extent, 64 KB, 8 blocks
```

> **Kết luận**: Khi DEFERRED_SEGMENT_CREATION = FALSE, mỗi bảng rỗng đã tiêu tốn 64 KB ngay khi tạo. Với 1,000 bảng → lãng phí 64 MB!

---

## Phần 2: Tạo bảng KHI BẬT Deferred Segment Creation

### Bước 10: Bật Deferred Segment Creation và tạo lại 10 bảng

```sql
ALTER SESSION SET DEFERRED_SEGMENT_CREATION = TRUE;

@ create_tables.sql
```

### Bước 11: Xác nhận bảng tồn tại nhưng segment KHÔNG được tạo

```sql
-- Bảng có trong USER_TABLES
SELECT COUNT(*) FROM USER_TABLES WHERE TABLE_NAME LIKE 'TABLE%';
-- Kết quả: 10

-- Nhưng KHÔNG có segment nào
SELECT SUM(BYTES/1024) KB FROM USER_SEGMENTS WHERE SEGMENT_NAME LIKE 'TABLE%';
-- Kết quả: (null) hoặc 0 → KHÔNG tiêu tốn không gian!
```

> **Kết luận**: 10 bảng rỗng KHÔNG tiêu tốn bất kỳ không gian đĩa nào.

### Bước 12: INSERT row đầu tiên vào TABLE1

```sql
INSERT INTO TABLE1 VALUES (1, 'PERSON1');
COMMIT;
```

### Bước 13: Xác nhận segment được tạo CHỈ cho TABLE1

```sql
SELECT SUM(BYTES/1024) KB FROM USER_SEGMENTS WHERE SEGMENT_NAME = 'TABLE1';
-- Kết quả: 64 KB → Segment vừa được tạo sau INSERT đầu tiên

-- Các bảng khác vẫn chưa có segment
SELECT COUNT(*) FROM USER_SEGMENTS WHERE SEGMENT_NAME LIKE 'TABLE%';
-- Kết quả: 1 (chỉ TABLE1)
```

---

## Phần 3: Materialize tất cả Deferred Segments

### Bước 14: Kết nối với SYS và materialize toàn bộ schema HR

```sql
conn sys/ABcd##1234@//srv1/pdb1.localdomain as sysdba

-- Materialize tất cả segment còn trì hoãn trong schema HR
EXEC DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS(SCHEMA_NAME => 'HR');
```

> **Lưu ý**: HR không có quyền thực thi `DBMS_SPACE_ADMIN` nên phải dùng SYS.

### Bước 15: Xác nhận tất cả segment đã được tạo

```sql
conn HR/ABcd##1234@//srv1/pdb1.localdomain

SELECT COUNT(*) CNT, SUM(BYTES/1024) KB
FROM USER_SEGMENTS
WHERE SEGMENT_NAME LIKE 'TABLE%';
-- Kết quả mong đợi: CNT=10, KB=640 KB
```

---

## Dọn dẹp

### Bước 16: Xóa các bảng test

```sql
-- Kết nối HR
DECLARE
  T VARCHAR2(10);
  N INTEGER;
BEGIN
  FOR I IN 1..10 LOOP
    T := 'TABLE' || TO_CHAR(I);
    SELECT COUNT(*) INTO N FROM USER_TABLES WHERE TABLE_NAME = T;
    IF N > 0 THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || T || ' PURGE';
    END IF;
  END LOOP;
END;
/
```

### Bước 17: Xóa script file

```sql
host rm create_tables.sql
```

---

## Tổng kết

| Trạng thái | USER_TABLES | USER_SEGMENTS | Không gian |
|-----------|------------|--------------|-----------|
| Tạo bảng, DEFERRED=FALSE | ✅ Có | ✅ Có ngay | Tiêu tốn ngay |
| Tạo bảng, DEFERRED=TRUE | ✅ Có | ❌ Chưa có | Không tốn |
| INSERT row đầu tiên | ✅ Có | ✅ Có (tự động) | Bắt đầu tiêu tốn |
| Sau MATERIALIZE | ✅ Có | ✅ Có (tất cả) | Tiêu tốn |

> **Ghi nhớ**: Materialization tạo extent cho segment mà **không cần insert data** — hữu ích khi cần kiểm soát việc phân bổ không gian trước khi ứng dụng đi vào hoạt động.

---

## Câu hỏi ôn tập

**Câu 1**: Deferred Segment Creation được bật mặc định bởi tham số nào?

> **Trả lời**: `DEFERRED_SEGMENT_CREATION = TRUE` (mặc định từ Oracle 11g R2).

**Câu 2**: Sau khi tạo bảng với Deferred Segment Creation bật, bảng có xuất hiện trong `USER_SEGMENTS` không?

> **Trả lời**: **Không**. Bảng chỉ xuất hiện trong `USER_TABLES` (metadata), nhưng chưa có trong `USER_SEGMENTS`. Segment chỉ được tạo khi có **row đầu tiên được INSERT**.

**Câu 3**: Lệnh nào dùng để cụ thể hóa (materialize) tất cả deferred segments của schema `HR`?

> **Trả lời**:
> ```sql
> EXEC DBMS_SPACE_ADMIN.MATERIALIZE_DEFERRED_SEGMENTS(SCHEMA_NAME => 'HR');
> ```

**Câu 4**: Cột `SEGMENT_CREATED` trong `USER_TABLES` có giá trị gì khi bảng chưa được tạo segment?

> **Trả lời**: `NO`. Khi segment đã tồn tại (có dữ liệu hoặc đã materialize), giá trị là `YES`.

**Câu 5**: Tại sao không nên dùng HR để chạy lệnh MATERIALIZE_DEFERRED_SEGMENTS?

> **Trả lời**: Vì HR không có quyền `EXECUTE` trên package `DBMS_SPACE_ADMIN`. Cần dùng `SYS` hoặc user được cấp quyền tương ứng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/44-thuc-hanh-deferred-segment.md`
