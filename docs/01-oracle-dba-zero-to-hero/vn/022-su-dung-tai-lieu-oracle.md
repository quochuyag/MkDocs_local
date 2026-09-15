---
title: 'Bài 22: Sử dụng Tài liệu Oracle Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/22-su-dung-tai-lieu-oracle.md
---

# Bài 22: Sử dụng Tài liệu Oracle Database

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Biết được các loại tài liệu Oracle Database phổ biến và cách sử dụng chúng.
- Biết cách tra cứu tài liệu Oracle online một cách hiệu quả.
- Hiểu khi nào nên sử dụng loại tài liệu nào.

---

## 1. Tài liệu Oracle Database là gì và tại sao quan trọng?

> 💡 **Tài liệu chính thức** là nguồn tham khảo đáng tin cậy nhất cho Oracle Database. Với Oracle - một hệ thống cực kỳ phức tạp - tài liệu chính thức thường là nơi duy nhất có câu trả lời chính xác và đầy đủ.

**Link truy cập tài liệu Oracle:**
```
https://docs.oracle.com/en/database/oracle/oracle-database/
```

**Lời khuyên sử dụng:**
- **Đừng** đọc từ đầu đến cuối như tiểu thuyết.
- **Hãy** dùng như từ điển: tìm đúng chủ đề cần, đọc phần đó.
- Tài liệu Oracle chủ yếu mang tính **tham khảo** (reference), không phải tutorial.

---

## 2. Các loại tài liệu Oracle

Oracle chia tài liệu thành 3 loại chính:

| Loại | Mô tả | Ví dụ |
|------|-------|-------|
| **Concepts (Khái niệm)** | Giải thích lý thuyết, cơ chế hoạt động | Database Concepts |
| **Guide (Hướng dẫn)** | Hướng dẫn thực hiện từng task cụ thể | Administrator's Guide, Backup and Recovery User's Guide |
| **Reference (Tham khảo)** | Danh sách đầy đủ các lệnh, tham số, views | SQL Language Reference, Oracle Database Reference |

---

## 3. Bảng tra cứu: Dùng tài liệu nào cho từng tình huống?

| Tình huống | Tài liệu cần dùng |
|------------|------------------|
| Muốn hiểu cơ chế hoạt động của Oracle (SGA, Redo, Undo...) | **Database Concepts** |
| Cần hướng dẫn thực hiện tác vụ DBA thường ngày | **Oracle Database Administrator's Guide** |
| Cài đặt Oracle trên Linux hoặc Windows | **Database Installation Guide for [platform]** |
| Quản lý môi trường Multitenant (CDB/PDB) | **Multitenant Administrators Guide** |
| Nâng cấp Oracle lên phiên bản mới | **Oracle Database Upgrade Guide** |
| Thực hiện Backup và Recovery | **Backup and Recovery User's Guide** |
| Tra cứu lệnh RMAN | **Backup and Recovery Reference** |
| Sử dụng Data Pump, SQL*Loader | **Oracle Database Utilities** |
| Tra cứu built-in PL/SQL packages | **PL/SQL Packages and Types Reference** |
| Tra cứu tham số, data dictionary views, V$ views | **Oracle Database Reference** |
| Về bảo mật Database | **Database Security Guide** |
| Cấu hình kết nối Oracle (listener, tnsnames) | **Net Services Administrator's Guide** |

---

## 4. Nhóm tài liệu theo trình độ

Oracle cũng phân chia tài liệu theo mức độ kinh nghiệm:

### 4.1. Nhóm Basic (Cơ bản) - Dành cho người mới bắt đầu
- **Oracle Database 2 Day Developer's Guide** - Lập trình với Oracle trong 2 ngày
- Phù hợp cho cả DBA và Developer mới làm quen Oracle.

### 4.2. Nhóm Intermediate (Trung cấp)
- **Oracle Database 2 Day + Performance Tuning Guide** - Dành cho DBA muốn tối ưu hiệu năng
- **Oracle Database 2 Day + Java Developer's Guide** - Dành cho Java Developer

### 4.3. Nhóm Advanced (Nâng cao) - Dành cho DBA chuyên nghiệp
- **Oracle Database Administrator's Guide**
- **Oracle Database Backup and Recovery User's Guide**
- **Oracle Database Performance Tuning Guide**
- **Oracle Database SQL Tuning Guide**
- **Oracle Real Application Clusters Administration Guide**
- **Oracle Database Security Guide**

### 4.4. Nhóm Reference (Tài liệu tham khảo)
- **Oracle Database SQL Language Reference** - Tra cứu mọi cú pháp SQL
- **Oracle Database Reference** - Tra cứu tham số, dictionary views, V$ views, wait events
- **Oracle Database PL/SQL Packages and Types Reference** - Tra cứu các package built-in

---

## 5. Các tài liệu DBA cần biết nhất

Trong công việc DBA hàng ngày, 4 tài liệu sau là quan trọng nhất:

### 📘 Oracle Database Concepts
- **Khi nào dùng:** Khi bạn không hiểu *tại sao* một cơ chế lại hoạt động như vậy.
- **Ví dụ:** Muốn hiểu Undo Segment hoạt động như thế nào? → Đọc Concepts.

