---
title: 'Bài 33: Quản lý Tablespaces'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/33-quan-ly-tablespace.md
---

# Bài 33: Quản lý Tablespaces

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Phân loại các loại tablespace trong Oracle.
- Tạo **permanent tablespace** với các tùy chọn khác nhau.
- Hiểu và sử dụng **Oracle-Managed Files (OMF)**.
- Tra cứu thông tin và không gian tablespace.
- Mở rộng, xóa tablespace; quản lý tính khả dụng.
- Tạo và quản lý **Bigfile Tablespace**.
- Phân bổ **quota** tablespace cho users.

---

## 1. Các loại Tablespace

### 1.1. Phân loại theo chức năng

| Loại | Tên ví dụ | Chức năng |
|------|----------|-----------|
| **SYSTEM** | SYSTEM | Lõi của database: data dictionary, system objects. |
| **SYSAUX** | SYSAUX | Các schema phụ trợ: AWR, Enterprise Manager, ...|
| **Undo** | UNDOTBS1 | Lưu undo records: dùng cho rollback và read consistency. |
| **Temporary** | TEMP | Dữ liệu tạm (sort, hash join) - mất sau khi session kết thúc. |
| **Permanent (User)** | USERS, HRTBS | Lưu dữ liệu ứng dụng thực tế. |

### 1.2. Phân loại theo quản lý extent

| Loại | Mô tả | Trạng thái |
|------|-------|-----------|
| **Dictionary Managed** | Extents được quản lý trong SYSTEM tablespace. | ❌ Deprecated - không dùng nữa |
| **Locally Managed** | Extents được quản lý bằng bitmap trong chính tablespace. | ✅ Mặc định và được khuyến nghị |

---

## 2. Tạo Permanent Tablespace

### 2.1. Cú pháp đầy đủ

```sql
CREATE [BIGFILE | SMALLFILE] TABLESPACE <tên-tablespace>
  [DATAFILE 'đường-dẫn-đầy-đủ'
    [SIZE <kích-thước>]
    [REUSE]
    [AUTOEXTEND OFF | ON [NEXT <kích-thước>] [MAXSIZE UNLIMITED | <kích-thước>]]
  ]
  [EXTENT MANAGEMENT LOCAL [AUTOALLOCATE | UNIFORM SIZE <kích-thước>]]
  [SEGMENT SPACE MANAGEMENT AUTO | MANUAL];
```

**Các giá trị mặc định (khi không chỉ định):**
- Kích thước datafile: **100MB**
- AUTOEXTEND: **ON** (nếu dùng OMF), **OFF** (nếu chỉ định thủ công)
- NEXT (kích thước tăng): kích thước ban đầu hoặc 100MB (tùy cái nào nhỏ hơn)

### 2.2. Ví dụ tạo tablespace

```sql
-- Ví dụ 1: Tablespace với autoextend
CREATE TABLESPACE hrtbs
  DATAFILE '/u02/oracle/data/hrtbs01.dbf'
  SIZE 50M
  AUTOEXTEND ON NEXT 10M MAXSIZE 32G;

-- Ví dụ 2: Tablespace cố định, không tự mở rộng
CREATE TABLESPACE statictbs
  DATAFILE '/u02/oracle/data/statictbs01.dbf'
  SIZE 10G AUTOEXTEND OFF;

-- Ví dụ 3: Tablespace với quản lý extent tự động (mặc định)
CREATE TABLESPACE lmtbs
  DATAFILE '/u02/oracle/data/lmtbs01.dbf'
  SIZE 50M
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE;

-- Ví dụ 4: Tablespace với extent đồng đều 128KB
CREATE TABLESPACE uniformtbs
  DATAFILE '/u02/oracle/data/uniformtbs01.dbf'
  SIZE 50M
  EXTENT MANAGEMENT LOCAL UNIFORM SIZE 128K;
```

### 2.3. Tùy chọn quản lý Extent

| Tùy chọn | Mô tả |
|---------|-------|
| `AUTOALLOCATE` | Oracle tự quyết định kích thước extent (bắt đầu nhỏ, tăng dần). ✅ Được khuyến nghị |
| `UNIFORM SIZE n` | Tất cả extents có cùng kích thước cố định (mặc định 1MB). |

