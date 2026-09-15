---
title: 'Bài 23: Kiến trúc Oracle Database Multitenant (CDB và PDB)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/23-kien-truc-multitenant.md
---

# Bài 23: Kiến trúc Oracle Database Multitenant (CDB và PDB)

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Hiểu **Multitenant Architecture** là gì và tại sao Oracle giới thiệu nó.
- Phân biệt **CDB** (Container Database) và **PDB** (Pluggable Database).
- Nắm được các thành phần của kiến trúc Multitenant.
- Hiểu sự khác biệt giữa **Local Users** và **Common Users**.
- Hiểu **Shared Undo** và **Local Undo**.

---

## 1. Bài toán trước Multitenant: Quản lý nhiều Database

> 💡 **Trước đây (non-CDB):** Mỗi ứng dụng cần một Database riêng biệt. Mỗi Database cần một **Instance riêng** (SGA + Background processes). Để chạy 10 ứng dụng, bạn cần 10 Database Instance → tốn rất nhiều RAM, CPU.

**Vấn đề với non-CDB:**
- 10 DB = 10 SGA riêng biệt → Lãng phí tài nguyên server.
- Mỗi DB cần bảo trì riêng (backup, patching, upgrade) → Tốn nhiều công sức DBA.

---

## 2. Giải pháp: Oracle Multitenant Architecture

> 💡 **Ý tưởng cốt lõi:** Nhiều Database chia sẻ **một Instance duy nhất** (một SGA, một bộ background processes). Mỗi "Database ứng dụng" trở thành một **Pluggable Database (PDB)** nằm trong một **Container Database (CDB)**.

Hình dung như tòa nhà chung cư:
- **CDB** = Tòa nhà (có hệ thống điện, nước, thang máy chung)
- **PDB** = Căn hộ riêng (mỗi căn hộ độc lập, nhưng dùng chung cơ sở hạ tầng)

---

## 3. Các thành phần của Multitenant Architecture

### 3.1. Container Database (CDB)
Là Database chứa (container) cho các PDB. CDB có:
- Một **Instance** duy nhất (SGA + background processes).
- Các **Control Files**, **Redo Log Files**, **Archive Log Files** dùng chung cho tất cả PDB.
- Một **SPFILE** (tham số khởi động) dùng chung.

### 3.2. CDB$ROOT (Root Container)
- Là "căn phòng quản lý" của CDB.
- Chứa các Oracle-supplied objects, system users (SYS, SYSTEM).
- Là nơi DBA thực hiện các tác vụ quản trị cấp CDB.
- Có **CON_ID = 1**.

### 3.3. PDB$SEED (Seed Container)
- Là **template (bản mẫu)** để tạo các PDB mới.
- **Không thể** sửa đổi hoặc kết nối để làm việc trực tiếp.
- Khi tạo PDB mới, Oracle copy file từ PDB$SEED sang vị trí mới.
- Có **CON_ID = 2**.

### 3.4. Pluggable Database (PDB) - User PDB
- Là Database ứng dụng thực sự (HR, CRM, Sales...).
- Mỗi PDB có bộ Datafiles riêng (SYSTEM, SYSAUX, TEMP, data files của ứng dụng).
- Application users kết nối vào PDB (không phải CDB$ROOT).
- Có **CON_ID >= 3**.

---

## 4. Bảng thuật ngữ Multitenant

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **CDB** (Container Database) | Database đa thuê bao, chứa các PDB. |
| **non-CDB** | Database Oracle truyền thống, không phải Multitenant. |
| **PDB** (Pluggable Database) | Collection các schema và objects, trông giống non-CDB với client. |
| **Root Container** (CDB$ROOT) | Chứa metadata và objects Oracle-supplied cho toàn CDB. |
| **PDB$SEED** | Template để tạo PDB mới. |
| **CON_ID** | ID định danh container trong CDB. |
| **CON_UID** | Unique ID không đổi khi PDB di chuyển giữa CDB. |
| **GUID** | 16-byte RAW, không bao giờ thay đổi. |

---

## 5. Data Dictionary Views trong Multitenant

### 5.1. Views khi kết nối vào PDB

| Loại View | Mô tả |
|-----------|-------|
| **USER_** | Objects do user hiện tại sở hữu (trong PDB). |
| **ALL_** | Objects mà user được phép truy cập (trong PDB). |
| **DBA_** | Tất cả objects trong PDB hiện tại. |

### 5.2. Views khi kết nối vào CDB$ROOT (thêm loại mới)

| Loại View | Mô tả |
|-----------|-------|
| **USER_** | Objects do user hiện tại sở hữu (trong root). |
| **ALL_** | Objects mà user được phép truy cập (trong root). |
| **DBA_** | Tất cả objects trong container hiện tại (root hoặc PDB). |
| **CDB_** | **Tất cả objects trong toàn bộ CDB** (mọi PDB). Có cột CON_ID. |
| **V$** | SGA data - truy cập được từ tất cả containers. Có cột CON_ID. |

