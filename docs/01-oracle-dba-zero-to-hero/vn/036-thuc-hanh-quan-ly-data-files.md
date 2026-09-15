---
title: 'Bài 36: Thực hành - Quản lý Data Files'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/36-thuc-hanh-quan-ly-data-files.md
---

# Bài 36: Thực hành - Quản lý Data Files

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- **Di chuyển datafile online** từ vị trí này sang vị trí khác
- **Di chuyển datafile offline** và đưa lại online
- **Xử lý** tình huống datafile bị mất trong PDB

---

## Điều kiện tiên quyết
Máy ảo `srv1` với CDB database đang chạy.

---

## Phần 1: Di chuyển Data File khi đang Online

### Bước 1: Kết nối admin session

```sql
-- Kết nối srv1 qua Putty với user oracle
sqlplus / as sysdba
set sqlprompt "admin> "
```

### Bước 2: Tạo tablespace MYTBS trong PDB1

```sql
ALTER SESSION SET CONTAINER=PDB1;

CREATE TABLESPACE MYTBS
  DATAFILE '/home/oracle/mytbs1.dbf' SIZE 150M AUTOEXTEND OFF;

ALTER USER HR QUOTA UNLIMITED ON MYTBS;
GRANT EXECUTE ON DBMS_LOCK TO HR;
```

### Bước 3: Kết nối client session

Mở Putty session thứ 2, đổi màu chữ thành xanh lá để phân biệt:

```bash
sqlplus HR/ABcd##1234@//srv1/pdb1.localdomain
set sqlprompt "client> "
```

### Bước 4: Tạo bảng test và liên tục cập nhật dữ liệu

```sql
-- Tạo bảng trong tablespace MYTBS
CREATE TABLE HR.TEST(RID NUMBER, RNAME CHAR(250)) TABLESPACE MYTBS;

-- Insert dữ liệu ngẫu nhiên
BEGIN
  FOR I IN 1..10000 LOOP
    INSERT INTO TEST (RID, RNAME) VALUES (I, DBMS_RANDOM.STRING('U',250));
    IF MOD(I,100) = 0 THEN
      COMMIT;
    END IF;
  END LOOP;
  COMMIT;
END;
/

-- Liên tục cập nhật dữ liệu (vô hạn - không cần chờ kết thúc)
DECLARE
  N INTEGER := 0;
BEGIN
  WHILE (TRUE) LOOP
    UPDATE TEST SET RNAME = DBMS_RANDOM.STRING('U',250)
    WHERE RID = ROUND(DBMS_RANDOM.VALUE(1,10000));
    N := N + 1;
    IF N = 10 THEN
      DBMS_LOCK.SLEEP(0.25);
      COMMIT;
      N := 1;
    END IF;
  END LOOP;
END;
/
```

> **Lưu ý**: Đừng chờ block này kết thúc, chuyển sang bước tiếp theo ngay.

### Bước 5: Di chuyển datafile online (trong admin session)

```sql
-- Di chuyển datafile trong khi client session vẫn đang cập nhật
ALTER DATABASE MOVE DATAFILE '/home/oracle/mytbs1.dbf'
  TO '/home/oracle/mytbs2.dbf';
```

> **Quan sát**: Lệnh thành công dù client session đang liên tục ghi vào datafile!

### Bước 6: Kiểm tra kết quả

```bash
-- File cũ phải không còn tồn tại
host ls -al /home/oracle/mytbs1.dbf

-- File mới phải tồn tại
host ls -al /home/oracle/mytbs2.dbf
```

### Bước 7: Dừng client session

Trong client session, nhấn `[Ctrl]+[c]` để hủy.

---

## Phần 2: Di chuyển Data File khi Offline

### Bước 8: Thử đưa datafile về offline

```sql
-- Trong admin session
ALTER DATABASE DATAFILE '/home/oracle/mytbs2.dbf' OFFLINE;
```

> **Lỗi dự kiến**: `ORA-01145: offline immediate disallowed unless media recovery enabled`
> 
> → Cần bật **ARCHIVELOG mode** trước.

### Bước 9: Bật ARCHIVELOG mode

```sql
ALTER SESSION SET CONTAINER=CDB$ROOT;

ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST'
  SCOPE=SPFILE;

SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE PDB1 OPEN;
```

### Bước 10: Đưa datafile về offline

```sql
ALTER SESSION SET CONTAINER=PDB1;
ALTER DATABASE DATAFILE '/home/oracle/mytbs2.dbf' OFFLINE;
```

### Bước 11: Kết nối lại client session

```sql
CONN HR/ABcd##1234@//srv1/pdb1.localdomain
```

### Bước 12: Thử chạy lại - sẽ thất bại

