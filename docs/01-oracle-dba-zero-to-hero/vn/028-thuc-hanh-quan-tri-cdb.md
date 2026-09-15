---
title: 'Bài 28: Thực hành - Quản trị CDB Cơ bản'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/28-thuc-hanh-quan-tri-cdb.md
---

# Bài 28: Thực hành - Quản trị CDB Cơ bản

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- Thay đổi trạng thái CDB và PDB theo nhiều cách khác nhau.
- Cấu hình PDB tự động mở khi CDB restart (SAVE STATE).
- Thực hành thay đổi tham số tại cấp PDB và CDB.
- Đổi tên (Global Database Name) của một PDB.

---

## Điều kiện tiên quyết
Máy ảo `srv1` với CDB database đang chạy.

---

## Phần A: Thay đổi trạng thái PDB từ CDB$ROOT

### Bước 1-2: Kết nối và kiểm tra container

```bash
sqlplus / as sysdba
```

```sql
-- Xác nhận đang ở ROOT (CON_ID = 1, CON_NAME = CDB$ROOT)
SHOW CON_ID CON_NAME
```

### Bước 3-4: Kiểm tra và tắt PDB1

```sql
-- Kiểm tra trạng thái PDB1
SELECT OPEN_MODE FROM V$PDBS WHERE NAME = 'PDB1';

-- Tắt PDB1 (IMMEDIATE = không chờ transactions hoàn tất)
ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE;
```

### Bước 5: Xác nhận PDB1 đã đóng

```sql
-- MOUNTED = đã đóng (trong ngữ cảnh PDB)
SELECT OPEN_MODE FROM V$PDBS WHERE NAME = 'PDB1';
-- Kết quả: MOUNTED
```

### Bước 6: Mở lại PDB1

```sql
-- Cách 1: Dùng ALTER PLUGGABLE DATABASE (SQL statement)
ALTER PLUGGABLE DATABASE pdb1 OPEN;

-- Cách 2: Dùng STARTUP (SQL*Plus command)
-- STARTUP PLUGGABLE DATABASE pdb1
```

> 💡 **Tốc độ:** Mở/tắt PDB **nhanh hơn rất nhiều** so với mở/tắt toàn CDB vì chỉ cần xử lý các file của PDB đó.

---

## Phần B: Thay đổi trạng thái tất cả PDB

### Bước 7-9: Đóng và mở tất cả PDB

```sql
-- Đóng tất cả PDB trong một lệnh
ALTER PLUGGABLE DATABASE ALL CLOSE;

-- Kiểm tra - PDB$SEED không bị ảnh hưởng (luôn READ ONLY)
col name format a10
SELECT NAME, OPEN_MODE FROM V$PDBS ORDER BY 1;

-- Mở lại tất cả PDB
ALTER PLUGGABLE DATABASE ALL OPEN;
```

---

## Phần C: Tắt và Khởi động toàn bộ CDB

### Bước 10-12: Restart CDB và quan sát PDB

```sql
-- Tắt toàn CDB (khi đang ở ROOT)
SHUTDOWN IMMEDIATE

-- Khởi động lại CDB
STARTUP

-- Kiểm tra trạng thái PDB sau khi CDB restart
SELECT NAME, OPEN_MODE FROM V$PDBS ORDER BY 1;
-- Quan sát: Tất cả PDB đang MOUNTED (đóng) - đây là hành vi mặc định!
```

> 💡 **Hành vi mặc định:** Khi CDB restart, PDB không tự mở. DBA phải mở thủ công.

---

## Phần D: Lưu trạng thái PDB (SAVE STATE)

### Bước 13-16: Cấu hình tự động mở

```sql
-- Mở tất cả PDB
ALTER PLUGGABLE DATABASE ALL OPEN;

-- Lưu trạng thái hiện tại (OPEN) để tự động khôi phục sau restart
ALTER PLUGGABLE DATABASE ALL SAVE STATE;

-- Kiểm tra trạng thái đã lưu
col con_name format a10
SELECT CON_NAME, STATE FROM CDB_PDB_SAVED_STATES;
-- Kết quả: PDB1 → OPEN

-- Test: Restart CDB và kiểm tra
SHUTDOWN IMMEDIATE
STARTUP OPEN

SELECT NAME, OPEN_MODE FROM V$PDBS ORDER BY 1;
-- Kết quả: PDB1 bây giờ đã tự động READ WRITE!
```

---

## Phần E: Thay đổi trạng thái PDB khi đang ở trong PDB đó

### Bước 17-20: Chuyển vào PDB và quản lý

