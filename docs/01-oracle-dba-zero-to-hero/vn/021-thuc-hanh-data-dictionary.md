---
title: 'Bài 21: Thực hành - Truy vấn Data Dictionary và Dynamic Performance Views'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/21-thuc-hanh-data-dictionary.md
---

# Bài 21: Thực hành - Truy vấn Data Dictionary và Dynamic Performance Views

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- Thực hành truy vấn các **Dynamic Performance Views (V$)** ở các trạng thái khác nhau của Database.
- Khám phá sự khác biệt giữa **USER_**, **ALL_** và **DBA_** views.
- Biết cách kết hợp nhiều view để lấy thông tin đầy đủ.

---

## Điều kiện tiên quyết
Máy chủ `srv1` và Database phải đang chạy.

---

## Phần 1: Thực hành V$ Views theo trạng thái Database

### Bước 1-2: Kết nối và Tắt Database

Mở Putty kết nối đến `srv1` với user `oracle`. Sau đó mở SQL*Plus với quyền SYSDBA:

```bash
sqlplus / as sysdba
```

Tắt database:

```sql
shutdown immediate
```

### Bước 3-4: Khởi động ở chế độ MOUNT

Khởi động database ở chế độ MOUNT (chưa mở file dữ liệu):

```sql
startup mount
```

### Bước 5: Thử truy vấn Data Dictionary (sẽ bị lỗi)

```sql
-- Truy vấn này sẽ thất bại vì Data Dictionary chỉ khả dụng khi DB ở trạng thái OPEN
SELECT NAME FROM DBA_DATAFILES;
```

> 💡 **Giải thích:** Data Dictionary views đọc dữ liệu từ file datafiles (trên ổ cứng). Ở chế độ `MOUNT`, các file datafiles **chưa được mở**, nên không thể truy vấn được.

### Bước 6: Truy vấn V$DATABASE (thành công ở MOUNT)

```sql
-- View này đọc từ Control File (đã được mở ở MOUNT) nên hoạt động
SELECT NAME, OPEN_MODE FROM V$DATABASE;
```

> 💡 **Tại sao được?** `V$DATABASE` đọc từ **Control File** - file này đã được mở ngay từ bước MOUNT.

### Bước 7: Thử V$ROLLNAME (sẽ bị lỗi)

```sql
-- View này cần đọc từ datafiles nên cũng thất bại ở MOUNT
SELECT NAME FROM V$ROLLNAME;
```

> ℹ️ **Lưu ý:** Không phải tất cả V$ views đều có thể truy cập ở MOUNT. Chỉ những view đọc từ **RAM (SGA)** hoặc **Control File** mới hoạt động được.

### Bước 8: Mở Database hoàn toàn

```sql
ALTER DATABASE OPEN;
```

---

## Phần 2: Thực hành với Dynamic Performance Views

### Bước 9: Đăng nhập bằng user SYSTEM

```sql
conn system/ABcd##1234
```

### Bước 10: Xem thông tin session hiện tại

```sql
-- SID: Session ID, SERIAL#: Số serial (dùng để kill session), STATUS: trạng thái
SELECT SID, SERIAL#, STATUS FROM V$SESSION WHERE USERNAME='SYSTEM';
```

---

## Phần 3: So sánh V$TABLESPACE và DBA_TABLESPACES

### Bước 11: Khám phá cấu trúc hai view

```sql
-- Xem cấu trúc V$TABLESPACE (Dynamic Performance View)
DESC V$TABLESPACE

-- Xem cấu trúc DBA_TABLESPACES (Data Dictionary View)
DESC DBA_TABLESPACES
```

| Đặc điểm | V$TABLESPACE | DBA_TABLESPACES |
|-----------|-------------|-----------------|
| Nguồn dữ liệu | SGA (bộ nhớ) | SYSTEM Tablespace |
| Tên (quy ước) | Số ít | Số nhiều |
| Thông tin | Cơ bản (ID, Name) | Chi tiết hơn (Extent management, Logging,...) |

> 💡 **Quy tắc nhớ:** Hầu hết V$ views đặt tên **số ít** (`V$TABLESPACE`), còn Dictionary views đặt tên **số nhiều** (`DBA_TABLESPACES`).

### Bước 12: Kết hợp nhiều view để lấy thông tin đầy đủ

```sql
-- Lấy tên Tablespace và các datafiles của nó
-- Kết hợp V$TABLESPACE (có tên) và V$DATAFILE (có tên file)
SELECT S.NAME TABLESPACE_NAME, D.NAME DATAFILE
FROM V$TABLESPACE S, V$DATAFILE D
WHERE S.TS# = D.TS#   -- TS# là ID tablespace, dùng để JOIN
ORDER BY 1;
```

---

## Phần 4: Phân biệt USER_, ALL_, DBA_ Views

### Bước 13: Xem cấu trúc 3 loại view *_TABLES

```sql
-- DBA_TABLES - Có cột OWNER, dành cho toàn bộ DB
desc DBA_TABLES

-- ALL_TABLES - Có cột OWNER, dành cho những gì user được phép xem
desc ALL_TABLES

-- USER_TABLES - KHÔNG có cột OWNER (vì luôn là của user hiện tại)
desc USER_TABLES
```

### Bước 14: Đếm số bảng ở mỗi mức (kết nối là SYSTEM)

