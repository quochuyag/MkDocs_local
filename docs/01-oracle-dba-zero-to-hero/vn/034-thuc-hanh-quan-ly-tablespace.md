---
title: 'Bài 34: Thực hành - Quản lý Tablespaces'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/34-thuc-hanh-quan-ly-tablespace.md
---

# Bài 34: Thực hành - Quản lý Tablespaces

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- Khám phá mối quan hệ **segment → extent → block** trực quan.
- Tạo và quản lý tablespace **HRTBS** trong PDB1.
- Thêm, resize datafiles; di chuyển table sang tablespace khác.
- Khám phá tablespaces và datafiles trong môi trường **CDB**.

---

## Điều kiện tiên quyết
Máy ảo `srv1` với CDB database đang chạy.

---

## Phần 1: Chuẩn bị Script files

### Bước 1-4: Tạo các script tiện ích

```bash
# Kết nối srv1 qua Putty với user oracle

# Script 1: Insert dữ liệu vào bảng test
cat > /home/oracle/insertrows.sql <<EOF
BEGIN
  FOR I IN 1..&1 LOOP
    INSERT INTO TEST_TABLE (RNAME) VALUES (DBMS_RANDOM.STRING('U', 10));
  END LOOP;
  COMMIT;
END;
/
EOF

# Script 2: Hiển thị thông tin segment của TEST_TABLE
cat > /home/oracle/display_segment.sql <<EOF
col SEGMENT_TYPE for a10
col TABLESPACE_NAME for a10

SELECT SEGMENT_TYPE, TABLESPACE_NAME, EXTENTS, BYTES/1024 KB, BLOCKS
FROM USER_SEGMENTS
WHERE SEGMENT_NAME='TEST_TABLE';
EOF

# Script 3: Hiển thị datafiles của HRTBS
cat > /home/oracle/display_hrtbs_datafiles.sql <<EOF
SELECT FILE_ID, BYTES/1024/1024 SIZE_MB,
       INCREMENT_BY*8/1024 INC_BY_MB,
       ROUND(MAXBYTES/1024/1024,2) MAX_MB,
       AUTOEXTENSIBLE
FROM DBA_DATA_FILES
WHERE TABLESPACE_NAME='HRTBS';
EOF
```

---

## Phần 2: Khám phá Segments, Extents, và Data Blocks

### Bước 5-6: Đăng nhập và xem block size

```bash
sqlplus / as sysdba
```

```sql
-- Block size mặc định là 8K và KHÔNG THỂ thay đổi sau khi tạo DB
SHOW PARAMETER BLOCK_SIZE
-- Kết quả: db_block_size = 8192 (8KB)
```

### Bước 7-8: Kết nối HR và tạo bảng test

```sql
-- Kết nối vào PDB1 với user HR
conn hr/ABcd##1234@//srv1/pdb1.localdomain

-- Tạo bảng test với cột auto-increment
CREATE TABLE TEST_TABLE (
  ROW_ID NUMBER GENERATED ALWAYS AS IDENTITY,
  RNAME  VARCHAR2(10)
);
```

### Bước 9-10: Kiểm tra tablespace và segment ban đầu

```sql
-- Bảng nằm trong tablespace USERS (là default tablespace của HR)
SELECT TABLESPACE_NAME FROM USER_TABLES WHERE TABLE_NAME = 'TEST_TABLE';

-- Chưa có segment vì bảng rỗng!
@ /home/oracle/display_segment.sql
-- Kết quả: không có rows (0 rows selected)
```

> 💡 **Quan sát quan trọng:** Oracle **không tạo segment ngay** khi tạo table. Segment chỉ được cấp phát khi có **dữ liệu thực sự** được INSERT.

### Bước 11-12: Insert 10 rows và kiểm tra segment

```sql
-- Insert 10 rows
@ /home/oracle/insertrows.sql 10

-- Bây giờ mới có segment
@ /home/oracle/display_segment.sql
```

