---
title: 'Bài 35: Quản lý Data Files'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/35-quan-ly-data-files.md
---

# Bài 35: Quản lý Data Files

## Mục tiêu
Trong bài này, bạn sẽ học cách thực hiện các thao tác sau:
- **Thay đổi kích thước** (resize) data files
- **Thay đổi trạng thái** (online/offline) data files
- **Đổi tên và di chuyển** data files
- **Xóa** data files

---

## Quan hệ Logical và Physical

```
Database
 └── Tablespace (Logical)
      └── Data file (Physical)
           └── OS block
 └── Segment (Logical)
      └── Extent
           └── Data block
```

---

## 1. Thay đổi kích thước Data File thủ công

Data files có thể được **tăng hoặc giảm** kích thước thủ công.

### Khi nào cần resize?
- Sửa lại ước lượng tablespace ban đầu bị sai
- Tăng kích thước datafile thay vì thêm file mới
- Chuẩn bị trước cho việc nạp dữ liệu lớn

### Cú pháp:
```sql
ALTER DATABASE DATAFILE '<data file>' RESIZE <n>M|G|T;
```

### Ví dụ:
```sql
ALTER DATABASE DATAFILE
  '/u01/oracle/oradata/ORADB/datafile/o1_mf_system_k7.dbf'
  RESIZE 100M;
```

---

## 2. Thay đổi trạng thái Data File (Online/Offline)

### Khi nào cần đưa datafile về Offline?
- Muốn đổi tên hoặc di chuyển datafile (không bắt buộc)
- Backup offline cho datafile đó
- Datafile bị mất hoặc bị hỏng — phải đưa offline trước khi mở database

### Cú pháp:
```sql
-- Thay đổi trạng thái một datafile
ALTER DATABASE DATAFILE '<datafile>' ONLINE | OFFLINE [FOR DROP];

-- Thay đổi toàn bộ datafile trong tablespace
ALTER TABLESPACE ... DATAFILE {ONLINE|OFFLINE}
ALTER TABLESPACE ... TEMPFILE {ONLINE|OFFLINE}
```

> **Lưu ý**: Tùy chọn `FOR DROP` dùng khi database đang chạy ở chế độ **NOARCHIVELOG**. Nó đánh dấu datafile để xóa và không thể đưa lại online.

---

## 3. Đổi tên và Di chuyển Data File khi đang Online

### Khi nào cần rename/relocate?
- Chuyển datafiles từ loại storage này sang loại khác
- Di chuyển từ vị trí này sang vị trí khác (kể cả ASM diskgroups)

**Online rename/relocation** = datafile được di chuyển trong khi users vẫn đang truy cập vào nó.

### Cú pháp:
```sql
ALTER DATABASE
  MOVE DATAFILE '<old name>' TO '<new name>' [REUSE] [KEEP];
```

| Tùy chọn | Ý nghĩa |
|----------|---------|
| `REUSE`  | Ghi đè file đích nếu đã tồn tại |
| `KEEP`   | Giữ lại file cũ, chỉ copy sang vị trí mới |

### Các ví dụ:

```sql
-- Đổi tên datafile trong cùng vị trí:
ALTER DATABASE MOVE DATAFILE '/u01/oracle/rbdb1/user1.dbf'
  TO '/u01/oracle/rbdb1/user01.dbf';

-- Di chuyển datafile sang vị trí khác:
ALTER DATABASE MOVE DATAFILE '/u01/oracle/rbdb1/user1.dbf'
  TO '/u02/oracle/rbdb1/user1.dbf';

-- Copy datafile sang vị trí khác (giữ nguyên bản gốc):
ALTER DATABASE MOVE DATAFILE '/u01/oracle/rbdb1/user1.dbf'
  TO '/u02/oracle/rbdb1/user1.dbf' KEEP;
```

---

## 4. Đổi tên và Di chuyển Data File khi Offline

Khi datafile đã được đưa về trạng thái **offline sạch** (cleanly offline):

### Các bước thực hiện:

1. **Đảm bảo** datafile đang ở trạng thái offline
2. **Di chuyển/đổi tên** datafile bằng lệnh OS
3. **Cập nhật** thông tin vào database dictionary:
   ```sql
   ALTER DATABASE RENAME FILE '..' TO '..';
   -- hoặc:
   ALTER TABLESPACE <tbs-name> RENAME DATAFILE '..' TO '..';
   ```
4. **Áp dụng redo logs** (nếu DB đang mở):
   ```sql
   RECOVER DATAFILE '...';
   ```
5. **Đưa datafile về online**
6. **Backup** database

---

## 5. Xóa Data File

### Điều kiện để xóa:
- Datafile phải **rỗng** (không có extent nào của segment trong đó)
- Datafile duy nhất trong tablespace **không thể xóa** — phải drop cả tablespace

### Cú pháp:
```sql
-- Xóa datafile thông thường:
ALTER TABLESPACE <tbs-name> DROP DATAFILE | TEMPFILE '...';

-- Xóa tempfile:
ALTER DATABASE TEMPFILE '...' DROP INCLUDING DATAFILES;
```

> **Lưu ý**: Khi xóa, datafile sẽ bị xóa khỏi data dictionary, control files **và xóa vật lý** trên đĩa.

---

## Tổng kết

| Thao tác | Lệnh chính |
|----------|-----------|
| Resize datafile | `ALTER DATABASE DATAFILE ... RESIZE` |
| Offline/Online | `ALTER DATABASE DATAFILE ... OFFLINE/ONLINE` |
| Di chuyển online | `ALTER DATABASE MOVE DATAFILE ... TO ...` |
| Rename offline | `ALTER DATABASE RENAME FILE ... TO ...` |
| Xóa datafile | `ALTER TABLESPACE ... DROP DATAFILE ...` |


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/35-quan-ly-data-files.md`
