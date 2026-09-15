---
title: 'Bài 55: Áp dụng Nguyên tắc Đặc quyền Tối thiểu (Principle of Least Privilege)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/55-nguyen-tac-least-privileges.md
---

# Bài 55: Áp dụng Nguyên tắc Đặc quyền Tối thiểu (Principle of Least Privilege)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu cốt lõi của nguyên tắc đặc quyền tối thiểu (**Principle of Least Privilege - PoLP**) trong quản trị cơ sở dữ liệu.
- Nhận diện các rủi ro bảo mật tiềm ẩn từ các thiết lập mặc định của Oracle Database.
- Áp dụng danh sách kiểm tra (Security Checklist) để khóa chặt các lỗ hổng cấp quyền phổ biến.
- Cấu hình các tham số và thu hồi quyền trên các package nguy hiểm từ `PUBLIC`.

---

## 1. Khái niệm Principle of Least Privilege (PoLP)

**Nguyên tắc Đặc quyền Tối thiểu** quy định:
> *"Mỗi chủ thể (người dùng, tiến trình, ứng dụng) chỉ được cấp đúng những đặc quyền vừa đủ để hoàn thành chức năng công việc được giao, không thừa một quyền nào, và chỉ trong thời gian cần thiết."*

```
     [Người dùng / Ứng dụng]
                 │
  Chỉ cấp đúng quyền cần thiết
                 ▼
 ┌───────────────────────────────┐
 │ Data Entry: INSERT, SELECT    │ ── Chỉ nhập liệu
 │ Line Manager: SELECT, UPDATE  │ ── Duyệt hồ sơ
 │ Supervisor: READ ONLY Reports │ ── Báo cáo
 └───────────────────────────────┘
                 │
   ❌ TUYỆT ĐỐI KHÔNG CẤP:
   - DBA Role cho developer / app
   - DROP ANY TABLE, ALTER ANY TABLE
   - Quyền truy cập trực tiếp OS
```

---

## 2. Các điểm chốt an ninh quan trọng trong Oracle Database

Để hiện thực hóa nguyên tắc này trong môi trường sản xuất, Oracle DBA cần kiểm tra và cấu hình các điểm then chốt sau:

### 2.1. Đảm bảo tham số `O7_DICTIONARY_ACCESSIBILITY = FALSE`
- Tham số này bắt đầu bằng chữ `O` (chữ O, không phải số 0) và số `7`, xuất phát từ Oracle phiên bản 7.
- **Ý nghĩa:**
  - Nếu bằng `TRUE`: Bất kỳ user nào được cấp quyền `SELECT ANY TABLE` đều có thể đọc trộm các bảng bảo mật cốt lõi trong schema `SYS` (như `SYS.USER$` chứa hash mật khẩu của mọi user).
  - Nếu bằng `FALSE` (Mặc định và Bắt buộc): Quyền `SELECT ANY TABLE` chỉ cho phép đọc bảng người dùng thông thường, **ngăn chặn hoàn toàn** việc truy cập vào từ điển dữ liệu của `SYS`.
```sql
SHOW PARAMETER O7_DICTIONARY_ACCESSIBILITY;
-- Giá trị phải là: FALSE
```

### 2.2. Thu hồi quyền trên các Package mạng và I/O từ `PUBLIC`
Theo mặc định trong các bản cũ hoặc sau khi chạy một số script, role `PUBLIC` (mọi user đều có) có thể được gán quyền thực thi trên các package nhạy cảm:
- `UTL_FILE`: Đọc/ghi file trực tiếp trên ổ cứng máy chủ database.
- `UTL_HTTP`: Gửi yêu cầu HTTP ra bên ngoài, có thể dùng để đánh cắp dữ liệu (Data Exfiltration).
- `UTL_TCP`: Mở kết nối mạng TCP tùy ý.
- `UTL_SMTP`: Gửi email spam hoặc gửi dữ liệu nhạy cảm ra ngoài.

