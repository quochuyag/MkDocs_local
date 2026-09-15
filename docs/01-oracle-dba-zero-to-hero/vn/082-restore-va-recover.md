---
title: 'Bài 82: Giới thiệu lệnh RESTORE và RECOVER'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/82-restore-va-recover.md
---

# Bài 82: Giới thiệu lệnh RESTORE và RECOVER

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Khái niệm về Data Recovery (Khôi phục dữ liệu).
- Sử dụng lệnh RESTORE.
- Sử dụng lệnh RECOVER.

## Data Recovery (Khôi phục dữ liệu)
Khôi phục dữ liệu thông thường bao gồm hai giai đoạn tách biệt: **Restore** và **Recover**.

### Giai đoạn 1: RESTORE (Phục hồi)
- **Restore** có nghĩa là lấy ra các dữ liệu từ trong các bản backup (backupset hoặc image copies) để tái tạo lại các file vật lý đã bị mất hoặc bị hỏng trên hệ thống lưu trữ.
- Khi một file bị hỏng (ví dụ `users01.dbf`), RMAN sẽ tìm bản backup gần nhất của file này và ghi đè nó ra ổ cứng. Tại thời điểm này, file `users01.dbf` đang ở trạng thái dữ liệu của *ngày hôm qua* (thời điểm backup).

### Giai đoạn 2: RECOVER (Khôi phục / Cập nhật dữ liệu)
- **Recover** có nghĩa là "roll forward" (cuộn tới trước) dữ liệu.
- Nó sẽ áp dụng các bản sao lưu tăng dần (Incremental backups) và các file log (Archived Redo Logs và Online Redo Logs) lên trên file vừa được Restore để đẩy trạng thái dữ liệu từ "ngày hôm qua" tới đúng thời điểm "hiện tại" (trước khi xảy ra sự cố).

## Sử dụng lệnh RESTORE
Lệnh `RESTORE` trong RMAN sẽ xác định file nào cần được phục hồi, tìm bản backup thích hợp nhất, sau đó trích xuất các file đó ra vị trí mặc định (hoặc vị trí bạn chỉ định).
*Lưu ý: Chỉ thực hiện Restore đối với các file đang bị thiếu hoặc hỏng.*

### Cú pháp cơ bản
```rman
-- Khôi phục toàn bộ database
RESTORE DATABASE;

-- Khôi phục một tablespace cụ thể
RESTORE TABLESPACE users;

-- Khôi phục một datafile cụ thể (bằng ID hoặc đường dẫn)
RESTORE DATAFILE 4;

-- Khôi phục Control file
RESTORE CONTROLFILE;

-- Khôi phục SPFILE
RESTORE SPFILE;
```

## Sử dụng lệnh RECOVER
Sau khi đã `RESTORE` xong, bạn cần chạy lệnh `RECOVER` để áp dụng redo/incremental backups và đưa các datafiles về trạng thái nhất quán.
*Lưu ý: Bạn không cần phải biết chính xác file archive log hay incremental backup nào cần đắp vào. RMAN sẽ tự động tìm các file cần thiết từ repository và thực hiện công việc này.*

### Cú pháp cơ bản
```rman
-- Khôi phục (roll forward) toàn bộ database
RECOVER DATABASE;

-- Khôi phục (roll forward) một tablespace cụ thể
RECOVER TABLESPACE users;

-- Khôi phục (roll forward) một datafile cụ thể
RECOVER DATAFILE 4;
```

---
## Câu hỏi ôn tập

**Câu 1: Sự khác biệt chính giữa RESTORE và RECOVER là gì?**
- **Trả lời:** `RESTORE` là thao tác chép lại file từ bản backup về lại ổ đĩa vật lý (dữ liệu đang ở quá khứ). `RECOVER` là thao tác đọc các log/incremental backup đắp vào file đó để cập nhật dữ liệu tới thời điểm hiện tại (hoặc 1 mốc thời gian cụ thể).

**Câu 2: RMAN có tự động chạy RECOVER ngay sau khi RESTORE không?**
- **Trả lời:** Không. Bạn phải gõ lệnh `RECOVER` một cách tường minh sau khi chạy xong `RESTORE`.

**Câu 3: Tôi bị xóa nhầm SPFILE, tôi có thể dùng RMAN để lấy lại không?**
- **Trả lời:** Có. Bằng cách sử dụng lệnh `RESTORE SPFILE FROM AUTOBACKUP;` (hoặc từ một bản backup cụ thể).

**Câu 4: Quá trình `RECOVER` cần những file gì để hoạt động?**
- **Trả lời:** Nó cần các Incremental Backups (nếu có), Archived Redo Logs và Online Redo Logs.

**Câu 5: Nếu tôi mới cấu hình hệ thống chạy ở chế độ NOARCHIVELOG, liệu tôi có thể thực hiện lệnh RECOVER không?**
- **Trả lời:** Rất hạn chế. Trong chế độ NOARCHIVELOG, bạn không có archive logs nên không thể roll forward dữ liệu. Bạn thường chỉ có thể `RESTORE` về bản backup gần nhất và chấp nhận mất trắng dữ liệu phát sinh từ lúc backup tới lúc hỏng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/82-restore-va-recover.md`
