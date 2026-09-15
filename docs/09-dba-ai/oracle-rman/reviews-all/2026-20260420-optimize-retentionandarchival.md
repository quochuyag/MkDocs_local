---
title: '🛠️ Thử Thách Tối Ưu: Bài Toán Archival Backup (Lưu Trữ Dài Hạn)'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260420_Optimize_RetentionAndArchival.md
---

# 🛠️ Thử Thách Tối Ưu: Bài Toán Archival Backup (Lưu Trữ Dài Hạn)

**Chế độ**: Tối ưu & Tái cấu trúc (Optimization Challenge - Module 6, 8)
**Ngày tạo**: 2026-04-20

## 1. Tình huống doanh nghiệp
Cơ sở dữ liệu `HCMDB` có chính sách Retention Policy (Thời gian lưu giữ bản sao lưu) được cấu hình là:
`CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;`

Điều này có nghĩa là mọi bản backup cũ hơn 7 ngày sẽ bị RMAN coi là `OBSOLETE` và sẽ bị xóa đi khi chạy lệnh `DELETE OBSOLETE` hàng ngày. Hệ thống đĩa (SAN) đã được căn chuẩn để chỉ chứa vừa đủ 7 ngày backup.

Hôm nay là ngày 31/12 (Cuối năm). Bộ phận Kiểm toán (Audit) yêu cầu: 
*"Hãy thực hiện một bản Backup Chốt sổ Cuối năm nay. Bản backup này bắt buộc phải được giữ lại trên hệ thống đĩa trong vòng **3 năm (1095 ngày)** để phục vụ thanh tra."*

### Thao tác của DBA mới (Junior):
Người đồng nghiệp Junior của bạn định cấu hình lại toàn bộ hệ thống:
```rman
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 1095 DAYS;
RMAN> BACKUP DATABASE;
```

## 2. Nhiệm vụ của bạn (DBA)
1. Hãy chỉ ra hậu quả tai hại (Thảm họa dung lượng) nếu làm theo cách của bạn Junior.
2. Viết câu lệnh chuẩn để thực hiện một bản "Archival Backup" (Backup lưu trữ dài hạn) chuyên biệt, giải quyết triệt để yêu cầu của Audit mà KHÔNG động chạm đến Retention Policy chung của hệ thống.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích hậu quả nếu làm theo cách Junior:
Đổi Retention Policy toàn hệ thống thành `1095 DAYS` (3 năm) có nghĩa là TẤT CẢ các bản backup hàng ngày (từ giờ trở đi) đều sẽ được lưu lại trong 3 năm. Lệnh `DELETE OBSOLETE` sẽ mất tác dụng dọn rác.
**Hậu quả**: Ổ cứng SAN (vốn chỉ thiết kế cho 7 ngày) sẽ đầy 100% (Disk Full) chỉ trong chưa đầy 2 tuần tiếp theo, khiến cho database treo cứng (Archiver bị kẹt).

### Giải pháp Tối ưu: Archival Backup (Sao lưu Ngoại lệ)
RMAN có tính năng `KEEP` dành riêng cho mục đích tạo ra một bản backup "miễn nhiễm" với Retention Policy. Nó được đánh dấu là tài sản lưu trữ dài hạn.

### Kịch bản Tái cấu trúc (Lệnh thực thi):

Bạn để nguyên Retention Policy là 7 ngày. Sau đó, chạy một lệnh BACKUP duy nhất như sau:

```rman
RMAN> BACKUP DATABASE
      FORMAT '/backup/longterm/yearend_%U.bkp'
      KEEP UNTIL TIME 'SYSDATE+1095'
      RESTORE POINT 'YEAR_END_2026';
```

### Phân tích giá trị của đoạn Script:
1. **KEEP UNTIL TIME 'SYSDATE+1095'**: Đánh dấu bản backup cụ thể này được giữ lại đúng 1095 ngày. Lệnh `DELETE OBSOLETE` hàng ngày khi quét qua bản backup này sẽ thấy cờ "KEEP" và **bỏ qua**, không xóa nó.
2. Khóa học khuyến nghị thêm `RESTORE POINT`: Tính năng này tạo ra một Restore Point lưu trong Control file, giúp bạn dễ dàng khôi phục lại (flashback/restore) database về đúng thời điểm đêm cuối năm bằng cái tên `YEAR_END_2026` dễ nhớ thay vì phải mò mẫm tìm SCN của 3 năm trước.
3. Gọn gàng và an toàn, SAN sẽ không bị nổ tung do cấu hình sai Retention Policy!


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260420_Optimize_RetentionAndArchival.md`
