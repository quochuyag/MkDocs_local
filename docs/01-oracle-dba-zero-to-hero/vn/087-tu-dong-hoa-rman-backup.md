---
title: 'Bài 87: Tự động hoá RMAN Backup Jobs'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/87-tu-dong-hoa-rman-backup.md
---

# Bài 87: Tự động hoá RMAN Backup Jobs

## Mục tiêu
Trong bài học này, bạn sẽ học cách thiết lập cấu hình cơ bản để:
- Tự động hóa lịch trình sao lưu (backup jobs) bằng RMAN trên cả Linux và Windows.

## Tổng quan về Tự động hóa RMAN (Automating RMAN)
- Việc sao lưu (Backup) là tác vụ cực kỳ quan trọng và phải được thực hiện hàng ngày (hoặc hàng giờ tùy nghiệp vụ). Bạn không thể lúc nào cũng thức đến nửa đêm để gõ lệnh RMAN thủ công.
- RMAN tự bản thân nó chỉ là một công cụ dòng lệnh (CLI). Nó **không có bộ đếm thời gian (scheduler) tích hợp sẵn** để tự động chạy.
- Để tự động hóa RMAN, ta phải kết hợp nó với các hệ thống lập lịch của Hệ điều hành (OS Scheduler) hoặc các phần mềm quản trị:
  - **Trên Linux/Unix:** Sử dụng `cron` (chỉnh sửa `crontab`).
  - **Trên Windows:** Sử dụng công cụ `Task Scheduler`.
  - **Sử dụng phần mềm hãng thứ 3:** Oracle Enterprise Manager (OEM), BMC Control-M, IBM Tivoli...

## Cơ chế tạo Script (Kịch bản) RMAN
Để thiết lập tự động hóa, quy trình chung luôn tuân theo 3 bước:
1. Viết một file script chứa tập hợp các câu lệnh RMAN (ví dụ: `script.rman` hoặc `.rcv`).
2. Viết một file shell script (`.sh` trên Linux) hoặc batch file (`.bat` trên Windows) để thiết lập biến môi trường (ORACLE_SID, ORACLE_HOME) rồi gọi file script RMAN trên.
3. Cấu hình OS Scheduler để chạy file shell/batch đó theo lịch trình.

### 1. Ví dụ cấu trúc RMAN Script
Tạo một file text (vd: `my_backup.rman`):
```rman
connect target '/ AS SYSBACKUP';
RUN {
  BACKUP DATABASE TAG 'NIGHTLY_FULL';
  BACKUP ARCHIVELOG ALL DELETE ALL INPUT;
  DELETE NOPROMPT OBSOLETE;
}
EXIT;
```
*(Từ khóa `NOPROMPT` rất quan trọng. Khi chạy tự động, RMAN không có người thật ở đó để nhấn phím 'Y' xác nhận, nên NOPROMPT bắt buộc RMAN tự động đồng ý xóa các file obsolete).*

### 2. Ví dụ cấu trúc Shell/Batch Script
**Trên Linux (`run_backup.sh`):**
```bash
#!/bin/bash
export ORACLE_SID=oradb
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/db_1

# Gọi rman, nạp file lệnh bằng cmdfile, xuất log ra file rman.log
$ORACLE_HOME/bin/rman cmdfile=/home/oracle/scripts/my_backup.rman log=/home/oracle/scripts/rman.log append
```

**Trên Windows (`run_backup.bat`):**
```bat
set ORACLE_SID=ORAWINDB
set ORACLE_HOME=D:\oracle\product\19.0.0\db_1
%ORACLE_HOME%\bin\rman cmdfile=C:\scripts\my_backup.rman log=C:\scripts\rman.log append
```

## Các lệnh thường dùng khi tự động hóa
- `cmdfile=<đường_dẫn_file>`: Nói cho RMAN biết hãy đọc và thực thi các lệnh từ file này thay vì chờ gõ phím.
- `log=<đường_dẫn_file>`: Xuất kết quả thực thi ra file text để quản trị viên có thể kiểm tra vào sáng hôm sau.
- `append`: Nếu có file log cũ, hãy viết nối tiếp (append) vào cuối file thay vì ghi đè (overwrite) xóa mất log hôm qua.

---
## Câu hỏi ôn tập

**Câu 1: RMAN có cung cấp chức năng hẹn giờ (Schedule) nội bộ để tự động backup không?**
- **Trả lời:** Không. RMAN chỉ là công cụ dòng lệnh (client). Để hẹn giờ chạy, bắt buộc phải sử dụng trình lập lịch của hệ điều hành (crontab trên Linux hoặc Task Scheduler trên Windows).

**Câu 2: Tại sao việc thiết lập các biến môi trường (`ORACLE_SID`, `ORACLE_HOME`) trong Shell/Batch script là bắt buộc khi tự động hóa?**
- **Trả lời:** Bởi vì OS Scheduler (như Cron) chạy script trong một phiên làm việc (shell session) ẩn, trống rỗng, không tự động nạp profile `.bash_profile` của user. Không có hai biến này, cron sẽ báo lỗi "rman: command not found" hoặc không biết kết nối vào database nào.

**Câu 3: Mục đích của tùy chọn `append` khi cấu hình file log cho RMAN là gì?**
- **Trả lời:** Giúp ghi nối tiếp các kết quả log mới vào phần cuối của file log đã có. Nhờ đó bạn giữ lại được lịch sử báo cáo của nhiều ngày trước đó, tránh việc bị ghi đè xóa sạch sau mỗi lần chạy job.

**Câu 4: Tùy chọn `NOPROMPT` có chức năng gì trong các lệnh xóa (`DELETE`) của RMAN?**
- **Trả lời:** Khi tự động hóa, thao tác lệnh là không có tính tương tác. `NOPROMPT` chặn RMAN đưa ra thông báo "Do you really want to delete...? (YES/NO)", giúp kịch bản tiếp tục chạy mà không bị treo mãi mãi chờ người nhấn phím.

**Câu 5: RMAN `cmdfile` có thể được thay thế bằng phương pháp nào khác trong bash script không?**
- **Trả lời:** Có, trong Linux bạn có thể sử dụng cấu trúc tài liệu Here-Doc (`<<EOF ... EOF`) để nhúng trực tiếp lệnh RMAN vào ngay trong file bash script mà không cần tạo thêm file `.rman` rời bên ngoài.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/87-tu-dong-hoa-rman-backup.md`
