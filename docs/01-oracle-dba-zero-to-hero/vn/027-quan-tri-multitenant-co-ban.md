---
title: 'Bài 27: Quản trị Multitenant Cơ bản'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/27-quan-tri-multitenant-co-ban.md
---

# Bài 27: Quản trị Multitenant Cơ bản

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Biết cách **chuyển đổi container** (switch current container).
- Hiểu và quản lý **trạng thái của CDB và PDB**.
- Biết cách **lưu trạng thái mở** của PDB để tự động khôi phục sau restart.
- Quản lý **tham số khởi tạo** ở cấp CDB và PDB.
- **Đổi tên** (Global Database Name) của PDB.

---

## 1. Chuyển đổi Container (Switch Container)

Khi bạn kết nối vào CDB$ROOT (với quyền SYSDBA), bạn có thể chuyển session sang bất kỳ PDB nào mà không cần đăng xuất rồi đăng nhập lại.

### 1.1. Lệnh chuyển container

```sql
-- Chuyển sang PDB1
ALTER SESSION SET CONTAINER = pdb1;

-- Chuyển về Root
ALTER SESSION SET CONTAINER = CDB$ROOT;
```

> ⚠️ **Quan trọng:** Khi chuyển container, hãy chắc chắn kết thúc mọi transaction đang mở trước (COMMIT hoặc ROLLBACK). Chuyển container không tự động commit transaction.

### 1.2. Kiểm tra container hiện tại

```sql
-- Trong SQL*Plus (lệnh đặc biệt của SQL*Plus):
SHOW CON_ID CON_NAME

-- Trong SQL (chạy được ở bất kỳ đâu):
SELECT SYS_CONTEXT('USERENV', 'CON_ID')   CON_ID,
       SYS_CONTEXT('USERENV', 'CON_NAME') CON_NAME
FROM DUAL;
```

---

## 2. Trạng thái của CDB và PDB

### 2.1. Bảng trạng thái

| Trạng thái | Áp dụng cho | Mô tả |
|-----------|------------|-------|
| **NOMOUNT** | CDB only | Instance đang chạy nhưng Control File chưa được đọc. |
| **MOUNTED** | CDB và PDB | Control File đã được đọc (CDB). Với PDB: PDB đang đóng. |
| **READ ONLY** | CDB và PDB | Người dùng có thể kết nối và đọc dữ liệu, không thể ghi. |
| **READ WRITE** | CDB và PDB | Truy cập đầy đủ - đọc và ghi. |
| **MIGRATE** | CDB và PDB | Trạng thái trong quá trình nâng cấp (upgrade). |

### 2.2. Khởi động và Tắt CDB

Hoàn toàn giống như non-CDB:

```sql
-- Trong SQL*Plus kết nối với CDB$ROOT
STARTUP          -- Khởi động CDB
SHUTDOWN IMMEDIATE  -- Tắt CDB (và tất cả PDB)
```

### 2.3. Khởi động và Tắt PDB

**Cách 1: Từ CDB$ROOT (ảnh hưởng đến PDB được đặt tên)**

```sql
-- Mở PDB cụ thể
ALTER PLUGGABLE DATABASE pdb1 OPEN;
ALTER PLUGGABLE DATABASE pdb1 OPEN READ ONLY;    -- Chỉ đọc

-- Mở tất cả PDB
ALTER PLUGGABLE DATABASE ALL OPEN;

-- Mở tất cả PDB trừ pdb1
ALTER PLUGGABLE DATABASE ALL EXCEPT pdb1 OPEN;

-- Đóng PDB
ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE;

-- Lệnh STARTUP/SHUTDOWN dạng SQL*Plus cũng được:
STARTUP PLUGGABLE DATABASE pdb1 OPEN READ WRITE FORCE;
```

**Cách 2: Từ chính PDB đó (sau khi ALTER SESSION SET CONTAINER)**

```sql
-- Khi đang ở trong PDB
ALTER PLUGGABLE DATABASE OPEN;    -- Mở PDB hiện tại
ALTER PLUGGABLE DATABASE CLOSE;   -- Đóng PDB hiện tại

-- Hoặc dùng SQL*Plus:
STARTUP OPEN
SHUTDOWN IMMEDIATE
```

> ⚠️ **Mẹo an toàn:** Ưu tiên dùng `ALTER PLUGGABLE DATABASE` thay vì `SHUTDOWN` khi đang ở PDB. Nếu bạn nhầm đang ở ROOT mà gõ `SHUTDOWN`, toàn bộ CDB sẽ tắt!

---

## 3. Xem trạng thái OPEN_MODE của PDB

```sql
SELECT NAME, OPEN_MODE FROM V$PDBS WHERE NAME = 'PDB1';
```

| Giá trị OPEN_MODE | Ý nghĩa |
|------------------|---------|
| **MOUNTED** | PDB đang đóng (closed) |
| **READ WRITE** | PDB đang mở bình thường |
| **READ ONLY** | PDB đang mở ở chế độ chỉ đọc |
| **MIGRATE** | PDB đang trong quá trình upgrade |

