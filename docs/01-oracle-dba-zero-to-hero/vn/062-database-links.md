---
title: 'Bài 62: Sử dụng Database Links (Using Database Links)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/62-database-links.md
---

# Bài 62: Sử dụng Database Links (Using Database Links)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu khái niệm, bản chất và cách thức hoạt động của **Database Link** trong Oracle.
- Phân biệt các loại Database Link: **Private**, **Public** và **Global**.
- Nắm vững các loại người dùng xác thực trong Database Link: **Connected User**, **Fixed User**, và **Current User**.
- Hiểu về quy tắc đặt tên Database Link và vai trò của tham số `GLOBAL_NAMES`.
- Sử dụng kết hợp Database Link với **Synonym** và Views để che giấu vị trí vật lý của dữ liệu từ xa.
- Xóa và quản trị các Database Links trong từ điển dữ liệu.

---

## 1. Khái niệm và Cơ chế hoạt động của Database Link

![Database Link Overview](108-109-using-database-links/images/using-database-links-01.jpeg)

- **Database Link (DB Link):** Là một con trỏ (pointer) định nghĩa một đường truyền thông **một chiều (one-way)** từ cơ sở dữ liệu cục bộ (Local Database) sang một cơ sở dữ liệu từ xa (Remote Database).
- Cho phép người dùng đứng ở Database A có thể thực hiện truy vấn hoặc thao tác dữ liệu (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) trên các bảng/view nằm ở Database B bằng cách gắn thêm đuôi **`@dblink_name`**:
  ```sql
  SELECT * FROM employees@hrbase;
  ```
- **Bản chất kỹ thuật:** Local Database đóng vai trò như một **Client** kết nối qua mạng (dùng Oracle Net và TNS Listener) tới Remote Database bằng một tài khoản xác thực được định nghĩa sẵn trong DB Link.

---

## 2. Các Loại Database Link

| Loại DB Link | Cú pháp tạo | Phạm vi truy cập & Ai được dùng? | Lưu ý bảo mật |
| :--- | :--- | :--- | :--- |
| **Private** *(Khuyến nghị)* | `CREATE DATABASE LINK link_name ...` | **Chỉ riêng người tạo (chủ sở hữu)** mới được phép sử dụng. | An toàn nhất, tuân thủ nguyên tắc Least Privilege. |
| **Public** | `CREATE PUBLIC DATABASE LINK link_name ...` | **Tất cả người dùng** trong database cục bộ đều có thể sử dụng. | Tiềm ẩn rủi ro cao nếu tài khoản đích có nhiều quyền. |
| **Global** | Định nghĩa tập trung qua LDAP/OID | Áp dụng cho các cụm cơ sở dữ liệu doanh nghiệp dùng Oracle Internet Directory. | Quản trị tập trung, không cần tạo thủ công từng DB. |

---

## 3. Các Cơ chế Người dùng Xác thực trong DB Link

![Database Link Users](108-109-using-database-links/images/using-database-links-03.jpeg)

1. **Fixed User (Người dùng cố định - Phổ biến nhất):**
   Chỉ định rõ username và password của tài khoản trên Remote Database:
   ```sql
   CREATE DATABASE LINK remote_hr
     CONNECT TO remote_user IDENTIFIED BY "Password##123"
     USING 'remote_tns_alias';
   ```
   *Bất kỳ ai được phép dùng link này đều sẽ thao tác trên database từ xa dưới danh nghĩa `remote_user`.*

2. **Connected User (Người dùng kết nối hiện tại):**
   Không khai báo mệnh đề `CONNECT TO`:
   ```sql
   CREATE DATABASE LINK remote_link USING 'remote_tns_alias';
   ```
   *Khi bạn là user `SCOTT` chạy câu lệnh, Oracle sẽ cố gắng kết nối sang database từ xa bằng đúng username `SCOTT` và mật khẩu giống hệt mật khẩu bạn vừa đăng nhập ở local.*

3. **Current User (Người dùng toàn cục):**
   Sử dụng mệnh đề `CONNECT TO CURRENT_USER`. Thường dùng trong các Enterprise User Security (EUS) hoặc Stored Procedure bảo mật cao.

---

## 4. Tham số `GLOBAL_NAMES` và Quy tắc Đặt tên DB Link

![Global Database Names](108-109-using-database-links/images/using-database-links-05.jpeg)

Mỗi cơ sở dữ liệu Oracle có một tên định danh toàn cầu (**Global Database Name**) gồm:
`[DB_NAME].[DB_DOMAIN]` (Ví dụ: `ORADB.LOCALDOMAIN`).
Kiểm tra bằng: `SELECT * FROM GLOBAL_NAME;`.

### Tác động của tham số `GLOBAL_NAMES`:
- **Nếu `GLOBAL_NAMES = FALSE` (Mặc định):**
  Bạn có thể đặt tên cho Database Link bằng **bất kỳ cái tên nào bạn thích** (ví dụ `link_to_sale`, `hrbase`, `mydb_link`).
