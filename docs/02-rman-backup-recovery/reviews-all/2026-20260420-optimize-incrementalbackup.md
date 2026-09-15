---
title: '🛠️ Thử Thách Tối Ưu: Giải Quyết Nút Thắt Incremental Backup'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_Optimize_IncrementalBackup.md
---

# 🛠️ Thử Thách Tối Ưu: Giải Quyết Nút Thắt Incremental Backup

**Chế độ**: Tối ưu & Tái cấu trúc (Optimization Challenge - Module 5, 8)
**Ngày tạo**: 2026-04-20

## 1. Tình huống doanh nghiệp
Hệ thống Data Warehouse (`DWHDB`) của công ty có dung lượng **10TB**.
Chiến lược Backup hiện tại là:
- Chủ Nhật: Incremental Level 0 (Full) mất 14 tiếng.
- Thứ 2 đến Thứ 7: Incremental Level 1 (Differential) mất khoảng **8 tiếng**.

IT Manager không hiểu tại sao: *"Dữ liệu thay đổi mỗi ngày chỉ khoảng 50GB (rất ít), tại sao Incremental Level 1 lấy mỗi 50GB đó mà phải mất tới 8 TIẾNG để backup?"*
Do thời gian chạy backup 8 tiếng ban đêm đã lấn sang giờ làm việc buổi sáng (bắt đầu lúc 8:00 AM), hệ thống bị I/O bottleneck cực nặng.

### Script backup hiện tại của Level 1:
```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  BACKUP INCREMENTAL LEVEL 1 DATABASE FORMAT '/backup/inc1_%U.bkp';
}
```

## 2. Nhiệm vụ của bạn (DBA)
1. Giải thích cho sếp biết **tại sao** backup chỉ 50GB mà mất tới 8 tiếng?
2. Đề xuất công nghệ của Oracle để tối ưu thời gian Incremental Backup từ 8 tiếng xuống còn dưới 10 phút. Nêu lệnh thực thi.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích gốc rễ vấn đề (Nguyên nhân chậm):
Dù chỉ có 50GB dữ liệu thay đổi trên tổng số 10TB, nhưng theo mặc định, khi chạy lệnh `BACKUP INCREMENTAL LEVEL 1`, RMAN **bắt buộc phải quét (scan) toàn bộ 10TB datafiles** để kiểm tra giá trị SCN trên header của *từng block một* xem block nào đã thay đổi kể từ lần backup trước. 
Thao tác cày ải (scan) 10TB này tốn I/O khổng lồ và mất 8 tiếng, mặc dù kết quả lấy ra chỉ là 50GB.

### Giải pháp Tối ưu: Block Change Tracking (BCT)
Oracle cung cấp tính năng siêu việt tên là **Block Change Tracking (BCT)**.
Khi BCT được bật, một background process tên là `CTWR` (Change Tracking Writer) sẽ liên tục theo dõi các block bị thay đổi trong quá trình DB đang hoạt động và ghi danh sách block đó ra một file nhỏ (BCT file).
Khi RMAN chạy Incremental Backup, nó chỉ cần mở BCT file ra, đọc danh sách block cần backup và chạy thẳng đến các block đó để copy, **bỏ qua hoàn toàn bước scan 10TB datafiles**.

### Kịch bản Tái cấu trúc (Lệnh thực thi):

**Bước 1: Bật tính năng BCT trên Database (Dùng SQL*Plus)**
```sql
SQL> ALTER DATABASE ENABLE BLOCK CHANGE TRACKING 
     USING FILE '/u01/app/oracle/oradata/DWHDB/bct_file.trk';
```
*(File này dung lượng rất nhỏ, thường chỉ khoảng ~11MB cho mỗi TB database)*

**Bước 2: (Tùy chọn) Kiểm tra trạng thái BCT**
```sql
SQL> SELECT status, filename FROM v$block_change_tracking;
```

**Bước 3: Điều chỉnh Script Backup**
Thực tế Script RMAN không cần phải sửa đổi thêm tham số gì phức tạp. Chỉ cần tối ưu cấu hình channel để tự động. Tuy nhiên, hiệu năng bây giờ sẽ đạt tốc độ "Bàn thờ" (vài phút thay vì 8 tiếng).
```rman
RUN {
  BACKUP AS COMPRESSED BACKUPSET 
  INCREMENTAL LEVEL 1 DATABASE FORMAT '/backup/inc1_%U.bkp';
}
```

> [!TIP]
> Sự kết hợp giữa BCT (giảm đọc I/O) và COMPRESSION (giảm ghi I/O) sẽ biến chiến lược Incremental Backup thành vũ khí cực kỳ sắc bén cho các CSDL khổng lồ (VLDB).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_Optimize_IncrementalBackup.md`