**Kết quả dự kiến:**

| SEGMENT_TYPE | TABLESPACE_NAME | EXTENTS | KB | BLOCKS |
|-------------|----------------|---------|-----|--------|
| TABLE | USERS | 1 | 64 | 8 |

> 💡 **Giải thích:** Segment có 1 extent, 8 blocks × 8KB/block = 64KB. Oracle cấp tối thiểu 8 blocks cho extent đầu tiên.

### Bước 13-14: Insert 10,000 rows và xem segment mở rộng

```sql
-- Insert thêm 10,000 rows
@ /home/oracle/insertrows.sql 10000

-- Segment đã mở rộng thêm extents
@ /home/oracle/display_segment.sql
```

**Kết quả dự kiến:**

| EXTENTS | KB | BLOCKS |
|---------|-----|--------|
| 4 | 256 | 32 |

> 💡 **AUTOALLOCATE:** Extent đầu = 8 blocks, các extent tiếp theo Oracle tự điều chỉnh kích thước (thường tăng dần).

### Bước 15-16: Xóa toàn bộ data và quan sát

```sql
-- Xóa tất cả rows
DELETE TEST_TABLE;
COMMIT;

-- Kiểm tra segment sau khi xóa
@ /home/oracle/display_segment.sql
```

> 💡 **Kết quả bất ngờ:** Segment VẪN CÒN với số extents như cũ! Oracle **không trả ngay** không gian về tablespace sau DELETE. Data blocks chỉ được đánh dấu là "trống" nhưng vẫn thuộc về segment đó.

---

## Phần 3: Quản lý Tablespace HRTBS

### Bước 17-19: Kiểm tra OMF và kết nối SYSTEM

```sql
-- HR không có quyền xem system parameters → lỗi
show parameter DB_CREATE_FILE_DEST
-- ORA-00942: table or view does not exist (với HR user)

-- Kết nối với SYSTEM user
conn system/ABcd##1234@//srv1/pdb1.localdomain

-- SYSTEM có thể xem parameter - OMF đã được bật
show parameter DB_CREATE_FILE_DEST
-- Có giá trị → OMF đang hoạt động
```

### Bước 20-23: Tạo HRTBS và kiểm tra thuộc tính

```sql
-- Tạo tablespace với OMF (không chỉ định datafile)
CREATE TABLESPACE HRTBS;

-- Xem thuộc tính extent management và segment space management
SELECT EXTENT_MANAGEMENT, SEGMENT_SPACE_MANAGEMENT
FROM DBA_TABLESPACES
WHERE TABLESPACE_NAME = 'HRTBS';
-- EXTENT_MANAGEMENT = LOCAL (locally managed)
-- SEGMENT_SPACE_MANAGEMENT = AUTO (ASSM - bitmap)

-- Xem tên datafile được OMF tự tạo
SELECT FILE_NAME FROM DBA_DATA_FILES WHERE TABLESPACE_NAME = 'HRTBS';
-- Kết quả: <OMF>/<CDB_name>/<PDB_GUID>/datafile/<auto_name>.dbf

-- Xem chi tiết datafile
@ /home/oracle/display_hrtbs_datafiles.sql
-- SIZE_MB = 100, INC_BY_MB ≈ 100, MAX_MB ≈ 32768, AUTOEXTENSIBLE = YES
```

### Bước 24-26: Resize và thay đổi increment

```sql
-- Lấy FILE_ID từ bước trên, giả sử FILE_ID = 7
-- Tăng kích thước datafile lên 110MB
ALTER DATABASE DATAFILE 7 RESIZE 110M;

-- Thay đổi increment tự động tăng thành 10MB mỗi lần
ALTER DATABASE DATAFILE 7 AUTOEXTEND ON NEXT 10M;

-- Xác nhận thay đổi
@ /home/oracle/display_hrtbs_datafiles.sql
-- SIZE_MB = 110, INC_BY_MB = 10
```

