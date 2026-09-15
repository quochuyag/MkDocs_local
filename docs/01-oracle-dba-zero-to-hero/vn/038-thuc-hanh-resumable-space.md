---
title: 'Bài 38: Thực hành - Quản lý Resumable Space Allocation'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/38-thuc-hanh-resumable-space.md
---

# Bài 38: Thực hành - Quản lý Resumable Space Allocation

## Mục tiêu thực hành
Triển khai các bước liên quan đến quản lý resumable space allocation:
- Kiểm tra và cấp quyền `RESUMABLE`
- Mô phỏng lỗi hết không gian
- Kích hoạt resumable và quan sát session bị tạm dừng
- Giải quyết vấn đề để statement tiếp tục

---

## Điều kiện tiên quyết
Máy ảo `srv1` với CDB database đang chạy.

---

## Các bước thực hành

### Bước 1: Kết nối srv1

```bash
# Kết nối qua Putty với user oracle
```

### Bước 2: Kiểm tra quyền RESUMABLE của HR

```sql
-- Kết nối PDB1 với SYSTEM
sqlplus system/ABcd##1234@//srv1/pdb1.localdomain

-- Kiểm tra quyền RESUMABLE
SELECT 'Yes' FROM DBA_SYS_PRIVS
WHERE GRANTEE='HR' AND PRIVILEGE='RESUMABLE';
```

> **Kết quả**: Không có dòng nào → HR chưa có quyền RESUMABLE.

### Bước 3: Cấp quyền RESUMABLE cho HR

```sql
GRANT RESUMABLE TO HR;

-- Xác nhận lại:
SELECT 'Yes' FROM DBA_SYS_PRIVS
WHERE GRANTEE='HR' AND PRIVILEGE='RESUMABLE';
```

### Bước 4: Kiểm tra tham số RESUMABLE_TIMEOUT

```sql
SHOW PARAMETER RESUMABLE_TIMEOUT
```

> **Kết quả**: Giá trị = `0` → Resumable bị tắt theo mặc định. Ta sẽ để nguyên ở cấp system và để user tự bật ở cấp session.

### Bước 5: Tạo tablespace nhỏ, không tự mở rộng

```sql
-- Tablespace chỉ 10M, không AUTOEXTEND
CREATE TABLESPACE RS DATAFILE SIZE 10M AUTOEXTEND OFF;

-- Cấp quota cho HR
ALTER USER HR QUOTA UNLIMITED ON RS;
```

### Bước 6: Thử nạp dữ liệu KHÔNG có resumable → Lỗi ngay

```sql
-- Đăng nhập với HR
CONN HR/ABcd##1234@//srv1/pdb1.localdomain

-- Tạo bảng trong tablespace RS
CREATE TABLE TEST(A CHAR(250)) TABLESPACE RS;

-- Thử nạp 100,000 records vào tablespace chỉ 10M
BEGIN
  FOR I IN 1..100000 LOOP
    INSERT INTO TEST (A) VALUES (DBMS_RANDOM.STRING('U',250));
    IF MOD(I,100) = 0 THEN
      COMMIT;
    END IF;
  END LOOP;
  COMMIT;
END;
/
```

> **Lỗi dự kiến**:
> ```
> ORA-01653: unable to extend table SOE.TEST by xxx in tablespace RS
> ```

### Bước 7: Kích hoạt resumable với timeout 8000 giây

```sql
ALTER SESSION ENABLE RESUMABLE TIMEOUT 8000;
```

### Bước 8: Chạy lại code nạp dữ liệu → Statement bị tạm dừng

```sql
BEGIN
  FOR I IN 1..100000 LOOP
    INSERT INTO TEST (A) VALUES (DBMS_RANDOM.STRING('U',250));
    IF MOD(I,100) = 0 THEN
      COMMIT;
    END IF;
  END LOOP;
  COMMIT;
END;
/
```

> **Quan sát**: Code bị **treo/hang** — không trả lỗi, không hoàn thành.  
> Đây là dấu hiệu statement đang bị **suspended**.  
> Trong thực tế, DBA sẽ nhận được thông báo qua email/SMS từ AFTER SUSPEND trigger.

### Bước 9: Mở SQL Developer, kết nối PDB1 với SYSTEM

Đây là session DBA dùng để kiểm tra và giải quyết vấn đề.

### Bước 10: Xem thông tin statement bị tạm dừng

```sql
-- Trong SQL Developer (kết nối SYSTEM)
SELECT * FROM DBA_RESUMABLE;
```

> Quan sát các cột: `STATUS`, `ERROR_NUMBER`, `ERROR_MSG`, `SUSPEND_TIME`, `RESUME_TIME`

### Bước 11: Giải quyết vấn đề - Thêm datafile vào tablespace

```sql
-- Thêm datafile 100M với AUTOEXTEND
ALTER TABLESPACE RS
  ADD DATAFILE SIZE 100M AUTOEXTEND ON NEXT 100M MAXSIZE 1G;
```

### Bước 12: Theo dõi tiến trình tiếp tục

```sql
-- Quay lại SQL*Plus session và quan sát
-- Statement sẽ tự tiếp tục thực thi

-- Có thể theo dõi tiến trình:
SELECT * FROM DBA_RESUMABLE;
```

> Chờ cho đến khi code hoàn thành.

---

## Dọn dẹp

### Bước 13: Xóa bảng test

```sql
DROP TABLE TEST PURGE;
EXIT;
```

### Bước 14: Xóa tablespace test (trong SQL Developer)

```sql
DROP TABLESPACE RS INCLUDING CONTENTS AND DATAFILES;
```

### Bước 15: Shutdown và restore snapshot

```
15. Shutdown srv1
16. Trong Oracle VirtualBox, khôi phục srv1 từ snapshot CDB
```

---

## Tổng kết

| Bài học | Điểm chính |
|---------|-----------|
| Không có resumable | Lỗi xảy ra ngay khi hết không gian → statement bị hủy |
| Có resumable | Statement bị tạm dừng (hang) → DBA thêm space → Statement tự tiếp tục |
| Yêu cầu | User cần quyền `RESUMABLE` + `ALTER SESSION ENABLE RESUMABLE TIMEOUT <n>` |
| Giám sát | Dùng `DBA_RESUMABLE` và `V$SESSION_WAIT` để theo dõi |


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/38-thuc-hanh-resumable-space.md`