- **Nếu `GLOBAL_NAMES = TRUE` (Tiêu chuẩn doanh nghiệp nghiêm ngặt):**
  Tên của Database Link **BẮT BUỘC PHẢI TRÙNG KHỚP 100%** với `GLOBAL_NAME` của cơ sở dữ liệu đích!
  *Ví dụ:* Nếu database đích có tên toàn cầu là `pdb1.localdomain`, bạn chỉ có thể tạo link tên là:
  ```sql
  CREATE DATABASE LINK pdb1.localdomain CONNECT TO ... USING 'tns_pdb1';
  ```

---

## 5. Che giấu Vị trí Dữ liệu bằng Synonym

Trong thực tế phát triển phần mềm, việc viết câu lệnh SQL chứa đuôi `@dblink_name` (như `SELECT * FROM employees@hr_remote`) là một bad practice vì:
- Lộ cấu trúc mạng và tên link ra tầng ứng dụng.
- Nếu sau này di dời database hoặc đổi tên link, phải sửa lại toàn bộ mã nguồn code.

**Giải pháp của DBA:** Tạo một **Synonym** (Bí danh) bọc lấy đối tượng từ xa:
```sql
CREATE SYNONYM emp FOR employees@hr_remote;
```
Từ lúc này, lập trình viên và ứng dụng chỉ cần viết:
```sql
SELECT * FROM emp;
```
Ứng dụng hoàn toàn không cần biết dữ liệu thực tế đang nằm ở máy chủ local hay nằm cách xa nửa vòng trái đất!

---

## 6. Tra cứu và Xóa Database Link

```sql
-- Xem tất cả DB Links trong hệ thống:
SELECT OWNER, DB_LINK, USERNAME, HOST, CREATED FROM DBA_DB_LINKS;

-- Xóa Private DB Link (do chính chủ sở hữu xóa):
DROP DATABASE LINK hr_remote;

-- Xóa Public DB Link (chỉ DBA mới có quyền xóa):
DROP PUBLIC DATABASE LINK public_hr_link;
```

---

## Câu hỏi ôn tập

**1. Một Database Link là đường truyền thông một chiều hay hai chiều? Giải thích.**
> **Trả lời:**
> Database Link là đường truyền thông **MỘT CHIỀU (One-way communication path)**. Nếu bạn tạo DB Link từ Database A trỏ sang Database B, người dùng ở Database A có thể truy vấn dữ liệu ở Database B. Tuy nhiên, chiều ngược lại người dùng ở Database B **hoàn toàn không thể** truy vấn dữ liệu ở Database A thông qua link đó (muốn truy vấn ngược lại thì Database B phải tự tạo một DB Link riêng trỏ về Database A).

**2. Sự khác biệt giữa `CREATE DATABASE LINK` và `CREATE PUBLIC DATABASE LINK` là gì?**
> **Trả lời:**
> - `CREATE DATABASE LINK`: Tạo ra một **Private Database Link** thuộc quyền sở hữu của schema tạo ra nó. Chỉ người tạo mới được quyền sử dụng link này để truy vấn.
> - `CREATE PUBLIC DATABASE LINK`: Tạo ra một **Public Database Link**. Tất cả mọi người dùng hiện có và tương lai trong cơ sở dữ liệu cục bộ đều có thể sử dụng link này để kết nối sang database từ xa.

**3. Khi tham số `GLOBAL_NAMES = TRUE`, điều kiện bắt buộc khi đặt tên cho Database Link là gì?**
> **Trả lời:**
> Tên của Database Link **bắt buộc phải trùng khớp hoàn toàn với Global Database Name của cơ sở dữ liệu đích** (được xác định bởi `SELECT * FROM GLOBAL_NAME;` tại database đích). Nếu bạn đặt tên khác, Oracle sẽ báo lỗi `ORA-02085: database link connects to ...` và từ chối tạo/sử dụng link.

**4. Tại sao DBA nên kết hợp việc tạo Synonym với Database Link cho các lập trình viên ứng dụng sử dụng?**
> **Trả lời:**
> Giúp đạt được tính **Độc lập vị trí dữ liệu (Location Transparency)**:
> - Giấu kín chi tiết kiến trúc mạng và tên DB Link khỏi mã nguồn ứng dụng.
> - Nếu cơ sở dữ liệu đích được chuyển dời sang máy chủ khác, hoặc dữ liệu sau này được chuyển về lưu trữ cục bộ, DBA chỉ cần cập nhật lại định nghĩa của Synonym mà không cần phải yêu cầu đội ngũ phát triển sửa đổi và deploy lại mã nguồn phần mềm.

**5. Để một user thông thường có thể tạo được Private Database Link, DBA cần cấp quyền hệ thống nào?**
> **Trả lời:**
> DBA cần cấp quyền hệ thống **`CREATE DATABASE LINK`** cho user đó:
> ```sql
> GRANT CREATE DATABASE LINK TO username;
> ```
> (Nếu muốn user có quyền tạo Public Database Link, phải cấp quyền `CREATE PUBLIC DATABASE LINK`).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/62-database-links.md`