### Bước 27-30: Thêm datafiles vào HRTBS

```sql
-- Thêm datafile thủ công (không dùng OMF)
ALTER TABLESPACE hrtbs ADD DATAFILE
  '/home/oracle/hrtbs2.dbf'
  SIZE 10M AUTOEXTEND OFF;

-- Xác nhận
@ /home/oracle/display_hrtbs_datafiles.sql
-- Thấy 2 datafiles: một OMF, một thủ công

-- Thêm datafile thứ 3 bằng OMF (kích thước 20MB)
ALTER TABLESPACE hrtbs ADD DATAFILE SIZE 20M;

-- Xác nhận - bây giờ có 3 datafiles
@ /home/oracle/display_hrtbs_datafiles.sql
```

> 💡 **Lưu ý:** Ngay cả khi OMF đã bật, bạn vẫn có thể tạo datafile ở vị trí thủ công (mixed mode).

### Bước 31-35: Di chuyển table sang HRTBS

```sql
-- Kết nối HR
conn hr/ABcd##1234@//srv1/pdb1.localdomain

-- Di chuyển TEST_TABLE sang HRTBS
ALTER TABLE TEST_TABLE MOVE TABLESPACE HRTBS;

-- Xác nhận tablespace mới
SELECT TABLESPACE_NAME FROM USER_TABLES WHERE TABLE_NAME = 'TEST_TABLE';
-- HRTBS

-- Kiểm tra segment sau khi move
@ /home/oracle/display_segment.sql
-- Dù trước đó xóa data, sau MOVE bảng được compact lại → 1 extent nhỏ
```

> 💡 **Tác dụng phụ có lợi:** MOVE TABLESPACE **compact segment** - xóa sạch fragmentation do DELETE/UPDATE. Sau MOVE, segment chỉ chiếm đúng lượng không gian cần thiết.

```sql
-- Insert thêm data để kiểm tra
@ /home/oracle/insertrows.sql 1000

-- Dọn dẹp: Xóa HRTBS (xóa luôn TEST_TABLE)
conn SYSTEM/ABcd##1234@//srv1/pdb1.localdomain
DROP TABLESPACE HRTBS INCLUDING CONTENTS AND DATAFILES;
```

```bash
# Xóa các script files
exit
rm /home/oracle/insertrows.sql
rm /home/oracle/display_segment.sql
rm /home/oracle/display_hrtbs_datafiles.sql
```

---

## Phần 4: Khám phá CDB Tablespaces và Datafiles

### Bước 38-39: Kết nối ROOT và xem tablespace mặc định

```bash
sqlplus / as sysdba
```

```sql
-- Xem tablespace mặc định của ROOT container
col property_name format a30
col property_value format a25

SELECT PROPERTY_NAME, PROPERTY_VALUE
FROM DATABASE_PROPERTIES
WHERE PROPERTY_NAME LIKE 'DEFAULT_%TABLE%';
-- DEFAULT_PERMANENT_TABLESPACE = SYSTEM
-- DEFAULT_TEMP_TABLESPACE = TEMP
```

### Bước 40: Xem tablespaces toàn bộ CDB

```sql
-- CDB_TABLESPACES: xem tablespace của tất cả PDB (không có PDB$SEED)
col pdb_name format a10

SELECT T.TABLESPACE_NAME, T.CON_ID, P.PDB_NAME
FROM CDB_TABLESPACES T, CDB_PDBS P
WHERE T.CON_ID = P.CON_ID (+)
ORDER BY 2, 1;
```

### Bước 41-42: So sánh CDB_DATA_FILES và DBA_DATA_FILES

