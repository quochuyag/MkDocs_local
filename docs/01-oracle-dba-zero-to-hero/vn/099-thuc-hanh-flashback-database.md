---
title: 'Bài 99: Thực hành - Flashback Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/99-thuc-hanh-flashback-database.md
---

# Bài 99: Thực hành - Flashback Database

## Mục tiêu
Trong bài thực hành này, bạn sẽ sử dụng tính năng Flashback Database để "tua ngược" thời gian của cơ sở dữ liệu về một mốc an toàn.

## A. Bật tính năng Flashback Database
**1.** Kiểm tra thư mục FRA đã được cấu hình chưa:
```sql
SHOW PARAMETER DB_RECOVERY_FILE_DEST;
```
**2.** Đặt thời gian lưu giữ (Retention Target) là 2880 phút (48 giờ):
```sql
ALTER SYSTEM SET DB_FLASHBACK_RETENTION_TARGET=2880 SCOPE=BOTH;
```
**3.** Bật chế độ ARCHIVELOG (nếu chưa bật) và bật Flashback Database (đòi hỏi MOUNT state):
```sql
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN;
```
**4.** Kiểm tra lại trạng thái:
```sql
SELECT FLASHBACK_ON FROM V$DATABASE;
```

## B. Tạo Restore Point (Điểm khôi phục)
Thay vì phải nhớ thời điểm chính xác (Timestamp) hoặc số SCN dài dòng, ta có thể đánh dấu dòng thời gian bằng một cái tên.
**5.** Tạo một Guaranteed Restore Point trước khi nâng cấp phần mềm:
```sql
CREATE RESTORE POINT b4_upgrade GUARANTEE FLASHBACK DATABASE;
```

## C. Giả lập Lỗi dữ liệu
**6.** Trong `PDB1`, một người dùng vô tình làm hỏng dữ liệu (Ví dụ `DROP` nhầm bảng hoặc cập nhật sai toàn bộ bảng).
```sql
ALTER SESSION SET CONTAINER=PDB1;
CREATE TABLE hr.test_table (id NUMBER);
-- Giả sử đây là sai lầm:
DROP TABLE hr.test_table;
```

## D. Thực hiện Flashback (Tua lại thời gian)
**7.** Để sửa lỗi, bạn có thể tua lại riêng `PDB1` về mốc Restore Point vừa tạo mà không cần tắt CDB. Kết nối dưới quyền `SYS`:
```sql
ALTER SESSION SET CONTAINER=PDB1;
ALTER PLUGGABLE DATABASE CLOSE;
FLASHBACK PLUGGABLE DATABASE TO RESTORE POINT b4_upgrade;
```
**8.** Sau khi flashback xong, luôn mở bằng tùy chọn RESETLOGS:
```sql
ALTER PLUGGABLE DATABASE OPEN RESETLOGS;
```
**9.** Kiểm tra lại, bảng `hr.test_table` chưa từng được tạo ra hoặc bị xóa (vì ta tua về trước lúc đó).

## E. Dọn dẹp Guaranteed Restore Point
**10.** RẤT QUAN TRỌNG: Phải xóa Guaranteed Restore Point sau khi đã dùng xong hoặc không cần nữa để tránh đầy ổ đĩa FRA:
```sql
DROP RESTORE POINT b4_upgrade;
```

---
## Câu hỏi ôn tập
**Câu 1: Tôi có thể đặt `DB_FLASHBACK_RETENTION_TARGET` thành 10 năm được không?**
- **Trả lời:** Về mặt kỹ thuật là có thể, tuy nhiên lượng Flashback log sinh ra trong 10 năm sẽ làm tiêu tốn một dung lượng đĩa FRA khổng lồ không thể chấp nhận được. Người ta thường chỉ đặt 1 đến vài ngày.

**Câu 2: Nếu Database đang ở chế độ NOARCHIVELOG, tôi có bật được Flashback không?**
- **Trả lời:** Không. Bật ARCHIVELOG là điều kiện tiên quyết bắt buộc trước khi bật FLASHBACK.

**Câu 3: Làm thế nào để xem tiến trình Flashback đang chạy được bao nhiêu phần trăm?**
- **Trả lời:** Bạn có thể truy vấn bảng `V$SESSION_LONGOPS` để theo dõi tiến độ của tiến trình tua ngược.

**Câu 4: Quên xóa Guaranteed Restore Point (GRP) gây ra hậu quả gì?**
- **Trả lời:** Oracle sẽ không bao giờ dám xóa các file log chứa ảnh cũ sau mốc GRP đó. Dẫn đến FRA bị đầy 100%, lúc này Database sẽ bị treo (hang) và ngừng hoạt động.

**Câu 5: Có thể tạo Normal Restore Point thay vì Guaranteed không? Khác biệt là gì?**
- **Trả lời:** Có. Normal Restore Point chỉ là nhãn dán cho dễ nhớ, nếu FRA bị đầy, Oracle sẽ tự động ghi đè và xóa bỏ vùng thời gian đó, khiến bạn không thể tua về Normal Restore Point được nữa. Guaranteed thì ép Oracle giữ lại bằng mọi giá.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/99-thuc-hanh-flashback-database.md`
