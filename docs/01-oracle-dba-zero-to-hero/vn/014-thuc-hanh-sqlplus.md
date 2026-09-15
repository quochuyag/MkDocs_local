---
title: 'Bài 14: Thực hành - Sử dụng SQL*Plus'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/14-thuc-hanh-sqlplus.md
---

# Bài 14: Thực hành - Sử dụng SQL*Plus

## 🎯 Mục tiêu bài học
Trong bài thực hành này, bạn sẽ làm quen với việc sử dụng công cụ SQL*Plus. SQL*Plus là một trong những công cụ phổ biến nhất và không thể thiếu đối với bất kỳ Oracle DBA nào. Giống như việc một người thợ mộc không thể thiếu cái cưa, một DBA cũng không thể làm việc hiệu quả nếu không thành thạo SQL*Plus.

Kết thúc bài học, bạn sẽ nắm được:
- Cách mở và kết nối vào cơ sở dữ liệu qua SQL*Plus.
- Chạy và quản lý các câu lệnh SQL.
- Định dạng kết quả hiển thị (formatting).
- Tương tác với hệ điều hành và chạy script tự động.
- Sử dụng biến số trong SQL*Plus.

---

## 1. Mở SQL*Plus và Các Phương Thức Kết Nối

Bạn có thể chạy SQL*Plus trên cả Windows và Linux một cách dễ dàng thông qua cửa sổ dòng lệnh (Command Prompt/Terminal).

### 1.1. Khởi động SQL*Plus không kết nối
Đầu tiên, mở Command Prompt (Windows) hoặc Terminal (Linux) bằng user `oracle`, sau đó gõ:

```bash
# Khởi động SQL*Plus nhưng chưa kết nối vào bất kỳ Database nào
sqlplus /nolog
```
> 💡 **Tip:** `/nolog` giúp bạn vào môi trường SQL*Plus trước, sau đó có thể từ từ setup các thông số hoặc kết nối sau. Điều này rất hữu ích khi bạn không muốn mật khẩu bị lộ trong lịch sử câu lệnh của hệ điều hành.

### 1.2. Kết nối với các quyền khác nhau

**Quyền Quản trị cao nhất (SYSDBA):**
```sql
-- Kết nối bằng quyền SYSDBA (Sử dụng xác thực hệ điều hành - OS Authentication)
-- Không cần mật khẩu nếu user OS (oracle) thuộc group ORA_DBA (Windows) hoặc dba (Linux)
SQL> conn / as sysdba
```
*Ví von:* Đăng nhập bằng `sysdba` giống như bạn cầm "chìa khóa vạn năng" của tòa nhà. Bạn có quyền làm mọi thứ, kể cả phá hủy tòa nhà đó (Drop database)! Khi bạn đăng nhập cách này, hệ thống ghi nhận bạn là user `SYS` (Superuser).

**Kiểm tra xem mình đang là ai:**
```sql
SQL> show user
USER is "SYS"
```

**Đăng nhập bằng user thông thường:**
```sql
-- Kết nối vào user SYSTEM với mật khẩu ABcd##1234
SQL> conn system/ABcd##1234
Connected.

-- Hoặc kết nối vào user HR
SQL> conn hr/ABcd##1234
Connected.
```

> ⚠️ **Lưu ý:** Tên user không phân biệt chữ hoa chữ thường, nhưng **mật khẩu thì có phân biệt**. `CONN` là viết tắt của `CONNECT`. Trong SQL*Plus, hầu hết các lệnh đều có thể viết tắt để tiết kiệm thời gian.

---

## 2. Các Lệnh SQL*Plus Quan Trọng

### 2.1. Lệnh `DESCRIBE` (Xem cấu trúc bảng)
Khi bạn cần biết một bảng có những cột nào, kiểu dữ liệu là gì:
```sql
-- Xem cấu trúc bảng EMPLOYEES (Có thể viết tắt là desc)
SQL> desc employees
```

### 2.2. Làm việc với Buffer (Bộ đệm câu lệnh)
SQL*Plus lưu lại câu lệnh SQL **cuối cùng** mà bạn vừa chạy vào một bộ đệm (buffer) để dễ dàng chỉnh sửa hoặc chạy lại.

```sql
-- Chạy một câu lệnh SQL bình thường
SQL> SELECT EMPLOYEE_ID, FIRST_NAME, LAST_NAME, SALARY FROM EMPLOYEES ORDER BY 1;
```

**Xem lại lệnh trong bộ đệm:**
```sql
-- Dùng lệnh LIST hoặc viết tắt là L
SQL> l
  1  SELECT EMPLOYEE_ID, FIRST_NAME, LAST_NAME, SALARY FROM EMPLOYEES
  2* ORDER BY 1
```

