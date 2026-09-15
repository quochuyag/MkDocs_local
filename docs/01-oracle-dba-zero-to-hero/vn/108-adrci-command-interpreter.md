---
title: 'Bài 108: Trình thông dịch lệnh ADR (`adrci`)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/108-adrci-command-interpreter.md
---

# Bài 108: Trình thông dịch lệnh ADR (`adrci`)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Mở và quản lý màn hình dòng lệnh của ADRCI.
- Định hướng kiến trúc thư mục chẩn đoán ADR Home.
- Đọc file Alert Log và phân tích báo cáo lỗi (Incidents).
- Đóng gói dữ liệu báo lỗi (Incident Package) để gửi cho bộ phận Oracle Support.
- Thiết lập và thi hành chính sách thanh lọc (Purging) dữ liệu chẩn đoán để tiết kiệm ổ đĩa.

## Giới thiệu ADRCI
`adrci` (ADR Command Interpreter) là công cụ dòng lệnh xuất hiện từ bản 11g, được dùng để xem, phân tích và đóng gói toàn bộ các file chẩn đoán lỗi (như `alert.log`, `trace files`, `core dumps`) nằm bên trong Automatic Diagnostic Repository (ADR) mà không cần phải truy cập vào database. 

Đây là công cụ CỨU CÁNH tuyệt vời khi database bị sập không thể dùng SQL*Plus được nữa.

**Các thuật ngữ quan trọng:**
- **Problem Key:** Mã định danh lỗi (ví dụ `ORA-600` hoặc `ORA-07445`).
- **Incident:** Khi một "Problem" xảy ra, nó có thể được lặp lại nhiều lần. Mỗi một lần hệ thống bốc hỏa văng lỗi, nó gọi là một Incident.
- **Incident Package:** Một gói nén (zip) gom toàn bộ các file trace và dump liên quan đến Incident đó để bạn đem gửi cho hãng Oracle phân tích.

## Khởi động và Chọn Homepath
Bạn chỉ cần mở cửa sổ Linux, đăng nhập tài khoản OS `oracle` và gõ:
```bash
adrci
```
Hệ thống sẽ hiển thị thư mục gốc của kiến trúc, ví dụ `ADR base = "/u01/app/oracle"`.
- Lệnh liệt kê các thư mục nhà của các database: `show homes`
- Lệnh di chuyển con trỏ vào thư mục chẩn đoán của một database cụ thể:
```bash
set homepath diag/rdbms/oradb/oradb
```

## Xem lỗi với Alert Log và Trace file
Thay vì phải dùng lệnh `tail` trong OS, adrci cung cấp bộ xem file thông minh:
- Đọc trực tiếp Alert Log: `show alert` (Bấm q để thoát).
- Lọc xem các lỗi quan trọng trong Alert Log: `show alert -p "MESSAGE_TEXT LIKE '%ORA-600%'"`
- Liệt kê toàn bộ các sự cố nghiêm trọng đang nằm trong sổ: `show incident -mode detail`
- Liệt kê các file theo dõi (Trace files): `show tracefile -rt` (Liệt kê ưu tiên file mới sửa đổi nằm dưới cùng).

## Đóng gói Lỗi (Incident Packaging)
Khi có sự cố nghiêm trọng (ORA-600), Oracle Support sẽ đòi bạn gửi file log. Thay vì lặn lội copy từng file, adrci sẽ làm tự động:
**1.** Tạo một gói rỗng (logical package) cho một lỗi cụ thể:
```bash
ips create package problemkey 'ORA-600'
```
*(Hệ thống sẽ gom nhặt mọi thứ và tạo một Logical Package mang số hiệu ID, ví dụ package số 1).*

**2.** Sinh ra file Zip vật lý (Physical package) chứa toàn bộ dữ liệu:
```bash
ips generate package 1 IN /tmp
```
Bây giờ, bạn chỉ việc ra thư mục `/tmp` lấy file `.zip` và gửi lên hệ thống Hỗ trợ của Oracle.

## Xóa dữ liệu lỗi cũ (Purging ADR Data)
Càng để lâu, các file log rác (trace) của Oracle sinh ra sẽ làm đầy ổ cứng.
**1.** Xem chính sách tự động xóa đang thiết lập bao nhiêu giờ: `show control`
- `SHORTP_POLICY`: Số giờ giữ file trace (Mặc định: 720 giờ = 30 ngày).
- `LONGP_POLICY`: Số giờ giữ file alert và sự cố (Mặc định: 8760 giờ = 365 ngày).

**2.** Đổi thời hạn xóa ngắn hơn: 
```bash
set control (SHORTP_POLICY = 360)
```
**3.** Dọn rác bằng tay (ép xóa ngay lập tức những file trace cũ hơn 1 tháng):
```bash
purge -age 43200 -type TRACE
```
*(43200 phút = 30 ngày).*

---
## Câu hỏi ôn tập

**Câu 1: Tôi có cần nhập mật khẩu `SYSDBA` để sử dụng `adrci` không?**
- **Trả lời:** Không cần. `adrci` là một công cụ hoàn toàn chạy ở cấp độ hệ điều hành. Chỉ cần bạn là user OS sở hữu phần mềm Oracle (ví dụ `oracle`), bạn có thể gọi tiện ích này lên và đọc các file chẩn đoán mà Database không cần phải mở.

**Câu 2: Tại sao phải sử dụng tiện ích `ips` trong adrci để đóng gói log thay vì tôi tự tìm file gửi đi?**
- **Trả lời:** Bởi vì khi một Incident xảy ra, hệ thống không chỉ ghi 1 file log, nó có thể ghi dữ liệu ra chục file trace khác nhau cộng thêm dữ liệu dump memory (Core dump). Nếu tự nhặt tay, bạn sẽ nhặt thiếu, làm chậm tiến độ phân tích lỗi của hãng Oracle.

**Câu 3: Đâu là sự khác biệt giữa `SHORTP_POLICY` và `LONGP_POLICY`?**
- **Trả lời:** Chữ "SHORT" chỉ những dữ liệu có vòng đời ngắn, rác sinh ra mỗi ngày (file trace, file cdmp). Chữ "LONG" chỉ vòng đời dài, là những file ghi chép lịch sử mang ý nghĩa lưu trữ bảo hành và thống kê toàn bộ hoạt động (Alert log, Incident info).

**Câu 4: Mệnh lệnh `purge` trong adrci có xóa hỏng các file chạy hệ thống không?**
- **Trả lời:** Không. Lệnh purge được thiết kế cực kỳ an toàn, nó chỉ xóa các dữ liệu chẩn đoán cũ theo tham số `-age` mà bạn cung cấp. Nó không bao giờ đụng đến Datafile, Control file, Redo Log hay các file thực thi của phần mềm.

**Câu 5: Nếu tôi nhận được mã lỗi `ORA-00942: table or view does not exist` từ màn hình SQL Developer, adrci có tự sinh ra một Incident để tôi gửi Oracle không?**
- **Trả lời:** Không. Chỉ các lỗi sập hệ thống (Internal errors/Exceptions) đe dọa vòng đời của database như ORA-00600 (Lỗi bug nội bộ) hay ORA-07445 (lỗi vỡ RAM) mới được Database ghi nhận thành Incident để đóng gói gửi đi. Các lỗi gõ sai câu SQL thì không.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/108-adrci-command-interpreter.md`
