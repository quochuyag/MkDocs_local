---
title: 'Bài 25: Tạo Pluggable Databases (PDBs)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/25-tao-pluggable-database.md
---

# Bài 25: Tạo Pluggable Databases (PDBs)

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Hiểu các điều kiện tiên quyết để tạo PDB.
- Biết các công cụ và phương pháp tạo PDB.
- Thực hiện tạo PDB từ **PDB$SEED** bằng lệnh SQL.
- Thực hiện **clone** (nhân bản) PDB.
- Biết cách **xóa** một PDB.

---

## 1. Điều kiện tiên quyết để tạo PDB

Trước khi tạo PDB, cần đảm bảo:

| Điều kiện | Lý do |
|-----------|-------|
| CDB phải đang ở chế độ **READ/WRITE** | PDB cần đọc/ghi khi được tạo. |
| User thực hiện phải là **Common User** | Local User không có quyền tạo PDB. |
| User phải có quyền **CREATE PLUGGABLE DATABASE** | Đây là system privilege đặc biệt. |

```sql
-- Cấp quyền tạo PDB cho user SYSTEM (đã có sẵn)
-- Hoặc cấp cho common user khác
GRANT CREATE PLUGGABLE DATABASE TO C##ADMIN;
```

---

## 2. Các công cụ tạo PDB

| Công cụ | Phương pháp hỗ trợ |
|---------|-------------------|
| **SQL*Plus** | Lệnh `CREATE PLUGGABLE DATABASE` |
| **dbca** | Copy từ seed, Unplug/Plug, Clone từ remote PDB (19c) |
| **SQL Developer** | Giao diện đồ họa |
| **EM Cloud Control** | Giao diện web quản trị |

---

## 3. Các phương pháp tạo PDB

### 3.1. Tạo từ PDB$SEED (Phổ biến nhất)
Copy file từ template PDB$SEED để tạo PDB rỗng.

### 3.2. Clone từ PDB cục bộ (Local Clone)
Sao chép (clone) từ một PDB đang tồn tại trong cùng CDB.

### 3.3. Clone từ PDB từ xa (Remote Clone - 19c+)
Sao chép từ PDB trên CDB khác qua Database Link.

### 3.4. Unplug / Plug
Tháo (unplug) PDB khỏi CDB nguồn và gắn (plug) vào CDB đích.

### 3.5. Tạo từ non-CDB
Chuyển đổi non-CDB thành PDB và gắn vào CDB (dùng DBMS_PDB).

---

## 4. Tạo PDB từ PDB$SEED

### 4.1. Cơ chế hoạt động

```
PDB$SEED (Template)
     │
     │ Copy files
     ▼
New PDB (vị trí mới)
```

Oracle copy datafiles từ PDB$SEED sang vị trí mới được chỉ định.

### 4.2. Quy tắc xác định vị trí file mới

Oracle ưu tiên tìm vị trí đặt file theo thứ tự sau:

| Thứ tự ưu tiên | Cách xác định |
|----------------|---------------|
| 1 (cao nhất) | `FILE_NAME_CONVERT` clause trong lệnh CREATE |
| 2 | `CREATE_FILE_DEST` clause trong lệnh CREATE |
| 3 | Tham số `DB_CREATE_FILE_DEST` của CDB |
| 4 | Tham số `PDB_FILE_NAME_CONVERT` |

---

### 4.3. Ví dụ tạo PDB từ Seed

**Ví dụ 1: Đơn giản nhất (dùng DB_CREATE_FILE_DEST)**

```sql
-- Kết nối vào ROOT với quyền SYSDBA hoặc là SYSTEM
conn system/ABcd##1234

-- Tạo PDB1 với local admin là pdb1admin
CREATE PLUGGABLE DATABASE pdb1
  ADMIN USER pdb1admin IDENTIFIED BY mypassword
  ROLES = (CONNECT, DBA);

-- Mở PDB vừa tạo
ALTER PLUGGABLE DATABASE pdb1 OPEN;
```

> 💡 Cần đặt `DB_CREATE_FILE_DEST` trước khi dùng cách này, hoặc Oracle sẽ báo lỗi không biết đặt file ở đâu.

**Ví dụ 2: Chỉ định thư mục chứa file**

```sql
CREATE PLUGGABLE DATABASE pdb1
  ADMIN USER pdb1admin IDENTIFIED BY mypassword
  ROLES = (DBA)
  CREATE_FILE_DEST = '/u01/oradata/cdb1/pdb1';

ALTER PLUGGABLE DATABASE pdb1 OPEN;
```

**Ví dụ 3: Đầy đủ với giới hạn storage và tablespace mặc định**