### 2.4. Quản lý không gian trong Segment (SSMA)

| Tùy chọn | Cơ chế | Phù hợp |
|---------|--------|---------|
| `AUTO` (ASSM) | Dùng **bitmap** để theo dõi free space | ✅ Mặc định, hiệu năng tốt hơn |
| `MANUAL` | Dùng **freelists** (linked list) | Các hệ thống cũ |

---

## 3. Oracle-Managed Files (OMF)

OMF là tính năng giúp Oracle **tự động tạo và quản lý tên file** cho tablespace.

### 3.1. Các tham số OMF

| Tham số | Mô tả | Phạm vi thay đổi |
|---------|-------|-----------------|
| `DB_CREATE_FILE_DEST` | Thư mục mặc định cho **datafiles** và tempfiles. | SYSTEM và SESSION |
| `DB_CREATE_ONLINE_LOG_DEST_n` | Thư mục cho **redo log** và control files. | SYSTEM |
| `DB_RECOVERY_FILE_DEST` | Thư mục **Fast Recovery Area (FRA)**. | SYSTEM |

### 3.2. Bật OMF và tạo tablespace

```sql
-- Bật OMF ở cấp system
ALTER SYSTEM SET DB_CREATE_FILE_DEST = '/u01/app/oracle/oradata';

-- Hoặc chỉ cho session hiện tại
ALTER SESSION SET DB_CREATE_FILE_DEST = '/u01/app/oracle/oradata';

-- Tạo tablespace với OMF (không cần chỉ định datafile)
CREATE TABLESPACE hrtbs;          -- Dùng kích thước mặc định 100MB
CREATE TABLESPACE hrtbs SIZE 1G;  -- Ghi đè kích thước mặc định
```

**Định dạng tên file tự động của OMF:**
```
-- Non-CDB:
<OMF>/<ORACLE_SID>/datafile/<tên-tự-sinh>.dbf

-- CDB:
<OMF>/<CDB-name>/<PDB-GUID>/datafile/<tên-tự-sinh>.dbf
```

---

## 4. Tra cứu thông tin Tablespace

### 4.1. Các view chính

| View | Mô tả |
|------|-------|
| `DBA_TABLESPACES` | Thuộc tính của tất cả tablespace (loại, extent management, ...). |
| `V$TABLESPACE` | Thông tin tablespace từ control file. |
| `DBA_DATA_FILES` | Thông tin tất cả datafiles. |
| `V$DATAFILE` | Thông tin datafile từ control file. |
| `DBA_TEMP_FILES` | Thông tin temp files. |

### 4.2. Query xem mức độ sử dụng tablespace

```sql
-- Query xem tình trạng không gian của các tablespace
SELECT F.TABLESPACE_NAME    "Tablespace",
       F.TOTALSPACE         "Size MB",
       (F.TOTALSPACE - U.TOTALUSEDSPACE) "Free MB",
       ROUND(100 * ((F.TOTALSPACE - U.TOTALUSEDSPACE) / F.TOTALSPACE)) || '%' "Free %",
       T.MAX_S              "Max Size"
FROM
  (SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024) TOTALSPACE
   FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME) F,
  (SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024) TOTALUSEDSPACE
   FROM DBA_SEGMENTS GROUP BY TABLESPACE_NAME) U,
  (SELECT TABLESPACE_NAME, ROUND(MAX_SIZE/1024/1024) MAX_S
   FROM DBA_TABLESPACES) T
WHERE F.TABLESPACE_NAME = U.TABLESPACE_NAME(+)
AND   F.TABLESPACE_NAME = T.TABLESPACE_NAME;
```

---

## 5. Mở rộng Tablespace (Enlarging)

Có bốn cách để mở rộng không gian database:

