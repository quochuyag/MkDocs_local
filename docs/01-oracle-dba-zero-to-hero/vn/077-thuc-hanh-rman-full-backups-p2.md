---
title: 'Bài 77: Thực hành - Thực hiện RMAN Full Backups - Phần II'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/77-thuc-hanh-rman-full-backups-p2.md
---

# Bài 77: Thực hành - Thực hiện RMAN Full Backups - Phần II

## Mục tiêu
Trong bài thực hành này, bạn sẽ thực hiện các tác vụ sau:
- Kích hoạt tính năng Control file Autobackup.
- Nén bản sao lưu (Compressing backup sets).
- Khởi tạo Image Copies bằng RMAN.

## A. Kích hoạt Control File Autobackup

**1.** Mở terminal (Putty) và đăng nhập vào `srv1` với quyền `oracle`.

**2.** Truy cập RMAN và kết nối với target database:
```bash
rman target "'/ as sysbackup'"
```

**3.** Kiểm tra trạng thái cấu hình hiện tại của Autobackup bằng lệnh:
```rman
SHOW CONTROLFILE AUTOBACKUP;
```
*(Có thể mặc định nó đã được ON hoặc OFF tùy phiên bản).*

**4.** Bật tính năng Autobackup của Control file:
```rman
CONFIGURE CONTROLFILE AUTOBACKUP ON;
```

**5.** Thực hiện sao lưu tablespace `USERS` để kích hoạt RMAN tự động tạo autobackup:
```rman
BACKUP TABLESPACE users;
```

**6.** Liệt kê các bản backup của control file để xác nhận:
```rman
LIST BACKUP OF CONTROLFILE;
```
*(Bạn sẽ thấy một bản backup riêng rẽ của Control file và SPFILE vừa được sinh ra cùng lúc với bản backup của users tablespace).*

## B. Nén bản sao lưu (Compressed Backup sets)

**7.** Kiểm tra dung lượng hiện tại của ổ chứa backup (ví dụ phân vùng chứa FRA). Bạn có thể mở một terminal mới và gõ:
```bash
df -h
```
*(Ghi chú lại dung lượng trống để so sánh sau)*.

**8.** Trong RMAN, tiến hành backup toàn bộ database ở dạng không nén (để lấy dữ liệu so sánh):
```rman
BACKUP DATABASE TAG 'no_comp_db';
```

**9.** Khi quá trình hoàn tất, ghi chú lại thời gian chạy (ví dụ mất 1 phút 30 giây).

**10.** Tiếp tục backup toàn bộ database, nhưng lần này sử dụng chế độ **nén**:
```rman
BACKUP AS COMPRESSED BACKUPSET DATABASE TAG 'comp_db';
```

**11.** Quan sát và ghi chú lại thời gian chạy của lệnh backup nén (ví dụ mất 2 phút 15 giây).
*(Quá trình backup nén thường tốn nhiều thời gian hơn do CPU phải xử lý nén dữ liệu).*

**12.** Liệt kê và xem báo cáo tổng quan về kích thước của các bản backup:
```rman
LIST BACKUP OF DATABASE SUMMARY;
```
*(So sánh cột `Size` giữa bản backup có tag `NO_COMP_DB` và bản có tag `COMP_DB`. Bản nén có kích thước nhỏ hơn đáng kể).*

## C. Tạo Image Copies

**13.** Tạo một bản Image Copy cho tablespace `USERS`:
```rman
BACKUP AS COPY TABLESPACE users;
```
*(Image copies là bản sao y hệt từng byte của datafile).*

**14.** Liệt kê tất cả các bản image copy hiện có trong RMAN repository:
```rman
LIST COPY OF DATABASE;
```

**15.** Mở một terminal Linux khác và kiểm tra kích thước vật lý của bản Image Copy vừa tạo (trong đường dẫn được liệt kê từ bước 14):
```bash
ls -lh /u01/app/oracle/fast_recovery_area/ORCL/.../datafile/...
```

**16.** Xóa tất cả các bản backup và image copy để dọn dẹp hệ thống:
```rman
DELETE BACKUP;
DELETE COPY OF DATABASE;
```

---
## Câu hỏi ôn tập

**Câu 1: Việc bật `CONTROLFILE AUTOBACKUP ON` giúp ích gì trong tình huống thực tế?**
- **Trả lời:** Giúp đảm bảo rằng luôn có một bản sao lưu mới nhất của Control file và SPFILE bất cứ khi nào có thay đổi về cấu trúc vật lý của database hoặc sau khi một lệnh BACKUP chạy xong. Điều này cứu sống database trong các thảm họa mất toàn bộ Control file.

**Câu 2: Tại sao bản backup nén (COMPRESSED BACKUPSET) lại chạy chậm hơn bản không nén?**
- **Trả lời:** Vì thuật toán nén (BZIP2) sử dụng rất nhiều tài nguyên CPU để xử lý việc nén dữ liệu trước khi ghi ra đĩa. Do đó, I/O giảm nhưng thời gian xử lý CPU tăng lên.

**Câu 3: Làm thế nào để phân biệt bản nén và bản không nén khi dùng lệnh `LIST BACKUP`?**
- **Trả lời:** Trong bảng kết quả của `LIST BACKUP SUMMARY`, bạn hãy xem cột `TAG` mà bạn đã đặt (ví dụ `comp_db`), hoặc xem cột `Size` để nhận biết sự chênh lệch kích thước rõ rệt giữa bản nén và không nén.

**Câu 4: Lệnh nào dùng để xóa tất cả các bản image copy của database?**
- **Trả lời:** Lệnh `DELETE COPY OF DATABASE;` trong RMAN.

**Câu 5: Có thể nén Image Copy được không?**
- **Trả lời:** Không. Image Copy bắt buộc phải là một bản sao y hệt nguyên bản từng byte (byte-for-byte copy) của file gốc để có thể sử dụng ngay mà không cần khôi phục. Chỉ Backupset mới có thể nén được.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/77-thuc-hanh-rman-full-backups-p2.md`
