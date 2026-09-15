---
title: 'Bài 24: Thực hành - Tạo CDB Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/24-thuc-hanh-tao-cdb.md
---

# Bài 24: Thực hành - Tạo CDB Database

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- Tạo snapshot VirtualBox để bảo toàn trạng thái non-CDB database.
- Xóa database non-CDB hiện tại và tạo mới một **CDB database** sử dụng `dbca`.
- Xác minh CDB database mới và khám phá các PDB có trong đó.
- Tạo schema HR trong PDB1.

---

## Bối cảnh thực hành

> 💡 **Mục tiêu kép:** Trong khóa học này, chúng ta sẽ thực hành trên cả **non-CDB** lẫn **CDB**. Vì vậy, bạn cần tạo snapshot VirtualBox để có thể chuyển đổi giữa hai loại database khi cần.

---

## Phần 1: Tạo VirtualBox Snapshots

### Bước 1: Tạo 2 snapshots trước khi thay đổi

Trong Oracle VirtualBox Manager:
1. Click vào biểu tượng **"..."** (ba chấm) cạnh `srv1` → chọn **Snapshots**.
2. Click **Take** → nhập tên `root snapshot` → click **OK**. Chờ hoàn tất.
3. Click **Take** → nhập tên `oradb non-CDB database` → click **OK**. Chờ hoàn tất.

> ℹ️ **Snapshot "oradb non-CDB database"** đại diện cho trạng thái non-CDB. Sau này khi cần thực hành với non-CDB, khôi phục snapshot này.

---

## Phần 2: Xóa Database Cũ

### Bước 2: Tắt srv1

Tắt máy ảo `srv1` qua VirtualBox.

### Bước 3: Khôi phục từ "root snapshot"

1. Click vào `root snapshot`.
2. Click **Restore**.

> ⚠️ **Tại sao khôi phục về root snapshot?** Snapshot "non-CDB database" đã chứa Oracle DB software sẵn. Chúng ta chỉ cần xóa database cũ và tạo lại database mới dạng CDB.

### Bước 4: Kết nối vào srv1

Mở Putty, kết nối với user `oracle`.

### Bước 5: Xóa database cũ bằng dbca

```bash
cd ${ORACLE_HOME}/bin

# Xóa database hiện tại (silent mode)
dbca -silent -deleteDatabase \
     -sourceDB ${ORACLE_SID} \
     -sysDBAUserName sys \
     -sysDBAPassword ABcd##1234
```

---

## Phần 3: Tạo CDB Database

### Bước 6-7: Tải file response và chạy dbca

```bash
# File oradb-cdb.rsp đã được tải sẵn vào /media/sf_staging/
# Tạo CDB database từ response file
dbca -createDatabase -silent \
     -responseFile /media/sf_staging/oradb-cdb.rsp \
     -dbOptions JSERVER:true,DV:false,APEX:false,OMS:false,SPATIAL:false,IMEDIA:false,ORACLE_TEXT:false,CWMLITE:false \
     -pdbAdminPassword ABcd##1234
```

> Nhập mật khẩu `ABcd##1234` khi được hỏi cho SYS, SYSTEM, PDBADMIN.
> Quá trình tạo database mất khoảng 15-30 phút.

**Sự khác biệt giữa file response CDB và non-CDB:**
- File `oradb-cdb.rsp` có `createAsContainerDatabase=true`
- Có thêm tham số `pdbName` và `numberOfPDBs`

---

## Phần 4: Cấu hình sau khi tạo Database

### Bước 8-9: Cập nhật /etc/oratab

```bash
# Mở file oratab với vi
vi /etc/oratab

# Tìm dòng chứa tên database và đổi ký tự cuối từ N thành Y
# oradb:/u01/app/oracle/product/19.0.0/db_1:Y
```

> ℹ️ `dbca` tự động xóa entry cũ khi xóa database, nên phải thêm lại để database tự động start khi server khởi động lại.

---

## Phần 5: Xác minh CDB Database

### Bước 10: Đăng nhập và kiểm tra

```bash
sqlplus / as sysdba
```

### Bước 11: Xác nhận đây là CDB