```sql
-- Số bảng chỉ của user SYSTEM
SELECT COUNT(*) FROM USER_TABLES;

-- Số bảng SYSTEM được quyền xem (bao gồm của người khác cấp quyền)
SELECT COUNT(*) FROM ALL_TABLES;

-- Toàn bộ số bảng trong Database (quyền DBA)
SELECT COUNT(*) FROM DBA_TABLES;
```

> ℹ️ **Kết quả dự kiến:** Khi đăng nhập là SYSTEM (user có quyền DBA), `DBA_TABLES` và `ALL_TABLES` thường trả về số hàng bằng nhau vì SYSTEM có quyền xem mọi thứ.

### Bước 15: So sánh khi đăng nhập là HR (user thường)

```sql
conn hr/ABcd##1234

-- HR chỉ sở hữu ít bảng (7 bảng schema HR)
SELECT COUNT(*) FROM USER_TABLES;

-- HR được xem nhiều hơn nếu được cấp quyền từ user khác
SELECT COUNT(*) FROM ALL_TABLES;

-- Lỗi! HR không có quyền xem DBA_TABLES
SELECT COUNT(*) FROM DBA_TABLES;
```

> ⚠️ **Quan trọng:** User thông thường không có quyền truy cập `DBA_*` views. Đây là lý do bảo mật quan trọng - không phải ai cũng được xem toàn bộ metadata của hệ thống.

---

## Bảng tổng kết: Khi nào V$ view hoạt động?

| Trạng thái DB | Data Dictionary (DBA_) | V$ từ RAM | V$ từ Control File | V$ từ Datafiles |
|---------------|----------------------|-----------|-------------------|-----------------|
| NOMOUNT | ❌ | ✅ | ❌ | ❌ |
| MOUNT | ❌ | ✅ | ✅ | ❌ |
| OPEN | ✅ | ✅ | ✅ | ✅ |

---

## Tóm tắt bài thực hành

1. **Data Dictionary views** chỉ hoạt động khi DB ở trạng thái **OPEN**.
2. **V$ views** có thể hoạt động ở `MOUNT` hoặc `NOMOUNT` nếu chúng đọc từ SGA hoặc Control File.
3. Ba mức phân quyền: **USER_** (của tôi) → **ALL_** (tôi được xem) → **DBA_** (toàn DB).
4. Dùng `TS#` để JOIN giữa các V$ tablespace và datafile views.
5. Kết hợp nhiều view để có thông tin đầy đủ hơn.

---

## Câu hỏi ôn tập

**1. Ở trạng thái `MOUNT`, lệnh `SELECT NAME FROM DBA_DATAFILES` sẽ trả về lỗi gì?**
> **Trả lời:**
> Lệnh sẽ trả về lỗi **`ORA-01219: database or pluggable database not open`**.
> Nguyên nhân: `DBA_DATAFILES` là một view trong Data Dictionary tĩnh, dữ liệu của nó được lưu trong các datafiles của `SYSTEM` tablespace. Khi database đang ở trạng thái `MOUNT`, các datafiles chưa được mở (`OPEN`), nên Oracle không thể đọc bảng dữ liệu từ điển bên trong để hiển thị kết quả.

**2. Tại sao `V$DATABASE` hoạt động được ở chế độ MOUNT?**
> **Trả lời:**
> `V$DATABASE` là một **Dynamic Performance View (V$ view)**. Thông tin của view này được Oracle đọc trực tiếp từ **Control File** và vùng nhớ RAM (SGA). Khi database ở chế độ `MOUNT`, Control File đã được mở và nạp vào bộ nhớ, do đó các view hiệu năng động liên quan đến cấu trúc vật lý (`V$DATABASE`, `V$INSTANCE`, `V$DATAFILE`, `V$LOG`) đều có thể truy vấn bình thường.

**3. Tại sao `USER_TABLES` không có cột `OWNER` mà `DBA_TABLES` lại có?**
> **Trả lời:**
> Vì view `USER_TABLES` được thiết kế chỉ để liệt kê các bảng do **chính người dùng đang đăng nhập sở hữu** (schema hiện tại). Do chủ sở hữu hiển nhiên là chính bạn (user hiện tại), việc thêm cột `OWNER` là thừa thãi. Trong khi đó, `DBA_TABLES` (và `ALL_TABLES`) hiển thị bảng thuộc về nhiều người dùng/schema khác nhau trong toàn bộ hệ thống, nên bắt buộc phải có cột `OWNER` để phân biệt bảng đó thuộc về ai (ví dụ `HR.EMPLOYEES` hay `SCOTT.EMPLOYEES`).

**4. User HR muốn xem tất cả bảng trong toàn bộ Database, cần cấp quyền gì?**
> **Trả lời:**
> DBA cần cấp quyền hệ thống **`SELECT ANY DICTIONARY`** (hoặc gán role **`SELECT_CATALOG_ROLE`**) cho user HR:
> ```sql
> GRANT SELECT_CATALOG_ROLE TO hr;
> -- hoặc:
> GRANT SELECT ANY DICTIONARY TO hr;
> ```
> Khi đó user HR có thể truy vấn view `DBA_TABLES` và toàn bộ từ điển dữ liệu của hệ thống mà không cần phải có quyền DBA.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/21-thuc-hanh-data-dictionary.md`
