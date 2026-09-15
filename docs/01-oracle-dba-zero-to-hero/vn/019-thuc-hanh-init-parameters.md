---
title: 'Bài 19: Thực hành - Quản lý Init Parameters'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/19-thuc-hanh-init-parameters.md
---

# Bài 19: Thực hành - Quản lý Init Parameters

## 🎯 Mục tiêu học tập
Trong bài thực hành này, bạn sẽ tự tay thực hiện các công việc quản trị cấu hình (Initialization Parameters) của Oracle Database. Cụ thể:
- Xem các giá trị tham số cấu hình hiện tại.
- Thay đổi tham số hệ thống (Dynamic & Static Parameters).
- Thay đổi cấu hình ở mức Session.
- Xử lý sự cố "Database không khởi động được" do cấu hình sai bằng cách dùng PFILE và SPFILE.

> 💡 **Ví von đời thường:** Tưởng tượng Database như một chiếc xe hơi. **Init Parameters** chính là các "nút điều chỉnh" trên xe: có nút bạn có thể vặn ngay khi xe đang chạy (Dynamic parameter - ví dụ: chỉnh nhiệt độ điều hòa, âm lượng nhạc), có nút bắt buộc bạn phải tắt máy, điều chỉnh rồi mới khởi động lại (Static parameter - ví dụ: thay đổi kích thước mâm xe, độ lại ống xả).

## 🛠️ Chuẩn bị
Đảm bảo máy chủ `srv1` và database (non-CDB) đang hoạt động (up and running).

---

## 1️⃣ Kiểm tra SPFILE và các tham số khởi tạo

Đầu tiên, chúng ta sẽ xem xét các tham số khởi tạo đang được lưu trong SPFILE.

**Bước 1:** Mở session Putty kết nối vào máy chủ `srv1` với user `oracle`.

**Bước 2:** Truy cập SQL*Plus kết nối vào database với quyền `system`.
```bash
sqlplus system/ABcd##1234
```

**Bước 3:** Kiểm tra xem Database đang dùng file cấu hình nào lúc khởi động.
```sql
-- Lệnh này hiển thị đường dẫn file SPFILE đang được sử dụng
show parameter SPFILE
```
> 💡 Thông thường, SPFILE có tên mặc định là `spfile<ORACLE_SID>.ora` và nằm ở `$ORACLE_HOME/dbs`. Mỗi khi database khởi động, nó tự động đọc file này (trừ khi bạn chỉ định rõ dùng PFILE thông qua lệnh STARTUP).

**Bước 4:** Thử xem nội dung của SPFILE.
```bash
-- Gọi lệnh hệ điều hành (host) để xem nội dung file
host cat /u01/app/oracle/product/19.0.0/db_1/dbs/spfileoradb.ora
```
> ⚠️ **CẢNH BÁO:** Bạn sẽ thấy nội dung file khá lộn xộn vì **SPFILE là file nhị phân (binary file)**. TUYỆT ĐỐI KHÔNG mở file này bằng các trình soạn thảo text (như vi, nano) để chỉnh sửa, nếu không file sẽ bị hỏng. Cách duy nhất để sửa là dùng lệnh `ALTER SYSTEM SET`. Các tham số tiền tố `*` có ý nghĩa quan trọng trong môi trường RAC. Các tham số `*._` là do Oracle tự quản lý.

**Bước 5:** Kiểm tra giá trị của tham số `SGA_TARGET` (dung lượng RAM cấp cho SGA).
```sql
-- Xem giá trị trong bộ nhớ hiện tại
show parameter SGA_TARGET

-- Hoặc dùng query từ view V$PARAMETER (tên cột thường viết thường)
SELECT VALUE/1024/1024 MB FROM V$PARAMETER WHERE NAME='sga_target';
```

**Bước 6:** Kiểm tra giá trị của tham số này đang lưu trong SPFILE.
```sql
-- Xem giá trị được lưu trong SPFILE
SELECT VALUE/1024/1024 MB FROM V$SPPARAMETER WHERE NAME='sga_target';
```
*(Giá trị trong bộ nhớ và trong SPFILE lúc này cơ bản là giống nhau, có thể chênh lệch 1MB không đáng kể).*

---

## 2️⃣ Thay đổi tham số Dynamic (SCOPE=MEMORY)

Bạn có thể thay đổi các thông số động ngay khi DB đang chạy.

**Bước 7:** Đổi `SGA_TARGET` thành 2000MB nhưng chỉ áp dụng trên bộ nhớ.
```sql
-- SCOPE=MEMORY nghĩa là chỉ thay đổi trên RAM, khi khởi động lại DB sẽ mất.
ALTER SYSTEM SET SGA_TARGET=2000M SCOPE=MEMORY;
```

