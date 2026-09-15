---
title: 'Bài 83: Thực hiện Khôi phục (Recovery) Phần I - Thực hiện Khôi phục Toàn bộ (Full
  Recovery)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/83-thuc-hien-recovery-p1.md
---

# Bài 83: Thực hiện Khôi phục (Recovery) Phần I - Thực hiện Khôi phục Toàn bộ (Full Recovery)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Thực hiện các hành động chung trước khi khôi phục (pre-recovery actions).
- Khôi phục toàn bộ database khi đang chạy ở chế độ NOARCHIVELOG.
- Khôi phục toàn bộ database khi đang chạy ở chế độ ARCHIVELOG.
- Thực hiện khôi phục hoàn toàn trên một tablespace của người dùng.

## Khi nào cần đến Recovery?
- **Sự cố vật lý (Physical issues):** Thường được nhận biết thông qua các thông báo lỗi trả về. Ví dụ:
  `ORA-00205: error in identifying control file, check alert log for more info`
- **Sự cố logic (Logical issues):** Thường được báo cáo bởi các người dùng (client users) khi thấy dữ liệu bị sai lệch hoặc mất mát.
- **Xác định các data files bị mất bằng RMAN:**
  ```rman
  RMAN> VALIDATE DATABASE;
  RMAN> VALIDATE PLUGGABLE DATABASE pdb1;
  RMAN> VALIDATE TABLESPACE users;
  RMAN> VALIDATE DATAFILE '.';
  ```
  *(Kết quả sẽ báo lỗi như `RMAN-06056: could not access datafile 5` nếu file đó không tồn tại hoặc không thể truy cập).*

## Xem trước (Previewing) các Backups sẽ được sử dụng để Restore
- Để liệt kê các file backup sẽ được sử dụng trong quá trình khôi phục:
  - Lệnh `RESTORE ... PREVIEW`: Truy cập vào RMAN repository để truy xuất danh sách.
  - Lệnh `RESTORE ... VALIDATE HEADER`: Xác thực phần header (tiêu đề) của các file backup và xác nhận sự tồn tại của chúng.
- **Ví dụ:**
  ```rman
  RESTORE DATABASE PREVIEW;
  RESTORE DATABASE PREVIEW SUMMARY;
  ```

## Xác thực (Validating) Backups trước khi Restore
- Để đảm bảo rằng các file backup hoàn toàn có thể sử dụng được cho việc restore:
  - Lệnh `RESTORE ... VALIDATE`
  - Lệnh `VALIDATE BACKUPSET`
- Tất cả các block bên trong file backup sẽ được đọc để kiểm tra lỗi.

## Về việc thực hiện Khôi phục toàn bộ Database (Whole Database)
- **Database đang chạy ở chế độ NOARCHIVELOG:**
  - *Nếu không có incremental backup:* Database chỉ có thể được khôi phục về bản backup nhất quán (consistent backup) cuối cùng được tạo. Dữ liệu từ sau lúc backup sẽ bị mất.
  - *Nếu có incremental backup:* Các incremental backups có thể được áp dụng nếu chúng nhất quán. Lệnh `RECOVER` phải đi kèm với tùy chọn `NOREDO` (Vì không có redo logs để apply).
- **Database đang chạy ở chế độ ARCHIVELOG:**
  - Nếu các nhóm online redo log và các file archived redo log có sẵn, bạn có thể thực hiện phục hồi hoàn toàn (complete recovery) hoặc không hoàn toàn (incomplete recovery) mà không bị mất dữ liệu.

## Khôi phục hoàn toàn toàn bộ Database trong chế độ NOARCHIVELOG
- **Tình huống:** Một hoặc nhiều datafiles của database bị mất.
- **Giả định:** Database chạy NOARCHIVELOG mode, không có incremental backup.
- **Giải pháp:**
  ```rman
  STARTUP MOUNT;
  RESTORE DATABASE;
  RECOVER DATABASE [UNTIL CANCEL];
  ALTER DATABASE OPEN RESETLOGS;
  ```
- **Lưu ý:** Các temporary tablespaces sẽ tự động được tạo lại khi bạn mở database (`OPEN`). Tùy chọn `RESETLOGS` là bắt buộc vì bạn đang mở một database với SCN cũ hơn hiện tại (hoặc không có redo để roll forward).

## Khôi phục hoàn toàn toàn bộ Database trong chế độ ARCHIVELOG
- **Tình huống:** Tất cả hoặc hầu hết các datafiles của database bị mất.
- **Giả định:** Database chạy ARCHIVELOG mode, online redo log files vẫn còn nguyên vẹn.
- **Giải pháp:**
  ```rman
  STARTUP MOUNT;
  RESTORE DATABASE;
  RECOVER DATABASE;
  ALTER DATABASE OPEN;
  ```
  *(Bạn không cần `RESETLOGS` ở đây vì quá trình `RECOVER` đã áp dụng toàn bộ redo log để khôi phục dữ liệu đến thời điểm hiện tại).*