```sql
/
```

> **Lỗi dự kiến**:
> ```
> ORA-00376: file xx cannot be read at this time
> ORA-01110: data file 25: '/home/oracle/mytbs2.dbf'
> ```

### Bước 13: Copy datafile sang vị trí mới (bằng OS)

```bash
host cp /home/oracle/mytbs2.dbf /home/oracle/mytbs1.dbf
```

### Bước 14: Cập nhật đường dẫn trong database dictionary

```sql
-- Chạy MỘT trong hai lệnh sau:

ALTER TABLESPACE mytbs RENAME DATAFILE '/home/oracle/mytbs2.dbf'
  TO '/home/oracle/mytbs1.dbf';

-- hoặc:
ALTER DATABASE RENAME FILE '/home/oracle/mytbs2.dbf'
  TO '/home/oracle/mytbs1.dbf';
```

### Bước 15: Thử đưa datafile về online - sẽ thất bại

```sql
ALTER DATABASE DATAFILE '/home/oracle/mytbs1.dbf' ONLINE;
```

> **Lỗi dự kiến**: `ORA-01113: file xx needs media recovery`
> 
> → Cần áp dụng redo logs để đồng bộ datafile.

### Bước 16: Áp dụng redo logs và đưa online

```sql
RECOVER DATAFILE '/home/oracle/mytbs1.dbf';
ALTER DATABASE DATAFILE '/home/oracle/mytbs1.dbf' ONLINE;
```

### Bước 17: Kiểm tra client session

```sql
-- Trong client session - chạy lại block, phải thành công
/
```

### Bước 18: Dừng client session

Nhấn `[Ctrl]+[c]`.

---

## Phần 3: Xử lý Data File bị mất trong PDB

> **⚠️ Kịch bản thực tế**: Trong thực tế, nếu datafile bị mất, phải restore từ backup. Ở đây ta giả định không có backup và chấp nhận mất toàn bộ PDB.

### Bước 19: Xóa datafile bằng OS command

```bash
host rm /home/oracle/mytbs1.dbf
```

### Bước 20: Chạy lại client update

```sql
-- Trong client session
/
```

> **Lưu ý**: Có thể vẫn chạy được vì data blocks đang ở trong memory.

### Bước 21: Ép buộc checkpoint để database ghi ra đĩa

```sql
-- Trong admin session
ALTER SYSTEM CHECKPOINT;
```

> → Kết nối bị ngắt ở tất cả sessions.

### Bước 22: Kiểm tra trạng thái PDB1

```sql
-- Kết nối lại
CONN / AS SYSDBA
CONN / AS SYSDBA

SELECT OPEN_MODE, RESTRICTED FROM V$PDBS WHERE NAME='PDB1';
```

> **Kết quả**: `MOUNTED` → PDB1 không thể mở được!

**Câu hỏi**: Các PDB khác có bị ảnh hưởng không?  
**Trả lời**: Không! Các PDB khác vẫn hoạt động bình thường. Tuy nhiên, khi cần restart CDB, sẽ có vấn đề vì datafiles không nhất quán. Phải xử lý: hoặc restore hoặc drop PDB.

### Bước 23: Thử mở PDB1 - sẽ thất bại

```sql
ALTER PLUGGABLE DATABASE PDB1 OPEN;
```

> **Lỗi**: Không thể mở vì datafile không có.

### Bước 24: Kiểm tra status từ CDB_DATA_FILES - không xem được

```sql
SELECT STATUS FROM CDB_DATA_FILES
WHERE FILE_NAME='/home/oracle/mytbs1.dbf';
```

> → Không có kết quả vì PDB đang down.

### Bước 25: Kiểm tra từ V$DATAFILE

```sql
SELECT STATUS FROM V$DATAFILE
WHERE NAME='/home/oracle/mytbs1.dbf';
```

> **Kết quả**: `ONLINE` — file bị xóa trên OS nhưng database chưa cập nhật status.

### Bước 26: Xóa PDB1 cùng tất cả datafiles

```sql
DROP PLUGGABLE DATABASE PDB1 INCLUDING DATAFILES;
```

---

## Dọn dẹp

```
27. Shutdown srv1.
28. Trong Oracle VirtualBox, khôi phục srv1 từ snapshot CDB.
```

---

## Tổng kết

| Bài học | Điểm chính |
|---------|-----------|
| Di chuyển online | Datafile có thể di chuyển trong khi users vẫn truy cập |
| Di chuyển offline | Cần ARCHIVELOG mode + RECOVER sau khi đưa lại online |
| Datafile bị mất | Nếu không có backup → phải DROP toàn bộ PDB |


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/36-thuc-hanh-quan-ly-data-files.md`