**Bước 8:** Kiểm chứng lại sự thay đổi.
```sql
-- Kiểm tra lại, bạn sẽ thấy trên RAM (V$PARAMETER) đã đổi
SELECT VALUE/1024/1024 MB FROM V$PARAMETER WHERE NAME='sga_target';

-- Trong file (V$SPPARAMETER) vẫn giữ giá trị cũ.
SELECT VALUE/1024/1024 MB FROM V$SPPARAMETER WHERE NAME='sga_target';
```

---

## 3️⃣ Cố gắng thay đổi tham số Static

`SGA_MAX_SIZE` quy định kích thước tối đa của SGA. Đây là một tham số tĩnh (Static). Thử xem điều gì xảy ra nếu ta sửa nó như tham số động.

**Bước 9 & 10:**
```sql
show parameter sga_max_size

-- Cố gắng đổi mà không ghi rõ SCOPE (mặc định Oracle sẽ hiểu là SCOPE=BOTH)
ALTER SYSTEM SET SGA_MAX_SIZE=1000M;
```
> 🛑 **Lỗi hiển thị:** `ORA-02095: specified initialization parameter cannot be modified`.
> Lỗi này xảy ra vì `SGA_MAX_SIZE` là tham số tĩnh. Tham số tĩnh bắt buộc phải dùng `SCOPE=SPFILE`, sau đó restart DB thì hệ thống mới áp dụng được.

---

## 4️⃣ Thay đổi tham số ở mức Session

Mức Session giống như bạn thuê một căn phòng khách sạn và tự chỉnh điều hòa cho riêng phòng mình. Nó không ảnh hưởng tới người khác.

**Bước 11 & 12:** Kiểm tra định dạng ngày tháng hiện tại.
```sql
-- Xem định dạng ngày hiện tại
show parameter NLS_DATE_FORMAT

-- Xem thử kết quả thực tế
SELECT SYSDATE FROM DUAL;
```

**Bước 13:** Đổi định dạng ngày giờ CHỈ CHO SESSION NÀY.
```sql
-- Lệnh ALTER SESSION chỉ ảnh hưởng đến session hiện tại
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MM-YY HH24:MI:SS';

-- Xem lại ngày giờ
SELECT SYSDATE FROM DUAL;
```

**Bước 14 & 15:** Thoát ra vào lại để kiểm chứng.
```sql
-- Khởi tạo một session mới
conn system/ABcd##1234

-- Ngày giờ sẽ quay về format mặc định ban đầu
SELECT SYSDATE FROM DUAL;
```

---

## 5️⃣ Cứu hộ Database khi cấu hình sai (SPFILE bị hỏng)

Đây là tình huống thực tế các DBA rất hay gặp: Cấu hình sai tham số trong SPFILE, Database sập và không bật lên được.

**Bước 16 & 17:** Tự "phá" Database bằng cách set `SGA_TARGET` quá nhỏ.
```sql
-- Cấu hình sai và lưu thẳng vào SPFILE
ALTER SYSTEM SET SGA_TARGET=50M SCOPE=SPFILE;

-- Chuyển qua user SYSDBA và Khởi động lại Database
conn / as sysdba
shutdown immediate
startup
```
> 🛑 **Lỗi trả về:** 
> `ORA-00821: Specified value of sga_target 52M is too small, needs to be at least 272M`
> `ORA-01078: failure in processing system parameters`
> 
> Database KHÔNG khởi động được do SGA_TARGET quá nhỏ. Lúc này bạn không thể dùng `ALTER SYSTEM` vì DB đang tắt. Bạn cũng không thể dùng lệnh `vi` sửa SPFILE vì nó là file nhị phân. Vậy phải làm sao?

**Cách khắc phục: Dùng PFILE để làm cầu nối**
PFILE là file văn bản (text file), có thể chỉnh sửa dễ dàng bằng trình soạn thảo (vi/nano). Ta sẽ trích xuất PFILE từ SPFILE, sửa lỗi trên PFILE, khởi động DB bằng PFILE, và cuối cùng tạo lại SPFILE.

**Bước 18:** Trích xuất SPFILE ra thành PFILE
```sql
-- Lệnh này đọc SPFILE hiện tại và xuất ra dạng text vào file tạm
CREATE PFILE='/home/oracle/PFILEtemp.ora' from SPFILE;
```

**Bước 19:** Dùng trình soạn thảo sửa lỗi trong PFILE
```bash
-- Mở file bằng vi
host vi /home/oracle/PFILEtemp.ora
```
*(Tìm dòng chứa `SGA_TARGET`, sửa giá trị thành `2516582400` tương đương 2400MB, lưu và thoát `vi` bằng `:wq`)*

