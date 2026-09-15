---
title: 'Bài 111: Thực hành - Áp dụng Bản vá RU lên Cơ sở dữ liệu'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/111-practice-patching-oracle-databases.md
---

# Bài 111: Thực hành - Áp dụng Bản vá RU lên Cơ sở dữ liệu

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Cập nhật công cụ `OPatch` lên phiên bản mới nhất.
- Kiểm tra xung đột bản vá (Conflict check).
- Áp dụng bản vá hệ thống (RU) và bản vá Java (OJVM) lên Database 19.3.
- Chạy công cụ `datapatch` để đồng bộ Data Dictionary.

## A. Cập nhật Tiện ích OPatch
**1.** Kiểm tra phiên bản OPatch hiện tại:
```bash
$ORACLE_HOME/OPatch/opatch version
```
**2.** Lấy file `p6880880...` (phiên bản cập nhật của OPatch) từ ổ đĩa chia sẻ.
**3.** Xóa OPatch cũ và giải nén OPatch mới:
```bash
rm -fr $ORACLE_HOME/OPatch
unzip /media/sf_staging/p6880880_190000_Linux-x86-64.zip -d $ORACLE_HOME
```
**4.** Kiểm tra lại lệnh `$ORACLE_HOME/OPatch/opatch lsinventory` xem mọi thứ vẫn chạy trơn tru không.

## B. Chuẩn bị và Kiểm tra xung đột (Pre-Check)
**5.** Tải file bộ vá Database RU 19.16 (ví dụ `p34133642...`) vào Linux và giải nén ra thư mục `~/staging`.
**6.** Thêm đường dẫn OPatch vào biến môi trường:
```bash
export PATH=$PATH:$ORACLE_HOME/OPatch
```
**7.** Di chuyển vào thư mục bản vá vừa giải nén và chạy lệnh Pre-check:
```bash
cd ~/staging/34133642
opatch prereq CheckConflictAgainstOHWithDetail -ph ./
```
*(Lệnh này đọc thông tin cấu trúc hệ thống và trả về thông báo Passed nếu không có xung đột).*

## C. Áp dụng bản vá vật lý (Binary Patch)
**8.** Phải tắt TOÀN BỘ tiến trình đang giữ file của Database (Database, Listener):
```bash
sqlplus / as sysdba
shutdown immediate;
exit;
lsnrctl stop
```
**9.** Chạy lệnh áp dụng bản vá (Quá trình này có thể mất 10 phút, nó sẽ thay thế các file lõi của phần mềm Oracle):
```bash
opatch apply
```
*(Nếu nó hỏi bạn có muốn cập nhật cấu hình không, cứ chọn Y).*

## D. Cập nhật Data Dictionary (`datapatch`)
Bây giờ phần cứng (Binaries) đã lên đời, nhưng cấu trúc bảng bên trong Database (ruột) vẫn ở bản cũ.

**10.** Bật lại Database và toàn bộ các PDB:
```bash
sqlplus / as sysdba
startup;
ALTER PLUGGABLE DATABASE ALL OPEN;
exit;
```
**11.** Chạy công cụ `datapatch` để chạy các script SQL nội bộ:
```bash
cd $ORACLE_HOME/OPatch
./datapatch -verbose
```
*(Quá trình này sẽ đăng nhập vào CDB và chạy một loạt các file `.sql` để cập nhật bảng từ bản 19.3 lên 19.16. Nó tự động lan xuống tất cả các PDB đang OPEN).*

**12.** (Tùy chọn) Chạy `utlrp.sql` để biên dịch lại các đối tượng bị văng lỗi Invalid.
**13.** Kiểm tra thành quả bằng cách query vào bảng báo cáo phiên bản:
```sql
SELECT patch_id, version, status, description FROM dba_registry_sqlpatch;
```

---
## Câu hỏi ôn tập

**Câu 1: Nếu lệnh `opatch prereq CheckConflictAgainstOHWithDetail` báo có xung đột (Conflict), tôi phải làm gì?**
- **Trả lời:** Bạn PHẢI DỪNG việc cài đặt ngay lập tức. Việc này có nghĩa là bạn đã từng cài một bản vá cá nhân (one-off patch) có khả năng ghi đè lên các thay đổi của RU này. Bạn cần tạo Service Request (SR) gửi cho Oracle Support để xin một bản vá giải quyết xung đột (Merge patch).

**Câu 2: Tại sao trước khi chạy `opatch apply` phải chạy lệnh `lsnrctl stop`?**
- **Trả lời:** Tiến trình Listener và các tiến trình chạy nền của Database (PMON, SMON) nắm giữ các file thư viện động (`.so` hoặc `.dll`) vào trong bộ nhớ RAM để hoạt động. Nếu không tắt chúng đi, OPatch sẽ không thể ghi đè file mới lên đĩa cứng vì hệ điều hành đang khóa các file đó (File in use).

**Câu 3: Mục đích của lệnh `ALTER PLUGGABLE DATABASE ALL OPEN` ở bước 10 là gì?**
- **Trả lời:** Khi CDB khởi động lên (`startup`), theo mặc định các PDB nằm bên trong nó đang ở trạng thái MOUNT. Nếu không mở (OPEN) các PDB ra, tiện ích `datapatch` sẽ bỏ qua chúng và không chịu chạy lệnh SQL cập nhật lên Data Dictionary của các PDB này.

**Câu 4: Quá trình `datapatch` có thể gây treo hệ thống ứng dụng không?**
- **Trả lời:** Rất có thể. Quá trình `datapatch` chạy hàng trăm câu lệnh DDL sửa đổi cấu trúc hệ thống và cấp quyền lại. Người dùng ứng dụng truy cập lúc này có thể gặp lỗi văng vỡ hệ thống. Vì thế người ta thường cấm ứng dụng (vẫn tắt Listener) cho đến khi datapatch chạy xong 100%.

**Câu 5: Bảng `dba_registry_sqlpatch` lưu giữ thông tin gì?**
- **Trả lời:** Nó là một cuốn nhật ký sổ cái hệ thống nội bộ lưu giữ danh sách và trạng thái (THÀNH CÔNG hay LỖI) của toàn bộ các lần chạy công cụ `datapatch`. DBA kiểm tra bảng này để xác nhận Database đã được vá đủ các lỗ hổng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/111-practice-patching-oracle-databases.md`