```sql
CREATE PLUGGABLE DATABASE pdb2
  ADMIN USER pdb2admin IDENTIFIED BY mypassword
  STORAGE (MAXSIZE 2G)                                    -- Giới hạn tối đa 2GB
  DEFAULT TABLESPACE hr                                   -- Tablespace mặc định
  DATAFILE '/u01/oracle/dbs/pdb2/hr01.dbf' SIZE 250M AUTOEXTEND ON
  FILE_NAME_CONVERT = ('/u01/oracle/dbs/pdbseed/', '/u01/oradata/cdb1/pdb2/');
```

### 4.4. Quy trình chuẩn tạo PDB từ Seed

```
Bước 1: Kết nối vào ROOT với common user có quyền CREATE PLUGGABLE DATABASE
         ↓
Bước 2: Chạy lệnh CREATE PLUGGABLE DATABASE
         ↓
Bước 3: ALTER PLUGGABLE DATABASE <name> OPEN
         ↓
Bước 4: Backup PDB (khuyến nghị)
```

---

## 5. Clone PDB cục bộ (Local Clone)

### 5.1. Cơ chế hoạt động

```
PDB1 (nguồn)
     │
     │ Copy files
     ▼
PDB2 (clone)
```

### 5.2. Điều kiện clone

| Phiên bản Oracle | Yêu cầu |
|-----------------|---------|
| 12.1 | PDB nguồn phải ở **READ ONLY** |
| 12.2+ | PDB nguồn có thể đang OPEN, nếu CDB đang ở **ARCHIVELOG mode** và dùng **Local UNDO** |

### 5.3. Ví dụ clone PDB

```sql
-- Bước 1: Đặt PDB1 về READ ONLY (cho 12.1 hoặc khi không có archivelog)
ALTER PLUGGABLE DATABASE pdb1 CLOSE;
ALTER PLUGGABLE DATABASE pdb1 OPEN READ ONLY;

-- Bước 2: Clone pdb1 thành pdb2
CREATE PLUGGABLE DATABASE pdb2 FROM pdb1;

-- Hoặc với chỉ định đường dẫn file
CREATE PLUGGABLE DATABASE pdb2 FROM pdb1
  FILE_NAME_CONVERT = ('/u01/pdb1', '/u01/pdb2');

-- Bước 3: Mở PDB2
ALTER PLUGGABLE DATABASE pdb2 OPEN;

-- Bước 4: Mở lại PDB1 bình thường
ALTER PLUGGABLE DATABASE pdb1 CLOSE;
ALTER PLUGGABLE DATABASE pdb1 OPEN;
```

---

## 6. Các clause tùy chọn quan trọng trong CREATE PLUGGABLE DATABASE

| Clause | Mô tả |
|--------|-------|
| `DEFAULT TABLESPACE` | Tạo tablespace mới và làm tablespace mặc định của PDB. |
| `STORAGE (MAXSIZE nG)` | Giới hạn tổng dung lượng PDB được phép dùng. |
| `ROLES = (role1, role2)` | Cấp các roles này cho local role `PDB_DBA` (và cho local admin). |
| `NO DATA` | Khi clone, chỉ copy cấu trúc (schema) mà không copy data. |
| `FILE_NAME_CONVERT` | Chỉ định cách đổi tên file: từ pattern này sang pattern khác. |
| `CREATE_FILE_DEST` | Chỉ định thư mục OMF cho PDB mới. |

---

## 7. Xóa PDB (Drop PDB)

### 7.1. Điều kiện

- PDB phải được **đóng** (CLOSE) trước khi xóa.
- Phải thực hiện từ **CDB$ROOT**.

### 7.2. Cú pháp

```sql
-- Xóa PDB nhưng GIỮ datafiles trên đĩa (PDB ở trạng thái unplugged)
DROP PLUGGABLE DATABASE pdb1 KEEP DATAFILES;

-- Xóa PDB và XÓA LUÔN datafiles
DROP PLUGGABLE DATABASE pdb1 INCLUDING DATAFILES;
```

> ⚠️ **Cẩn thận:** `INCLUDING DATAFILES` xóa vĩnh viễn tất cả dữ liệu của PDB. Hãy chắc chắn đã backup trước.

### 7.3. Quy trình xóa PDB

```sql
-- Bước 1: Đóng PDB
ALTER PLUGGABLE DATABASE pdb1 CLOSE;

-- Bước 2: Xóa PDB
DROP PLUGGABLE DATABASE pdb1 INCLUDING DATAFILES;
```

---

## 8. Quản lý trạng thái PDB

```sql
-- Mở một PDB
ALTER PLUGGABLE DATABASE pdb1 OPEN;
ALTER PLUGGABLE DATABASE pdb1 OPEN READ ONLY;    -- Chỉ đọc
ALTER PLUGGABLE DATABASE pdb1 OPEN READ WRITE;   -- Đọc/ghi (mặc định)

-- Đóng một PDB
ALTER PLUGGABLE DATABASE pdb1 CLOSE;
ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE;

-- Mở tất cả PDB
ALTER PLUGGABLE DATABASE ALL OPEN;

-- Tự động mở PDB khi CDB restart (lưu trạng thái)
ALTER PLUGGABLE DATABASE pdb1 SAVE STATE;
```

