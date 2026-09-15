---
title: '⏱️ Thi Thử: Quản Lý Recovery Catalog'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133506_MockExam_CatalogCommands.md
---

# ⏱️ Thi Thử: Quản Lý Recovery Catalog

**Chế độ**: Mock Exam (Module 9)
**Ngày tạo**: 2026-04-20 13:35:06

## 1. Tình huống / Đề bài
Để chứng minh sự am hiểu về Recovery Catalog, bạn phải vượt qua 3 câu hỏi nhanh dưới đây.

**Câu 1:** 
Khi bạn thêm một Database mới vào hệ thống và muốn RMAN quản lý nó qua Recovery Catalog, bạn dùng lệnh gì sau khi kết nối RMAN với Catalog?
A) `ADD DATABASE;`
B) `REGISTER DATABASE;`
C) `ENROLL DATABASE;`

**Câu 2:**
Controlfile của Target DB vừa được giãn ra (thêm datafile mới). Bạn muốn Cập nhật ngay thông tin thay đổi này vào Recovery Catalog, lệnh nào sau đây là ĐÚNG?
A) `UPDATE CATALOG;`
B) `SYNC CATALOG;`
C) `RESYNC CATALOG;`

**Câu 3:**
Một trong những siêu tính năng của Recovery Catalog mà Controlfile nội bộ KHÔNG có là gì?
A) Lưu giữ được lịch sử backup lâu hơn thời gian định sẵn trong thông số `CONTROL_FILE_RECORD_KEEP_TIME`.
B) Tự động sửa lỗi Block.
C) Tự động sinh Script backup.

---

## 2. Hướng dẫn xử lý (Action Plan - Đáp án)

### Đáp án Câu 1
**Đáp án đúng: B (`REGISTER DATABASE;`)**
- Quy trình chuẩn: Kết nối tới Target DB và Catalog DB trong RMAN. Đảm bảo Target DB đang ở MOUNT hoặc OPEN. Sau đó chạy lệnh `REGISTER DATABASE;`. Thông tin DBID của Target sẽ được ghi vào sổ của Catalog.

### Đáp án Câu 2
**Đáp án đúng: C (`RESYNC CATALOG;`)**
- Lệnh `RESYNC CATALOG` sẽ ép RMAN so sánh metadata từ Controlfile của Target DB và copy những dòng mới nhất (như thêm logfile, datafile, bản backup mới) sang Schema của Catalog. *(Thực tế RMAN thường tự động resync khi bạn chạy backup, nhưng chủ động resync sau khi đổi cấu trúc là Best Practice).*

### Đáp án Câu 3
**Đáp án đúng: A**
- Controlfile của DB rất nhỏ, nó sẽ ghi đè các bản ghi lịch sử backup cũ sau một khoảng thời gian (mặc định là 7 ngày theo tham số `CONTROL_FILE_RECORD_KEEP_TIME`). 
- **Recovery Catalog** là một Database độc lập, nó lưu giữ lịch sử backup MÃI MÃI, qua hàng chục năm, rất tiện cho Kiểm toán (Audit) và lưu trữ dài hạn. Đồng thời Catalog còn chứa được tính năng `STORED SCRIPTS` (kịch bản lưu sẵn).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133506_MockExam_CatalogCommands.md`