## Khôi phục hoàn toàn toàn bộ Database: Sang Vị trí mới (New Location)
- **Tình huống:** Hầu hết datafiles bị mất và ổ đĩa (destination) ban đầu bị hỏng hoặc không thể truy cập.
- **Giải pháp:** (Chuyển hướng file sang ổ `/disk2`)
  ```rman
  RUN { 
    SET NEWNAME FOR DATAFILE 2 TO '/disk2/df1.dbf';
    SET NEWNAME FOR DATAFILE 3 TO '/disk2/df2.dbf';
    SET NEWNAME FOR DATAFILE 4 TO '/disk2/df3.dbf';
    RESTORE DATABASE;
    SWITCH DATAFILE ALL;
    RECOVER DATABASE; 
  }
  ALTER DATABASE OPEN;
  ```
  *(Lệnh `SWITCH DATAFILE ALL` sẽ cập nhật đường dẫn mới vào Control File).*

## Khôi phục hoàn toàn một Tablespace của Người dùng (User Tablespace)
- **Tình huống:** Một hoặc nhiều datafiles của một user tablespace bị mất.
- **Giả định:** Database vẫn đang mở (OPEN) bình thường.
- **Giải pháp:**
  ```rman
  ALTER TABLESPACE hrtbs OFFLINE IMMEDIATE;
  RESTORE TABLESPACE hrtbs;
  RECOVER TABLESPACE hrtbs;
  ALTER TABLESPACE hrtbs ONLINE;
  ```

## Khôi phục hoàn toàn Tablespace sang Vị trí mới
- **Giải pháp:**
  ```rman
  ALTER TABLESPACE hrtbs OFFLINE IMMEDIATE;
  RUN {
    SET NEWNAME FOR DATAFILE '/disk1/hrtbs01.f' TO '/disk2/hrtbs01.f';
    SET NEWNAME FOR DATAFILE '/disk1/hrtbs02.f' TO '/disk2/hrtbs02.f';
    RESTORE TABLESPACE hrtbs;
    SWITCH DATAFILE ALL;
    RECOVER TABLESPACE hrtbs;
  }
  ALTER TABLESPACE hrtbs ONLINE;
  ```

---
## Câu hỏi ôn tập

**Câu 1: Lệnh `RESTORE DATABASE PREVIEW` dùng để làm gì?**
- **Trả lời:** Lệnh này giúp liệt kê tất cả các file backup sẽ được sử dụng trong quá trình khôi phục thực tế, mà không thực sự thực hiện việc sao chép các data files.

**Câu 2: Tại sao phải sử dụng lệnh `ALTER DATABASE OPEN RESETLOGS` sau khi khôi phục database ở chế độ NOARCHIVELOG?**
- **Trả lời:** Vì ở chế độ NOARCHIVELOG, không có archived redo logs để roll forward dữ liệu. Bạn phải mở database ở trạng thái của thời điểm backup trong quá khứ. Việc dùng `RESETLOGS` là bắt buộc để thiết lập lại sequence của các redo logs, tránh sự không nhất quán (inconsistency) trong tương lai.

**Câu 3: Điều kiện tiên quyết để khôi phục hoàn toàn (complete recovery) database ở chế độ ARCHIVELOG là gì?**
- **Trả lời:** Cần phải có đầy đủ các bản backup của datafile bị mất và toàn bộ các archived redo logs sinh ra từ thời điểm backup đó cho tới thời điểm xảy ra sự cố, cộng thêm online redo log hiện tại.

**Câu 4: Khi muốn restore datafiles sang một thư mục/ổ đĩa mới (vì ổ cũ bị hỏng), bạn cần dùng lệnh gì trong khối lệnh `RUN`?**
- **Trả lời:** Cần dùng lệnh `SET NEWNAME FOR DATAFILE ... TO ...;` để chỉ định vị trí mới, sau đó dùng `SWITCH DATAFILE ALL;` (hoặc `SWITCH DATAFILE ...`) để cập nhật đường dẫn mới này vào Control File.

**Câu 5: Có cần phải tắt (SHUTDOWN) database khi khôi phục một User Tablespace bị lỗi không?**
- **Trả lời:** Không cần thiết. Bạn chỉ cần đưa riêng tablespace bị lỗi đó về trạng thái OFFLINE (`ALTER TABLESPACE ... OFFLINE IMMEDIATE;`), sau đó thực hiện RESTORE và RECOVER tablespace đó, rồi đưa nó ONLINE trở lại. Database vẫn có thể phục vụ người dùng ở các tablespace khác bình thường.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/83-thuc-hien-recovery-p1.md`