```sql
-- Chuyển session vào PDB1
ALTER SESSION SET CONTAINER = PDB1;

-- Xác nhận đang ở PDB1
SHOW CON_ID CON_NAME

-- Tắt và bật PDB hiện tại
SHUTDOWN IMMEDIATE
STARTUP OPEN

-- Quay về ROOT
ALTER SESSION SET CONTAINER = CDB$ROOT;
```

> ⚠️ **Cảnh báo quan trọng:** Nếu nhầm đang ở ROOT mà gõ `SHUTDOWN`, sẽ tắt **toàn bộ CDB**. Hãy luôn kiểm tra `SHOW CON_ID CON_NAME` trước khi dùng `SHUTDOWN`.

---

## Phần F: Tham số không thể thay đổi ở PDB

### Bước 21-25: Thực hành với tham số non-PDB-modifiable

```sql
-- Kiểm tra DB_RECOVERY_FILE_DEST_SIZE (không thể sửa ở PDB)
col value format a15

SELECT VALUE, VALUE/1024/1024/1024 GB, ISPDB_MODIFIABLE
FROM   V$SYSTEM_PARAMETER
WHERE  NAME = 'db_recovery_file_dest_size';
-- ISPDB_MODIFIABLE = FALSE

-- Chuyển vào PDB1 và thử thay đổi
ALTER SESSION SET CONTAINER = PDB1;

SELECT VALUE FROM V$SYSTEM_PARAMETER WHERE NAME = 'db_recovery_file_dest_size';

-- Thử thay đổi - sẽ bị lỗi!
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 10903094248;
-- ORA-65040: operation not allowed from within a pluggable database
```

```sql
-- Quay về ROOT và thay đổi thành công
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 10903094248 SCOPE = BOTH;

-- Vào PDB1 lại - thấy giá trị mới (kế thừa từ CDB)
ALTER SESSION SET CONTAINER = PDB1;
SELECT VALUE, VALUE/1024/1024/1024 GB 
FROM V$SYSTEM_PARAMETER 
WHERE NAME = 'db_recovery_file_dest_size';

-- Trở về ROOT
ALTER SESSION SET CONTAINER = CDB$ROOT;
```

---

## Phần G: Tham số có thể thay đổi ở PDB

### Bước 26-28: Thực hành với tham số PDB-modifiable

```sql
-- Kiểm tra DDL_LOCK_TIMEOUT (có thể sửa ở PDB)
col VALUE for a10
SELECT VALUE, ISPDB_MODIFIABLE
FROM V$SYSTEM_PARAMETER
WHERE NAME = 'ddl_lock_timeout';
-- ISPDB_MODIFIABLE = TRUE

-- Thay đổi trong PDB1
ALTER SESSION SET CONTAINER = PDB1;
ALTER SYSTEM SET DDL_LOCK_TIMEOUT = 12;
-- Thành công!

-- Về ROOT - xem giá trị theo từng container
ALTER SESSION SET CONTAINER = CDB$ROOT;
col name format a20

SELECT CON_ID, NAME, VALUE
FROM V$SYSTEM_PARAMETER
WHERE NAME = 'ddl_lock_timeout';
```

**Kết quả dự kiến:**

| CON_ID | NAME | VALUE |
|--------|------|-------|
| 0 | ddl_lock_timeout | 0 (mặc định CDB) |
| 3 | ddl_lock_timeout | 12 (đã sửa cho PDB1) |

> 💡 `CON_ID = 0` nghĩa là giá trị áp dụng ở cấp CDB (không gắn với PDB cụ thể nào).

---

## Phần H: Đổi tên PDB

### Bước 29-33: Tạo PDB mới, đổi tên, rồi xóa

```sql
-- Tạo PDB test
CREATE PLUGGABLE DATABASE pdb_test
  ADMIN USER pdbtestadmin IDENTIFIED BY ABcd##1234;

ALTER PLUGGABLE DATABASE pdb_test OPEN;

-- Đóng và mở ở chế độ RESTRICTED để đổi tên
ALTER PLUGGABLE DATABASE pdb_test CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb_test OPEN RESTRICTED;

-- Xác nhận RESTRICTED = YES
SELECT CON_ID, OPEN_MODE, RESTRICTED FROM V$PDBS WHERE NAME = 'PDB_TEST';

-- Chuyển vào PDB_TEST để đổi tên
ALTER SESSION SET CONTAINER = PDB_TEST;
ALTER PLUGGABLE DATABASE pdb_test RENAME GLOBAL_NAME TO pdb2;

-- Đóng và mở lại bình thường
ALTER PLUGGABLE DATABASE pdb2 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb2 OPEN;

-- Xác nhận đã đổi tên thành công
SELECT CON_ID, OPEN_MODE, RESTRICTED FROM V$PDBS WHERE NAME = 'PDB2';

-- Test kết nối
conn system/ABcd##1234@//srv1:1521/pdb2.localdomain
conn / as sysdba

-- Dọn dẹp: Xóa PDB2
ALTER PLUGGABLE DATABASE pdb2 CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE pdb2 INCLUDING DATAFILES;

-- Kiểm tra chỉ còn PDB1
col name format a10
SELECT NAME, CON_ID, OPEN_MODE, RESTRICTED FROM V$PDBS ORDER BY 1;
```

