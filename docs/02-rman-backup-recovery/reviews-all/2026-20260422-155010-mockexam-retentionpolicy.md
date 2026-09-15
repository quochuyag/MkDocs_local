---
title: '📝 Mock Exam: RMAN Retention Policy vs. Archivelog Deletion Policy'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260422_155010_MockExam_RetentionPolicy.md
---

# 📝 Mock Exam: RMAN Retention Policy vs. Archivelog Deletion Policy

**Chế độ**: Mock Exam (Architecture & Configuration - Module 06 & 07)
**Ngày tạo**: 2026-04-22 15:50:10

## 1. Tình huống sự cố
Hệ thống giám sát dung lượng đĩa (Disk Monitor) liên tục cảnh báo Fast Recovery Area (FRA) đang đạt 90% dung lượng.
Bạn kiểm tra cấu hình RMAN và thấy Retention Policy đã được set chuẩn:
`CONFIGURE RETENTION POLICY TO REDUNDANCY 2;`
Tuy nhiên, khi nhìn vào FRA, bạn thấy hàng ngàn Archive Logs từ 2 tuần trước vẫn còn nằm chình ình ở đó, không bị xóa tự động. Bạn cũng có cấu hình Backup Job hàng đêm chạy `BACKUP DATABASE PLUS ARCHIVELOG;` và kết thúc bằng `DELETE NOPROMPT OBSOLETE;`.

## 2. Nhiệm vụ của bạn (DBA)
1. Giải thích tại sao lệnh `DELETE OBSOLETE` lại không dọn dẹp các Archive logs cũ kia dù chính sách là Redundancy 2?
2. Sự khác biệt giữa **Backup Retention Policy** và **Archivelog Deletion Policy** là gì?
3. Viết Action Plan cấu hình chính xác để hệ thống tự động xóa Archive logs sau khi chúng đã an toàn trong các bản backup đĩa/tape.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích vấn đề
Nhiều DBA thường nhầm lẫn vai trò của các tham số cấu hình tự động.
- **`RETENTION POLICY` (Redundancy/Recovery Window)**: Tham số này dùng để kiểm soát RMAN sẽ giữ lại bao nhiêu bản **Full/Incremental Backup** hoặc giữ lại các bản backup phủ lấp số ngày chỉ định. Nó giúp quyết định file nào bị chuyển thành `OBSOLETE`. Tuy nhiên, Archivelog có một quy trình quản lý vòng đời riêng, đặc biệt nếu DB đang cấu hình Data Guard hoặc dùng cho các luồng khai thác dữ liệu khác (GoldenGate/Streams). Do đó, chỉ dựa vào `DELETE OBSOLETE` đôi khi không đủ mạnh/chính xác để giải phóng Archive log nếu không có Deletion Policy rõ ràng.
- **`ARCHIVELOG DELETION POLICY`**: Đây là chính sách định nghĩa chính xác **điều kiện nào thì một Archive log được phép xóa tự động** khỏi Fast Recovery Area (khi có áp lực về không gian đĩa) hoặc xóa bởi lệnh `BACKUP ARCHIVELOG ... DELETE INPUT`.

### Action Plan (Khắc phục sự cố)

**Bước 1: Kiểm tra cấu hình Deletion Policy hiện tại**
```rman
RMAN> SHOW ARCHIVELOG DELETION POLICY;
```
*Mặc định nó thường là `NONE`. Nếu là `NONE`, Oracle sẽ ngần ngại xóa archivelog vì không biết bạn đã backup chúng chưa hay Standby DB đã nhận được chúng chưa.*

**Bước 2: Cấu hình lại Archivelog Deletion Policy**
Vì bạn muốn đảm bảo Archive logs chỉ bị xóa **sau khi** chúng đã được backup (để an toàn), bạn có thể cấu hình số lần backup tối thiểu. Ở đây hệ thống có Redundancy 2, nên ta set Archive log phải được backup tối thiểu 2 lần ra Disk/Tape rồi mới cho phép dọn dẹp.
```rman
RMAN> CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 2 TIMES TO DEVICE TYPE DISK;

-- Nếu có Data Guard Standby, bạn phải cấu hình:
-- CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY;
```

**Bước 3: Dọn dẹp thủ công không gian ngay lúc này**
Sau khi cấu hình chính sách, bạn có thể buộc RMAN quét và xóa những file giờ đây đã thỏa mãn điều kiện bị xóa:
```rman
-- Xóa các archivelog đã obsolete theo chính sách
RMAN> CROSSCHECK ARCHIVELOG ALL;
RMAN> DELETE ARCHIVELOG ALL BACKED UP 2 TIMES TO DEVICE TYPE DISK;
```
*Hoặc trong cronjob hàng ngày, thay vì `BACKUP DATABASE PLUS ARCHIVELOG`, hãy đảm bảo dùng câu lệnh tối ưu:*
```rman
RMAN> BACKUP ARCHIVELOG ALL NOT BACKED UP 2 TIMES;
```

### 💡 Lưu ý cho Mock Exam:
FRA (Fast Recovery Area) là vùng không gian tự quản. Nếu không gian trống trong FRA tụt xuống thấp, database sẽ tự động kiểm tra `ARCHIVELOG DELETION POLICY`. Nếu có bất kỳ Archive log nào đã thỏa mãn chính sách (đã backup 2 lần), cơ sở dữ liệu sẽ tự động `unlink` (xóa) file đó để lấy không gian cho Archive log mới, giúp DB không bị treo lỗi `ORA-19809`.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260422_155010_MockExam_RetentionPolicy.md`