```sql
-- Cách 1: Tạo tablespace mới (đã học ở trên)
CREATE TABLESPACE newtbs ...;

-- Cách 2: Thêm datafile mới vào tablespace đã có
-- Dùng OMF (không cần chỉ định tên file)
ALTER TABLESPACE hrtbs ADD DATAFILE;

-- Hoặc chỉ định rõ tên và thuộc tính
ALTER TABLESPACE hrtbs ADD DATAFILE
  '/u02/oracle/data/hrtbs02.dbf'
  SIZE 50M AUTOEXTEND ON NEXT 10M MAXSIZE 32G;

-- Cách 3: Tăng kích thước datafile hiện có
ALTER DATABASE DATAFILE 15 RESIZE 10240M;
-- Hoặc dùng tên file:
ALTER DATABASE DATAFILE '/u01/oracle/data/hrtbs01.dbf' RESIZE 200M;

-- Cách 4: Bật AUTOEXTEND cho datafile
ALTER DATABASE DATAFILE 15 AUTOEXTEND ON NEXT 50M MAXSIZE UNLIMITED;
```

> ℹ️ **Lưu ý:** Để thay đổi thuộc tính datafile (resize, autoextend), dùng `ALTER DATABASE DATAFILE`. Không có lệnh `ALTER DATAFILE`.

---

## 6. Xóa Tablespace

```sql
-- Xóa tablespace (không xóa dữ liệu nếu còn dữ liệu sẽ báo lỗi)
DROP TABLESPACE hrtbs;

-- Xóa tablespace kèm tất cả dữ liệu (segments)
DROP TABLESPACE hrtbs INCLUDING CONTENTS;

-- Xóa tablespace, dữ liệu VÀ xóa luôn datafiles trên đĩa
DROP TABLESPACE hrtbs INCLUDING CONTENTS AND DATAFILES;
```

---

## 7. Tạo table trong Tablespace cụ thể

```sql
-- Tạo table trong tablespace cụ thể
CREATE TABLE employees (...) TABLESPACE hrtbs;

-- Di chuyển table sang tablespace khác
ALTER TABLE employees MOVE TABLESPACE hrtbs;

-- Xem table đang nằm trong tablespace nào
SELECT TABLESPACE_NAME FROM USER_TABLES WHERE TABLE_NAME = 'EMPLOYEES';
```

> 💡 **Lợi ích của MOVE TABLESPACE:** Khi di chuyển bảng sang tablespace khác, bảng được **compacted** (nén lại) - loại bỏ fragmentation do DELETE/UPDATE. Đây là cách defragmentation table.

---

## 8. Bigfile Tablespace

### 8.1. Khái niệm

Tablespace thông thường (**Smallfile**) có thể có **nhiều datafiles** nhỏ.
**Bigfile Tablespace** chỉ có **một datafile duy nhất** nhưng rất lớn.

| | Smallfile | Bigfile |
|-|-----------|---------|
| Số datafiles | Nhiều (tối đa 1022) | **Chỉ một** |
| Kích thước tối đa (8K block) | 32GB/file × 1022 files | **32TB** (8K block) |
| Quản lý | Nhiều files phức tạp hơn | Đơn giản hơn |
| Phù hợp | Hầu hết trường hợp | Database multi-TB với ASM |

### 8.2. Tạo Bigfile Tablespace

```sql
-- Tạo Bigfile Tablespace
CREATE BIGFILE TABLESPACE bigtbs
  DATAFILE '/u02/oracle/data/bigtbs01.dbf' SIZE 500G;

-- Kiểm tra loại tablespace
SELECT TABLESPACE_NAME, BIGFILE
FROM DBA_TABLESPACES
WHERE TABLESPACE_NAME = 'BIGTBS';
-- BIGFILE = YES

-- Xem loại tablespace mặc định
SELECT PROPERTY_VALUE
FROM DATABASE_PROPERTIES
WHERE PROPERTY_NAME = 'DEFAULT_TBS_TYPE';

-- Thay đổi loại tablespace mặc định
ALTER DATABASE SET DEFAULT BIGFILE TABLESPACE;
ALTER DATABASE SET DEFAULT SMALLFILE TABLESPACE;
```

> ⚠️ **Khi nào dùng Bigfile?** Chỉ khi database multi-TB và dùng **Oracle ASM** (hỗ trợ striping). Không phù hợp với filesystem thông thường vì một file quá lớn.

---

## 9. Quản lý tính khả dụng (Availability)

### 9.1. Đưa tablespace Offline/Online

