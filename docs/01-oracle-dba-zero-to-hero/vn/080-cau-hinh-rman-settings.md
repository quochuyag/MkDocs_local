---
title: 'Bài 80: Cấu hình RMAN Persistent Settings'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/80-cau-hinh-rman-settings.md
---

# Bài 80: Cấu hình RMAN Persistent Settings

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Quản lý các cấu hình bền vững (persistent settings) của RMAN.
- Định cấu hình retention policy (chính sách lưu giữ).
- Quản lý các file backup đã hết hạn (obsolete) và bị mất (expired).

## Khái niệm về RMAN Persistent Settings
- Khi bạn chạy lệnh `BACKUP`, RMAN sẽ sử dụng các thiết lập mặc định nếu bạn không cung cấp các tham số cụ thể. 
- Những cài đặt mặc định này có thể được cấu hình lại để phù hợp với hệ thống của bạn, và chúng được gọi là **Persistent Settings** (thiết lập bền vững), vì chúng sẽ được lưu lại trong Control File của database (hoặc Recovery Catalog) và áp dụng cho mọi phiên làm việc tiếp theo.
- Lệnh để cấu hình là `CONFIGURE`. 
- Lệnh để hiển thị các cấu hình hiện tại là `SHOW ALL`. 
- Lệnh để đưa một cấu hình về lại mặc định ban đầu là `CONFIGURE ... CLEAR`.

### Một số thiết lập phổ biến:
- `CONFIGURE DEFAULT DEVICE TYPE TO DISK;` (Mặc định backup ra đĩa).
- `CONFIGURE CONTROLFILE AUTOBACKUP ON;` (Tự động backup Control file như đã học).
- `CONFIGURE DEVICE TYPE DISK PARALLELISM 2;` (Sử dụng 2 luồng song song để backup).

## Quản lý Retention Policy (Chính sách lưu giữ)
**Retention Policy** là chính sách quyết định xem một bản sao lưu (backup) cần được lưu giữ trong bao lâu trước khi nó được coi là "không còn cần thiết" (obsolete).
Có hai kiểu thiết lập Retention Policy:

1. **Recovery Window (Khung thời gian khôi phục):**
   - Đảm bảo rằng bạn luôn có đủ các file backup để khôi phục cơ sở dữ liệu về bất kỳ thời điểm nào trong một khoảng thời gian N ngày gần nhất.
   - *Cú pháp:* `CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;`
   - Nghĩa là: RMAN sẽ giữ lại mọi backup cần thiết để có thể point-in-time recovery về bất cứ giây phút nào trong 7 ngày qua.

2. **Redundancy (Độ dư thừa):**
   - Đảm bảo rằng bạn luôn giữ lại ít nhất N bản backup toàn bộ (full/level 0) của mỗi datafile.
   - *Cú pháp:* `CONFIGURE RETENTION POLICY TO REDUNDANCY 2;`
   - Nghĩa là: RMAN luôn giữ lại 2 bản full backup mới nhất. Bản thứ 3 trở về trước sẽ bị coi là obsolete. (Đây là thiết lập mặc định với `REDUNDANCY 1`).

## Xử lý các Backup "Obsolete" và "Expired"

### Obsolete Backups (Bản sao lưu đã lỗi thời)
- Bất kỳ bản backup nào không còn thỏa mãn điều kiện của Retention Policy (ví dụ: cũ hơn 7 ngày, hoặc là bản full backup thứ 3) sẽ bị đánh dấu là **OBSOLETE**.
- *Cách xem:* `REPORT OBSOLETE;`
- *Cách xóa:* `DELETE OBSOLETE;` (RMAN sẽ tự động tìm và xóa các file backup đã lỗi thời này để giải phóng dung lượng cho FRA).

### Expired Backups (Bản sao lưu bị thất lạc)
- Nếu một file backup vật lý bị ai đó xóa nhầm trên hệ điều hành (ví dụ dùng lệnh `rm` trong Linux) nhưng RMAN không biết điều đó, khi RMAN kiểm tra nó sẽ không thấy file đâu.
- Khi bạn chạy lệnh `CROSSCHECK BACKUP;`, RMAN sẽ đối chiếu kho lưu trữ (repository) với file thực tế trên ổ cứng. Nếu file thực tế đã bị mất, RMAN sẽ đánh dấu bản backup đó là **EXPIRED**.
- *Cách xóa:* `DELETE EXPIRED BACKUP;` (Lệnh này không xóa file vật lý vì nó đã mất rồi, nó chỉ xóa dòng ghi chép về bản backup đó trong RMAN repository).

---
## Câu hỏi ôn tập

**Câu 1: Lệnh nào dùng để đưa một cấu hình RMAN cụ thể trở về trạng thái mặc định của Oracle?**
- **Trả lời:** Dùng lệnh `CONFIGURE <tên_cấu_hình> CLEAR;`. Ví dụ: `CONFIGURE RETENTION POLICY CLEAR;`.

**Câu 2: Nếu bạn thiết lập `REDUNDANCY 2`, và bạn vừa thực hiện bản backup thứ 3, chuyện gì sẽ xảy ra với bản backup đầu tiên?**
- **Trả lời:** Bản backup thứ 1 (cũ nhất) sẽ tự động bị RMAN đánh dấu là `OBSOLETE` vì bạn chỉ yêu cầu giữ lại 2 bản gần nhất.

**Câu 3: Sự khác biệt giữa OBSOLETE và EXPIRED là gì?**
- **Trả lời:** OBSOLETE là bản backup vật lý vẫn còn trên đĩa, nhưng RMAN cho rằng nó không còn cần thiết nữa (dựa trên retention policy). EXPIRED là bản backup đáng lẽ phải còn, nhưng khi RMAN kiểm tra ổ đĩa thì phát hiện nó đã bị mất/xóa ngoài hệ điều hành.

**Câu 4: KhiFRA (Fast Recovery Area) bị đầy, Oracle có tự động xóa các file OBSOLETE không?**
- **Trả lời:** Có. Oracle sẽ tự động xóa các file đã được đánh dấu là OBSOLETE trong FRA khi nó cần thêm không gian đĩa cho các file quan trọng mới.

**Câu 5: Tại sao bạn cần phải chạy lệnh `CROSSCHECK`?**
- **Trả lời:** Để đồng bộ hóa thông tin giữa RMAN repository (lưu trong Control file) và thực trạng các file vật lý trên hệ điều hành, giúp phát hiện ra các file bị xóa thủ công ngoài OS và cập nhật trạng thái của chúng thành EXPIRED.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/80-cau-hinh-rman-settings.md`
