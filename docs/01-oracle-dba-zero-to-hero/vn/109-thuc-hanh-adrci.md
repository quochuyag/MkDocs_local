---
title: 'Bài 109: Thực hành - Sử dụng ADRCI'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/109-thuc-hanh-adrci.md
---

# Bài 109: Thực hành - Sử dụng ADRCI

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Sử dụng tiện ích `adrci` để đọc nhật ký (Alert Log) từ OS mà không cần mở Database.
- Tra cứu các file Trace của các tiến trình nền.
- Sử dụng tính năng Incident Packaging Service (IPS) để đóng gói file lỗi.

## A. Tra cứu Alert Log
**1.** Trên máy ảo Linux `srv1`, đăng nhập tài khoản OS `oracle` và mở terminal.
**2.** Khởi chạy công cụ ADRCI:
```bash
adrci
```
*(Bạn sẽ thấy dấu nhắc lệnh `adrci>` xuất hiện).*
**3.** Xem đường dẫn thư mục gốc ADR Base và danh sách các thư mục Home:
```bash
show base
show homes
```
**4.** Thiết lập Homepath để trỏ vào thư mục của cơ sở dữ liệu (Ví dụ `oradb`):
```bash
set homepath diag/rdbms/oradb/oradb
```
**5.** Mở xem file Alert Log (nó sẽ gọi chương trình `vi` hoặc `less` mặc định của Linux):
```bash
show alert
```
*(Kéo xuống cuối để xem các sự kiện mới nhất, nhấn phím `q` để thoát).*

## B. Xem Trace File và Lọc lỗi
**6.** Xem tất cả các file Trace (Nhật ký chuyên sâu) được sắp xếp theo thời gian mới nhất (reverse time):
```bash
show tracefile -rt
```
**7.** Giả sử bạn chỉ muốn xem các file Trace liên quan đến tiến trình MMON:
```bash
show tracefile %mmon%
```
**8.** Quét Alert Log để lọc ra mọi sự cố liên quan đến lỗi hệ thống "ORA-600":
```bash
show alert -p "MESSAGE_TEXT LIKE '%ORA-600%'"
```
*(Nếu không có, màn hình sẽ không in ra gì cả).*

## C. Đóng gói lỗi (Incident Packaging)
Giả định hệ thống của bạn vừa gặp lỗi ORA-600 và Oracle Support yêu cầu bạn gửi file log.
**9.** Tạo một gói rỗng (Logical Package) dựa trên Problem Key `ORA-600`:
```bash
ips create package problemkey 'ORA-600'
```
*(Hệ thống sẽ trả về câu thông báo dạng: `Created package 1 without any contents...`)*
**10.** Ra lệnh cho hệ thống thu thập mọi file rác, file dump, file trace sinh ra bởi lỗi đó và nén thành file zip vật lý:
```bash
ips generate package 1 IN /tmp
```
**11.** Thoát khỏi `adrci` bằng lệnh `exit`.
**12.** Ra ngoài Linux kiểm tra thư mục `/tmp`, bạn sẽ thấy một file nén dạng `.zip` chứa toàn bộ dữ liệu cần thiết để gửi cho Oracle.

---
## Câu hỏi ôn tập

**Câu 1: Tôi có thể sử dụng `adrci` khi Database đang bị sập (SHUTDOWN) không?**
- **Trả lời:** Có. `adrci` đọc trực tiếp các file văn bản và file log trên đĩa cứng hệ điều hành. Nó không cần kết nối vào Oracle Database (Instance), do đó nó đặc biệt hữu ích khi database bị hỏng không thể startup được.

**Câu 2: Nếu tôi có 3 database (CDB1, CDB2, TESTDB) trên cùng 1 server, `adrci` sẽ làm việc với database nào?**
- **Trả lời:** Theo mặc định, nếu bạn không chọn, `adrci` sẽ thực thi lệnh trên TẤT CẢ các homepath hiện có. Để làm việc riêng biệt với CDB1, bạn phải dùng lệnh `set homepath diag/rdbms/cdb1/cdb1`.

**Câu 3: Mục đích của lệnh `ips create package` là gì?**
- **Trả lời:** Nó tạo ra một "phiếu đóng gói ảo" (Logical Package). Bạn có thể tưởng tượng nó như một giỏ hàng trống. Bạn có thể dùng các lệnh `ips add...` để bỏ thêm các file trace bổ sung vào giỏ hàng đó trước khi thực sự nén thành file zip.

**Câu 4: Khi dùng lệnh `show alert`, làm sao để nhảy thẳng đến dòng cuối cùng?**
- **Trả lời:** Nếu `adrci` dùng chương trình `vi` làm editor mặc định, bạn có thể gõ phím `Shift + G` để nhảy tới dòng cuối cùng. Hoặc bạn có thể dùng lệnh `show alert -tail 50` để chỉ in 50 dòng cuối ra màn hình mà không cần mở editor.

**Câu 5: Có bắt buộc phải đóng gói theo `problemkey` không?**
- **Trả lời:** Không. Nếu bạn không biết mã lỗi, bạn có thể tạo package dựa trên khoảng thời gian. Ví dụ: Gom toàn bộ log sự cố xảy ra từ 12h đêm qua đến hiện tại bằng lệnh `ips create package time 'start_time' to 'end_time'`.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/109-thuc-hanh-adrci.md`
