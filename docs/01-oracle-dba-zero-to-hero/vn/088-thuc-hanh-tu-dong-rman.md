---
title: 'Bài 88: Thực hành - Tự động hoá RMAN Backup Jobs'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/88-thuc-hanh-tu-dong-rman.md
---

# Bài 88: Thực hành - Tự động hoá RMAN Backup Jobs

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Tự động hóa các RMAN backup jobs trên nền tảng Linux (sử dụng Cron).
- Tự động hóa các RMAN backup jobs trên nền tảng Windows (sử dụng Task Scheduler).

## A. Tự động hóa trên nền tảng Linux (Cron)

**Kịch bản:** Bạn cần cấu hình hệ thống Linux tự động thực hiện **Level 0 Incremental Backup** vào lúc 22:00 ngày Thứ Sáu, và **Level 1 Incremental Backup** vào lúc 13:00 và 20:00 các ngày từ Thứ Hai đến Thứ Năm.

**1.** Khởi động Putty và đăng nhập vào `srv1` với quyền `oracle`.
**2.** Tạo một thư mục con tên là `scripts` trong thư mục home:
```bash
mkdir ~/scripts
```
**3.** Tạo file bash script cho bản sao lưu Level 0:
```bash
vi ~/scripts/rman_script0.sh
```
Chèn đoạn code bash sử dụng cấu trúc `<<EOF` (Here-Doc) sau:
```bash
#!/bin/bash
export ORACLE_SID=oradb
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/db_1
$ORACLE_HOME/bin/rman log=/home/oracle/scripts/rman0.log append <<EOF
connect target '/ AS SYSBACKUP';
set echo on;
run {
  BACKUP INCREMENTAL LEVEL 0 DATABASE TAG 'DBLVL0';
  DELETE NOPROMPT OBSOLETE;
}
exit;
EOF
```
*(Lưu và thoát vim: `:wq`)*
**4.** Đặt quyền thực thi cho script:
```bash
chmod 774 ~/scripts/rman_script0.sh
```
**5.** Tạo thêm một file script tương tự cho Level 1 (đổi tham số LEVEL 0 thành LEVEL 1) và cũng cấp quyền `chmod 774` cho nó.
**6.** Mở file cấu hình lịch trình `crontab` của user oracle:
```bash
crontab -e
```
**7.** Thêm hai dòng sau vào file (Nhấn phím `i` để vào chế độ Insert):
```bash
# Chạy script Level 0 lúc 22:00 ngày Thứ 6 (số 5)
00 22 * * 5 /bin/sh /home/oracle/scripts/rman_script0.sh >> /home/oracle/scripts/rman_lvl0.log 2>&1

# Chạy script Level 1 lúc 13:00 và 20:00 các ngày Thứ 2,3,4,5
00 13,20 * * 1,2,3,4 /bin/sh /home/oracle/scripts/rman_script1.sh >> /home/oracle/scripts/rman_lvl1.log 2>&1
```
*(Lưu và thoát vim bằng `:wq`. Vậy là cron đã được thiết lập).*
**8.** (Tùy chọn): Kiểm tra thủ công xem script có chạy tốt không:
```bash
/home/oracle/scripts/rman_script0.sh
```

## B. Lấy DBID và Trace Control File
Vì lý do an toàn (trong thảm họa lớn), ta nên lưu ra ngoài một bản DBID và cấu trúc text của Control file.
**9.** Trong SQL*Plus, gọi lệnh xuất cấu trúc control file:
```sql
ALTER DATABASE BACKUP CONTROLFILE TO TRACE;
```
*(Lệnh này sinh ra một file dạng `.trc` lưu lại cấu trúc bảng, tablespace, datafiles trong thư mục trace mặc định).*
**10.** Kiểm tra alert log để biết đường dẫn file trace vừa sinh ra:
```bash
tail /u01/app/oracle/diag/rdbms/oradb/oradb/trace/alert_oradb.log
```
Bạn hãy copy file đó cất vào một thư mục an toàn khác.

## C. Tự động hóa trên nền tảng Windows (Task Scheduler)