```sql
-- Kiểm tra và thu hồi quyền từ PUBLIC:
REVOKE EXECUTE ON UTL_FILE FROM PUBLIC;
REVOKE EXECUTE ON UTL_HTTP FROM PUBLIC;
REVOKE EXECUTE ON UTL_TCP  FROM PUBLIC;
REVOKE EXECUTE ON UTL_SMTP FROM PUBLIC;

-- Chỉ cấp quyền cho user/schema ứng dụng nào thực sự cần:
GRANT EXECUTE ON UTL_FILE TO hr_batch_user;
```

### 2.3. Hạn chế quyền truy cập Directory Objects (OS Directories)
Directory Object trong Oracle đại diện cho một đường dẫn thư mục vật lý trên máy chủ.
- Không bao giờ `GRANT READ, WRITE ON DIRECTORY ... TO PUBLIC;`.
- Kiểm tra danh sách quyền Directory qua view:
```sql
SELECT GRANTEE, TABLE_NAME AS DIRECTORY_NAME, PRIVILEGE 
FROM DBA_TAB_PRIVS 
WHERE TYPE = 'DIRECTORY';
```

### 2.4. Hạn chế tối đa việc gán Role `DBA`
- Không bao giờ cấp role `DBA` cho tài khoản kết nối của ứng dụng (Application Schema).
- Tách biệt tài khoản Developer: Developer chỉ cần quyền tạo đối tượng trong schema của chính họ (`CREATE TABLE`, `CREATE PROCEDURE`, `CREATE VIEW`), không cần quyền `ANY` (`CREATE ANY TABLE`).
- Định kỳ rà soát các user có role DBA:
```sql
SELECT GRANTEE FROM DBA_ROLE_PRIVS WHERE GRANTED_ROLE = 'DBA';
```

### 2.5. Đảm bảo `REMOTE_OS_AUTHENT = FALSE`
- Nếu tham số này bật (`TRUE`), bất kỳ ai trên mạng nội bộ tạo một tài khoản OS giả mạo trùng tên với một user trong database đều có thể đăng nhập thẳng vào database mà không cần mật khẩu!
- Tham số này đã bị deprecated và bắt buộc phải luôn luôn là **`FALSE`**.

### 2.6. Bật kiểm toán thao tác quản trị: `AUDIT_SYS_OPERATIONS = TRUE`
- Mọi câu lệnh SQL do user kết nối với quyền `SYSDBA`, `SYSOPER`, `SYSASM` thực thi sẽ được ghi lại vào file nhật ký của hệ điều hành (trong thư mục `audit_file_dest`), ngăn chặn việc DBA "xóa dấu vết" sau khi thực hiện thao tác nhạy cảm.

### 2.7. Hạn chế Public Database Links
- `PUBLIC DATABASE LINK` cho phép bất kỳ user nào trong database đều có thể "nhảy cóc" sang cơ sở dữ liệu từ xa.
- Khuyến nghị chỉ tạo **Private Database Link** thuộc quyền sở hữu của schema cụ thể.

---

## 3. Quy trình phê duyệt phân quyền (Privilege Governance)

Trong doanh nghiệp, DBA không được tự ý cấp quyền theo yêu cầu miệng hay chat cá nhân. Cần tuân thủ quy trình:
1. **Yêu cầu bằng văn bản (Ticket/Request):** Chỉ rõ User cần quyền gì, trên đối tượng nào, mục đích công việc là gì.
2. **Phê duyệt (Approval):** Phải có sự đồng ý của Data Owner / Trưởng bộ phận phụ trách dữ liệu đó.
3. **Thực thi và Ghi nhật ký (Log):** DBA thực thi qua Role cụ thể, lưu lại ticket phê duyệt để phục vụ kiểm toán (Security Audit) định kỳ hàng năm.

---

## Tổng kết

| Hạng mục an ninh | Cấu hình chuẩn khuyến nghị |
| :--- | :--- |
| `O7_DICTIONARY_ACCESSIBILITY` | `FALSE` |
| `REMOTE_OS_AUTHENT` | `FALSE` |
| `AUDIT_SYS_OPERATIONS` | `TRUE` |
| `UTL_FILE`, `UTL_HTTP`, `UTL_TCP`, `UTL_SMTP` | Đã `REVOKE` khỏi `PUBLIC` |
| Role `DBA` | Chỉ cấp cho nhân sự DBA chịu trách nhiệm |
| Database Link | Ưu tiên Private, hạn chế Public |

