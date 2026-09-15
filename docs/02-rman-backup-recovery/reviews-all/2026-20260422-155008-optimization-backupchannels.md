---
title: '⚡ Tối Ưu Hóa: Tuning Kênh Backup RMAN Cho Hiệu Suất Tối Đa'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260422_155008_Optimization_BackupChannels.md
---

# ⚡ Tối Ưu Hóa: Tuning Kênh Backup RMAN Cho Hiệu Suất Tối Đa

**Chế độ**: Optimization (Performance - Module 12)
**Ngày tạo**: 2026-04-22 15:50:08

## 1. Tình huống sự cố
Trong hệ thống của một công ty tài chính, Database có kích thước 10TB. Bạn nhận được phàn nàn từ đội quản trị hệ thống rằng quá trình RMAN Full Backup hàng đêm (chạy ra hệ thống Disk/SAN) diễn ra quá chậm.
Thông số I/O trên SAN cho thấy dải băng thông (throughput) của hệ thống lưu trữ có khả năng ghi đến 1000 MB/s, nhưng RMAN chỉ đang ghi ở mức tà tà khoảng 150 MB/s. Job backup chạy một kênh duy nhất và thường kéo dài hơn 18 tiếng, vượt ra ngoài Maintenance Window.

## 2. Nhiệm vụ của bạn (DBA)
1. Xác định lý do tại sao RMAN không tận dụng hết băng thông của hệ thống lưu trữ.
2. Đề xuất và viết Action Plan để Tuning (tối ưu hóa) hiệu suất RMAN Backup thông qua việc điều chỉnh các Channel và các cấu hình I/O khác.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích vấn đề
Mặc định khi chạy RMAN, nếu bạn không cấu hình gì thêm, nó chỉ cấp phát **1 Channel** (1 tiến trình ghi file). Mỗi tiến trình đọc datafile rồi ghi ra backup piece sẽ có giới hạn tốc độ nhất định. Vì vậy, mặc dù đĩa cứng có thể chịu tải 1000 MB/s, 1 channel của RMAN không thể "ép" I/O lên mức đó.
Để giải quyết bài toán này, ta cần thực hiện **đọc và ghi song song (Parallelization)** bằng cách phân bổ nhiều kênh làm việc (Channels) và tối ưu hóa số lượng file xử lý.

### Action Plan (Khắc phục sự cố)

**Bước 1: Cấu hình Đa luồng (Parallelism)**
Xác định số lượng CPU Core còn rảnh trong Maintenance Window và năng lực của Storage. Giả sử máy chủ có 16 CPU và SAN rất mạnh, ta có thể thử nghiệm cấp phát 4 đến 8 kênh.
Bạn có thể cấu hình Parallelism ở mức Global (tác dụng cho mọi script):
```rman
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
```
Với lệnh này, RMAN sẽ tự động sinh ra 4 tiến trình ORA_DISK_1 đến ORA_DISK_4 chạy song song khi bạn gọi `BACKUP DATABASE`. Thời gian dự kiến có thể giảm từ 18 tiếng xuống còn dưới 5 tiếng.

**Bước 2: Tối ưu hóa việc đọc Datafiles (FILESPERSET)**
Mặc định, RMAN nhóm 64 datafiles vào một Backup Set (nếu có đủ số file). Nếu một Backup Set có quá nhiều file nhỏ hoặc file rác, tiến trình có thể bị chậm. Tối ưu hóa tham số này giúp kiểm soát luồng đọc dữ liệu từ đĩa.
Nên phối hợp số `FILESPERSET` phù hợp với số lượng Channel.
Ví dụ trong Run block:
```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
  BACKUP AS BACKUPSET 
         FILESPERSET 4 
         DATABASE FORMAT '/backup/db_%U.bkp';
}
```

**Bước 3: Tối ưu hóa I/O Asynchronous (Bất đồng bộ)**
Đảm bảo hệ điều hành (OS) và Oracle hỗ trợ ASYNC I/O, giúp các tiến trình đọc/ghi của RMAN không phải chờ đợi lẫn nhau.
Kiểm tra tham số DB:
```sql
SQL> SHOW PARAMETER disk_asynch_io;
-- Nếu nó là FALSE, hãy bật lên:
SQL> ALTER SYSTEM SET disk_asynch_io=TRUE SCOPE=SPFILE;
```

**Bước 4: Điều chỉnh kích thước MAXPIECESIZE (Nếu cần)**
Nếu filesystem lưu backup (ext4, NTFS...) hoặc môi trường Cloud có giới hạn file size, hãy chặt nhỏ Backup Piece để nhiều channel có thể ghi các file nhỏ liên tục mà không bị nghẽn ở hệ điều hành.
```rman
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK MAXPIECESIZE 10G;
```

### 💡 Bài học kinh nghiệm:
Việc tăng số channel (`PARALLELISM`) không phải lúc nào cũng tốt. Tăng quá nhiều kênh có thể gây ra hiện tượng **I/O Thrashing** (nút thắt cổ chai quay ngược về tốc độ đọc của đĩa chứa Datafile). Hãy thử nghiệm (baseline) từ 2, 4, rồi 8 kênh để tìm ra điểm cân bằng tối ưu (sweet spot) nhất cho hệ thống cụ thể của bạn.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260422_155008_Optimization_BackupChannels.md`
