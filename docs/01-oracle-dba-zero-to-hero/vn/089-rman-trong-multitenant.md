---
title: 'Bài 89: Sử dụng RMAN trong kiến trúc Multitenant (CDB/PDB)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/89-rman-trong-multitenant.md
---

# Bài 89: Sử dụng RMAN trong kiến trúc Multitenant (CDB/PDB)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Nêu rõ sự khác biệt giữa Backup & Recovery trên CDB và non-CDB.
- Sử dụng RMAN để sao lưu một CDB (Container Database) hoặc PDB (Pluggable Database).
- Thực hiện khôi phục hoàn toàn (Complete Recovery) và không hoàn toàn (Incomplete Recovery / PITR) trong CDB và PDB.
- Sử dụng các lệnh LIST và REPORT trong kiến trúc Multitenant.

## Tổng quan về Backup CDB
- Các lệnh RMAN sử dụng cho database non-CDB vẫn được giữ nguyên và áp dụng tương tự khi backup cho CDB.
- Khi bạn thực thi lệnh `BACKUP DATABASE` ở cấp độ Root, **toàn bộ dữ liệu của Root (CDB$ROOT) và TẤT CẢ các PDBs** bên trong đều được sao lưu.
- Quy trình bật chế độ ARCHIVELOG cho CDB hoàn toàn giống hệt như non-CDB.

```rman
-- Ví dụ sao lưu toàn bộ CDB
BACKUP AS BACKUPSET FORMAT '/backups/cdb%U' DATABASE TAG='FULLCDB';
```

## Sao lưu các PDBs (Pluggable Databases)
Bạn có hai cách để backup một PDB cụ thể:
1. **Kết nối vào Root (CDB$ROOT) và chỉ định tên PDB cần backup:**
   ```rman
   BACKUP AS BACKUPSET PLUGGABLE DATABASE pdb1, pdb2;
   BACKUP AS COPY PLUGGABLE DATABASE pdb1, pdb2;
   ```
2. **Kết nối trực tiếp vào PDB (thông qua user có quyền SYSBACKUP) và thực hiện backup:**
   ```rman
   rman target "'pdb1admin/password@PDB1 AS SYSBACKUP'"
   BACKUP DATABASE;
   ```
   *(Lưu ý: Khi kết nối trực tiếp vào PDB, RMAN sẽ giới hạn một số quyền. Bạn **không thể** backup, restore, hoặc xóa các file archived logs, đồng thời **không thể** cập nhật cấu hình mặc định của RMAN).*

## Sao lưu Tablespace trong Multitenant
- Nếu kết nối vào Root, bạn có thể sao lưu tablespace của một PDB bằng cách dùng cú pháp `tên_pdb:tên_tablespace`:
  ```rman
  BACKUP TABLESPACE users, pdb1:users;
  ```
- Nếu đã kết nối trực tiếp vào PDB đó, bạn gọi tên tablespace bình thường như non-CDB.

## Thực hiện Khôi phục Hoàn toàn (Complete Recovery)
**1. Khôi phục toàn bộ CDB (Giống hệt non-CDB):**
```rman
STARTUP MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
```
**2. Chỉ khôi phục CDB$ROOT:**
```rman
STARTUP MOUNT;
RESTORE DATABASE "CDB$ROOT";
RECOVER DATABASE "CDB$ROOT";
ALTER DATABASE OPEN;
```
**3. Khôi phục một PDB cụ thể (từ Root):**
```rman
ALTER PLUGGABLE DATABASE pdb1 CLOSE;
RESTORE PLUGGABLE DATABASE pdb1;
RECOVER PLUGGABLE DATABASE pdb1;
ALTER PLUGGABLE DATABASE pdb1 OPEN;
```
**4. Khôi phục PDB$SEED (Container mẫu):**
- Tương tự như khôi phục PDB thông thường, tuy nhiên khi hoàn tất phải mở Seed container bằng chế độ `READ ONLY`.

## Khôi phục theo thời điểm (PITR - Point-in-Time Recovery) cho PDBs
- Việc thực hiện PITR trên một PDB **không làm ảnh hưởng** đến các PDBs khác đang chạy trong cùng CDB.
- Quá trình này RMAN sẽ tự động khởi tạo một *Auxiliary Instance* (Instance phụ) ngầm bên dưới để khôi phục. Các file phụ tạm thời này mặc định lưu ở FRA hoặc thư mục chỉ định qua tham số `AUXILIARY DESTINATION`.

```rman
RUN {
  SET UNTIL TIME "TO_DATE('2022-10-01 07:00:00','yyyy-mm-dd hh24:mi:ss')";
  ALTER PLUGGABLE DATABASE pdb1 CLOSE;
  RESTORE PLUGGABLE DATABASE pdb1;
  RECOVER PLUGGABLE DATABASE pdb1 AUXILIARY DESTINATION '/u01/disk1';
  ALTER PLUGGABLE DATABASE pdb1 OPEN RESETLOGS; 
}
```

---
## Câu hỏi ôn tập

**Câu 1: Khi chạy lệnh `BACKUP DATABASE` ở chế độ kết nối vào CDB$ROOT, những thành phần nào sẽ được sao lưu?**
- **Trả lời:** Lệnh này sẽ sao lưu toàn bộ Root container (CDB$ROOT), Seed container (PDB$SEED), và TẤT CẢ các Pluggable Databases (PDBs) đang tồn tại bên trong nó.

**Câu 2: Một quản trị viên PDB (PDB Administrator) khi kết nối RMAN trực tiếp vào PDB của mình có quyền xóa Archive Logs cũ không?**
- **Trả lời:** Không. Việc quản lý, sao lưu hay xóa Archived Redo Logs là trách nhiệm của toàn cục hệ thống (thuộc quyền quản lý của CDB/Root). Quản trị viên cấp PDB không có quyền can thiệp vào các log này.

**Câu 3: Để khôi phục một PDB duy nhất bị lỗi, ta có cần phải Shutdown toàn bộ CDB không?**
- **Trả lời:** Không cần. Bạn chỉ cần đóng (CLOSE) riêng PDB bị lỗi đó, sau đó chạy `RESTORE PLUGGABLE DATABASE` và `RECOVER`, các PDB khác vẫn hoạt động phục vụ người dùng bình thường.

**Câu 4: Cú pháp để backup tablespace `USERS` nằm bên trong PDB có tên là `HR_PDB` khi đang kết nối ở Root là gì?**
- **Trả lời:** Câu lệnh là: `BACKUP TABLESPACE HR_PDB:USERS;`

**Câu 5: Tại sao thao tác PITR (Point-in-Time Recovery) trên một PDB lại yêu cầu một thư mục Auxiliary Destination?**
- **Trả lời:** Vì để đưa một PDB lùi về quá khứ mà không làm ảnh hưởng (đảo lộn SCN) của các PDB khác và CDB gốc, RMAN phải dựng một Instance tạm (Auxiliary Instance) ở một thư mục độc lập để bung dữ liệu quá khứ ra, chạy phục hồi, rồi "gắn" (plug) nó lại vào hệ thống. Thư mục phụ đó chứa các file tạm phục vụ quá trình này.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/89-rman-trong-multitenant.md`