---

## Tóm tắt bài thực hành

| Tình huống | Hành vi |
|------------|---------|
| CDB restart (không SAVE STATE) | PDB ở trạng thái **MOUNTED** (đóng) |
| CDB restart (có SAVE STATE = OPEN) | PDB tự động **READ WRITE** |
| `SHUTDOWN` khi ở ROOT | Tắt **toàn bộ CDB** |
| `SHUTDOWN` khi ở PDB | Chỉ tắt **PDB đó** |
| Tham số `ISPDB_MODIFIABLE=FALSE` | Chỉ sửa được từ **CDB$ROOT** |
| Tham số `ISPDB_MODIFIABLE=TRUE` | Có thể sửa **từ PDB** |

---

## Câu hỏi ôn tập

**1. Sau khi chạy `ALTER PLUGGABLE DATABASE ALL SAVE STATE`, bạn cần làm gì thêm để PDB tự động mở sau restart?**
> **Trả lời:**
> Bạn **không cần làm gì thêm nữa**. Lệnh này đã ghi nhận trạng thái của các PDB vào Data Dictionary của CDB. Khi bạn restart CDB (bằng `SHUTDOWN IMMEDIATE` rồi `STARTUP`), tiến trình nền của Oracle sẽ tự động đọc bảng `PDB_SAVED_STATES$` và kích hoạt mở tất cả các PDB lên chế độ đã lưu một cách hoàn toàn tự động.

**2. Nếu bạn đang ở PDB1 và muốn restart toàn bộ CDB, bạn phải làm gì trước?**
> **Trả lời:**
> Bạn **bắt buộc phải chuyển phiên làm việc về Root Container (`CDB$ROOT`)** trước bằng lệnh:
> ```sql
> ALTER SESSION SET CONTAINER = CDB$ROOT;
> ```
> Hoặc thoát ra và kết nối lại bằng tài khoản SYS ở Root: `CONNECT / as sysdba`.
> Sau đó mới có thể thực hiện lệnh `SHUTDOWN IMMEDIATE;` và `STARTUP;` để khởi động lại toàn bộ CDB Instance. (Nếu bạn gõ `SHUTDOWN` khi đang ở PDB1, bạn chỉ đóng duy nhất PDB1 chứ không thể restart được máy chủ hay CDB).

**3. `CDB_PDB_SAVED_STATES` khác `DBA_PDB_SAVED_STATES` như thế nào?**
> **Trả lời:**
> - `DBA_PDB_SAVED_STATES`: Hiển thị thông tin trạng thái đã lưu của các PDB thuộc phạm vi container hiện tại.
> - `CDB_PDB_SAVED_STATES`: Hiển thị trạng thái đã lưu của tất cả các PDB trên toàn bộ CDB, có thêm cột `CON_ID` để định danh container tương ứng. Về mặt thực tế, do tính năng SAVE STATE được quản lý tập trung từ Root, hai view này khi truy vấn từ `CDB$ROOT` đều cho thông tin tương đồng về danh sách các PDB đã được lưu trạng thái mở.

**4. Tại sao khi đổi tên PDB, PDB phải được mở ở chế độ RESTRICTED thay vì READ WRITE?**
> **Trả lời:**
> - Đổi tên PDB làm thay đổi tên Service Name toàn cục mà Listener mạng quản lý, đồng thời cập nhật lại các bản ghi định danh trong Data Dictionary.
> - Nếu mở ở chế độ `READ WRITE` thông thường, các kết nối ứng dụng từ bên ngoài có thể gửi câu lệnh DML, tạo transaction dở dang hoặc lock các đối tượng hệ thống, gây xung đột và làm hỏng tính toàn vẹn của tiến trình đổi tên PDB. Chế độ `RESTRICTED` đảm bảo chỉ có phiên làm việc độc quyền của DBA mới được phép tác động vào PDB trong quá trình đổi tên.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/28-thuc-hanh-quan-tri-cdb.md`
