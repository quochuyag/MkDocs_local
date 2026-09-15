---
title: 'Bài 42: Thực hành - Thu nhỏ Segments'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/42-thuc-hanh-thu-nho-segments.md
---

# Bài 42: Thực hành - Thu nhỏ Segments

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- Tạo bảng test và tạo phân mảnh
- Đo thống kê không gian trước và sau khi shrink
- Thực hiện shrink bảng và cascade sang indexes
- So sánh hiệu quả giữa shrink và rebuild index

---

## Điều kiện tiên quyết
- Máy ảo `srv1` với **CDB** database đang chạy.

---

## Các bước thực hành

### Bước 1: Kết nối srv1 qua Putty với user oracle

### Bước 2: Tạo script hiển thị thống kê bảng CUST

```bash
cat > display_cust_stats.sql <<EOL
ANALYZE TABLE CUST COMPUTE STATISTICS;

SELECT BLOCKS, BLOCKS*8192/1024 TOTAL_SIZE_KB, NUM_ROWS,
       round(BLOCKS*AVG_SPACE/1024,2) FREE_SPACE_KB
FROM USER_TABLES WHERE TABLE_NAME='CUST';

col INDEX_NAME for a20

ANALYZE INDEX CUST_FNAME_IDX COMPUTE STATISTICS;
ANALYZE INDEX CUST_NO_IDX COMPUTE STATISTICS;

SELECT SEGMENT_NAME INDEX_NAME, BLOCKS
FROM USER_SEGMENTS
WHERE SEGMENT_NAME IN ('CUST_NO_IDX','CUST_FNAME_IDX');

SELECT INDEX_NAME, STATUS, LEAF_BLOCKS, NUM_ROWS
FROM USER_INDEXES
WHERE INDEX_NAME IN ('CUST_NO_IDX','CUST_FNAME_IDX');
EOL
```

### Bước 3: Kết nối PDB1 với SYSTEM

```sql
sqlplus system/ABcd##1234@//srv1/pdb1.localdomain
```

### Bước 4: Xác nhận tablespace USERS dùng ASSM

```sql
SELECT EXTENT_MANAGEMENT, SEGMENT_SPACE_MANAGEMENT
FROM dba_tablespaces
WHERE TABLESPACE_NAME = 'USERS';
```

> **Kết quả mong đợi**:
> - `EXTENT_MANAGEMENT` = `LOCAL`
> - `SEGMENT_SPACE_MANAGEMENT` = `AUTO`
>
> Shrink chỉ hoạt động trên tablespace **Locally Managed** với **ASSM**.

### Bước 5: Tạo bảng CUST và hai indexes (kết nối HR)

```sql
conn hr/ABcd##1234@//srv1/pdb1.localdomain

-- Tạo bảng CUST với PCTFREE 0 (tối ưu chèn dữ liệu)
CREATE TABLE CUST (
  CUSTOMER_NO  NUMBER(6),
  FIRST_NAME   VARCHAR2(20),
  LAST_NAME    VARCHAR2(20),
  NOTE1        VARCHAR2(100),
  NOTE2        VARCHAR2(100)
) PCTFREE 0 TABLESPACE USERS;

-- Nạp 100,000 records
INSERT INTO CUST
  SELECT LEVEL AS CUSTOMER_NO,
         DBMS_RANDOM.STRING('A', 15) FIRST_NAME,
         DBMS_RANDOM.STRING('A', 12) LAST_NAME,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(0,100))) NOTE1,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(0,100))) NOTE2
  FROM DUAL
  CONNECT BY LEVEL <= 100000;

COMMIT;

-- Tạo indexes
CREATE INDEX CUST_NO_IDX ON CUST (CUSTOMER_NO) NOLOGGING TABLESPACE USERS;
CREATE INDEX CUST_FNAME_IDX ON CUST(FIRST_NAME) NOLOGGING TABLESPACE USERS;
```

### Bước 6: Xem thống kê ban đầu — TRƯỚC khi phân mảnh

```sql
@ display_cust_stats.sql
```

> **Quan sát và ghi lại**:
> - Tổng số blocks
> - Kích thước tổng (KB)
> - Free space (KB) — rất nhỏ vì dữ liệu vừa được nạp
> - Số rows trong bảng và index

### Bước 7: Tạo phân mảnh cho bảng CUST