```sql
-- Kiểm tra xem database có phải CDB không
SELECT CDB FROM V$DATABASE;
-- Kết quả: YES
```

### Bước 12: Xóa file response (dọn dẹp)

```sql
-- Trong SQL*Plus
host rm /media/sf_staging/oradb-cdb.rsp
```

### Bước 13: Xem các components đã cài trong database

```sql
set linesize 180
col COMP_NAME for a40
col STATUS for a15
col VERSION for a10

SELECT COMP_NAME, STATUS, VERSION 
FROM DBA_REGISTRY 
ORDER BY 1;
```

---

## Phần 6: Khám phá PDBs

### Bước 14: Xem danh sách PDB

```sql
-- Cách 1: Lệnh SQL*Plus
show pdbs

-- Cách 2: Từ V$PDBS (không hiển thị ROOT)
col NAME for a10
SELECT CON_ID, NAME FROM V$PDBS;

-- Cách 3: Từ CDB_PDBS (không hiển thị ROOT)
SELECT PDB_ID, PDB_NAME NAME FROM CDB_PDBS;

-- Cách 4: Từ V$CONTAINERS (hiển thị cả ROOT)
SELECT CON_ID, NAME FROM V$CONTAINERS;
```

**Kết quả dự kiến:**

| CON_ID | NAME |
|--------|------|
| 1 | CDB$ROOT |
| 2 | PDB$SEED |
| 3 | PDB1 |

### Bước 15: Xem properties của PDB1

```sql
set linesize 180
col PROPERTY_NAME for a35
col PROPERTY_VALUE for a35

-- CON_ID=3 là PDB1
SELECT PROPERTY_NAME, PROPERTY_VALUE 
FROM CDB_PROPERTIES 
WHERE CON_ID = 3;
```

### Bước 16: Xem datafiles của từng container

```sql
COL PDB_ID FOR 999
COL PDB_NAME FOR A8
COL FILE_ID FOR 9999
COL TABLESPACE_NAME FOR A10
COL FILE_NAME FOR A45

SELECT p.CON_ID, p.NAME PDB_NAME, d.FILE_ID, d.TABLESPACE_NAME, d.FILE_NAME
FROM V$CONTAINERS p, CDB_DATA_FILES d
WHERE p.CON_ID = d.CON_ID
ORDER BY p.CON_ID;
```

> ℹ️ **Quan sát:**
> - Datafiles của ROOT nằm trong thư mục OMF (DB_CREATE_FILE_DEST).
> - Datafiles của PDB1 nằm trong thư mục con của ROOT, tên thư mục lấy từ GUID của PDB.
> - Cả ROOT và PDB1 đều có tablespaces: SYSTEM, SYSAUX, UNDOTBS1, USERS.

---

## Phần 7: Tạo Schema HR trong PDB1

### Bước 17: Chuyển sang PDB1 và tạo HR schema

```sql
-- Kết nối lại với sysdba
conn / as sysdba

-- Chuyển sang container PDB1
ALTER SESSION SET CONTAINER = PDB1;

-- Chạy script tạo HR schema (nhập password: ABcd##1234)
-- Default tablespace: users, Temp tablespace: temp, Log file: hr.log
@ $ORACLE_HOME/demo/schema/human_resources/hr_main.sql
```

### Bước 18: Xem bảng của HR trong PDB1

```sql
col TABLE_NAME for a25

-- Vì đang ở PDB1, CDB_TABLES chỉ trả về data của PDB1
SELECT CON_ID, T.TABLE_NAME
FROM CDB_TABLES T
WHERE T.OWNER = 'HR'
ORDER BY T.TABLE_NAME;
```

### Bước 19: Quay về Root Container

```sql
ALTER SESSION SET CONTAINER = CDB$ROOT;
```

### Bước 20: Xem HR tables từ Root (xuyên tất cả PDB)

```sql
set linesize 180
COL PDB_NAME FOR A15
COL OWNER FOR A15
COL TABLE_NAME FOR A30

-- Vì đang ở ROOT, CDB_TABLES trả về data của tất cả PDB đang OPEN
SELECT P.PDB_ID, T.OWNER, P.PDB_NAME, T.TABLE_NAME
FROM DBA_PDBS P, CDB_TABLES T
WHERE P.PDB_ID > 2         -- Bỏ qua ROOT và SEED
AND P.PDB_ID = T.CON_ID
AND T.OWNER = 'HR'
ORDER BY P.PDB_ID, T.OWNER;
```

