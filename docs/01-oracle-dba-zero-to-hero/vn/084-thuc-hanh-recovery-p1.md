---
title: 'Bài 84: Thực hành - Thực hiện Khôi phục (Recovery) Phần I'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/84-thuc-hanh-recovery-p1.md
---

# Bài 84: Thực hành - Thực hiện Khôi phục (Recovery) Phần I

## Mục tiêu
Trong bài thực hành này, bạn sẽ thực hiện quy trình khôi phục hoàn toàn cho các kịch bản sau:
- Khôi phục toàn bộ database ở chế độ NOARCHIVELOG.
- Khôi phục toàn bộ database ở chế độ ARCHIVELOG.
- Khôi phục một datafile bị mất của user tablespace.

## A. Kịch bản 1: Khôi phục toàn bộ database (NOARCHIVELOG)

**Giả định:** Database chạy NOARCHIVELOG. Bạn vô tình bị mất một datafile quan trọng thuộc tablespace SYSTEM.

**1.** Mở terminal và đăng nhập vào `srv1` quyền `oracle`.
**2.** Kết nối RMAN và lấy một bản full backup trước khi thực hành:
```bash
rman target /
BACKUP DATABASE;
```
**3.** Thoát RMAN và giả lập sự cố xóa mất file `SYSTEM`:
```bash
rm /u01/app/oracle/oradata/ORADB/datafile/*_system_*.dbf
```
**4.** Truy cập SQL*Plus và thử truy vấn dữ liệu từ khóa hệ thống:
```sql
sqlplus / as sysdba
SELECT * FROM DBA_OBJECTS;
```
*(Bạn sẽ nhận được lỗi ORA-01116, ORA-01110 do không tìm thấy file SYSTEM).*
**5.** Kiểm tra nội dung alert log (ở cuối file) để xem thông báo lỗi chi tiết:
```bash
vi /u01/app/oracle/diag/rdbms/oradb/oradb/trace/alert_oradb.log
```
**6.** Vì không thể shutdown sạch một database mất file SYSTEM, hãy ép tắt (abort) và mở ở chế độ MOUNT:
```sql
SHUTDOWN ABORT;
STARTUP MOUNT;
EXIT;
```
**7.** Vào RMAN, khôi phục database và mở lại bằng tùy chọn `RESETLOGS`:
```rman
rman target /
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;
```
*(Lưu ý: Vì database ở chế độ NOARCHIVELOG, toàn bộ dữ liệu từ sau lúc backup sẽ bị mất. Tùy chọn RESETLOGS là bắt buộc).*

## B. Kịch bản 2: Khôi phục toàn bộ database (ARCHIVELOG)

**Giả định:** Database chạy ARCHIVELOG. Tất cả datafiles bị mất.

**8.** Bật chế độ ARCHIVELOG cho database:
```sql
sqlplus / as sysdba
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```
**9.** Lấy một bản backup toàn bộ bằng RMAN:
```rman
rman target /
BACKUP DATABASE TAG 'FULL_DB';
```
**10.** Xóa datafile SYSTEM để giả lập sự cố:
```bash
rm /u01/app/oracle/oradata/ORADB/datafile/*_system_*.dbf
```
**11.** Tắt nóng và mount database:
```sql
sqlplus / as sysdba
SHUTDOWN ABORT;
STARTUP MOUNT;
```
**12.** Xác thực backup trước khi restore để đảm bảo file backup khả dụng:
```rman
rman target /
RESTORE DATABASE VALIDATE;
```
**13.** Khôi phục database. Khác với Kịch bản 1, lần này bạn mở database bình thường mà KHÔNG CẦN `RESETLOGS`:
```rman
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
```
*(Nhờ chế độ ARCHIVELOG, database phục hồi hoàn chỉnh đến thời điểm hiện tại, không bị mất dữ liệu).*

## C. Kịch bản 3: Khôi phục Tablespace của người dùng

**Giả định:** Database đang chạy (OPEN). Datafile của tablespace `USERS` bị mất.

**14.** Lấy một bản backup riêng cho tablespace USERS:
```rman
BACKUP TABLESPACE users TAG 'FULL_USERS';
```
**15.** Xóa datafile của tablespace USERS để giả lập sự cố:
```bash
rm /u01/app/oracle/oradata/ORADB/datafile/*_users*.dbf
```
**16.** Trong RMAN, chạy lệnh kiểm tra lỗi:
```rman
VALIDATE TABLESPACE USERS;
```
*(Kết quả sẽ báo ORA-01122 vì không tìm thấy file).*
**17.** Đưa riêng tablespace bị lỗi về OFFLINE, sau đó khôi phục và đưa trở lại ONLINE mà không cần tắt Database:
```rman
ALTER TABLESPACE users OFFLINE IMMEDIATE;
RESTORE TABLESPACE users;
RECOVER TABLESPACE users;
ALTER TABLESPACE users ONLINE;
```

---
## Câu hỏi ôn tập

**Câu 1: Tại sao phải sử dụng `SHUTDOWN ABORT` thay vì `SHUTDOWN IMMEDIATE` khi giả lập mất datafile SYSTEM?**
- **Trả lời:** Khi mất tablespace SYSTEM, database không thể thực hiện các bước ghi checkpoint lên data dictionary một cách bình thường. Nếu dùng `IMMEDIATE`, database sẽ bị treo.

**Câu 2: Tại sao trong kịch bản ARCHIVELOG, bạn lại không dùng lệnh `ALTER DATABASE OPEN RESETLOGS`?**
- **Trả lời:** Vì ở chế độ ARCHIVELOG, RMAN có thể áp dụng toàn bộ archived redo logs và online redo logs để "roll forward" dữ liệu đến đúng khoảnh khắc hiện tại (thời điểm trước khi bị hỏng). Vì SCN vẫn ở trạng thái hiện tại, bạn chỉ cần mở bình thường bằng `OPEN`.

**Câu 3: Mục đích của việc dùng `RESTORE DATABASE VALIDATE;` là gì?**
- **Trả lời:** Dùng để kiểm tra trước xem các file backup có tồn tại vật lý và hoàn toàn nguyên vẹn (không bị lỗi) để phục vụ cho thao tác `RESTORE` hay không. Việc này giảm rủi ro lỗi giữa chừng khi đang chạy `RESTORE`.

**Câu 4: Có thể khôi phục tablespace USERS khi database vẫn đang OPEN không?**
- **Trả lời:** Có. Chỉ cần đưa riêng tablespace USERS đó vào trạng thái `OFFLINE IMMEDIATE` trước khi khôi phục, sau đó đưa `ONLINE` trở lại. Người dùng ở các tablespace khác không bị ảnh hưởng.

**Câu 5: Tại sao sau khi thực hiện Khôi phục trong NOARCHIVELOG, incarnation history lại bị thay đổi?**
- **Trả lời:** Vì thao tác `OPEN RESETLOGS` đã thiết lập lại chuỗi sequence (log sequence number) bắt đầu lại từ 1, tạo ra một "kiếp mới" (incarnation) của database để tránh xung đột SCN trong tương lai.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/84-thuc-hanh-recovery-p1.md`
