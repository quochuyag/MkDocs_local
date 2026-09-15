---
title: 'Bài 76: Thực hiện RMAN Full Backups - Phần II'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/76-thuc-hien-rman-full-backups-p2.md
---

# Bài 76: Thực hiện RMAN Full Backups - Phần II

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Nén bản sao lưu (Compressing Backups).
- Sử dụng Image Copies.
- Kích hoạt tính năng sao lưu tự động Control file (Control file autobackup).

## Nén bản sao lưu (Compressing Backups)
- RMAN hỗ trợ nén file backup dưới định dạng nhị phân, giúp tiết kiệm đáng kể không gian lưu trữ.
- Khi cần restore, RMAN có khả năng giải nén tự động trong quá trình đọc mà không yêu cầu thêm thao tác nào từ quản trị viên.
- Mặc định, RMAN sử dụng thuật toán nén `BZIP2` (tỷ lệ nén tốt nhưng tiêu tốn CPU).
- Tùy chọn `ZLIB` yêu cầu giấy phép (license) Advanced Compression.

### Cú pháp lệnh Backup nén
- Bạn chỉ cần thêm từ khóa `AS COMPRESSED BACKUPSET` vào câu lệnh BACKUP.
```rman
BACKUP AS COMPRESSED BACKUPSET DATABASE;
BACKUP AS COMPRESSED BACKUPSET TABLESPACE users;
```

## Khái niệm Image Copies
- Một **Image Copy** là bản sao (copy) từng byte một của một database file.
- Không giống như backupsets (là định dạng độc quyền của RMAN, có thể gộp nhiều file và bỏ qua các block rỗng), Image Copies là file nguyên bản.
- Lệnh `BACKUP AS COPY` tạo ra các image copies. Lệnh này tương tự như lệnh copy của hệ điều hành, ngoại trừ việc RMAN có kiểm tra hỏng hóc (corruption checking) trong quá trình copy và ghi lại file copy vào RMAN repository.
- Image copies cung cấp tốc độ khôi phục (restore) cực nhanh vì chúng có thể được sử dụng trực tiếp để thay thế cho file bị hỏng mà không cần "giải nén" hay trích xuất từ backupset.

### Tạo Image Copies
```rman
BACKUP AS COPY DATABASE;
BACKUP AS COPY TABLESPACE users;
```
- Bạn cũng có thể copy một datafile bằng lệnh:
```rman
BACKUP AS COPY DATAFILE 4 FORMAT '/u01/backup/users01.dbf';
```

## Giới thiệu tính năng Control File Autobackup
- Control file chứa cấu trúc vật lý của database (đường dẫn datafile, redo log) và cả các siêu dữ liệu (metadata) của RMAN.
- Do vai trò cực kỳ quan trọng, RMAN cung cấp tính năng **Control File Autobackup** để tự động tạo một bản sao của Control file và SPFILE.
- Tính năng này (mặc định được bật từ phiên bản 12cR2) đảm bảo rằng RMAN có thể restore database ngay cả khi mất toàn bộ control file và recovery catalog.

### Khi nào thì Control file được autobackup?
Nếu tính năng này được kích hoạt (`ON`), RMAN sẽ tự động backup control file trong các trường hợp:
1. Sau mỗi lệnh `BACKUP` hoặc `COPY` chạy thành công.
2. Bất cứ khi nào cấu trúc vật lý của database thay đổi (ví dụ: thêm/xóa datafile, tablespace).

### Cấu hình Control file Autobackup
```rman
-- Xem trạng thái hiện tại
SHOW CONTROLFILE AUTOBACKUP;

-- Kích hoạt tính năng
CONFIGURE CONTROLFILE AUTOBACKUP ON;

-- Chỉ định định dạng tên file cho autobackup (Tùy chọn)
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/u01/backup/cf_%F';
```

---
## Câu hỏi ôn tập

**Câu 1: Lợi ích lớn nhất của việc sử dụng lệnh `BACKUP AS COMPRESSED BACKUPSET` là gì?**
- **Trả lời:** Lợi ích lớn nhất là tiết kiệm dung lượng lưu trữ đĩa hoặc băng từ, dù nó sẽ đánh đổi bằng việc tiêu tốn thêm tài nguyên CPU trong quá trình backup và restore.

**Câu 2: Điểm khác biệt cơ bản giữa Backupset và Image Copy?**
- **Trả lời:** Backupset là định dạng độc quyền của RMAN, gom nhiều datafiles lại với nhau, nén được và bỏ qua các block trống. Image Copy là một bản sao giống hệt (byte-for-byte) của từng datafile riêng lẻ giống như copy trên hệ điều hành, giúp restore tức thì.

**Câu 3: Thuật toán nén mặc định của RMAN là gì? Có mất phí license không?**
- **Trả lời:** Thuật toán mặc định là `BZIP2` và nó không yêu cầu license bổ sung. Tuy nhiên `ZLIB` (nhanh hơn, ít tốn CPU hơn) thì yêu cầu license Advanced Compression Option.

**Câu 4: Control File Autobackup có bao gồm file nào khác ngoài Control File không?**
- **Trả lời:** Có. Bản autobackup sẽ luôn đi kèm với bản sao lưu của Server Parameter File (SPFILE) tại thời điểm đó.

**Câu 5: Database vừa tạo thêm một tablespace mới, RMAN có tự động backup control file không?**
- **Trả lời:** Có, miễn là tính năng `CONTROLFILE AUTOBACKUP` đang được đặt là `ON`. Mọi thay đổi về cấu trúc vật lý của database đều kích hoạt RMAN tự động backup control file ngay lập tức.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/76-thuc-hien-rman-full-backups-p2.md`