---

## Phần 8: Tạo Snapshot CDB

### Bước 21-22: Thoát và tạo snapshot

```sql
quit
```

Trong VirtualBox Manager:
- Click **Take** → nhập tên `oradb CDB database` → click **OK**.

> ✅ Bây giờ bạn có hai snapshots:
> - `oradb non-CDB database` - Để thực hành với non-CDB
> - `oradb CDB database` - Để thực hành với CDB

---

## Tóm tắt bài thực hành

1. **Quy trình tạo CDB** bằng `dbca` tương tự như tạo non-CDB, chỉ khác file response.
2. **CDB tự động tạo** PDB$SEED và một PDB mặc định (PDB1) từ file response.
3. **V$CONTAINERS** hiển thị tất cả containers (bao gồm ROOT), còn **V$PDBS** chỉ hiển thị PDB (không có ROOT).
4. **CDB_TABLES** từ ROOT trả về dữ liệu của **tất cả PDB đang OPEN**.
5. **CDB_TABLES** từ PDB chỉ trả về dữ liệu của **PDB đó**.

---

## Câu hỏi ôn tập

**1. Lệnh nào dùng để chuyển session sang một PDB cụ thể?**
> **Trả lời:**
> Sử dụng lệnh `ALTER SESSION`:
> ```sql
> ALTER SESSION SET CONTAINER = pdb1;
> ```
> Hoặc kết nối trực tiếp qua mạng thông qua TNS Service Name của PDB:
> ```sql
> CONNECT hr/password@//srv1:1521/pdb1.localdomain
> ```

**2. Tại sao chúng ta cần cập nhật file `/etc/oratab` sau khi tạo database?**
> **Trả lời:**
> - File `/etc/oratab` lưu danh sách các database instances trên máy chủ Linux kèm theo đường dẫn `ORACLE_HOME` tương ứng.
> - Tiện ích thiết lập biến môi trường `oraenv` (ví dụ `export ORACLE_SID=cdb1; . oraenv`) dựa vào file này để tự động thiết lập chính xác các biến `ORACLE_HOME`, `PATH`, `LD_LIBRARY_PATH`.
> - Ngoài ra, cờ `Y` ở cuối dòng (`cdb1:/u01/app/oracle/product/19.3.0/dbhome_1:Y`) cho phép các script khởi động tự động của hệ thống (`dbstart` / `systemd service`) tự động bật CDB này mỗi khi máy chủ Linux khởi động lại.

**3. `V$PDBS` và `V$CONTAINERS` khác nhau như thế nào?**
> **Trả lời:**
> - **`V$PDBS`:** Chỉ hiển thị danh sách các **Pluggable Databases thực thụ** (bao gồm `PDB$SEED` có CON_ID=2 và các User PDBs có CON_ID >= 3). View này **không chứa** Root container (`CDB$ROOT`).
> - **`V$CONTAINERS`:** Hiển thị **tất cả mọi container** có trong CDB, bao gồm cả `CDB$ROOT` (CON_ID=1), `PDB$SEED` (CON_ID=2) và toàn bộ các Pluggable Databases.

**4. Khi đang ở CDB$ROOT, nếu PDB1 bị CLOSED, lệnh truy vấn `CDB_TABLES` có hiển thị bảng của PDB1 không?**
> **Trả lời:**
> **Không hiển thị.** Khi PDB1 bị `CLOSED` (hoặc ở trạng thái `MOUNT`), các datafiles của PDB1 không được mở ra để đọc dữ liệu. Khi đó cơ chế truy vấn phân tán nội bộ của view `CDB_TABLES` sẽ tự động bỏ qua container PDB1 và chỉ trả về danh sách các bảng thuộc những container đang ở trạng thái `OPEN` (Read-Write hoặc Read-Only). Lệnh vẫn chạy thành công chứ không báo lỗi.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/24-thuc-hanh-tao-cdb.md`
