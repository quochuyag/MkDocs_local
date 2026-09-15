---
title: 'Bài 95: Thực hành - Sử dụng RMAN Recovery Catalog'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/95-thuc-hanh-recovery-catalog.md
---

# Bài 95: Thực hành - Sử dụng RMAN Recovery Catalog

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Tạo một Recovery Catalog trên máy chủ Windows (`orawindb`) và đăng ký máy chủ Linux (`oradb`) vào đó.
- Gắn (Catalog) các file lưu trữ bên ngoài vào RMAN.
- Tạo và thực thi các RMAN Stored Scripts (Kịch bản lưu sẵn).

## A. Tạo Recovery Catalog
Trong bài LAB này, chúng ta sẽ biến database `orawindb` trên máy Windows thành máy chủ Recovery Catalog.
**1.** Đăng nhập vào `srv1` (Linux) với quyền `oracle`.
**2.** Dùng SQL*Plus từ Linux kết nối sang Windows (`orawindb`) bằng tài khoản SYSTEM:
```bash
sqlplus system/password@ORAWINDB
```
**3.** Tạo Tablespace và User chuyên quản lý Catalog (trên máy Windows):
```sql
CREATE TABLESPACE rc_tbs;
CREATE USER rc_owner IDENTIFIED BY password
 DEFAULT TABLESPACE rc_tbs
 QUOTA UNLIMITED ON rc_tbs;
GRANT RECOVERY_CATALOG_OWNER TO rc_owner;
EXIT;
```
**4.** Mở RMAN trên Linux, kết nối đồng thời vào Target (chính nó) và Catalog (máy Windows):
```bash
rman target "'/ as SYSBACKUP'" catalog rc_owner/password@ORAWINDB
```
**5.** Khởi tạo Catalog và Đăng ký Database:
```rman
CREATE CATALOG;
REGISTER DATABASE;
```

## B. Biên mục (Cataloging) Backup Files
Giả sử bạn có 1 ổ cứng rời (mount tại `/media/sf_staging/backup`) chứa các file `.bkp` cũ được chép từ máy khác sang.
**6.** Dùng lệnh CATALOG để đăng ký từng file hoặc toàn bộ thư mục đó vào RMAN:
- Catalog 1 file Backupset:
  ```rman
  CATALOG BACKUPPIECE '/media/sf_staging/backup/ARC_BS.bkp';
  ```
- Catalog 1 file Datafile Copy (Image Copy):
  ```rman
  CATALOG DATAFILECOPY '/media/sf_staging/backup/mf_users.dbf';
  ```
- Catalog toàn bộ thư mục (RMAN sẽ quét và tự động nhận diện file):
  ```rman
  CATALOG START WITH '/media/sf_staging/backup/';
  ```

## C. Sử dụng RMAN Stored Scripts
Stored Script giống như các Procedure của SQL, chúng được lưu thẳng vào trong Recovery Catalog thay vì lưu ra file `.sh`.
**7.** Tạo một script dùng để sao lưu bảng USERS:
```rman
CREATE SCRIPT FULL_USERS_SCRIPT {
  BACKUP TABLESPACE USERS TAG 'USERS_TBS'; 
}
```
**8.** Kiểm tra nội dung script:
```rman
PRINT SCRIPT FULL_USERS_SCRIPT;
```
**9.** Gọi thực thi script đó từ trong dấu nhắc lệnh RMAN:
```rman
RUN { EXECUTE SCRIPT FULL_USERS_SCRIPT; }
```
**10.** Tạo một script CÓ CHỨA BIẾN số (Substitution Variables):
```rman
CREATE SCRIPT TBS_FULL_SCRIPT { 
  BACKUP TABLESPACE &1 TAG '&2';
}
```
**11.** Gọi thực thi script có truyền tham số vào biến:
```rman
RUN { EXECUTE SCRIPT TBS_FULL_SCRIPT USING USERS 'USERS_2026'; }
```
**12.** Bạn cũng có thể gọi Script ngay từ Command Line (Linux terminal) mà không cần vào hẳn giao diện của RMAN:
```bash
rman target "'/ as SYSBACKUP'" catalog rc_owner@orawindb script=TBS_FULL_SCRIPT USING USERS 'USERS_2026'
```

---
## Câu hỏi ôn tập

**Câu 1: Câu lệnh `REGISTER DATABASE` có tác dụng gì?**
- **Trả lời:** Câu lệnh này dùng để đăng ký Target Database hiện hành vào trong Recovery Catalog. RMAN sẽ tạo các bản ghi trong cơ sở dữ liệu của Catalog để nhận diện Target Database này và bắt đầu lưu trữ lịch sử sao lưu của nó.

**Câu 2: Tôi có thể sử dụng tính năng "Stored Scripts" nếu tôi không cấu hình Recovery Catalog không?**
- **Trả lời:** Không thể. Tính năng Stored Scripts bắt buộc phải có Recovery Catalog Database để làm nơi lưu trữ các đoạn code của script (lưu trong các bảng của Catalog owner). Nếu chỉ dùng Control File mặc định, bạn phải viết script ra file text hệ điều hành (Command files).

**Câu 3: Mục đích của lệnh `CATALOG START WITH` là gì?**
- **Trả lời:** Lệnh này giúp quét đệ quy một thư mục bất kỳ trên ổ cứng và tự động nhận dạng, thêm thông tin (biên mục) của TẤT CẢ các file backup (backup pieces, image copies, archive logs) hợp lệ tìm thấy vào trong kho siêu dữ liệu của RMAN.

**Câu 4: Cấu trúc biến trong RMAN Stored Scripts được định nghĩa như thế nào?**
- **Trả lời:** Các biến được định nghĩa bằng ký hiệu `&` kèm theo số thứ tự (hoặc tên), ví dụ `&1`, `&2`. Khi gọi bằng lệnh `EXECUTE SCRIPT ... USING`, bạn truyền các giá trị vào theo đúng thứ tự tương ứng.

**Câu 5: Nếu 1 file backup bị xoá trực tiếp bằng lệnh OS (`rm` trên Linux), RMAN có tự biết để xoá dữ liệu trên Catalog không?**
- **Trả lời:** Không. RMAN Catalog sẽ không tự biết file đã mất cho tới khi bạn chạy lệnh kiểm tra chéo `CROSSCHECK BACKUP`. Lúc này nó mới đánh dấu các file đó là EXPIRED.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/95-thuc-hanh-recovery-catalog.md`