```sql
BEGIN
  FOR I IN 1..100000 LOOP
    IF MOD(I,2) = 0 THEN
      -- UPDATE: thu nhỏ dữ liệu (NOTE1 → NULL, NOTE2 → chuỗi ngắn hơn)
      UPDATE CUST SET NOTE1 = NULL, 
                      NOTE2 = DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(0,10)))
      WHERE CUSTOMER_NO = I;
      
      IF MOD(I,100) = 0 THEN
        COMMIT;
      END IF;
    ELSIF MOD(I,3) = 0 THEN
      -- DELETE: xóa 1/3 số rows
      DELETE CUST WHERE CUSTOMER_NO = I;
    END IF;
  END LOOP;
  COMMIT;
END;
/
```

> **Kết quả**: Khoảng **1/2 bảng** bị UPDATE (thu nhỏ dữ liệu) và **1/3 bảng** bị DELETE.

### Bước 8: Xem thống kê SAU khi phân mảnh

```sql
@ display_cust_stats.sql
```

> **Quan sát**:
> - **Số blocks KHÔNG thay đổi** — HWM không giảm sau UPDATE/DELETE
> - **FREE_SPACE_KB tăng đáng kể** — khoảng 20% không gian là trống
> - Số rows giảm
> - Thống kê index **không thay đổi** (UPDATE/DELETE không ảnh hưởng nhiều đến index size)

### Bước 9: Thực hiện Shrink bảng (và cascade indexes)

```sql
-- Bật row movement (bắt buộc trước khi shrink)
ALTER TABLE CUST ENABLE ROW MOVEMENT;

-- Shrink bảng + cascade sang indexes
ALTER TABLE CUST SHRINK SPACE CASCADE;

-- Tắt row movement (tùy chọn nhưng là best practice)
ALTER TABLE CUST DISABLE ROW MOVEMENT;
```

> **Lưu ý**: Lệnh `ENABLE ROW MOVEMENT` sẽ thất bại nếu có transaction đang lock bảng.

### Bước 10: Xem thống kê SAU khi Shrink

```sql
@ display_cust_stats.sql
```

> **Quan sát so sánh**:

| Thông số | Trước Shrink | Sau Shrink |
|---------|------------|-----------|
| Số blocks | ___ | ___ |
| Total size (KB) | ___ | ___ |
| Free space (KB) | ___ | ___ |
| Số rows | ___ | ___ |

> **Kết quả mong đợi**:
> - Số blocks giảm còn **khoảng 1/2** so với trước shrink
> - Free space giảm xuống rất ít (< 5%)
> - Số rows không đổi
> - Index: tác động không đáng kể từ CASCADE shrink

### Bước 11: Rebuild indexes và so sánh

```sql
-- Rebuild indexes (thường hiệu quả hơn CASCADE shrink cho indexes)
ALTER INDEX CUST_FNAME_IDX REBUILD;
ALTER INDEX CUST_NO_IDX REBUILD;

@ display_cust_stats.sql
```

> **Quan sát**:
> - Sau REBUILD, kích thước index **giảm đáng kể hơn** so với sau CASCADE shrink
> - Đây là lý do Rebuild thường được ưu tiên hơn Shrink cho indexes

---

## Thực hành thêm (Tự nghiên cứu)

### Thử nghiệm Move Table

```sql
-- Tạo lại phân mảnh cho CUST (lặp lại bước 7)
-- Sau đó di chuyển bảng để defragment
ALTER TABLE CUST MOVE TABLESPACE USERS UPDATE INDEXES;

-- Kiểm tra kết quả
@ display_cust_stats.sql
```

> **So sánh** chất lượng defragmentation giữa MOVE và SHRINK.

---

## Dọn dẹp

### Bước 12: Xóa bảng CUST

```sql
DROP TABLE CUST PURGE;
```

### Bước 13: Xóa script file

```sql
host rm display_cust_stats.sql
```

---

## Tổng kết

| Kết luận | Chi tiết |
|---------|---------|
| Shrink table | Giảm số blocks ~50%, free space về mức tối thiểu |
| ENABLE ROW MOVEMENT | Bắt buộc trước khi SHRINK (ROWID của rows sẽ thay đổi) |
| CASCADE | Cho phép shrink indexes đi kèm, nhưng hiệu quả ít hơn REBUILD |
| Rebuild Index | Hiệu quả hơn CASCADE shrink trong việc tiết kiệm không gian index |
| ASSM bắt buộc | Shrink chỉ hoạt động trên tablespace dùng Automatic Segment Space Management |


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/42-thuc-hanh-thu-nho-segments.md`
