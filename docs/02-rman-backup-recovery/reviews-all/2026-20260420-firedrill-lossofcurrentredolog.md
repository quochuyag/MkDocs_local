---
title: '🚨 Báo Động Đỏ: Mất Current Redo Log Khi DB Đang Chạy'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_FireDrill_LossOfCurrentRedoLog.md
---

# 🚨 Báo Động Đỏ: Mất Current Redo Log Khi DB Đang Chạy

**Chế độ**: Fire Drill (Diễn tập sự cố khẩn cấp - Module 12)
**Ngày tạo**: 2026-04-20

## 1. Tình trạng sự cố
Hệ thống Database `FINANCE` đột nhiên treo cứng. 
Kiểm tra Alert Log, bạn thấy những dòng đỏ lừ:
```text
ORA-00313: open failed for members of log group 2 of thread 1
ORA-00312: online log 2 thread 1: '/u01/app/oracle/oradata/FINANCE/redo02a.log'
```
Storage báo cáo ổ đĩa chứa Log Group 2 vừa bị chết hoàn toàn do cháy controller. Đen đủi thay, Group 2 đang ở trạng thái **CURRENT** (chứa các giao dịch đang diễn ra chưa kịp đẩy xuống Datafiles, và chưa được Archive).
Database đã tự động CRASH (sập).

## 2. Nhiệm vụ của bạn (DBA)
Đưa database trở lại hoạt động. Bạn buộc phải đối mặt với một sự thật: Việc mất **CURRENT** online redo log đồng nghĩa với việc **SẼ MẤT DỮ LIỆU** (những giao dịch chưa commit hoặc vừa commit chưa được ghi vào datafiles). Nhiệm vụ của bạn là khôi phục Database với sự mất mát dữ liệu là tối thiểu (Incomplete Recovery).

## 3. Câu hỏi
1. Bạn có thể dùng `RECOVER DATABASE` thông thường trong trường hợp này không?
2. Cú pháp nào để yêu cầu RMAN khôi phục dữ liệu đến mức tối đa có thể (trước thời điểm cái log bị hỏng)?
3. Hành động bắt buộc sau khi Incomplete Recovery là gì?

---

## 4. Hướng dẫn xử lý (Action Plan - Đáp án)

Đây là một trong những tình huống "tồi tệ nhất" với DBA. Mất CURRENT Redo Log nghĩa là bạn mất các giao dịch.

### Bước 1: Xác nhận tình trạng và dọn dẹp
Database đang sập. Bạn cần khởi động nó lên chế độ MOUNT để RMAN có thể can thiệp.
```rman
RMAN> STARTUP MOUNT;
```

### Bước 2: Thực hiện Incomplete Recovery (UNTIL CANCEL)
Vì bạn mất chuỗi redo tại Group 2, bạn chỉ có thể phục hồi dữ liệu từ các bản backup và archivelog lên tới ĐÚNG TRƯỚC thời điểm chuyển sang Log Group 2.
Lệnh tối ưu nhất trong tình huống này là:
```rman
RMAN> RECOVER DATABASE UNTIL CANCEL;
```
*Ghi chú: Lệnh `UNTIL CANCEL` thông báo cho quá trình recovery cứ áp dụng lần lượt các Archivelog. Đến khi nó cần cái Redo Log bị hỏng (Group 2) và không tìm thấy, nó sẽ báo lỗi và dừng lại an toàn ở trạng thái nhất quán ngay trước đó.*

### Bước 3: Mở lại Database với Resetlogs
Vì bạn đã thực hiện Incomplete Recovery (khôi phục không hoàn toàn), chuỗi SCN đã bị cắt đứt. Bạn BẮT BUỘC phải khởi tạo lại chuỗi redo log mới (Incarnation mới) và dọn dẹp các log cũ bị hỏng.
```rman
RMAN> ALTER DATABASE OPEN RESETLOGS;
```
*Lúc này Oracle sẽ tự động tạo lại (recreate) các file Redo Log trống mới trên đĩa (nếu đĩa cũ hỏng, bạn cần dùng `ALTER DATABASE RENAME FILE` trước đó để trỏ sang ổ đĩa mới).*

> [!CAUTION]
> **Hậu quả**: Các giao dịch nằm trong Group 2 đã vĩnh viễn bốc hơi. Bạn cần báo cáo ngay với bộ phận Nghiệp vụ/Kế toán để đối soát và nhập lại các giao dịch trong khoảng thời gian vài phút trước khi sập hệ thống.
> Đừng quên chạy `BACKUP DATABASE PLUS ARCHIVELOG` ngay lập tức để bảo vệ Incarnation mới!


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_FireDrill_LossOfCurrentRedoLog.md`
