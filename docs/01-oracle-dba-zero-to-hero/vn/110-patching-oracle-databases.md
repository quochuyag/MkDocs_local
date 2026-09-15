---
title: 'Bài 110: Cập nhật Bản vá (Patching) Oracle Databases'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/110-patching-oracle-databases.md
---

# Bài 110: Cập nhật Bản vá (Patching) Oracle Databases

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Tầm quan trọng của việc cập nhật bản vá (Patching) phần mềm Oracle.
- Phân biệt các loại bản vá: RU (Release Update) và RUR (Release Update Revision).
- Sử dụng tiện ích OPatch để áp dụng các bản vá vào cơ sở dữ liệu.
- Xử lý các xung đột bản vá (Conflict Resolution).

## Tầm quan trọng của Patching
Các bản vá phần mềm không chỉ mang đến những tính năng mới mà còn rất quan trọng trong việc vá các lỗ hổng bảo mật, lỗi bộ nhớ, và các lỗi tính toán sai dữ liệu. Với Oracle 19c (phiên bản dài hạn), Oracle phát hành các bản vá định kỳ hàng quý.

## Phân loại bản vá (Từ bản 12.2 trở đi)
- **RU (Release Update):** Bản cập nhật lớn phát hành vào tháng 1, 4, 7, 10 hàng năm. Chứa bản vá bảo mật, sửa lỗi, và tối ưu hóa hệ thống mới nhất. (Nên dùng).
- **RUR (Release Update Revision):** Bản vá nhỏ giọt nhằm sửa các lỗi phát sinh của RU trước đó. Chỉ chứa thêm bản vá bảo mật, không có tính năng hay thay đổi nào lớn. Dành cho những môi trường cực kỳ nhạy cảm ngại cài RU mới.
- **OJVM Patch:** Bản vá riêng biệt dành cho máy ảo Java (Oracle Java Virtual Machine) chạy bên trong Database.

## Tiện ích OPatch
`OPatch` là một tiện ích dòng lệnh bằng Java dùng để cài đặt các bản vá vào trong `ORACLE_HOME`.
Luôn phải cập nhật `OPatch` lên phiên bản mới nhất (download từ Oracle Support - Patch 6880880) trước khi cài đặt bất kỳ RU nào.

**Các lệnh OPatch cơ bản:**
- `opatch version`: Xem phiên bản OPatch hiện tại.
- `opatch lsinventory`: Xem danh sách tất cả các bản vá đã từng được cài vào máy chủ này.
- `opatch prereq CheckConflictAgainstOHWithDetail -ph ./`: Kiểm tra xem bản vá chuẩn bị cài có bị xung đột (conflict) với bản vá cũ không.
- `opatch apply`: Thực thi cài đặt bản vá mới vào hệ thống.
- `opatch rollback`: Gỡ bỏ một bản vá bị lỗi để trả về trạng thái cũ.

## Quy trình áp dụng bản vá (Patching Workflow)
1. **Dừng hệ thống:** Tắt toàn bộ Database, Listener, và các ứng dụng kết nối vào `ORACLE_HOME`.
2. **Backup:** Nén (tar) toàn bộ thư mục `ORACLE_HOME` lại cất đi phòng hờ.
3. **Apply Binary Patch:** Chạy lệnh `opatch apply` để sửa đổi mã nguồn (thay thế các file `.dll`, `.so` của Oracle).
4. **Mở hệ thống:** Bật Database lên.
5. **Datapatch (Apply SQL Patch):** Chạy tiện ích `datapatch -verbose`. Đây là tiện ích chạy các lệnh `.sql` nhằm cập nhật cấu trúc bảng Data Dictionary bên trong ruột của Database cho tương thích với bộ cài vật lý vừa mới được nâng cấp.

---
## Câu hỏi ôn tập

**Câu 1: Tôi có thể bỏ qua quá trình cập nhật OPatch trước khi cài đặt một bản RU mới không?**
- **Trả lời:** Không nên và đôi khi không thể. Mỗi bản RU thường yêu cầu một phiên bản tối thiểu của tiện ích OPatch (được quy định trong file README). Nếu OPatch của bạn quá cũ, nó sẽ từ chối đọc file zip của bản RU mới.

**Câu 2: RUR (Release Update Revision) có bao gồm các bản vá của RU không?**
- **Trả lời:** RUR được xây dựng trên nền của một RU cụ thể. Ví dụ: RUR 19.3.1 chỉ sửa lỗi cho RU 19.3. Nó không chứa các cải tiến mới của RU 19.4. Do đó, hiện nay Oracle khuyến cáo khách hàng nên nâng cấp thẳng theo luồng RU để có chất lượng tốt nhất.

**Câu 3: Lệnh `opatch apply` tác động lên những thành phần nào?**
- **Trả lời:** Nó chỉ sửa đổi, sao chép và biên dịch lại các file thực thi (Binaries/Executables) nằm trên đĩa cứng hệ điều hành bên trong `ORACLE_HOME`. Nó hoàn toàn KHÔNG đụng chạm gì đến dữ liệu bên trong database (Datafiles).

**Câu 4: Nếu `opatch apply` không đụng chạm đến Database, tại sao tôi phải chạy thêm lệnh `datapatch`?**
- **Trả lời:** Mặc dù phần mềm hệ điều hành đã được cập nhật, cấu trúc các bảng hệ thống (Data Dictionary) bên trong ruột Database vẫn là cấu trúc cũ. Tiện ích `datapatch` sẽ tự động kết nối vào DB, thực thi các kịch bản SQL (ví dụ: tạo bảng mới, đổi tên cột hệ thống, cấp quyền mới) để Data Dictionary đồng bộ với phần mềm.

**Câu 5: Trong môi trường Multitenant, tiện ích `datapatch` xử lý các PDB như thế nào?**
- **Trả lời:** Theo mặc định, lệnh `datapatch` sẽ tự động quét và nâng cấp Data Dictionary cho toàn bộ các Container đang ở trạng thái OPEN. Nó sẽ chạy trên CDB Root và lan xuống tất cả các PDB. (Đó là lý do bạn phải lệnh mở tất cả PDB trước khi chạy datapatch).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/110-patching-oracle-databases.md`