```sql
-- OFFLINE - tablespace không khả dụng cho users
ALTER TABLESPACE hrtbs OFFLINE NORMAL;     -- Checkpoint, không cần recovery
ALTER TABLESPACE hrtbs OFFLINE TEMPORARY;  -- Có thể cần recovery
ALTER TABLESPACE hrtbs OFFLINE IMMEDIATE;  -- Cần media recovery

-- ONLINE - tablespace trở lại bình thường
ALTER TABLESPACE hrtbs ONLINE;
```

> ⚠️ **Không thể OFFLINE:** SYSTEM, Undo tablespace, Temporary tablespace.

### 9.2. Chế độ Read-Only/Read-Write

```sql
ALTER TABLESPACE hrtbs READ ONLY;   -- Chỉ đọc (dùng cho data archive)
ALTER TABLESPACE hrtbs READ WRITE;  -- Đọc/ghi bình thường

-- Kiểm tra trạng thái
SELECT TABLESPACE_NAME, STATUS
FROM DBA_TABLESPACES
WHERE TABLESPACE_NAME = 'HRTBS';
-- STATUS: ONLINE | OFFLINE | READ ONLY
```

---

## 10. Quota Tablespace cho Users

```sql
-- Gán quota khi tạo user
CREATE USER hr_user IDENTIFIED BY password
  DEFAULT TABLESPACE hrtbs
  QUOTA 100M ON hrtbs
  QUOTA 10M ON index_tbs;

-- Thay đổi quota cho user hiện có
ALTER USER hr_user QUOTA UNLIMITED ON hrtbs;  -- Không giới hạn
ALTER USER hr_user QUOTA 500M ON hrtbs;        -- Giới hạn 500MB
ALTER USER hr_user QUOTA 0 ON hrtbs;           -- Thu hồi quyền insert

-- Nếu vượt quota sẽ nhận lỗi:
-- ORA-01536: space quota exceeded for tablespace 'HRTBS'
```

**Quyền UNLIMITED TABLESPACE:**
```sql
-- Cấp quyền dùng không giới hạn mọi tablespace
GRANT UNLIMITED TABLESPACE TO hr_user;
-- Lưu ý: Quyền này mạnh - dùng thận trọng
```

---

## 11. Tóm tắt bài học

| Tác vụ | Lệnh/View |
|--------|-----------|
| Tạo tablespace | `CREATE TABLESPACE ... DATAFILE ...` |
| Tạo với OMF | `CREATE TABLESPACE hrtbs;` (không chỉ định DATAFILE) |
| Thêm datafile | `ALTER TABLESPACE ... ADD DATAFILE ...` |
| Thay đổi datafile | `ALTER DATABASE DATAFILE ... RESIZE/AUTOEXTEND` |
| Xóa tablespace | `DROP TABLESPACE ... INCLUDING CONTENTS AND DATAFILES` |
| Di chuyển table | `ALTER TABLE ... MOVE TABLESPACE ...` |
| Offline/Online | `ALTER TABLESPACE ... OFFLINE/ONLINE` |
| Read-Only | `ALTER TABLESPACE ... READ ONLY/READ WRITE` |
| Quota | `ALTER USER ... QUOTA ... ON ...` |
| Xem tablespace | `DBA_TABLESPACES`, `DBA_DATA_FILES` |

---

## 12. Câu hỏi ôn tập

**1. Sự khác biệt giữa Locally Managed và Dictionary Managed tablespace là gì? Cái nào nên dùng?**
> **Trả lời:**
> - **Dictionary Managed Tablespace (Cổ xưa):** Cấp phát và giải phóng extent bằng cách cập nhật các bảng từ điển dữ liệu (`SYS.UET$` và `SYS.FET$`). Nhược điểm: Gây nghẽn tranh chấp dữ liệu (contention) nặng nề, dễ phân mảnh và chậm chạp. Đã bị đào thải hoàn toàn.
> - **Locally Managed Tablespace - LMT (Hiện đại):** Quản lý cấp phát extent bằng **Bitmap** lưu trực tiếp ngay tại header của từng datafile. Mỗi bit tương ứng với một block/extent (0 = trống, 1 = đã dùng). Thao tác cấp phát diễn ra ngay tức thì, không gây nghẽn Data Dictionary, không bao giờ cần gom phân mảnh (coalescing).
> - **Nên dùng:** Luôn luôn và **bắt buộc dùng Locally Managed Tablespace** (đây là mặc định từ Oracle 9i đến nay).

