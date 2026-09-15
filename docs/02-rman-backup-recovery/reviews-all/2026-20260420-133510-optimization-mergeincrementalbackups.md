---
title: '🛠️ Thử Thách Tối Ưu: Chiến Lược Incrementally Updated Backups'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133510_Optimization_MergeIncrementalBackups.md
---

# 🛠️ Thử Thách Tối Ưu: Chiến Lược Incrementally Updated Backups

**Chế độ**: Tối ưu & Tái cấu trúc (Optimization Challenge - Module 5, 8)
**Ngày tạo**: 2026-04-20 13:35:10

## 1. Tình huống doanh nghiệp
Dung lượng Database `LOGISTICS` là **15TB**.
Để phục hồi an toàn, sếp yêu cầu: "Bất kể database sập lúc nào, thời gian khôi phục (Recovery Time Objective - RTO) tối đa chỉ được **2 tiếng**".

Bạn phân tích thấy:
- Nếu mỗi tuần chạy Full Backup (Level 0) vào Chủ Nhật, các ngày khác chạy Incremental Level 1.
- Rủi ro: Rơi vào Thứ Bảy, Database sập. Để phục hồi, RMAN phải Restore bản Full 15TB (mất 12 tiếng) + Apply 6 file Level 1 từ thứ Hai đến thứ Bảy (mất 2 tiếng nữa). 
=> RTO = 14 tiếng. Chậm hơn yêu cầu của Sếp tận 7 lần!
- Cả team không thể chạy Full Backup 15TB mỗi ngày vì không đủ thời gian và ổ đĩa.

## 2. Nhiệm vụ của bạn (DBA)
Hãy dùng công nghệ tối thượng của RMAN để hóa giải nghịch lý này: Vừa không phải chạy Full Backup hàng ngày, vừa đảm bảo RTO chỉ mất đúng vài phút. Nêu tên công nghệ và Script.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Giải pháp Tối ưu: Incrementally Updated Backups (Image Copy Update)
Đây là chiến lược siêu hạng của Oracle.
1. Bạn tạo một bản Image Copy (bản copy nguyên xi, không nén) của toàn bộ database vào ngày Chủ Nhật đầu tiên.
2. Hằng ngày, bạn chạy Incremental Level 1 siêu nhỏ.
3. Bí mật nằm ở chỗ: Thay vì để dành các file Level 1 đó, bạn yêu cầu RMAN lấy file Level 1 vừa chụp, **bơm (apply) thẳng vào bản Image Copy** 15TB gốc của Chủ Nhật.
4. Kết quả: Bản sao lưu 15TB Chủ Nhật tự động được "nâng cấp" (roll forward) thành bản 15TB của Thứ Hai. Sang ngày mai, nó được nâng cấp thành bản của Thứ Ba...
Lúc nào trên đĩa bạn cũng có sẵn một bản "Full Backup mới cứng của ngày hôm qua" mà không hề tốn 12 tiếng I/O để tạo mới.

Khi DB sập, bạn chỉ việc gõ `SWITCH DATABASE TO COPY`. RMAN chĩa ngay lập tức DB sang dùng bản Image Copy này. Thời gian Restore = 0 giây. Thời gian apply archivelog của ngày hôm nay = vài phút. RTO vượt kỳ vọng.

### Kịch bản Tái cấu trúc (Lệnh thực thi chạy tự động mỗi ngày):
Đoạn script kinh điển sau nên được đưa vào cronjob chạy hàng ngày.

```rman
RUN {
  -- Tìm một bản Level 1 từ đĩa và bơm nó vào bản Image Copy đang có (Cập nhật Image)
  RECOVER COPY OF DATABASE WITH TAG 'daily_update';
  
  -- Tạo một bản Incremental Level 1 hôm nay (để dành mai bơm vào)
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'daily_update' DATABASE;
}
```

> [!TIP]
> Thuật ngữ chuyên ngành của kỹ thuật này là **"Roll Forward Image Copy"**. Mặc dù nó đòi hỏi thêm một lượng ổ đĩa SAN để chứa file Image Copy (to bằng đúng DB gốc), nhưng nó giải quyết triệt để bài toán RTO cực khắt khe cho các Very Large Database (VLDB).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133510_Optimization_MergeIncrementalBackups.md`
