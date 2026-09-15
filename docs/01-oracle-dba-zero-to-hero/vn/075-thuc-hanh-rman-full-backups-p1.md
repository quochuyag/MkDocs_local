---
title: 'Bài 75: Thực hành - Thực hiện RMAN Full Backups - Phần I'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/75-thuc-hanh-rman-full-backups-p1.md
---

# Bài 75: Thực hành - Thực hiện RMAN Full Backups - Phần I

## Mục tiêu

Trong bài thực hành này, bạn sẽ sử dụng RMAN để thực hiện các tác vụ sau:
- Thực hiện backup cold/consistent toàn bộ cơ sở dữ liệu (ở chế độ NOARCHIVELOG).
- Thực hiện backup hot/inconsistent toàn bộ cơ sở dữ liệu.
- Thực hiện backup các tablespace cụ thể.
- Chỉ định thủ công vị trí đích của bản backup trong lệnh BACKUP.

## A. Thực hiện Cold Backup toàn bộ CSDL với RMAN
Trong các bước dưới đây, bạn sẽ thực hiện backup toàn bộ CSDL bằng dòng lệnh.

**1.** Mở terminal (Putty) và đăng nhập vào `srv1` với quyền `oracle`.
```bash
rman target /
```

**2.** Thực hiện backup toàn bộ CSDL bằng lệnh:
```rman
BACKUP DATABASE;
```

**3.** Quan sát kết quả khi lệnh backup hoàn thành.

**4.** Gõ lệnh sau trong RMAN:
```rman
LIST BACKUPSET;
```
*(Lệnh này hiển thị tất cả các backupset được đăng ký trong RMAN repository).*

**5.** Trả lời các câu hỏi sau:
- **Các file temp trong temporary tablespace có được lưu vào backup piece không?**
  - Không. Khi restore CSDL, chúng ta không cần dữ liệu từ temporary tablespace, Oracle sẽ tự tạo lại chúng.
- **Các file backup được lưu tại đâu?**
  - Tại FRA (Fast Recovery Area) theo mặc định.

## B. Thực hiện Hot Backup và Backup Tablespace

Trước hết, bạn cần chuyển database sang chế độ ARCHIVELOG.
*(Để tiết kiệm thời gian, giả định rằng bạn đã làm việc này ở bài trước, nếu chưa, hãy khởi động lại database ở chế độ Mount và chạy `ALTER DATABASE ARCHIVELOG;`)*.

**6.** Lấy thông tin ID của tablespace `USERS` bằng câu lệnh SQL:
```sql
SELECT tablespace_name, file_id FROM dba_data_files;
```

**7.** Gõ lệnh sau trong RMAN để thực hiện backup riêng tablespace `USERS`:
```rman
BACKUP TABLESPACE USERS;
```

**8.** Liệt kê danh sách các bản backup để xác nhận tablespace `USERS` đã được backup:
```rman
LIST BACKUP OF TABLESPACE USERS;
```

**9.** Thực hiện backup một datafile cụ thể (dùng ID lấy được ở bước 6, ví dụ datafile 4):
```rman
BACKUP DATAFILE 4;
```

## C. Chỉ định đích đến cho Backup

**10.** Tạo một thư mục mới trên OS để chứa backup:
```bash
mkdir -p /home/oracle/my_backups
```

**11.** Thực hiện backup database và trỏ đích đến thư mục vừa tạo bằng tham số `FORMAT`:
```rman
BACKUP DATABASE FORMAT '/home/oracle/my_backups/db_%U.bkp';
```

**12.** Kiểm tra lại các file đã được tạo ra trong thư mục:
```bash
ls -l /home/oracle/my_backups/
```

---
## Câu hỏi ôn tập

**Câu 1: Sự khác biệt chính giữa Cold Backup và Hot Backup là gì?**
- **Trả lời:** Cold backup (Consistent backup) được thực hiện khi database ở trạng thái MOUNT (đã shutdown sạch). Hot backup (Inconsistent backup) được thực hiện khi database đang OPEN và yêu cầu database phải ở chế độ ARCHIVELOG.

**Câu 2: Tại sao RMAN không backup các tempfiles?**
- **Trả lời:** Tempfiles chứa dữ liệu tạm thời phục vụ cho các thao tác sắp xếp (sort), hash join... không mang ý nghĩa lưu trữ dữ liệu vĩnh viễn. Khi recovery, Oracle sẽ tự động tạo lại các tempfiles này, do đó backup chúng là lãng phí tài nguyên.

**Câu 3: Tham số `FORMAT` trong lệnh BACKUP có tác dụng gì?**
- **Trả lời:** `FORMAT` dùng để ghi đè vị trí lưu trữ mặc định (FRA) và cấu trúc tên file của bản backup. Các biến như `%U` giúp sinh ra tên file độc nhất.

**Câu 4: Làm thế nào để biết RMAN đã backup thành công?**
- **Trả lời:** Có thể sử dụng lệnh `LIST BACKUP;` hoặc `LIST BACKUPSET;` trong RMAN để kiểm tra danh sách các bản backup đã được đăng ký thành công vào repository (hoặc control file).

**Câu 5: Có thể backup một datafile duy nhất thay vì toàn bộ tablespace không?**
- **Trả lời:** Có. Bằng cách sử dụng lệnh `BACKUP DATAFILE <file_id>;` hoặc cung cấp đường dẫn đầy đủ của datafile đó trong RMAN.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/75-thuc-hanh-rman-full-backups-p1.md`
