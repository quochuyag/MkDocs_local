---
title: '🔗 Kiến Trúc Chéo: Đồng Bộ Catalog Từ Máy Chủ Dự Phòng (Data Guard)'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133509_CrossModule_CatalogResyncFromStandby.md
---

# 🔗 Kiến Trúc Chéo: Đồng Bộ Catalog Từ Máy Chủ Dự Phòng (Data Guard)

**Chế độ**: Kiến trúc chéo (Cross-Module: Module 9 + Data Guard)
**Ngày tạo**: 2026-04-20 13:35:09

## 1. Tình huống doanh nghiệp
Hệ thống ngân hàng của bạn gồm 2 máy chủ: 
1. Máy chủ chính `PRIMARY_DB` đặt tại Hà Nội.
2. Máy chủ dự phòng `STANDBY_DB` đặt tại TP.HCM (sử dụng Oracle Data Guard đồng bộ real-time).

Để giảm tải I/O cho máy chủ chính (Hà Nội), bạn quyết định đẩy Job Backup hàng đêm sang chạy trên máy chủ dự phòng `STANDBY_DB` (TP.HCM). RMAN hoàn toàn hỗ trợ chạy backup trên Standby.
Bạn cũng có một `RCAT` (Recovery Catalog) đặt tại trung tâm thứ 3. Mọi lịch sử backup trên Standby đều đổ vào Catalog này.

**Vấn đề:** 
Tuần trước bạn chạy Backup trên Standby, nhưng do Catalog DB bị bảo trì mạng, bản ghi backup đã **không được đồng bộ** vào Recovery Catalog. Hiện tại Controlfile của máy `STANDBY_DB` biết rõ nó đã lưu backup ở đâu, nhưng Recovery Catalog `RCAT` thì trắng trơn, dẫn đến cảnh báo báo cáo hàng ngày bị hụt.

## 2. Nhiệm vụ của bạn (DBA)
Làm thế nào để đồng bộ (Resync) siêu dữ liệu backup từ máy chủ `STANDBY_DB` lên `RCAT`?
Điều kiện: Máy chủ `STANDBY_DB` đang ở trạng thái MOUNTED hoặc READ ONLY (như mọi Standby thông thường).

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Đây là đỉnh cao của quản trị RMAN trong môi trường Enterprise Data Guard.
Trong môi trường Data Guard, `PRIMARY` và `STANDBY` dùng chung 1 DBID. Catalog đủ thông minh để biết 2 anh chàng này là một. Tuy nhiên, nó cần bạn chỉ định RMAN connect vào đúng nơi đang nắm giữ sự thật.

### Bước 1: Kết nối đúng đích
Vì bản backup được thực thi trên máy `STANDBY_DB`, nên metadata của nó nằm ở Controlfile của `STANDBY_DB`. Bạn phải dùng RMAN kết nối với tư cách là TARGET vào máy Standby, và kết nối CATALOG vào `RCAT`.

Từ terminal (đứng tại site TP.HCM):
```bash
rman TARGET sys/pass@STANDBY_DB CATALOG rman/catpass@RCAT
```

### Bước 2: Thực thi đồng bộ ngược
Bình thường lệnh `RESYNC CATALOG` sẽ đổ dữ liệu từ Target lên Catalog. Vì bạn đang đứng ở Target là Standby DB, RMAN sẽ tự động lôi các metadata backup ẩn giấu trong Controlfile của con Standby này và chích (inject) vào Catalog.

```rman
RMAN> RESYNC CATALOG;
```

### Hậu trường:
Sau khi lệnh hoàn tất, Recovery Catalog giờ đây đã có danh sách toàn bộ các file backup nằm trên đĩa cứng tại TP.HCM. 
Trải nghiệm ma thuật: Ngày mai, nếu máy chủ `PRIMARY_DB` (Hà Nội) bị cháy, bạn mở máy `STANDBY_DB` lên làm Primary, vào RMAN (lúc này nó đã được nâng cấp), gõ lệnh `RESTORE`, nó sẽ tra trong Catalog và lập tức tìm thấy file backup đêm qua nó tự tạo! Mọi thứ liên kết hoàn hảo dưới chung 1 DBID.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133509_CrossModule_CatalogResyncFromStandby.md`