---

## 9. Tóm tắt bài học

1. **Điều kiện tạo PDB:** CDB READ/WRITE, dùng Common User, có quyền CREATE PLUGGABLE DATABASE.
2. **Phương pháp phổ biến nhất:** Tạo từ PDB$SEED bằng `CREATE PLUGGABLE DATABASE`.
3. **Sau khi tạo:** PDB ở trạng thái MOUNTED, phải `ALTER PLUGGABLE DATABASE ... OPEN`.
4. **Clone PDB:** Tạo bản sao hoàn chỉnh từ PDB nguồn, bao gồm cả dữ liệu.
5. **Xóa PDB:** Phải đóng trước, có thể giữ hoặc xóa datafiles.
6. **SAVE STATE:** Dùng để PDB tự động mở khi CDB restart.

---

## 10. Câu hỏi ôn tập

**1. Sau khi tạo PDB bằng `CREATE PLUGGABLE DATABASE`, PDB có tự động OPEN không? Phải làm gì để OPEN?**
> **Trả lời:**
> **Không tự động OPEN.** Ngay sau khi tạo xong, PDB luôn ở trạng thái **`MOUNTED`**.
> Để mở PDB cho người dùng kết nối, DBA phải chạy lệnh:
> ```sql
> ALTER PLUGGABLE DATABASE <pdb_name> OPEN;
> ```
> (Lưu ý: Nếu tạo từ PDB$SEED, lần mở đầu tiên sẽ mở ở chế độ `READ WRITE`).

**2. Trong Oracle 12.1, khi clone PDB, PDB nguồn phải ở trạng thái nào?**
> **Trả lời:**
> Trong Oracle 12c Release 1 (12.1), PDB nguồn bắt buộc phải được mở ở chế độ **`READ ONLY`** (`ALTER PLUGGABLE DATABASE <source_pdb> OPEN READ ONLY;`).
> (Từ Oracle 12.2 trở đi, nhờ tính năng Local Undo, Oracle mới hỗ trợ kỹ thuật *Hot Cloning* - cho phép clone PDB ngay cả khi PDB nguồn đang mở `READ WRITE`).

**3. Sự khác biệt giữa `KEEP DATAFILES` và `INCLUDING DATAFILES` khi xóa PDB?**
> **Trả lời:**
> - `DROP PLUGGABLE DATABASE <pdb_name> KEEP DATAFILES;`: Chỉ xóa định nghĩa metadata của PDB ra khỏi Data Dictionary của CDB. Toàn bộ các file dữ liệu vật lý (`.dbf`) của PDB vẫn được **giữ nguyên vẹn trên đĩa cứng** (dùng khi bạn muốn cắm lại PDB này vào CDB khác sau này - unplug/plug).
> - `DROP PLUGGABLE DATABASE <pdb_name> INCLUDING DATAFILES;`: Xóa sạch cả metadata lẫn **xóa vĩnh viễn toàn bộ các datafiles vật lý trên ổ cứng** của PDB đó, giải phóng hoàn toàn dung lượng đĩa.

**4. Làm thế nào để PDB tự động mở sau khi CDB restart mà không cần can thiệp thủ công?**
> **Trả lời:**
> Bạn mở PDB lên ở trạng thái mong muốn (`READ WRITE`), sau đó chạy lệnh lưu trạng thái:
> ```sql
> ALTER PLUGGABLE DATABASE <pdb_name> SAVE STATE;
> -- Hoặc lưu trạng thái cho toàn bộ các PDB:
> ALTER PLUGGABLE DATABASE ALL SAVE STATE;
> ```
> Oracle sẽ ghi nhận trạng thái này vào từ điển dữ liệu. Khi CDB khởi động lại, các PDB sẽ tự động chuyển về đúng trạng thái đã được lưu.

**5. `FILE_NAME_CONVERT` trong lệnh `CREATE PLUGGABLE DATABASE` có tác dụng gì?**
> **Trả lời:**
> Mệnh đề `FILE_NAME_CONVERT = ('chuoi_nguon', 'chuoi_dich')` có tác dụng hướng dẫn Oracle **quy tắc ánh xạ và đổi tên đường dẫn các datafiles** khi copy từ PDB mẫu (hoặc PDB nguồn) sang PDB mới tạo.
> Ví dụ: `FILE_NAME_CONVERT = ('/pdbseed/', '/pdb2/')` sẽ thay thế chuỗi `/pdbseed/` trong tên file gốc thành `/pdb2/` để tạo các file dữ liệu mới cho `pdb2` tại thư mục riêng biệt. (Nếu đã bật Oracle Managed Files - OMF thì không cần dùng mệnh đề này).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/25-tao-pluggable-database.md`