**Kịch bản:** Thực hiện backup database mỗi nửa đêm trên máy chủ Windows (`winsrv`).

**11.** Truy cập vào máy chủ Windows. Vào thư mục FRA: `D:\oracle\app\oraclesvc\fast_recovery_area\ORAWINDB`. Tạo thư mục `scripts`.
**12.** Tạo một file text tên là `rman.ora` (đây là file lệnh RMAN) và viết code sau:
```rman
connect target '/ AS SYSBACKUP';
SET ECHO ON;
run {
  BACKUP DATABASE TAG 'FULL_DB';
}
Exit;
```
**13.** Tạo một file tên là `rman.bat` (đây là file Batch Script cho Windows):
```bat
set ORACLE_SID=ORAWINDB
set ORACLE_HOME=D:\oracle\product\19.0.0\db_1
%ORACLE_HOME%\bin\rman cmdfile=D:\oracle\...\scripts\rman.ora log=D:\oracle\...\scripts\rman.log append
```
**14.** Mở ứng dụng **Task Scheduler** từ menu Start của Windows.
**15.** Chọn mục **Create Basic Task** ở khung bên phải.
- *Name:* Backup DB
- *Trigger:* Daily, chọn giờ 12:00 AM (nửa đêm).
- *Action:* Start a program. Chọn đường dẫn đến file `rman.bat` vừa tạo.
**16.** Sau khi tạo xong, click chuột phải vào task vừa tạo, chọn **Run** để thử nghiệm ngay lập tức.
**17.** Kiểm tra folder scripts xem file `rman.log` đã sinh ra chưa và có báo lỗi không. Mở folder FRA để xem backup files mới đã xuất hiện chưa.

---
## Câu hỏi ôn tập

**Câu 1: Câu lệnh `crontab -e` thực hiện chức năng gì?**
- **Trả lời:** Mở trình soạn thảo text (thường là vi/vim) để người dùng có thể chỉnh sửa cấu hình bảng lập lịch (cron table) cho riêng tài khoản hiện hành. Mỗi dòng thêm vào đại diện cho một tác vụ định kỳ.

**Câu 2: Ý nghĩa của cấu trúc `00 22 * * 5` trong Crontab là gì?**
- **Trả lời:** Cấu trúc có 5 vị trí: Phút (00), Giờ (22), Ngày trong tháng (*), Tháng (*), Ngày trong tuần (5 - tương đương Thứ Sáu). Vậy lệnh này có nghĩa là "Chạy vào lúc 22:00 mỗi Thứ Sáu hàng tuần".

**Câu 3: Ý nghĩa của đoạn `>> ... 2>&1` ở cuối lệnh crontab là gì?**
- **Trả lời:** `>>` giúp lưu Output tiêu chuẩn (STDOUT) vào cuối file log. Còn `2>&1` giúp gom toàn bộ các Lỗi (STDERR) đẩy chung vào cùng file STDOUT đó, đảm bảo ta không bỏ sót bất kỳ dòng báo lỗi nào do hệ thống ném ra.

**Câu 4: Tại sao trên Windows ta cần phải tách riêng 2 file `rman.bat` và `rman.ora`?**
- **Trả lời:** Dòng lệnh cmd/batch của Windows không hỗ trợ tốt cấu trúc `<<EOF` (Here-Doc) để viết trực tiếp lệnh RMAN vào cùng một file như bash shell của Linux. Do đó, việc tách 1 file Batch thực thi và 1 file Text rman riêng biệt sử dụng tham số `cmdfile=` là giải pháp truyền thống và an toàn nhất.

**Câu 5: File Trace Control File (Tạo ra bằng `BACKUP CONTROLFILE TO TRACE;`) có công dụng gì?**
- **Trả lời:** Khác với backup nhị phân (có thể bị hỏng/không tương thích), file trace lưu trữ các cấu trúc database dưới dạng mã lệnh text cơ bản (SQL script). Khi toàn bộ Control files bị mất và backup không thể hoạt động, bạn có thể chạy đoạn SQL trong file trace đó để tái tạo (Re-create) một Control file mới cứng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/88-thuc-hanh-tu-dong-rman.md`
