---
title: '⏱️ Thi Thử: Các Chính Sách Lưu Giữ (Retention Policies)'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133501_MockExam_RetentionPolicies.md
---

# ⏱️ Thi Thử: Các Chính Sách Lưu Giữ (Retention Policies)

**Chế độ**: Mock Exam (Module 6)
**Ngày tạo**: 2026-04-20 13:35:01

## 1. Tình huống / Đề bài
Trong một đợt tuyển dụng DBA, bạn nhận được bộ 3 câu hỏi trắc nghiệm và tự luận ngắn về cách RMAN quản lý chính sách lưu giữ bản sao lưu (Retention Policy). Hãy trả lời và giải thích lý do.

**Câu 1:** 
Lệnh `CONFIGURE RETENTION POLICY TO REDUNDANCY 3;` có ý nghĩa gì?
A) RMAN sẽ tự động xóa các bản sao lưu cũ hơn 3 ngày.
B) RMAN sẽ giữ lại đúng 3 bản sao lưu Full/Level 0 mới nhất cho mỗi datafile, các bản cũ hơn thứ 3 sẽ bị đánh dấu OBSOLETE.
C) RMAN sẽ tạo 3 bản copy cho mỗi lần chạy backup.

**Câu 2:**
Sự khác biệt cốt lõi giữa trạng thái `OBSOLETE` và `EXPIRED` trong RMAN là gì?

**Câu 3:**
Làm thế nào để xóa TẤT CẢ các bản backup đã vi phạm chính sách lưu giữ mà không bị RMAN hỏi lại (prompt) (Xóa tự động bằng cronjob)?

---

## 2. Hướng dẫn xử lý (Action Plan - Đáp án)

### Đáp án Câu 1
**Đáp án đúng: B**
- Lệnh này cấu hình chính sách theo "số lượng bản sao" (Redundancy) thay vì thời gian (Recovery Window). RMAN sẽ luôn đảm bảo có ít nhất 3 bản Full Backup / Level 0 hợp lệ có thể dùng để restore. Từ bản thứ 4 trở về trước, RMAN sẽ coi là dư thừa (`OBSOLETE`).

### Đáp án Câu 2
- **OBSOLETE (Lỗi thời)**: Là trạng thái do RMAN tự suy luận logic. File backup vẫn đang nằm sờ sờ trên ổ cứng, hoàn toàn khỏe mạnh, nhưng RMAN thấy nó đã "quá già" hoặc "quá dư thừa" so với Retention Policy (như REDUNDANCY 3 ở câu 1). Ta dùng lệnh `DELETE OBSOLETE` để dọn dẹp chúng.
- **EXPIRED (Mất tích)**: Là trạng thái vật lý. RMAN ghi trong sổ (Catalog/Controlfile) là có bản backup đó, nhưng khi chạy lệnh `CROSSCHECK`, RMAN mò ra đường dẫn OS thì không thấy file đâu (có thể do ai đó lỡ tay `rm -rf` hoặc ổ đĩa chết). File đã bốc hơi thực sự. Ta dùng lệnh `DELETE EXPIRED` để xóa thông tin rác trong sổ của RMAN.

### Đáp án Câu 3
Để script tự động xóa các bản backup lỗi thời mà không bị treo vì chờ người dùng gõ "YES", hãy thêm tham số `NOPROMPT`:
```rman
RMAN> DELETE NOPROMPT OBSOLETE;
```
*(Tham số này cực kỳ quan trọng khi viết shell script chạy qua đêm bằng Crontab).*


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133501_MockExam_RetentionPolicies.md`