**Sửa lệnh bằng Text Editor:**
```sql
-- Mở notepad (Windows) hoặc vi (Linux) để sửa lệnh vừa gõ
SQL> ed
```
Trong cửa sổ Editor hiện ra, bạn sửa lệnh thành:
```sql
SELECT EMPLOYEE_ID, FIRST_NAME, LAST_NAME, SALARY FROM EMPLOYEES
WHERE EMPLOYEE_ID = 100
ORDER BY 1
```
*Lưu ý: Không dùng dấu chấm phẩy `;` ở cuối khi sửa trong editor.* Lưu file và đóng lại.

**Chạy lại lệnh trong bộ đệm:**
```sql
-- Gõ dấu gạch chéo để thực thi lại lệnh đang lưu trong buffer
SQL> /
```

### 2.3. Tương tác với Hệ Điều Hành (`HOST`)
Đang làm việc trong SQL*Plus mà bạn muốn gõ lệnh của Windows/Linux (ví dụ: xem thư mục có file gì)? Không cần thoát ra, hãy dùng `HOST`.
```sql
-- Trên Windows:
SQL> host dir

-- Trên Linux:
SQL> host ls -l
```

---

## 3. Định Dạng Kết Quả Đầu Ra (Format Output)

Mặc định, kết quả hiển thị của SQL*Plus có thể rất lộn xộn, bị rớt dòng. Ta có các công cụ để "tút tát" lại.

### 3.1. Format cho từng Cột (`COLUMN`)
```sql
-- Giới hạn cột FIRST_NAME hiển thị tối đa 10 ký tự (a10)
SQL> col FIRST_NAME format a10

-- Định dạng cột tiền lương (SALARY) có dấu phẩy phân cách hàng ngàn
SQL> col SALARY format 999,999

-- Chạy lại lệnh để xem sự khác biệt
SQL> /
```

### 3.2. Chỉnh kích thước trang và dòng (`SET PAGESIZE`, `SET LINESIZE`)
- `PAGESIZE`: Số dòng hiển thị trước khi lặp lại tiêu đề cột (mặc định thường là 14).
- `LINESIZE`: Số ký tự tối đa trên 1 dòng (mặc định là 80). Nếu vượt quá, nó sẽ rớt xuống dòng dưới trông rất xấu.

```sql
-- Đặt độ rộng 1 dòng là 200 ký tự (tránh rớt dòng)
SQL> set linesize 200

-- Đặt 100 dòng mới lặp lại tiêu đề (Header) một lần
SQL> set pagesize 100
```

---

## 4. Chạy Script SQL từ File

Thay vì gõ từng lệnh, DBA thường gom nhiều lệnh vào một file (ví dụ: `script.sql`) và cho chạy tự động.

**Cách 1: Lưu câu lệnh trong bộ đệm ra file**
```sql
-- Lưu lệnh SELECT cuối cùng vào file có tên list-emps.sql
SQL> save list-emps
```

**Cách 2: Chạy file script**
Dùng ký hiệu `@` (tương đương lệnh `START`).
```sql
-- Chạy tất cả lệnh nằm trong file list-emps.sql
SQL> @list-emps
```
> 💡 **Tip cực hay:** Bạn có thể vừa đăng nhập, vừa chạy file script cùng lúc ở ngoài màn hình OS:
> ```bash
> sqlplus hr/ABcd##1234 @list-emps
> ```

---

## 5. Xuất Kết Quả Ra File (`SPOOL`)

Khi bạn chạy một báo cáo dài 1000 dòng, bạn không thể đọc trên màn hình đen. Bạn cần xuất kết quả đó ra một file text. Hãy dùng `SPOOL`.

```sql
-- Bước 1: Bật tính năng Spool và chỉ định tên file cần lưu
SQL> spool bao_cao_nhan_su.log

-- Bước 2: Chạy câu truy vấn (tất cả kết quả sẽ hiện trên màn hình VÀ ghi vào file)
SQL> SELECT EMPLOYEE_ID, FIRST_NAME, SALARY FROM EMPLOYEES;

-- Bước 3: Tắt tính năng Spool (Lúc này file mới thực sự được lưu hoàn tất)
SQL> spool off
```
Sau đó bạn có thể dùng lệnh `host notepad bao_cao_nhan_su.log` để xem thành quả!

---

## 6. Biến trong SQL*Plus (`DEFINE`, `ACCEPT`, `&`)

Giúp tạo ra các script "tương tác", hỏi người dùng nhập thông tin trước khi chạy.

- **Dấu `&`:** Dùng để yêu cầu người dùng nhập giá trị ngay lúc chạy câu lệnh.
```sql
SQL> SELECT FIRST_NAME, SALARY FROM EMPLOYEES WHERE EMPLOYEE_ID = &nhap_ma_nhan_vien;
-- Hệ thống sẽ hiện ra: Enter value for nhap_ma_nhan_vien: 
```

- **`ACCEPT`:** Hỏi một cách lịch sự, có tùy chọn ẩn mật khẩu (HIDE).
```sql
SQL> ACCEPT phong_ban PROMPT 'Xin vui lòng nhập Mã Phòng Ban: '
SQL> SELECT FIRST_NAME FROM EMPLOYEES WHERE DEPARTMENT_ID = &phong_ban;
```

