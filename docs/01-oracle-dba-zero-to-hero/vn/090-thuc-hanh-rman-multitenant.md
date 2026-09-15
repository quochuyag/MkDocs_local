---
title: 'Bài 90: Thực hành - Sử dụng RMAN trong kiến trúc Multitenant'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/90-thuc-hanh-rman-multitenant.md
---

# Bài 90: Thực hành - Sử dụng RMAN trong kiến trúc Multitenant

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Sử dụng RMAN tạo bản backup cho CDB và các PDB.
- Khôi phục lỗi mất Datafile hệ thống của CDB (CDB$ROOT).
- Khôi phục lỗi mất Datafile của PDB mẫu (PDB$SEED).
- Khôi phục lỗi mất Datafile người dùng bên trong một PDB.
- Thực hiện Point-In-Time Recovery (PITR) cho một PDB.

## A. Kịch bản 1: Khôi phục CDB$ROOT

**Giả định:** File `SYSTEM` của CDB$ROOT vô tình bị xóa mất.

**1.** Vào RMAN, lấy một bản backup toàn bộ CDB:
```rman
rman target /
BACKUP DATABASE TAG 'FULL_DB';
```
**2.** Dùng SQL lấy đường dẫn file SYSTEM của CDB$ROOT (nơi FILE# = 1) rồi xóa nó bằng lệnh hệ điều hành:
```bash
rm -f /u01/app/oracle/oradata/ORADB/datafile/*_system_*.dbf
```
**3.** Vào RMAN xác thực lỗi, bạn sẽ thấy datafile 1 bị báo thiếu:
```rman
VALIDATE DATABASE;
```
**4.** Tiến hành khôi phục. Ở đây, khôi phục duy nhất 1 file bị lỗi sẽ nhanh hơn là restore toàn bộ ROOT:
```rman
STARTUP FORCE MOUNT;
RESTORE DATAFILE 1;
RECOVER DATAFILE 1;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
```

## B. Kịch bản 2: Khôi phục PDB$SEED

**Giả định:** Một datafile của PDB$SEED bị xóa mất. (Chú ý: PDB$SEED luôn có `CON_ID=2`).

**5.** Xác định và xóa một file của PDB$SEED.
**6.** Trong RMAN, đóng Seed lại và thực hiện khôi phục toàn bộ PDB$SEED, sau đó bắt buộc mở lại ở chế độ `READ ONLY`:
```rman
ALTER PLUGGABLE DATABASE "PDB$SEED" CLOSE;
RESTORE PLUGGABLE DATABASE "PDB$SEED";
RECOVER PLUGGABLE DATABASE "PDB$SEED";
ALTER PLUGGABLE DATABASE "PDB$SEED" OPEN READ ONLY;
```
*(Ghi chú: Thao tác này không cần Shutdown CDB. Người dùng ở các PDB khác vẫn làm việc bình thường).*

## C. Kịch bản 3: Khôi phục một non-system datafile trong PDB

**Giả định:** File thuộc tablespace `SOETBS` của PDB1 bị xóa.

**7.** Giả lập xóa file `.dbf` thuộc tablespace SOETBS của `PDB1`.
**8.** Kết nối RMAN **trực tiếp vào PDB1** thông qua user SYS:
```bash
rman target sys/password@pdb1
```
**9.** Offline tablespace bị lỗi, restore, recover và online lại (hoàn toàn thao tác nội bộ trong PDB):
```rman
ALTER TABLESPACE soetbs OFFLINE IMMEDIATE;
RESTORE TABLESPACE soetbs;
RECOVER TABLESPACE soetbs;
ALTER TABLESPACE soetbs ONLINE;
```

## D. Kịch bản 4: PITR (Point-in-Time Recovery) cho PDB

**Giả định:** Một user trong PDB1 vô tình `DROP TABLE` dữ liệu quan trọng. Bạn phải lùi riêng PDB1 về thời điểm trước đó.

**10.** Trong SQL*Plus (kết nối PDB1), tạo 1 table tạm. Ghi chú lại thời gian hiện tại, sau đó `DROP` table đó đi.
```sql
ALTER SESSION SET CONTAINER = PDB1;
CREATE TABLE SYSTEM.MYDATA AS SELECT * FROM DUAL;
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD:HH24:MI:SS') FROM DUAL;
-- Ghi lại thời gian, ví dụ: 2026-09-10:14:00:00
DROP TABLE SYSTEM.MYDATA;
```
**11.** Kết nối RMAN vào cấp độ ROOT (`rman target /`).
**12.** Đóng PDB1, khôi phục PDB1 về thời điểm đã ghi chép, nhớ cung cấp thư mục phụ `AUXILIARY DESTINATION`:
```rman
ALTER PLUGGABLE DATABASE pdb1 CLOSE;

RESTORE PLUGGABLE DATABASE pdb1 
UNTIL TIME "TO_DATE('2026-09-10:14:00:00','yyyy-mm-dd:hh24:mi:ss')";

RECOVER PLUGGABLE DATABASE pdb1 
UNTIL TIME "TO_DATE('2026-09-10:14:00:00','yyyy-mm-dd:hh24:mi:ss')"
AUXILIARY DESTINATION '/media/sf_staging/';

ALTER PLUGGABLE DATABASE pdb1 OPEN RESETLOGS;
```
**13.** Vào lại PDB1 kiểm tra, bảng `SYSTEM.MYDATA` đã được khôi phục thành công.

---
## Câu hỏi ôn tập

**Câu 1: Khi khôi phục xong PDB$SEED, trạng thái OPEN cuối cùng phải là gì?**
- **Trả lời:** Phải là `READ ONLY`. Seed container là một bản mẫu chuẩn (template) đóng băng, không cho phép ai ghi đè dữ liệu lên nó.

**Câu 2: Lệnh `STARTUP FORCE MOUNT` trong Kịch bản 1 có tác dụng gì?**
- **Trả lời:** Lệnh này kết hợp 2 thao tác: Ép tắt khẩn cấp database (giống `SHUTDOWN ABORT`) và lập tức khởi động lại nó lên trạng thái `MOUNT`. Dùng khi file SYSTEM hỏng khiến database không thể tắt bình thường.

**Câu 3: Trong Kịch bản 3, việc kết nối `rman target sys/password@pdb1` có nghĩa là gì?**
- **Trả lời:** Đây là cách kết nối RMAN trực tiếp vào một PDB cụ thể (Local PDB Backup/Recovery) thay vì kết nối vào CDB$ROOT. Tại đây người dùng chỉ có phạm vi thao tác giới hạn nội trong PDB đó.

**Câu 4: Thư mục `/media/sf_staging/` ở Kịch bản 4 đóng vai trò gì?**
- **Trả lời:** Nó đóng vai trò là `AUXILIARY DESTINATION`. RMAN sử dụng thư mục tạm này để dựng lên một instance phụ, bung các file backup ra, chạy phục hồi dữ liệu về quá khứ rồi mới gắn PDB đó lại vào hệ thống chính.

**Câu 5: Lệnh `ALTER PLUGGABLE DATABASE pdb1 OPEN RESETLOGS;` có ảnh hưởng đến PDB2 hay CDB$ROOT không?**
- **Trả lời:** Hoàn toàn không. Cú pháp này chỉ khởi tạo lại (reset) dòng thời gian (incarnation) của riêng PDB1 mà không hề làm gián đoạn hay thay đổi SCN của CDB$ROOT hay bất kỳ PDB nào khác.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/90-thuc-hanh-rman-multitenant.md`
