---
title: 'Bài 86: Thực hành - Khôi phục Phần II'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/86-thuc-hanh-recovery-p2.md
---

# Bài 86: Thực hành - Khôi phục Phần II

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Khôi phục file bị mất bằng cách chuyển (switching) trực tiếp sang Image Copies.
- Thực hiện Database Point-In-Time Recovery (DBPITR).

## A. Kịch bản 4: Khôi phục bằng Switch to Image Copies

**Giả định:** Database chạy ARCHIVELOG. Datafile bị mất, nhưng bạn có sẵn bản sao lưu Image Copy nằm trong Fast Recovery Area (FRA).

**1.** Khởi động Putty, đăng nhập `srv1` quyền `oracle`.
**2.** Mở RMAN và tạo một bản Full Backup ở dạng Image Copies:
```rman
rman target /
BACKUP AS COPY DATABASE TAG 'DB_COPY';
```
**3.** Giả lập có người dùng thao tác dữ liệu sau khi backup (bằng cách ép ghi archive log):
```sql
ALTER SYSTEM SWITCH LOGFILE;
```
**4.** Truy xuất ID và đường dẫn của tablespace USERS (trong SQL*Plus):
```sql
SELECT FILE#, NAME FROM V$DATAFILE 
WHERE TS# = (SELECT TS# FROM V$TABLESPACE WHERE NAME='USERS');
```
*(Giả sử kết quả trả về `FILE#` là 4).*
**5.** Xóa file vật lý để giả lập sự cố (Chạy ở OS terminal):
```bash
rm /u01/app/oracle/oradata/ORADB/datafile/*_users*.dbf
```
**6.** Trở lại RMAN, chạy lệnh `VALIDATE DATABASE;` để xác nhận file USERS đã bị mất.
**7.** Thực hiện Switch Image Copy. Bạn sẽ nhận thấy quá trình phục hồi này nhanh hơn rất nhiều so với dùng `RESTORE`:
```rman
ALTER DATABASE DATAFILE 4 OFFLINE;
SWITCH DATAFILE 4 TO COPY;
RECOVER DATAFILE 4;
ALTER DATABASE DATAFILE 4 ONLINE;
```
*(RMAN đã trực tiếp trỏ hệ thống sang đọc file Image Copy nằm trong FRA và cập nhật Control File).*
**8.** Chạy lại `VALIDATE DATABASE;` để kiểm tra, nó sẽ báo thành công.

## B. Kịch bản 5: Thực hiện Database Point-In-Time Recovery (DBPITR)

**Giả định:** Ai đó vừa vô tình chạy nhầm lệnh `DROP TABLE`. Bạn cần quay ngược thời gian database để lấy lại cái bảng đó.

**9.** Trong RMAN, lấy một bản Full Backup dưới dạng Backupset:
```rman
BACKUP DATABASE TAG 'DB_FULL';
```
**10.** Mở SQL*Plus, kết nối dưới quyền sysdba:
```bash
sqlplus / as sysdba
```
**11.** Ghi lại mốc thời gian **BÂY GIỜ** (thời điểm chưa bị lỗi). Đây chính là cái đích mà ta muốn cỗ máy thời gian quay về:
```sql
SELECT TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS') FROM DUAL;
```
*(Hãy copy chuỗi thời gian trả về, ví dụ `09-SEP-2026 17:30:00`)*.
**12.** Thực hiện sự phá hoại giả lập:
```sql
ALTER SYSTEM SWITCH LOGFILE;
DROP TABLE HR.EMPLOYEES CASCADE CONSTRAINTS;
ALTER SYSTEM SWITCH LOGFILE;
```
**13.** Thoát SQL*Plus, truy cập RMAN. Khởi động lại database ở chế độ MOUNT (bắt buộc đối với DBPITR):
```rman
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
```
**14.** Sử dụng khối lệnh `RUN` kết hợp `SET UNTIL TIME` để chỉ định RMAN khôi phục về đúng cái giây phút mà bạn đã lưu ở Bước 11:
```rman
ALTER SESSION SET NLS_DATE_FORMAT='DD-MON-YYYY HH24:MI:SS';

RUN { 
  SET UNTIL TIME '09-SEP-2026 17:30:00';
  RESTORE DATABASE;
  RECOVER DATABASE;
}
```
**15.** Mở lại database bằng `RESETLOGS` (Bắt buộc vì bạn đã thay đổi dòng thời gian của database):
```rman
ALTER DATABASE OPEN RESETLOGS;
```
**16.** Kiểm tra lại xem bảng `HR.EMPLOYEES` đã sống lại chưa:
```sql
SELECT COUNT(*) FROM HR.EMPLOYEES;
```
*(Nếu count trả về số lượng nhân viên như cũ, chúc mừng bạn đã "quay ngược thời gian" thành công!)*

---
## Câu hỏi ôn tập

**Câu 1: Câu lệnh `ALTER DATABASE DATAFILE 4 OFFLINE;` có làm database bị gián đoạn toàn bộ không?**
- **Trả lời:** Không. Câu lệnh này chỉ khoanh vùng cô lập riêng datafile số 4, các user truy cập vào các datafile hay tablespace khác vẫn hoạt động bình thường, không làm gián đoạn toàn bộ hệ thống.

**Câu 2: Tại sao trong Kịch bản 4, ta phải dùng lệnh `SWITCH DATAFILE 4 TO COPY` thay vì `RESTORE`?**
- **Trả lời:** Để rút ngắn tối đa thời gian phục hồi. Lệnh `SWITCH` không copy file mà chỉ làm thay đổi siêu dữ liệu (metadata) trên Control File, trỏ thẳng tới file Image Copy đã có sẵn.

**Câu 3: DBPITR (Kịch bản 5) có thể áp dụng cho việc khôi phục một bảng dữ liệu duy nhất mà không ảnh hưởng tới toàn hệ thống không?**
- **Trả lời:** Không. DBPITR quay ngược thời gian của TOÀN BỘ database. Nếu bạn chỉ muốn cứu một bảng duy nhất mà không làm ảnh hưởng những bảng khác, bạn nên dùng Flashback Table thay vì RMAN DBPITR.

**Câu 4: Mốc thời gian thiết lập trong `SET UNTIL TIME` cần tuân theo định dạng (format) nào?**
- **Trả lời:** Chuỗi thời gian phải khớp (match) tuyệt đối với tham số môi trường `NLS_DATE_FORMAT`. Việc chạy lệnh `ALTER SESSION SET NLS_DATE_FORMAT='...'` trước khi thực thi là cách an toàn nhất để tránh lỗi sai định dạng ngày tháng.

**Câu 5: Nếu sau khi `OPEN RESETLOGS`, tôi nhận ra mình đã `SET UNTIL TIME` sai giờ (mới quay về giữa chừng, chưa lấy lại được dữ liệu). Tôi phải làm sao?**
- **Trả lời:** Vì bạn đã `RESETLOGS` và tạo một Incarnation mới, nếu bạn muốn dùng DBPITR quay lại thêm một lần nữa xa hơn, bạn phải dùng lệnh `RESET DATABASE TO INCARNATION <ID_cũ>` ở chế độ MOUNT để báo cho RMAN biết là bạn muốn lội về cái dòng thời gian trước đó.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/86-thuc-hanh-recovery-p2.md`