- **`DEFINE`:** Gán sẵn một giá trị cố định cho biến.
```sql
SQL> DEFINE luong_coban = 5000
SQL> SELECT FIRST_NAME FROM EMPLOYEES WHERE SALARY > &luong_coban;
```

---

## 7. Ví dụ Thực Tế Cho DBA

Dưới đây là một số lệnh "nằm lòng" của một DBA để kiểm tra sức khỏe của hệ thống:

**Kiểm tra trạng thái của Database (Đã mở chưa?)**
```sql
SQL> SELECT status, instance_name FROM v$instance;
```

**Kiểm tra phiên bản Oracle đang chạy**
```sql
SQL> SELECT banner FROM v$version;
```

**Xem các Tablespace (Nơi lưu trữ dữ liệu vật lý)**
```sql
SQL> col tablespace_name format a20
SQL> SELECT tablespace_name, status, contents FROM dba_tablespaces;
```

---

## 8. Tuỳ Biến Giao Diện và Thoát

**Thay đổi ký tự dấu nhắc lệnh (Prompt):**
Để biết mình đang ở Database nào, đăng nhập bằng User nào, tránh việc "râu ông nọ cắm cằm bà kia" (Drop nhầm Database Production thay vì Database Test).

```sql
SQL> set sqlprompt "_user'@'_connect_identifier'> '"
SYS@> 
-- Dấu nhắc lệnh bây giờ sẽ đổi từ "SQL>" thành "SYS@>"
```

**Thoát khỏi SQL*Plus:**
```sql
SQL> exit
-- Hoặc bạn có thể dùng lệnh QUIT
```

---

## 📝 Tóm tắt bài học

- Mở SQL*Plus bằng lệnh `sqlplus`.
- Kết nối bằng quyền quản trị: `conn / as sysdba`.
- Xem cấu trúc bảng: `DESC`.
- Sửa lệnh cũ: `L`, `ED`, `/`.
- Format hiển thị cho đẹp: `COL`, `SET LINESIZE`, `SET PAGESIZE`.
- Lưu và xuất file: `SAVE`, `SPOOL`, `@`.
- Chạy lệnh hệ điều hành: `HOST`.

## ❓ Câu hỏi ôn tập

**1. Sự khác biệt giữa `sqlplus /nolog` và `sqlplus / as sysdba` là gì?**
> **Trả lời:**
> - `sqlplus /nolog`: Mở tiện ích SQL*Plus ở chế độ **chưa đăng nhập** vào bất kỳ database nào (không tạo session). Thường dùng khi muốn vào giao diện trước rồi mới gõ lệnh `CONNECT`, hoặc dùng trong shell script an toàn để tránh lộ password trên danh sách tiến trình (`ps -ef`).
> - `sqlplus / as sysdba`: Mở SQL*Plus và **thực hiện kết nối ngay lập tức** bằng đặc quyền cao nhất `SYSDBA` thông qua cơ chế OS Authentication (xác thực cấp hệ điều hành mà không cần username/password).

**2. Khi dùng `SPOOL` để xuất báo cáo ra file, nếu bạn quên gõ `spool off` ở cuối thì điều gì sẽ xảy ra với file đó?**
> **Trả lời:**
> - Bộ đệm (buffer) ghi file của hệ điều hành có thể chưa được flush hoàn toàn, dẫn đến file xuất ra bị thiếu những dòng dữ liệu cuối cùng hoặc dung lượng file hiển thị 0 KB.
> - File tiếp tục bị khóa (file lock) và SQL*Plus sẽ tiếp tục ghi thêm mọi câu lệnh hoặc kết quả mới bạn gõ vào file đó cho đến khi bạn thoát hẳn phiên làm việc (`EXIT`). Vì vậy, luôn luôn phải có cặp lệnh `SPOOL <ten_file>` và `SPOOL OFF`.

**3. Tại sao trong môi trường làm việc thực tế, DBA lại ưu tiên viết các file `.sql` script rồi dùng lệnh `@` để chạy thay vì gõ tay từng lệnh SELECT trên giao diện?**
> **Trả lời:**
> - **Độ chính xác và Tái sử dụng:** Tránh gõ nhầm cú pháp hay điều kiện WHERE nguy hiểm khi thao tác trên Production. Các script chuẩn đã được kiểm thử (test) kỹ càng trên môi trường Dev/UAT.
> - **Tiết kiệm thời gian:** Các tác vụ kiểm tra sức khỏe hàng ngày (Daily Health Check), kiểm tra tablespace, lock, session thường dài hàng chục dòng. Dùng `@check_db.sql` chỉ mất 1 giây để chạy toàn bộ.
> - **Quản lý phiên bản (Version Control):** Các script SQL có thể được lưu trữ trên Git để theo dõi lịch sử thay đổi và chia sẻ cho cả đội ngũ DBA.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/14-thuc-hanh-sqlplus.md`