```sql
-- CDB_DATA_FILES: tất cả PDB (trừ PDB$SEED)
col file_name format a50
col tablespace_name format a8
col file_id format 9999
col con_id format 999

SELECT FILE_NAME, TABLESPACE_NAME, FILE_ID, CON_ID
FROM CDB_DATA_FILES
ORDER BY CON_ID;

-- DBA_DATA_FILES: chỉ ROOT container
SELECT FILE_NAME, TABLESPACE_NAME, FILE_ID
FROM DBA_DATA_FILES;
-- Chỉ thấy files của ROOT (CON_ID=1)
```

### Bước 43-44: Dùng V$ views để xem tất cả (kể cả SEED)

```sql
-- V$DATAFILE + V$TABLESPACE: bao gồm cả PDB$SEED (CON_ID=2)
col name format a12

SELECT FILE#, T.NAME, T.TS#, T.CON_ID
FROM V$DATAFILE D, V$TABLESPACE T
WHERE D.TS# = T.TS# AND D.CON_ID = T.CON_ID
ORDER BY 4, 3;

-- Vào PDB$SEED để xem datafiles
ALTER SESSION SET CONTAINER = PDB$SEED;
col FILE_NAME for a80
SELECT FILE_NAME FROM DBA_DATA_FILES;
```

### Bước 45-46: Query sử dụng không gian toàn CDB và từng PDB

```sql
-- Từ ROOT: xem toàn CDB dùng CDB_ views
conn / as sysdba
set linesize 180
col CON_ID for 99
col TABLESPACE_NAME for A15
col "Free %" for A8

SELECT F.CON_ID, F.TABLESPACE_NAME,
       F.TOTALSPACE "Size MB",
       (F.TOTALSPACE - U.TOTALUSEDSPACE) "Free MB",
       ROUND(100 * ((F.TOTALSPACE - U.TOTALUSEDSPACE) / F.TOTALSPACE)) || '%' "Free %"
FROM
  (SELECT CON_ID, TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024) TOTALSPACE
   FROM CDB_DATA_FILES GROUP BY CON_ID, TABLESPACE_NAME) F,
  (SELECT CON_ID, TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024) TOTALUSEDSPACE
   FROM CDB_SEGMENTS GROUP BY CON_ID, TABLESPACE_NAME) U
WHERE F.TABLESPACE_NAME = U.TABLESPACE_NAME
AND   F.CON_ID = U.CON_ID
ORDER BY CON_ID;

-- Từ PDB1: chỉ xem PDB1 dùng DBA_ views
ALTER SESSION SET CONTAINER = PDB1;

SELECT F.TABLESPACE_NAME,
       F.TOTALSPACE "Size MB",
       (F.TOTALSPACE - U.TOTALUSEDSPACE) "Free MB"
FROM
  (SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024) TOTALSPACE
   FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME) F,
  (SELECT TABLESPACE_NAME, ROUND(SUM(BYTES)/1024/1024) TOTALUSEDSPACE
   FROM DBA_SEGMENTS GROUP BY TABLESPACE_NAME) U
WHERE F.TABLESPACE_NAME = U.TABLESPACE_NAME(+);
```

---

## Tóm tắt bài thực hành

| Quan sát | Kết luận |
|----------|----------|
| CREATE TABLE chưa INSERT | Không có segment |
| INSERT đầu tiên | Segment + Extent đầu tiên được tạo |
| DELETE toàn bộ rows | Segment VẪN GIỮ không gian cũ |
| MOVE TABLESPACE | Segment được compact, không gian giảm |
| OMF và thủ công | Có thể dùng song song trong một tablespace |
| CDB_DATA_FILES | Tất cả PDB, trừ PDB$SEED |
| DBA_DATA_FILES từ ROOT | Chỉ ROOT container |
| V$DATAFILE | Tất cả, bao gồm cả PDB$SEED |

---

## Câu hỏi ôn tập

