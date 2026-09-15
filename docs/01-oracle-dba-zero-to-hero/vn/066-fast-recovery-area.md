---
title: 'Bài 66: Quản lý Vùng Phục hồi Nhanh (Fast Recovery Area - FRA)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/66-fast-recovery-area.md
---

# Bài 66: Quản lý Vùng Phục hồi Nhanh (Fast Recovery Area - FRA)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu khái niệm, bản chất và lợi ích của **Fast Recovery Area (FRA)**.
- Phân biệt các tệp tin vĩnh viễn (**Permanent Files**) và tệp tin tạm thời (**Transient Files**) trong FRA.
- Kích hoạt và cấu hình FRA thông qua hai tham số then chốt: `DB_RECOVERY_FILE_DEST` và `DB_RECOVERY_FILE_DEST_SIZE`.
- Giám sát dung lượng và tỷ lệ chiếm dụng của FRA qua view `V$RECOVERY_FILE_DEST` và `V$RECOVERY_AREA_USAGE`.
- Nắm vững cơ chế tự động xóa dọn file (Automatic Space Reclamation) của Oracle khi FRA bị đầy.
- Áp dụng các Best Practices trong thiết kế hạ tầng lưu trữ cho FRA.

---

## 1. Fast Recovery Area (FRA) là gì?

![Saving Recovery Files with FRA](117-117-managing-the-fast-recovery-area/images/managing-the-fast-recovery-are-02.jpeg)

**Fast Recovery Area (FRA)** là một vùng lưu trữ trên đĩa cứng (thư mục hệ điều hành hoặc ASM Diskgroup) được Oracle quản lý tập trung và tự động hóa để chứa tất cả các tệp tin liên quan đến **sao lưu, nhật ký và phục hồi cơ sở dữ liệu**.

### Các loại file nằm trong FRA:
Oracle chia các file trong FRA thành 2 nhóm rõ rệt:

| Nhóm tệp tin | Danh sách file cụ thể | Đặc điểm vòng đời |
| :--- | :--- | :--- |
| **Permanent Files**<br>*(Tệp tin vĩnh viễn)* | - Bản sao Control File (Multiplexed Control File)<br>- Bản sao Online Redo Log Member | Là các file đang được Database Instance sử dụng trực tiếp. **Oracle KHÔNG BAO GIỜ tự động xóa các file này**. |
| **Transient Files**<br>*(Tệp tin tạm thời)* | - Archived Redo Log files (Archive log)<br>- Bản sao lưu RMAN (Datafile copies, Backup pieces)<br>- Flashback Logs<br>- Control File Autobackup | Là các file phục vụ việc khôi phục dữ liệu. Khi FRA đầy, **Oracle có thể tự động xóa** các file này nếu chúng đã thỏa mãn chính sách lưu trữ (Retention Policy) hoặc đã được sao lưu ra băng từ. |

---

## 2. Lợi ích Cốt tử của Fast Recovery Area

1. **Quản lý không gian tự động (Self-Managing Space):**
   DBA không cần phải viết shell script cronjob để xóa archive log cũ. Oracle tự động theo dõi dung lượng và tự động xóa các tệp tin hết hạn khi đĩa chạm ngưỡng đầy.
2. **Đơn giản hóa câu lệnh RMAN:**
   Khi bật FRA, câu lệnh RMAN chỉ cần gõ `BACKUP DATABASE;` là Oracle tự động sinh tên file chuẩn OMF và lưu đúng vào thư mục FRA mà không cần chỉ định đường dẫn dài dòng `FORMAT '...'`.
3. **Phục hồi siêu tốc:**
   Các file backup và archive log tập trung tại một nơi giúp RMAN tự động định vị và khôi phục dữ liệu trong thời gian ngắn nhất.

---

## 3. Kích hoạt và Cấu hình FRA

Để bật FRA, bạn chỉ cần cấu hình 2 tham số khởi tạo (hoàn toàn trực tuyến, không cần tắt database):

```sql
-- Bước 1: Bắt buộc phải đặt dung lượng giới hạn trước (SIZE):
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 20G SCOPE=BOTH;

-- Bước 2: Chỉ định đường dẫn thư mục hoặc ASM Diskgroup:
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '/u01/app/oracle/fast_recovery_area' SCOPE=BOTH;
-- Hoặc trên hệ thống ASM:
-- ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '+FRA' SCOPE=BOTH;
```

> ⚠️ **Quy tắc bắt buộc:** Phải đặt `DB_RECOVERY_FILE_DEST_SIZE` trước khi đặt `DB_RECOVERY_FILE_DEST`, nếu làm ngược lại Oracle sẽ báo lỗi `ORA-01261 / ORA-01262`.
> Để tắt FRA, chỉ cần đặt `DB_RECOVERY_FILE_DEST = ''`.

---

## 4. Giám sát Dung lượng và Cơ chế Tự động Dọn dẹp

```sql
-- 1. Xem tổng dung lượng và tỷ lệ % đã dùng của FRA:
SELECT NAME, 
       SPACE_LIMIT / 1024 / 1024 / 1024 AS LIMIT_GB,
       SPACE_USED / 1024 / 1024 / 1024  AS USED_GB,
       SPACE_RECLAIMABLE / 1024 / 1024 / 1024 AS RECLAIMABLE_GB,
       NUMBER_OF_FILES
FROM V$RECOVERY_FILE_DEST;

-- 2. Xem chi tiết từng loại file chiếm bao nhiêu % trong FRA:
SELECT FILE_TYPE, PERCENT_SPACE_USED, PERCENT_SPACE_RECLAIMABLE, NUMBER_OF_FILES 
FROM V$RECOVERY_AREA_USAGE;
```