> 💡 **Mới trong Multitenant:** Views `CDB_*` là loại view thứ 4, cho phép DBA nhìn xuyên qua tất cả PDB từ một nơi.

### 5.3. Ví dụ: Xem bảng của HR trong tất cả PDB

```sql
-- Kết nối vào CDB$ROOT với quyền SYSDBA
SELECT p.PDB_ID, p.PDB_NAME, t.OWNER, t.TABLE_NAME
FROM DBA_PDBS p, CDB_TABLES t
WHERE p.PDB_ID > 2       -- Bỏ qua ROOT (CON_ID=1) và SEED (CON_ID=2)
AND t.OWNER = 'HR'
AND p.PDB_ID = t.CON_ID  -- Join bằng CON_ID
ORDER BY p.PDB_ID;
```

---

## 6. Container IDs (CON_ID)

| CON_ID | Container |
|--------|-----------|
| 0 | Không có container cụ thể (cấp CDB) |
| 1 | CDB$ROOT |
| 2 | PDB$SEED |
| >= 3 | User PDB (do người dùng tạo) |

```sql
-- Xem thông tin tất cả containers
SELECT CON_ID, NAME, OPEN_MODE FROM V$CONTAINERS;
```

---

## 7. Local Users và Common Users

### 7.1. Local User (User Cục bộ)
- Được tạo trong một PDB cụ thể.
- **Chỉ tồn tại** trong PDB đó, không biết ở ngoài.
- Chỉ có thể kết nối vào PDB nơi nó được tạo.
- **Không thể** được tạo trong CDB$ROOT.
- Ví dụ: Tài khoản ứng dụng HR trong PDB HR.

### 7.2. Common User (User Dùng chung)
- Được tạo trong **CDB$ROOT**.
- **Tự động tồn tại** trong tất cả PDB (hiện tại và tương lai).
- Tên bắt đầu bằng `C##` (ví dụ: `C##ADMIN`).
- SYSTEM, SYS đều là Common Users.
- Một số tác vụ quản trị chỉ có thể thực hiện bởi Common User.

```
CDB
├── CDB$ROOT
│   └── SYSTEM (Common User - có trong mọi PDB)
├── PDB$SEED
│   └── SYSTEM (cùng account, không độc lập)
├── PDB_HR
│   ├── SYSTEM (Common User)
│   └── HR_APP_USER (Local User - chỉ ở PDB này)
└── PDB_CRM
    ├── SYSTEM (Common User)
    └── CRM_APP_USER (Local User - chỉ ở PDB này)
```

---

## 8. Các file dùng chung trong CDB

### 8.1. SPFILE (Server Parameter File)
- Một SPFILE duy nhất cho toàn CDB.
- Một số tham số có thể được ghi đè ở cấp PDB (`ISPDB_MODIFIABLE = TRUE`).
- Giá trị ghi đè lưu trong bảng `PDB_SPFILE$` của CDB dictionary.

### 8.2. Control Files
- Chỉ tồn tại ở cấp CDB.
- Chứa thông tin về tất cả PDB trong CDB.

### 8.3. Temporary Tablespaces
- Mỗi PDB có thể có Temp Tablespace riêng.
- Hoặc sử dụng Temp Tablespace dùng chung của CDB$ROOT.
- Tham số `MAX_SHARED_TEMP_SIZE` giới hạn tối đa PDB dùng từ Temp dùng chung.

---

## 9. Shared Undo vs Local Undo

### 9.1. Shared Undo (Undo Dùng chung - Mặc định)
- **Một** Undo Tablespace duy nhất trong CDB$ROOT, dùng chung cho tất cả PDB.
- Đơn giản hơn để quản lý.
- Khó hơn khi thực hiện Point-in-Time Recovery cho từng PDB.

### 9.2. Local Undo (Undo Cục bộ - Khuyến nghị từ 12.2)
- Mỗi PDB có **Undo Tablespace riêng**.
- Dễ dàng thực hiện PDB-level Flashback và Point-in-Time Recovery.
- Phù hợp hơn cho môi trường production.

```sql
-- Kiểm tra CDB đang dùng Shared hay Local Undo
SELECT CON_ID, NAME, OPEN_MODE FROM V$CONTAINERS;
SELECT PROPERTY_NAME, PROPERTY_VALUE FROM DATABASE_PROPERTIES 
WHERE PROPERTY_NAME = 'LOCAL_UNDO_ENABLED';
```

---

## 10. Ưu điểm của Multitenant Architecture

| Ưu điểm | Giải thích |
|---------|-----------|
| **Hợp nhất tài nguyên** | Nhiều DB dùng chung 1 Instance → tiết kiệm RAM, CPU. |
| **Quản lý tập trung** | Patch, backup, upgrade một lần cho toàn CDB. |
| **Cách ly dữ liệu** | Mỗi PDB hoàn toàn độc lập về dữ liệu với PDB khác. |
| **Di chuyển linh hoạt** | PDB có thể Unplug khỏi CDB này và Plug vào CDB khác. |
| **Bảo mật** | Local Users không thể truy cập dữ liệu của PDB khác. |

