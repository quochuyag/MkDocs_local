---
title: '🔗 Kiến Trúc Chéo: Active Duplicate Cùng Catalog'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_CrossModule_ActiveDuplicateWithCatalog.md
---

# 🔗 Kiến Trúc Chéo: Active Duplicate Cùng Catalog

**Chế độ**: Kiến trúc chéo (Cross-Module: Module 9 + 15)
**Ngày tạo**: 2026-04-20

## 1. Tình huống doanh nghiệp
Công ty bạn có một Database Production tên là `PRODDB` (Target). Mọi thông tin sao lưu của `PRODDB` được lưu tập trung trong một cơ sở dữ liệu `RCAT` (Recovery Catalog).

Hôm nay, bộ phận Testing cần bạn nhân bản (Clone) hệ thống `PRODDB` sang một máy chủ mới để tạo ra môi trường `TESTDB`.
Bạn quyết định sử dụng tính năng **Active Database Duplication** (nhân bản trực tiếp qua mạng từ DB đang chạy mà không cần restore từ file backup vật lý). Tuy nhiên, vì lý do an ninh, công ty bắt buộc mọi thao tác RMAN lớn phải được ghi nhận (logged) qua Recovery Catalog `RCAT`.

**Các tham số hệ thống:**
- Target DB: `sys/pass@PRODDB`
- Catalog DB: `rcman/catpass@RCAT`
- Auxiliary DB (Môi trường mới): `sys/pass@TESTDB`

## 2. Nhiệm vụ của bạn (DBA)
Thiết kế quy trình thực hiện (Workflow) và viết chuỗi lệnh RMAN kết nối **3 đỉnh tam giác** (Target, Catalog, Auxiliary) để thực thi lệnh `DUPLICATE`.
Hãy chú ý nêu rõ trạng thái của từng instance trước khi chạy lệnh.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Việc kết hợp Recovery Catalog vào Active Duplication là bài toán kinh điển đo lường khả năng nắm bắt Kiến trúc RMAN. 

### Bước 1: Chuẩn bị môi trường (Prerequisites)
Để thực hiện Active Duplication, ở mức độ mạng lưới, 3 máy chủ phải nói chuyện được với nhau qua Oracle Net Services (TNS).
1. Copy Password File từ `PRODDB` sang máy chủ `TESTDB`. (Mật khẩu SYS phải giống hệt nhau).
2. Thiết lập Static Listener cho `TESTDB`.
3. Tạo file khởi tạo (PFILE) tạm thời cho `TESTDB` với một tham số tối thiểu: `DB_NAME=TESTDB`.

### Bước 2: Khởi động Auxiliary Instance
Môi trường đích (`TESTDB`) phải được khởi động ở chế độ **NOMOUNT** để sẵn sàng nhận metadata và dữ liệu từ RMAN.
```sql
-- Trên máy chủ TESTDB
SQL> STARTUP NOMOUNT PFILE='initTESTDB.ora';
```

### Bước 3: Cú pháp Kết nối 3 Đỉnh Tam Giác (Cực kỳ quan trọng)
Từ một terminal (bất kỳ máy nào có Oracle Client), bạn phải mở RMAN và kết nối đồng thời tới 3 nơi:
```bash
rman TARGET sys/pass@PRODDB CATALOG rcman/catpass@RCAT AUXILIARY sys/pass@TESTDB
```
*Lúc này RMAN session có mắt ở Target (để đọc dữ liệu), ở Catalog (để ghi log) và ở Auxiliary (để đổ dữ liệu).*

### Bước 4: Chạy lệnh Active Duplication
Rất đơn giản, không cần cấu hình channel nếu bạn dùng mặc định (disk):
```rman
RMAN> DUPLICATE TARGET DATABASE TO TESTDB 
      FROM ACTIVE DATABASE
      NOFILENAMECHECK;
```
*(Tham số `NOFILENAMECHECK` báo cho RMAN biết việc cấu trúc thư mục của TESTDB có thể giống PRODDB, RMAN không cần cảnh báo lỗi ghi đè nếu hai máy chủ hoàn toàn độc lập vật lý).*

> [!NOTE]
> Phía sau hậu trường: Instance `PRODDB` sẽ tạo các Image Copies trên bộ nhớ và bắn thẳng qua mạng tới instance `TESTDB`. Catalog `RCAT` sẽ ghi nhận lại toàn bộ tiến trình này.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_CrossModule_ActiveDuplicateWithCatalog.md`