### Khái niệm `SPACE_RECLAIMABLE` (Dung lượng có thể thu hồi):
- Cột `SPACE_RECLAIMABLE` hiển thị tổng dung lượng của các file tạm thời (như Archive log cũ đã backup ra tape, hoặc RMAN backup đã vượt quá retention policy) mà Oracle **có quyền lập tức xóa bỏ ngay khi không gian bị đầy**.
- Khi một file mới được ghi vào và dung lượng chạm trần `SPACE_LIMIT`, Oracle sẽ kích hoạt tiến trình dọn dẹp các block `RECLAIMABLE` theo nguyên tắc FIFO (file cũ nhất bị xóa trước).

---

## 5. Các Best Practices khi triển khai FRA

1. **Tách biệt ổ đĩa vật lý:** Vùng FRA nên nằm trên ổ đĩa vật lý (LUN / Storage Array) **hoàn toàn tách biệt** với ổ đĩa chứa Datafiles (`oradata`). Nếu ổ chứa Datafile bị hỏng phần cứng, bạn vẫn còn nguyên vẹn FRA để phục hồi.
2. **Kích thước FRA tối thiểu:** Nên đủ lớn để chứa:
   $$\text{Kích thước FRA} \ge \text{Dung lượng 1 bản Full Backup} + \text{Dung lượng Archive Log phát sinh trong 3 ngày} + \text{Flashback Logs}$$
3. **Tránh lỗi treo Database khi FRA đầy:**
   Nếu FRA bị đầy 100% và `SPACE_RECLAIMABLE = 0` (không còn gì để xóa), tiến trình ARCH (Archiver) sẽ bị treo, Redo Log không switch được và **toàn bộ Database sẽ lập tức ngừng phục vụ các câu lệnh DML**. DBA cần giám sát cảnh báo ngưỡng 80% để tăng kích thước `DB_RECOVERY_FILE_DEST_SIZE` kịp thời.

---

## Câu hỏi ôn tập

**1. Trong hai tham số `DB_RECOVERY_FILE_DEST` và `DB_RECOVERY_FILE_DEST_SIZE`, tham số nào bắt buộc phải được thiết lập trước? Tại sao?**
> **Trả lời:**
> Tham số **`DB_RECOVERY_FILE_DEST_SIZE` bắt buộc phải được thiết lập trước**. Oracle yêu cầu bạn phải ấn định rõ hạn mức dung lượng tối đa mà FRA được phép chiếm dụng trước khi khai báo vị trí lưu trữ. Nếu bạn cố tình đặt đường dẫn `DB_RECOVERY_FILE_DEST` khi kích thước đang bằng 0, Oracle sẽ báo lỗi từ chối.

**2. Sự khác nhau giữa Permanent Files và Transient Files trong Fast Recovery Area là gì?**
> **Trả lời:**
> - **Permanent Files:** Là các tệp tin thiết yếu đang hoạt động trực tiếp của database (Multiplexed Control Files, Online Redo Log members). Oracle cấm tuyệt đối và không bao giờ tự động xóa các file này.
> - **Transient Files:** Là các tệp tin tạm thời phục vụ cho sao lưu và khôi phục (Archived Redo Logs, RMAN Backups, Flashback Logs). Khi dung lượng FRA chạm trần, Oracle có thể tự động xóa các file này nếu chúng đã thỏa mãn chính sách lưu giữ để giải phóng chỗ trống.

**3. Ý nghĩa của cột `SPACE_RECLAIMABLE` trong view `V$RECOVERY_FILE_DEST` là gì?**
> **Trả lời:**
> Cột `SPACE_RECLAIMABLE` thể hiện dung lượng đĩa của các file trong FRA đã trở nên lỗi thời (Obsolete) theo chính sách lưu giữ của RMAN hoặc các archive log đã được sao lưu an toàn. Đây là lượng không gian "ảo" mà Oracle sẵn sàng tự động xóa bỏ ngay lập tức khi database cần chỗ trống để ghi thêm file mới mà không gây gián đoạn hệ thống.

**4. Điều gì sẽ xảy ra với các ứng dụng người dùng nếu vùng Fast Recovery Area bị đầy 100% và `SPACE_RECLAIMABLE = 0`?**
> **Trả lời:**
> Hệ thống sẽ rơi vào tình trạng **Treo tạm thời (Database Hang)**:
> - Tiến trình LGWR không thể switch sang Redo Log Group mới vì nhóm cũ chưa được tiến trình ARCH lưu thành Archive Log (do FRA hết chỗ).
> - Tất cả các câu lệnh DML (INSERT, UPDATE, DELETE) và COMMIT của người dùng sẽ bị đóng băng ở sự kiện chờ `log file switch (archiving needed)`.
> - Alert log sẽ báo lỗi `ORA-19809: limit exceeded for recovery files` và `ORA-19804`. Database chỉ hoạt động lại khi DBA tăng dung lượng `DB_RECOVERY_FILE_DEST_SIZE` hoặc xóa bớt archive log cũ bằng RMAN.

**5. Tại sao không nên đặt Fast Recovery Area trên cùng một ổ đĩa vật lý với các Datafiles của Database?**
> **Trả lời:**
> Theo nguyên tắc bảo vệ dữ liệu chống thảm họa phần cứng (Single Point of Failure): Nếu ổ đĩa vật lý bị cháy hoặc hỏng controller, toàn bộ cả Datafiles lẫn các bản sao lưu/Archive log trong FRA sẽ cùng biến mất một lúc, khiến bạn hoàn toàn mất khả năng phục hồi cơ sở dữ liệu. Tách riêng 2 vùng giúp đảm bảo khi ổ chứa Datafile bị hỏng, bản sao lưu trên ổ FRA vẫn an toàn để restore.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/66-fast-recovery-area.md`