**1. Tại sao sau khi DELETE toàn bộ rows, segment vẫn không được trả lại cho tablespace ngay?**
> **Trả lời:**
> Lệnh `DELETE` chỉ xóa các bản ghi dữ liệu bên trong các data blocks và đánh dấu các dòng đó là đã xóa (tạo ra các khoảng trống trong block), nhưng nó **không hạ vạch đỉnh High Water Mark (HWM)** của bảng và không giải phóng các Extents đã cấp phát. Toàn bộ các extents vẫn thuộc quyền sở hữu của Segment đó. Để thực sự thu hồi và trả lại không gian đĩa cho tablespace, bạn phải dùng lệnh `TRUNCATE TABLE` (giải phóng ngay lập tức), hoặc thực hiện `ALTER TABLE ... SHRINK SPACE` (yêu cầu bật row movement), hoặc `ALTER TABLE ... MOVE TABLESPACE`.

**2. Lệnh `ALTER TABLE ... MOVE TABLESPACE` có tác dụng phụ gì ngoài việc di chuyển sang tablespace mới?**
> **Trả lời:**
> Lệnh `ALTER TABLE ... MOVE` mang lại 2 tác động lớn:
> - **Tác dụng phụ tích cực (Chống phân mảnh):** Toàn bộ dữ liệu của bảng được đọc ra và ghi lại liên tục, nén chặt vào các block mới tinh, loại bỏ toàn bộ khoảng trống lãng phí do DELETE trước đó gây ra, đồng thời hạ vạch đỉnh High Water Mark về sát kích thước thực tế của dữ liệu.
> - **Tác dụng phụ nguy hiểm (Vô hiệu hóa Index):** Toàn bộ các **ROWID** (địa chỉ vật lý) của các dòng dữ liệu trong bảng đều bị thay đổi sau khi di chuyển. Hệ quả là **tất cả các Index gắn liền với bảng đó sẽ bị rơi vào trạng thái `UNUSABLE` (bị vô hiệu hóa)**. Mọi câu truy vấn dùng index sau đó sẽ báo lỗi hoặc phải quét toàn bộ bảng (Full Table Scan). DBA bắt buộc phải Rebuild lại toàn bộ Index (`ALTER INDEX ... REBUILD;`) ngay sau khi MOVE bảng. (Hoặc dùng cú pháp `MOVE ... UPDATE INDEXES;`).

**3. Từ CDB$ROOT, query `DBA_DATA_FILES` có trả về datafiles của PDB1 không? Vì sao?**
> **Trả lời:**
> **KHÔNG trả về.**
> View `DBA_DATA_FILES` là view cấp cục bộ của từng container. Khi bạn đang kết nối ở `CDB$ROOT`, `DBA_DATA_FILES` **chỉ hiển thị các datafiles thuộc về riêng Root container** (như `system01.dbf`, `sysaux01.dbf`, `undotbs01.dbf`, `users01.dbf` của Root). Nó hoàn toàn không hiển thị các file của PDB1 hay PDB$SEED.
> Để xem datafiles của tất cả các PDB từ Root, bạn bắt buộc phải dùng view **`CDB_DATA_FILES`** (view này có thêm cột `CON_ID` chỉ rõ file nào thuộc PDB nào).

**4. `CDB_DATA_FILES` có bao gồm datafiles của PDB$SEED không?**
> **Trả lời:**
> **KHÔNG bao gồm.**
> View `CDB_DATA_FILES` (và `DBA_DATA_FILES`) chỉ liệt kê các datafiles có thể ghi dữ liệu vĩnh viễn của Root và các User PDBs đang hoạt động. `PDB$SEED` (CON_ID = 2) là một PDB mẫu đặc biệt luôn luôn ở trạng thái **`READ ONLY`** và được quản lý theo cơ chế riêng. Để xem được datafiles của cả `PDB$SEED`, bạn phải truy vấn qua Dynamic Performance View **`V$DATAFILE`** (view này đọc từ Control File nên bao gồm toàn bộ mọi datafile tồn tại trong hệ thống).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/34-thuc-hanh-quan-ly-tablespace.md`