---

## 4. Lưu trạng thái mở của PDB (SAVE STATE)

**Vấn đề:** Mặc định, khi CDB khởi động lại, tất cả PDB đều ở trạng thái **MOUNTED** (đóng). DBA phải mở thủ công từng PDB - rất bất tiện!

**Giải pháp:** `SAVE STATE` - lưu lại trạng thái hiện tại, lần sau CDB restart PDB sẽ tự động về trạng thái đã lưu.

```sql
-- Mở PDB1 rồi lưu trạng thái
ALTER PLUGGABLE DATABASE pdb1 OPEN;
ALTER PLUGGABLE DATABASE pdb1 SAVE STATE;

-- Lưu tất cả PDB cùng lúc
ALTER PLUGGABLE DATABASE ALL SAVE STATE;

-- Xem trạng thái đã lưu
SELECT CON_NAME, STATE FROM DBA_PDB_SAVED_STATES;

-- Xóa trạng thái đã lưu (quay về mặc định: MOUNTED sau restart)
ALTER PLUGGABLE DATABASE pdb1 DISCARD STATE;
```

**Luồng hoạt động:**
```
CDB Restart
    │
    ▼
PDB tự động mở (nếu đã SAVE STATE = OPEN)
    │
    ▼
Người dùng kết nối được ngay
```

---

## 5. Quản lý Tham số Khởi tạo trong PDB

### 5.1. Nguyên tắc

- CDB dùng **SPFILE** chung.
- PDB **không có SPFILE riêng** - giá trị tham số riêng của PDB được lưu vào bảng `PDB_SPFILE$` trong CDB dictionary.
- Chỉ những tham số có `ISPDB_MODIFIABLE = TRUE` mới có thể thay đổi ở cấp PDB.

### 5.2. Xem danh sách tham số có thể thay đổi ở PDB

```sql
-- Kết nối ở CDB$ROOT
SELECT NAME FROM V$SYSTEM_PARAMETER
WHERE ISPDB_MODIFIABLE = 'TRUE'
ORDER BY NAME;
```

### 5.3. Thay đổi tham số ở cấp PDB

```sql
-- Ví dụ: thay đổi DDL_LOCK_TIMEOUT chỉ cho PDB1
ALTER SESSION SET CONTAINER = PDB1;
ALTER SYSTEM SET DDL_LOCK_TIMEOUT = 12;   -- Chỉ ảnh hưởng PDB1

-- Quay về ROOT và xem giá trị tham số theo từng container
ALTER SESSION SET CONTAINER = CDB$ROOT;

col name format a20
SELECT CON_ID, NAME, VALUE
FROM V$SYSTEM_PARAMETER
WHERE NAME = 'ddl_lock_timeout';
-- Sẽ thấy CON_ID=0 (giá trị mặc định) và CON_ID=3 (PDB1 với giá trị 12)
```

### 5.4. Thay đổi tham số áp dụng cho tất cả container

```sql
-- Thay đổi tham số cho tất cả containers (ROOT và mọi PDB)
ALTER SYSTEM SET TEMP_UNDO_ENABLED = TRUE CONTAINER = ALL SCOPE = BOTH;
```

> 💡 **V$SYSTEM_PARAMETER vs V$PARAMETER:**
> - `V$SYSTEM_PARAMETER`: Giá trị của tham số ở cấp instance/system.
> - `V$PARAMETER`: Giá trị của tham số cho session hiện tại.

---

## 6. Đổi tên (Global Database Name) của PDB

Đôi khi cần đổi tên một PDB sau khi tạo. Quy trình:

```sql
-- Bước 1: Đóng PDB cần đổi tên
ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE;

-- Bước 2: Mở ở chế độ RESTRICTED (chỉ DBA mới kết nối được)
ALTER PLUGGABLE DATABASE pdb1 OPEN RESTRICTED;

-- Xác nhận trạng thái RESTRICTED
SELECT CON_ID, OPEN_MODE, RESTRICTED FROM V$PDBS WHERE NAME = 'PDB1';

-- Bước 3: Chuyển vào PDB cần đổi tên
ALTER SESSION SET CONTAINER = PDB1;

-- Bước 4: Đổi tên
ALTER PLUGGABLE DATABASE pdb1 RENAME GLOBAL_NAME TO new_pdb_name;

-- Bước 5: Đóng rồi mở lại bình thường
ALTER PLUGGABLE DATABASE new_pdb_name CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE new_pdb_name OPEN;
```

> ⚠️ **Tại sao cần RESTRICTED?** Chế độ RESTRICTED ngăn người dùng thông thường kết nối trong khi đang thực hiện thao tác ảnh hưởng lớn đến PDB. Chỉ users có quyền RESTRICTED SESSION mới có thể kết nối.

---

## 7. Tóm tắt bài học