---

## Câu hỏi ôn tập

**1. Tham số `O7_DICTIONARY_ACCESSIBILITY = FALSE` ngăn chặn nguy cơ bảo mật nào?**
> **Trả lời:**
> Tham số này ngăn chặn các user có quyền hệ thống dạng `ANY` (đặc biệt là `SELECT ANY TABLE`) truy cập vào các bảng nội bộ của Data Dictionary thuộc sở hữu của schema `SYS`. Nếu để `TRUE`, một tài khoản người dùng bình thường có quyền `SELECT ANY TABLE` có thể đọc trộm bảng `SYS.USER$` (chứa toàn bộ hash mật khẩu của mọi user) hoặc thay đổi cấu hình lõi của hệ thống.

**2. Tại sao việc cấp quyền `EXECUTE` trên package `UTL_FILE` cho role `PUBLIC` lại cực kỳ nguy hiểm?**
> **Trả lời:**
> Role `PUBLIC` tự động gán cho mọi tài khoản trong database. Package `UTL_FILE` cho phép đọc và ghi trực tiếp các file trên ổ đĩa của máy chủ Database Server. Nếu `PUBLIC` có quyền này, bất kỳ tài khoản nào (thậm chí là tài khoản bị lộ lọt từ ứng dụng web) cũng có thể đọc trộm các file nhạy cảm của hệ điều hành hoặc ghi đè mã độc lên server.

**3. Tại sao trong môi trường Production hiện đại, tham số `REMOTE_OS_AUTHENT` bắt buộc phải là `FALSE`?**
> **Trả lời:**
> Nếu `REMOTE_OS_AUTHENT = TRUE`, Oracle Database sẽ tin tưởng hoàn toàn danh tính tài khoản do máy trạm (client máy tính cá nhân) gửi lên qua mạng. Kẻ tấn công chỉ cần đổi tên user trên máy tính của họ thành tên một DBA hoặc user database rồi kết nối vào là được hệ thống tự động cho qua mà không hỏi mật khẩu. Đặt bằng `FALSE` giúp vô hiệu hóa hoàn toàn cơ chế xác thực từ xa không an toàn này.

**4. Khi một lập trình viên (Developer) yêu cầu quyền để tạo bảng và test code, bạn nên cấp những quyền gì thay vì cấp role `DBA`?**
> **Trả lời:**
> Tuyệt đối không cấp role `DBA`. Bạn chỉ nên cấp các quyền hạn cục bộ bên trong schema của chính họ:
> - `CREATE SESSION`: Để kết nối vào database.
> - Role `RESOURCE` (hoặc các quyền lẻ: `CREATE TABLE`, `CREATE VIEW`, `CREATE SEQUENCE`, `CREATE PROCEDURE`).
> - Hạn mức dung lượng lưu trữ: `QUOTA <dung_luong> ON <tablespace_name>`.
> Nếu họ cần xem dữ liệu của schema khác, chỉ cấp quyền `SELECT` cụ thể trên từng bảng cần thiết.

**5. Lợi ích lớn nhất của việc áp dụng nguyên tắc PoLP khi có một tài khoản ứng dụng bị hacker chiếm quyền là gì?**
> **Trả lời:**
> Giúp **khoanh vùng và hạn chế tối đa thiệt hại (Blast Radius Mitigation)**. Nếu tài khoản đó chỉ có quyền `SELECT` và `INSERT` trên 2 bảng nghiệp vụ, kẻ tấn công không thể xóa dữ liệu (`DROP TABLE`), không thể can thiệp vào các bảng nhạy cảm khác, không thể đọc trộm mật khẩu hệ thống và không thể leo thang đặc quyền để chiếm quyền điều khiển máy chủ cơ sở dữ liệu.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/55-nguyen-tac-least-privileges.md`
