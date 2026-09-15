---
title: 'Bài 78: Thực hiện Incremental Backups (Sao lưu tăng dần)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/78-incremental-backups.md
---

# Bài 78: Thực hiện Incremental Backups (Sao lưu tăng dần)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Nêu rõ các khái niệm về incremental backups.
- Quản lý tính năng Block Change Tracking.
- Tạo Incrementally updated backups (Bản sao lưu cập nhật tăng dần).

## Khái niệm về Incremental Backups
- Nếu Database của bạn rất lớn (ví dụ: vài Terabyte), việc sao lưu lại toàn bộ (Full backup) mỗi ngày là không thực tế vì mất quá nhiều thời gian và dung lượng lưu trữ.
- **Incremental Backups** ra đời để giải quyết vấn đề này. Nó chỉ sao lưu những data block (khối dữ liệu) đã thực sự bị thay đổi kể từ lần backup trước.

### Các cấp độ của Incremental Backup
RMAN chia incremental backups thành 2 cấp độ (Levels):
- **Level 0:** Sao lưu TẤT CẢ các block có chứa dữ liệu. Một bản Level 0 incremental backup về cơ bản giống hệt với Full backup, điểm khác biệt duy nhất là Level 0 có thể được dùng làm mốc cơ sở (base) cho các bản backup Level 1 sau này.
- **Level 1:** Chỉ sao lưu các block đã bị thay đổi kể từ lần backup trước đó.

## Hai loại Incremental Backups Level 1
Khi bạn thực hiện Level 1 backup, có 2 loại hình thức:

1. **Differential (Mặc định):**
   - RMAN sẽ sao lưu tất cả các block đã thay đổi kể từ lần backup incremental gần nhất (có thể là Level 1 hoặc Level 0).
   - *Ưu điểm:* File backup rất nhỏ, chạy cực kỳ nhanh.
   - *Nhược điểm:* Khi cần khôi phục (restore), bạn phải đắp (apply) từng bản backup một theo thứ tự, làm chậm quá trình recovery.

2. **Cumulative (Tích lũy):**
   - RMAN sẽ sao lưu tất cả các block đã thay đổi kể từ bản backup **Level 0** gần nhất.
   - *Ưu điểm:* Khôi phục cực nhanh, vì bạn chỉ cần bản Level 0 và một bản Cumulative Level 1 duy nhất này (bản này đã gom toàn bộ thay đổi qua các ngày).
   - *Nhược điểm:* File backup sẽ to dần lên theo từng ngày và chạy chậm hơn so với Differential.
   - *Lệnh:* Thêm từ khóa `CUMULATIVE` (ví dụ: `BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE`).

## Tính năng Block Change Tracking (BCT)
- Ở chế độ bình thường, để biết block nào đã thay đổi, RMAN phải quét (scan) **toàn bộ** các datafiles. Quá trình này ngốn rất nhiều I/O và làm chậm hệ thống.
- **Block Change Tracking (BCT)** là một file nhỏ được sinh ra bên ngoài database để ghi nhận (track) các block bị thay đổi ngay khi chúng xảy ra.
- Khi có BCT, lệnh RMAN Level 1 backup chỉ việc đọc file BCT này để biết chính xác block nào cần sao lưu mà không cần quét lại datafiles.

### Bật và kiểm tra BCT
```sql
-- Bật BCT (lưu file ở vị trí tự động hoặc chỉ định)
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING USING FILE '/u01/app/oracle/bct.f';

-- Kiểm tra trạng thái
SELECT status, filename FROM v$block_change_tracking;
```

## Incrementally Updated Backups
- Mục đích: Tránh việc phải thực hiện bản Level 0 backup định kỳ (ví dụ cuối mỗi tuần), vốn tốn rất nhiều thời gian trên DB lớn.
- **Cơ chế hoạt động:**
  1. Tạo một bản Image Copy (Level 0) của database.
  2. Hàng ngày, tạo các bản Incremental Level 1 backups.
  3. RMAN có thể **áp dụng (apply)** các bản thay đổi Level 1 này đắp thẳng vào bản Image Copy (Level 0) ban đầu. Lúc này, bản Image Copy cũ đã biến thành bản Level 0 mới nhất mà không cần phải thực hiện sao lưu lại toàn bộ database.

### Kịch bản thực thi (Run Block)
```rman
RUN {
  -- Cập nhật bản Image Copy bằng các thay đổi từ bản Level 1
  RECOVER COPY OF DATABASE WITH TAG 'incr_update';
  
  -- Tạo bản Incremental Level 1 backup cho các thay đổi mới nhất
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_update' DATABASE;
}
```

---
## Câu hỏi ôn tập

**Câu 1: Điểm khác biệt giữa Full Backup và Incremental Level 0 Backup là gì?**
- **Trả lời:** Về mặt dữ liệu, cả hai đều sao lưu toàn bộ block có chứa dữ liệu. Điểm khác biệt duy nhất là Incremental Level 0 đóng vai trò là "mốc cơ sở" (base) để RMAN có thể tính toán các thay đổi cho các bản backup Level 1 sau này. Bản Full Backup không làm được điều này.

**Câu 2: Nếu tôi muốn khôi phục nhanh (Fast Recovery), tôi nên chọn loại Incremental Level 1 nào? Differential hay Cumulative?**
- **Trả lời:** Nên chọn **Cumulative**. Mặc dù tạo Cumulative backup tốn dung lượng hơn, nhưng khi khôi phục bạn chỉ cần cần đắp 1 file Cumulative duy nhất lên bản Level 0. Trong khi với Differential, bạn phải đắp tất cả các file differential tạo ra từ đầu tuần tới giờ.

**Câu 3: Tại sao nên bật Block Change Tracking (BCT) trong hệ thống Production?**
- **Trả lời:** Để tối ưu hóa thời gian backup. Thay vì RMAN phải đọc toàn bộ dung lượng của datafile (hàng Terabyte) để tìm ra vài Megabyte dữ liệu thay đổi, nó chỉ cần đọc file BCT để biết ngay vị trí các block thay đổi. Giảm tải I/O cực kỳ lớn.

**Câu 4: Incrementally Updated Backups giúp giải quyết bài toán gì?**
- **Trả lời:** Giúp loại bỏ hoàn toàn việc phải tạo lại một bản sao lưu Level 0 khổng lồ (vào dịp cuối tuần/cuối tháng). Bạn chỉ mất thời gian tạo bản copy 1 lần duy nhất, sau đó dùng các bản Level 1 đắp vào để luôn giữ cho bản copy này ở trạng thái mới nhất.

**Câu 5: File BCT có nên lưu cùng chung ổ đĩa với Datafiles không?**
- **Trả lời:** Nên lưu file BCT trên ổ đĩa có tốc độ I/O nhanh và nếu có thể thì tách biệt với ổ đĩa chứa Datafile để giảm sự cạnh tranh I/O, vì file BCT sẽ được Oracle ghi liên tục khi có các giao dịch xảy ra.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/78-incremental-backups.md`