| Tác vụ | Lệnh |
|--------|------|
| Chuyển container | `ALTER SESSION SET CONTAINER = pdb1` |
| Kiểm tra container hiện tại | `SHOW CON_ID CON_NAME` |
| Mở PDB | `ALTER PLUGGABLE DATABASE pdb1 OPEN` |
| Đóng PDB | `ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE` |
| Mở tất cả PDB | `ALTER PLUGGABLE DATABASE ALL OPEN` |
| Lưu trạng thái PDB | `ALTER PLUGGABLE DATABASE ALL SAVE STATE` |
| Xem trạng thái lưu | `SELECT CON_NAME, STATE FROM DBA_PDB_SAVED_STATES` |
| Xem tham số PDB-modifiable | `SELECT NAME FROM V$SYSTEM_PARAMETER WHERE ISPDB_MODIFIABLE='TRUE'` |
| Đổi tên PDB | `ALTER PLUGGABLE DATABASE ... RENAME GLOBAL_NAME TO ...` |

---

## 8. Câu hỏi ôn tập

**1. Sau khi CDB restart, các PDB sẽ ở trạng thái gì theo mặc định?**
> **Trả lời:**
> Theo mặc định của Oracle, khi CDB khởi động lại, tất cả các PDB sẽ ở trạng thái **`MOUNTED`** (chưa mở). Người dùng bên ngoài sẽ không thể kết nối vào PDB trừ khi DBA can thiệp mở thủ công, hoặc trừ khi trước đó DBA đã thực hiện lưu trạng thái tự động bằng lệnh `ALTER PLUGGABLE DATABASE ... SAVE STATE`.

**2. Lệnh `ALTER PLUGGABLE DATABASE ALL SAVE STATE` làm gì? Lưu vào đâu?**
> **Trả lời:**
> - **Chức năng:** Lưu lại trạng thái mở hiện hành (ví dụ `READ WRITE` hoặc `READ ONLY`) của toàn bộ tất cả các PDB đang có trong CDB. Mỗi khi CDB restart, Oracle sẽ tự động kích hoạt đưa các PDB về đúng trạng thái mở này mà không cần DBA phải gõ lệnh mở thủ công từng PDB.
> - **Nơi lưu trữ:** Thông tin này được lưu bền vững vào bảng Data Dictionary nội bộ trong Root container, có thể kiểm tra qua view **`DBA_PDB_SAVED_STATES`** hoặc **`CDB_PDB_SAVED_STATES`**.

**3. Tại sao nên dùng `ALTER PLUGGABLE DATABASE CLOSE` thay vì `SHUTDOWN` khi đang ở trong PDB?**
> **Trả lời:**
> - Lệnh `ALTER PLUGGABLE DATABASE CLOSE;` thể hiện rõ ràng và an toàn mục đích: chỉ đóng riêng Pluggable Database hiện tại.
> - Trong khi đó, lệnh `SHUTDOWN` (hoặc `SHUTDOWN IMMEDIATE`) nếu bạn vô tình gõ khi đang đứng ở Root container (`CDB$ROOT`) sẽ **hạ gục và tắt toàn bộ Database Instance của cả hệ thống CDB**, làm sập toàn bộ các PDB khác ngay lập tức. Dùng cú pháp `ALTER PLUGGABLE DATABASE CLOSE` giúp giảm thiểu rủi ro nhầm lẫn tai hại này.

**4. Tham số `ISPDB_MODIFIABLE = FALSE` có nghĩa là gì với DBA?**
> **Trả lời:**
> Khi tra cứu view `V$PARAMETER`, nếu cột `ISPDB_MODIFIABLE = 'FALSE'` nghĩa là tham số khởi tạo đó **không thể cấu hình riêng rẽ cho từng PDB**. Nó là tham số áp dụng chung ở cấp độ toàn bộ CDB (System-wide). Bạn chỉ có thể sửa tham số này khi đang kết nối ở Root container (`CDB$ROOT`) và giá trị đó sẽ áp dụng cho tất cả các PDB. Ngược lại, nếu là `'TRUE'`, PDB Administrator có thể dùng lệnh `ALTER SYSTEM SET ...` để tinh chỉnh giá trị riêng biệt cho PDB của mình.

**5. Để đổi tên PDB, tại sao phải mở ở chế độ `RESTRICTED`?**
> **Trả lời:**
> Đổi tên PDB (`ALTER PLUGGABLE DATABASE ... RENAME GLOBAL_NAME TO ...`) là một tác vụ thay đổi cấu hình nhận diện cốt lõi (Service Name, TNS, Data Dictionary).
> Mở ở chế độ **`RESTRICTED`** đảm bảo:
> - Không có bất kỳ phiên làm việc (session) của người dùng hoặc ứng dụng thông thường nào đang kết nối vào PDB.
> - Ngăn chặn các giao dịch mới phát sinh làm nghẽn hoặc xung đột trong quá trình Oracle cập nhật tên dịch vụ toàn cục và đồng bộ lại với Listener mạng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/27-quan-tri-multitenant-co-ban.md`