**Bước 20:** Khởi động tạm DB bằng PFILE
```sql
-- Chỉ định rõ file PFILE khi startup
startup PFILE=/home/oracle/PFILEtemp.ora
```
> 💡 **Thực tế:** Trong môi trường Production, trước bước này bạn nên tắt Listener đi để đảm bảo không user nào kết nối vào Database trong lúc bạn đang sửa chữa tạm thời.

**Bước 21:** Lưu lại cấu hình chuẩn vào SPFILE
```sql
-- Ghi đè cấu hình đúng từ PFILE ngược lại vào SPFILE mặc định
CREATE SPFILE FROM PFILE='/home/oracle/PFILEtemp.ora';
```

**Bước 22:** Khởi động lại bình thường.
```sql
-- Lần tắt bật này DB sẽ tự động đọc từ SPFILE mặc định đã được sửa lỗi
shutdown immediate
startup
```

**Bước 23 & 24:** Dọn dẹp và kết thúc.
```sql
-- Xóa file PFILE tạm
host rm /home/oracle/PFILEtemp.ora

-- Thoát SQL*Plus
quit
```

---

## 📝 Tóm tắt bài học

- **SPFILE (Server Parameter File)** là file cấu hình nhị phân, chỉ thay đổi thông qua lệnh `ALTER SYSTEM`.
- Các tham số **Dynamic** có thể đổi ngay lập tức trên RAM (SCOPE=MEMORY) hoặc cả RAM và SPFILE (SCOPE=BOTH). 
- Các tham số **Static** bắt buộc phải ghi vào SPFILE (SCOPE=SPFILE) và restart DB thì mới có tác dụng.
- Lệnh **ALTER SESSION** chỉ thay đổi cấu hình cho riêng kết nối hiện tại của bạn.
- Khi SPFILE bị lỗi khiến DB không mở được, hãy ghi nhớ "công thức cứu hộ": `CREATE PFILE FROM SPFILE` ➡️ Sửa lỗi trong PFILE bằng lệnh `vi` ➡️ `STARTUP PFILE=...` ➡️ `CREATE SPFILE FROM PFILE`.

## ❓ Câu hỏi ôn tập

**1. Điểm khác biệt lớn nhất giữa **PFILE** và **SPFILE** là gì về mặt định dạng và cách chỉnh sửa?**
> **Trả lời:**
> - **Định dạng:** PFILE là file văn bản thuần túy (ASCII Text File), có thể đọc và sửa bằng bất kỳ trình soạn thảo văn bản nào (`vi`, `nano`, Notepad). SPFILE là file nhị phân (Binary File) được biên dịch bởi Oracle, nếu dùng trình soạn thảo văn bản để sửa sẽ làm hỏng checksum/header của file.
> - **Cách chỉnh sửa:** PFILE được sửa bằng tay khi database offline hoặc phải restart để có hiệu lực. SPFILE được sửa trực tuyến bằng lệnh SQL `ALTER SYSTEM SET parameter = value [SCOPE=...]` mà không cần đụng đến hệ điều hành.

**2. Tại sao câu lệnh `ALTER SYSTEM SET SGA_MAX_SIZE=1000M;` lại trả về lỗi `ORA-02095`?**
> **Trả lời:**
> Lỗi `ORA-02095: specified initialization parameter cannot be modified` xảy ra vì:
> - `SGA_MAX_SIZE` là một **Static Parameter** (tham số tĩnh), nó quy định kích thước tối đa của vùng nhớ ảo mà Oracle cấp phát ngay lúc khởi động instance, không thể co giãn trên RAM khi DB đang chạy.
> - Khi bạn gõ `ALTER SYSTEM SET SGA_MAX_SIZE=1000M;` mà không chỉ định mệnh đề `SCOPE`, Oracle mặc định dùng `SCOPE=BOTH` (sửa cả MEMORY lẫn SPFILE). Do không thể sửa MEMORY, Oracle lập tức ném lỗi ORA-02095.
> - Cú pháp đúng bắt buộc phải là:
>   ```sql
>   ALTER SYSTEM SET SGA_MAX_SIZE=1000M SCOPE=SPFILE;
>   ```
>   Sau đó khởi động lại Database để nhận kích thước mới.

**3. Nếu bạn muốn thay đổi định dạng ngày tháng hiển thị cho một ứng dụng mà không ảnh hưởng đến các ứng dụng khác, bạn nên dùng lệnh nào?**
> **Trả lời:**
> Sử dụng lệnh **`ALTER SESSION`** ngay sau khi ứng dụng kết nối vào database:
> ```sql
> ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
> ```
> Lệnh này chỉ có phạm vi tác dụng duy nhất trong phiên làm việc (session) hiện tại của ứng dụng đó, hoàn toàn không làm thay đổi cấu hình toàn cục của Database và không ảnh hưởng đến các phiên làm việc của người dùng hay ứng dụng khác.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/19-thuc-hanh-init-parameters.md`