**2. Khi bật OMF, Oracle tự tạo tên file theo định dạng nào với CDB?**
> **Trả lời:**
> Khi bật Oracle Managed Files (OMF) qua tham số `DB_CREATE_FILE_DEST` (ví dụ `/u01/app/oracle/oradata`), Oracle sẽ tự động tổ chức thư mục và sinh tên file theo chuẩn:
> - Cấu trúc thư mục: `%ORACLE_BASE%/oradata/<DB_UNIQUE_NAME>/<PDB_GUID>/datafile/`
> - Định dạng tên file: `o1_mf_<tablespace_name>_<random_alphanumeric_string>.dbf`
>   (Ví dụ: `o1_mf_users_k8f93j2a_.dbf`). Oracle tự động đảm bảo tên file là duy nhất, tự động xóa file vật lý trên đĩa khi bạn DROP tablespace.

**3. Bạn muốn resize datafile hiện có. Lệnh đúng là `ALTER TABLESPACE` hay `ALTER DATABASE DATAFILE`?**
> **Trả lời:**
> Lệnh đúng là **`ALTER DATABASE DATAFILE ... RESIZE ...;`**.
> Ví dụ:
> ```sql
> ALTER DATABASE DATAFILE '/u01/app/oracle/oradata/ORADB/users01.dbf' RESIZE 500M;
> ```
> (Lưu ý: Lệnh `ALTER TABLESPACE` dùng để add datafile mới, đổi trạng thái READ ONLY/OFFLINE, hoặc resize bigfile tablespace; nhưng đối với từng datafile cụ thể của smallfile tablespace thì phải dùng `ALTER DATABASE DATAFILE`).

**4. Khi nào nên dùng Bigfile Tablespace? Hạn chế của nó là gì?**
> **Trả lời:**
> - **Khi nào nên dùng?** Dùng cho các cơ sở dữ liệu cực lớn (Very Large Databases - VLDB) từ hàng chục đến hàng trăm Terabytes, đặc biệt là khi lưu trữ trên kiến trúc ASM hoặc hệ thống lưu trữ LVM/SAN hiện đại có khả năng striping mạnh mẽ. Một Bigfile Tablespace chỉ gồm 1 Datafile duy nhất nhưng có thể phình to tới **32TB đến 128TB** (tùy block size), giúp giảm số lượng file mà hệ điều hành và Control File phải quản lý (không bao giờ lo đụng trần `MAXDATAFILES`).
> - **Hạn chế:**
>   + Chỉ có đúng **1 datafile duy nhất**, không thể thêm datafile thứ hai vào tablespace đó.
>   + Yêu cầu hệ thống lưu trữ bên dưới (Storage) phải hỗ trợ Dynamic Striping / RAID tốt; nếu lưu trên đĩa đơn truyền thống sẽ gây thắt cổ chai I/O cục bộ.
>   + Thời gian sao lưu/phục hồi một file đơn lẻ 32TB bằng công cụ truyền thống sẽ rất lâu (phải dùng tính năng RMAN Multisection Backup để chia nhỏ file khi backup).

**5. Tại sao không thể OFFLINE tablespace SYSTEM hay UNDO?**
> **Trả lời:**
> - **`SYSTEM` Tablespace:** Chứa từ điển dữ liệu (Data Dictionary), mã PL/SQL hệ thống, bảng phân vùng không gian lưu trữ và định nghĩa quyền hạn. Nếu SYSTEM bị offline, database không thể phân tích bất kỳ câu lệnh SQL nào và instance sẽ lập tức ngừng hoạt động (crash).
> - **`UNDO` Tablespace:** Cung cấp tính nhất quán đọc (Read Consistency - gán ảnh trước dữ liệu cho các câu SELECT) và hỗ trợ hoàn tác (`ROLLBACK`) cho tất cả các giao dịch đang hoạt động. Nếu Undo Tablespace bị offline, toàn bộ các phiên làm việc của người dùng sẽ bị lỗi và database không thể đảm bảo được nguyên lý ACID. Do đó Oracle cấm tuyệt đối việc đưa 2 tablespace này về trạng thái OFFLINE khi instance đang chạy.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/33-quan-ly-tablespace.md`