### 📗 Oracle Database Administrator's Guide
- **Khi nào dùng:** Khi cần làm một tác vụ cụ thể (tạo user, quản lý tablespace...).
- **Ví dụ:** Muốn biết cách tạo CDB? → Đọc Administrator's Guide.

### 📙 Oracle Database Reference
- **Khi nào dùng:** Tra cứu tên chính xác của tham số, xem ý nghĩa cột của một V$ view.
- **Ví dụ:** Tham số `UNDO_RETENTION` có thể đặt ở PDB không? → Tra trong Reference.

### 📕 Backup and Recovery User's Guide + Reference
- **Khi nào dùng:** Mọi thứ liên quan đến RMAN và backup/recovery.

---

## 6. Cách tra cứu hiệu quả

### 6.1. Tìm nhanh bằng tính năng Search
Truy cập trang docs.oracle.com, chọn đúng phiên bản (19c, 21c...), sau đó dùng ô tìm kiếm.

### 6.2. Tải PDF để đọc offline
Mỗi tài liệu đều có nút tải PDF. DBA nên tải các tài liệu hay dùng để tham khảo nhanh khi không có internet.

### 6.3. Tra cứu tham số initialization
```sql
-- Xem một tham số cụ thể trong Database Reference rất hữu ích
-- Nhưng bạn cũng có thể tra ngay trong DB:
SHOW PARAMETER undo_retention;

-- Hoặc dùng V$PARAMETER:
SELECT NAME, VALUE, DESCRIPTION FROM V$PARAMETER WHERE NAME = 'undo_retention';
```

---

## 7. Tóm tắt bài học

1. Tài liệu Oracle tại `https://docs.oracle.com/en/database/oracle/oracle-database/` là nguồn tham khảo chính thức và đáng tin cậy nhất.
2. Ba loại tài liệu chính: **Concepts** (hiểu lý thuyết), **Guide** (làm tác vụ), **Reference** (tra cứu).
3. Không cần đọc hết - hãy dùng như **từ điển**: tìm đúng chủ đề cần.
4. **4 tài liệu DBA cần biết nhất:** Concepts, Administrator's Guide, Reference, Backup & Recovery.
5. Có thể tải PDF để dùng offline.

---

## 8. Câu hỏi ôn tập

**1. Bạn muốn hiểu cơ chế Redo Log trong Oracle hoạt động như thế nào - bạn sẽ tra tài liệu nào?**
> **Trả lời:**
> Bạn nên tra cuốn **Oracle Database Concepts**. Đây là tài liệu nền tảng giải thích rõ ràng và chi tiết nhất về mặt kiến trúc lý thuyết, nguyên lý vận hành của bộ đệm Redo Log Buffer, tiến trình Log Writer (LGWR), chu kỳ Log Switch, Checkpoint và cơ chế phục hồi dữ liệu khi có sự cố.

**2. Bạn cần biết cú pháp lệnh `CREATE TABLE` đầy đủ với tất cả các tùy chọn - bạn sẽ tra tài liệu nào?**
> **Trả lời:**
> Bạn tra cứu cuốn **Oracle Database SQL Language Reference**. Cuốn sách này cung cấp đầy đủ sơ đồ cú pháp (syntax diagram), tất cả các mệnh đề, tham số tùy chọn (tablespace, pctfree, compression, partitioning, constraints...) và các ví dụ minh họa chuẩn xác nhất cho từng câu lệnh SQL.

**3. Bạn muốn biết cột `OPEN_MODE` trong `V$DATABASE` có những giá trị nào - bạn sẽ tra tài liệu nào?**
> **Trả lời:**
> Bạn tra cứu cuốn **Oracle Database Reference**. Đây là cuốn từ điển bách khoa toàn thư mô tả chi tiết từng cột của tất cả các Dynamic Performance Views (`V$`, `GV$`), Static Data Dictionary Views (`DBA_`, `ALL_`, `USER_`) và các tham số khởi tạo (`Initialization Parameters`).

**4. Sự khác biệt giữa Guide và Reference là gì?**
> **Trả lời:**
> - **Guide (Sách hướng dẫn - Task-oriented / Topic-oriented):** Tổ chức theo quy trình từng bước (how-to) hướng dẫn bạn cách làm một việc cụ thể (ví dụ: *Database Administrator's Guide* hướng dẫn cách tạo tablespace, quản lý user; *Backup and Recovery User's Guide* hướng dẫn cách khôi phục database bằng RMAN). Đọc Guide khi bạn muốn biết **cách thực hiện một tác vụ**.
> - **Reference (Sách tra cứu / Từ điển - Lookup-oriented):** Tổ chức theo thứ tự bảng chữ cái hoặc danh mục để tra cứu nhanh thông số kỹ thuật (ví dụ: *SQL Language Reference*, *Database Reference*, *Error Messages Reference*). Bạn mở Reference khi cần **tra cứu chính xác định nghĩa, cú pháp, mã lỗi hoặc ý nghĩa của một cột cụ thể**.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/22-su-dung-tai-lieu-oracle.md`
