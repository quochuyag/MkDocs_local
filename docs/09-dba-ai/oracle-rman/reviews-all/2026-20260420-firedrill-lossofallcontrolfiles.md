---
title: '🚨 Báo Động Đỏ: Mất Toàn Bộ Control Files'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260420_FireDrill_LossOfAllControlFiles.md
---

# 🚨 Báo Động Đỏ: Mất Toàn Bộ Control Files

**Chế độ**: Fire Drill (Diễn tập sự cố khẩn cấp - Module 12)
**Ngày tạo**: 2026-04-20

## 1. Tình trạng sự cố
Vào lúc 11:00 AM thứ Hai, tất cả các instance của database `PAYDB` đột ngột bị sập (crashed). 
Khi bạn kiểm tra OS log, bạn phát hiện ra một Admin Storage đã format nhầm phân vùng LUN chứa **tất cả 3 bản multiplexed Control Files**.
Hiện tại hệ thống không thể khởi động được (chỉ lên được NOMOUNT) với lỗi:
`ORA-00205: error in identifying control file, check alert log for more info`

Database đang chạy ở chế độ ARCHIVELOG và tính năng `CONTROLFILE AUTOBACKUP` đã được **BẬT**. Bản backup gần nhất chạy vào đêm qua và các file archivelog từ đêm qua đến hiện tại vẫn còn trên đĩa.

## 2. Nhiệm vụ của bạn (DBA)
Bạn cần khôi phục lại Control File và mở lại Database để đưa hệ thống thanh toán `PAYDB` trở lại hoạt động mà **không được mất bất kỳ giao dịch nào** (Zero Data Loss).

## 3. Câu hỏi
1. Bạn có thể kết nối vào Recovery Catalog trong trường hợp này để hỗ trợ không?
2. Vì mất Control file, RMAN làm sao biết DBID để restore autobackup?
3. Bạn cần dùng các lệnh gì để khôi phục hoàn toàn (Full Recovery) sau khi đã lấy lại được Control File?

---

## 4. Hướng dẫn xử lý (Action Plan - Đáp án)

Dưới đây là các bước chuẩn xác của một Senior DBA để giải cứu hệ thống:

### Bước 1: Khởi động vào trạng thái NOMOUNT và Thiết lập DBID
Vì mất Control File, database chỉ có thể lên NOMOUNT. Bạn không thể kết nối tới Target bình thường mà RMAN nhận diện được metadata. Nếu bạn không dùng Catalog, bạn cần tự chỉ định DBID (DBID này có thể lấy từ tên file autobackup hoặc log cũ).
```rman
RMAN> CONNECT TARGET /
RMAN> SET DBID 123456789; -- (Thay bằng DBID thật của hệ thống)
RMAN> STARTUP NOMOUNT;
```

### Bước 2: Khôi phục Control File từ Autobackup
RMAN sẽ tìm bản Autobackup mới nhất (trong đường dẫn cấu hình mặc định hoặc FRA) và restore nó.
```rman
RMAN> RESTORE CONTROLFILE FROM AUTOBACKUP;
```
*Lưu ý: Nếu autobackup nằm ở chỗ khác, cần chỉ định `SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/path/%F';` trước khi restore.*

### Bước 3: Mount Database
Sau khi đã có Control File, bạn có thể mount database để đọc metadata.
```rman
RMAN> ALTER DATABASE MOUNT;
```

### Bước 4: Phục hồi cơ sở dữ liệu (Recovery)
Dù bạn không mất Datafile, nhưng Control File vừa được restore là từ đêm qua (hoặc bản backup gần nhất). Số SCN trong Control File đang cũ hơn Datafile. Do đó, RMAN cần scan các Archivelog/Redo log hiện tại để đồng bộ hóa.
```rman
RMAN> RECOVER DATABASE;
```
*RMAN sẽ tự động áp dụng các Archivelog và Online Redo Log hiện có trên đĩa để khôi phục tới thời điểm 11:00 AM (thời điểm bị crash). Nhờ vậy, sẽ không có giao dịch nào bị mất.*

### Bước 5: Mở lại Database (RESETLOGS)
Vì bạn đã restore Control File, Oracle BẮT BUỘC phải mở DB với tùy chọn `RESETLOGS` để khởi tạo lại chuỗi Redo (incarnation mới).
```rman
RMAN> ALTER DATABASE OPEN RESETLOGS;
```

> [!WARNING]
> Ngay sau khi `OPEN RESETLOGS`, bạn BẮT BUỘC phải chạy ngay một lệnh `BACKUP DATABASE PLUS ARCHIVELOG` toàn bộ hệ thống để đảm bảo an toàn cho Incarnation mới này!


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260420_FireDrill_LossOfAllControlFiles.md`