---

## 11. Tóm tắt bài học

1. **CDB** là Database container, có **một Instance** chia sẻ cho tất cả PDB.
2. Kiến trúc gồm: **CDB$ROOT** (CON_ID=1) → **PDB$SEED** (CON_ID=2) → **User PDBs** (CON_ID≥3).
3. **Redo Log, Control Files, Archive Log** là của CDB, không thuộc PDB cụ thể.
4. Views `CDB_*` cho phép xem dữ liệu xuyên tất cả PDB từ CDB$ROOT.
5. **Local User**: Chỉ biết trong 1 PDB. **Common User**: Biết trong toàn bộ CDB (tên bắt đầu C##).
6. **Local Undo** (từ 12.2) được khuyến nghị cho môi trường production.

---

## 12. Câu hỏi ôn tập

**1. Nếu bạn muốn tạo một user có thể kết nối vào tất cả PDB trong CDB, bạn cần tạo loại user nào và ở đâu?**
> **Trả lời:**
> Bạn cần tạo một **Common User** (Người dùng chung).
> - **Nơi tạo:** Bắt buộc phải kết nối vào Root Container (`CDB$ROOT`).
> - **Quy tắc đặt tên:** Tên user bắt buộc phải bắt đầu bằng tiền tố `C##` hoặc `c##` (được định nghĩa bởi tham số `COMMON_USER_PREFIX`), ví dụ: `CREATE USER c##dba_admin IDENTIFIED BY password CONTAINER=ALL;`.

**2. CON_ID của CDB$ROOT là bao nhiêu? CON_ID của PDB$SEED là bao nhiêu?**
> **Trả lời:**
> - `CON_ID` của **CDB$ROOT** luôn luôn là **`1`**.
> - `CON_ID` của **PDB$SEED** (bản mẫu dùng để clone PDB) luôn luôn là **`2`**.
> - Các User PDB tự tạo sẽ có `CON_ID` từ **`3`** trở lên. (Giá trị `0` đại diện cho dữ liệu toàn cục áp dụng cho toàn bộ CDB).

**3. Tại sao `CDB_TABLES` lại có cột `CON_ID` còn `DBA_TABLES` thì không?**
> **Trả lời:**
> - `CDB_TABLES` là view hợp nhất dữ liệu từ điển của tất cả các container trong toàn bộ CDB. Do cùng một tên bảng (ví dụ `HR.EMPLOYEES`) có thể tồn tại đồng thời ở PDB1, PDB2 và PDB3, nên Oracle bắt buộc phải có cột **`CON_ID`** để người quản trị biết chính xác dòng dữ liệu đó thuộc về Container/PDB nào.
> - `DBA_TABLES` chỉ hiển thị các bảng nằm trong phạm vi của container hiện tại (nếu đang ở PDB1 thì chỉ thấy bảng của PDB1), nên không cần phân biệt `CON_ID`.

**4. Khi một PDB bị đóng (CLOSED), lệnh truy vấn `CDB_TABLES` từ CDB$ROOT có lỗi không? Giải thích.**
> **Trả lời:**
> **Lệnh không bị lỗi.** Lệnh vẫn thực thi và trả về kết quả thành công, tuy nhiên nó **sẽ bỏ qua (không hiển thị) các bảng thuộc về PDB đang bị CLOSED**.
> Giải thích: View `CDB_*` hoạt động bằng cơ chế chạy song song ngầm truy vấn vào Data Dictionary của từng PDB. Nếu một PDB đang đóng (hoặc chỉ ở trạng thái MOUNT), Oracle không thể đọc datafiles của PDB đó nên sẽ tự động loại trừ container đó ra khỏi tập kết quả trả về mà không làm gián đoạn toàn bộ câu truy vấn.

**5. Sự khác biệt giữa Shared Undo và Local Undo là gì? Khi nào nên dùng Local Undo?**
> **Trả lời:**
> - **Shared Undo (Mặc định trong 12.1):** Toàn bộ CDB chỉ có duy nhất 1 Undo Tablespace nằm ở Root container. Tất cả các PDB dùng chung vùng Undo này. Nhược điểm: Không hỗ trợ Flashback PDB độc lập, không hỗ trợ Hot Clone PDB (PDB nguồn phải Read-Only).
> - **Local Undo (Từ 12.2 trở lên):** Mỗi PDB có một Undo Tablespace riêng biệt cho chính mình.
> - **Khi nào nên dùng Local Undo?** Nên dùng trong **tất cả môi trường Production** hiện đại vì nó là điều kiện tiên quyết để kích hoạt các tính năng cao cấp: Hot Cloning PDB (nhân bản PDB khi nguồn đang mở Read-Write), Unplug/Plug PDB tốc độ cao, và Flashback PDB về quá khứ mà không ảnh hưởng đến các PDB khác trong CDB.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/23-kien-truc-multitenant.md`
