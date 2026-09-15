---
title: 'Bài 17: Thực hành - Khởi động và Tắt Database Instance'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/17-thuc-hanh-khoi-dong-tat-db.md
---

# Bài 17: Thực hành - Khởi động và Tắt Database Instance

Chào mừng bạn đến với bài thực hành về quản trị Database! Trong bài này, chúng ta sẽ "xắn tay áo" lên để trực tiếp thực hiện các thao tác tắt và mở một Oracle Database. 

> 💡 **Tại sao bài này quan trọng?** 
> Là một DBA (Quản trị viên Cơ sở dữ liệu), việc bật/tắt database là công việc cơ bản nhất nhưng cũng cực kỳ quan trọng. Hãy tưởng tượng database giống như một chiếc xe máy. Bạn không thể vừa đi vừa thay nhớt được! Có những lúc bạn cần tắt hẳn xe (Shutdown) để bảo trì, và có những lúc bạn cần nổ máy (Startup) theo từng nấc để kiểm tra lỗi.

---

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài thực hành này, bạn sẽ:
- Nắm vững các bước thiết lập môi trường Linux trước khi thao tác với Oracle.
- Biết cách theo dõi file **Alert Log** – "chiếc hộp đen" ghi lại toàn bộ hoạt động của Database.
- Trải nghiệm các chế độ **SHUTDOWN** (Tắt) khác nhau: Normal, Transactional, Immediate, Abort.
- Thực hành các chế độ **STARTUP** (Khởi động): Nomount, Mount, Open.

---

## 🛠️ Bước 1: Thiết lập môi trường và theo dõi Alert Log

Trước khi làm việc với Oracle trên Linux, chúng ta luôn cần khai báo cho hệ điều hành biết chúng ta đang muốn tương tác với Database nào.

### 1.1. Thiết lập biến môi trường
Mở Terminal (hoặc Putty) kết nối vào máy chủ Linux bằng user `oracle`:
```bash
# Thiết lập biến môi trường ORACLE_SID để trỏ tới database (ví dụ: orcl)
export ORACLE_SID=orcl

# (Tùy chọn) Chạy script oraenv để thiết lập tự động các biến khác
. oraenv
```

### 1.2. Mở cửa sổ theo dõi Alert Log
Alert Log là file nhật ký quan trọng nhất của Oracle, ghi lại mọi quá trình bật/tắt. Hãy mở một cửa sổ Terminal thứ hai, kết nối user `oracle` và dùng lệnh `tail -f` để theo dõi realtime (thời gian thực):
```bash
# Di chuyển đến thư mục chứa Alert Log (đường dẫn có thể khác tùy hệ thống của bạn)
cd $ORACLE_BASE/diag/rdbms/orcl/orcl/trace

# Xem file alert log liên tục
tail -f alert_orcl.log
```
> 💡 **Mẹo:** Hãy để cửa sổ này sang một bên. Khi bạn gõ lệnh STARTUP hay SHUTDOWN ở các bước sau, hãy nhìn vào cửa sổ này để thấy database đang chạy từng bước ra sao!

---

## 🛑 Bước 2: Thử nghiệm các chế độ SHUTDOWN (Tắt Database)

Trong Oracle, có 4 cách để tắt database. Giống như đóng cửa một siêu thị:
- **NORMAL**: Đợi tất cả khách mua xong và tự ra về rồi mới đóng cửa.
- **TRANSACTIONAL**: Khách đang mua thì mua nốt, nhưng không nhận thêm khách mới.
- **IMMEDIATE**: Khách đang mua bị mời ra ngay (roll back), siêu thị đóng cửa ngay lập tức.
- **ABORT**: Rút điện sập nguồn! (Chỉ dùng khi khẩn cấp).

### 2.1. Chuẩn bị dữ liệu test
Ở Terminal thứ nhất, đăng nhập bằng user `SYSTEM`:
```sql
sqlplus system/ABcd##1234

-- Tạo một bảng để test
CREATE TABLE test_shutdown (A VARCHAR2(20));

-- Thêm dữ liệu nhưng KHÔNG gõ lệnh COMMIT (giao dịch đang treo)
INSERT INTO test_shutdown VALUES ('Dang mua hang');
```

### 2.2. Thử nghiệm SHUTDOWN NORMAL
Mở Terminal thứ 3, đăng nhập với quyền cao nhất `SYSDBA`:
```bash
sqlplus / as sysdba
```
Gõ lệnh tắt mặc định:
```sql
SHUTDOWN NORMAL;
```
> ⚠️ **Hiện tượng:** Lệnh này sẽ **bị treo**! Tại vì phiên làm việc của user `SYSTEM` vẫn đang mở. Bạn phải quay lại cửa sổ `SYSTEM`, gõ `exit` để thoát thì lệnh Shutdown mới chạy tiếp. (Normal yêu cầu tất cả user phải disconnect).

Khởi động lại database để thử chế độ khác:
```sql
STARTUP;
```

### 2.3. Thử nghiệm SHUTDOWN TRANSACTIONAL
Lặp lại việc tạo giao dịch treo bên cửa sổ `SYSTEM`:
```sql
sqlplus system/ABcd##1234
INSERT INTO test_shutdown VALUES ('Khach dang xep hang');
```
Bên cửa sổ `SYSDBA`, gõ:
```sql
SHUTDOWN TRANSACTIONAL;
```
> ⚠️ **Hiện tượng:** Lệnh tiếp tục **bị treo**, nhưng lần này nó đang chờ bạn gõ `COMMIT` hoặc `ROLLBACK` bên cửa sổ `SYSTEM`.
Hãy quay lại cửa sổ `SYSTEM` và gõ `COMMIT;`. Ngay lập tức database sẽ tiến hành tắt, và user `SYSTEM` sẽ bị ngắt kết nối (`ORA-03135: connection lost contact`).

Khởi động lại database:
```sql
STARTUP;
```

### 2.4. Thử nghiệm SHUTDOWN IMMEDIATE
Đây là cách tắt phổ biến nhất mà các DBA thường dùng.
Tạo lại giao dịch bên cửa sổ `SYSTEM` (chưa commit).
Bên cửa sổ `SYSDBA` gõ:
```sql
SHUTDOWN IMMEDIATE;
```
> 💡 **Hiện tượng:** Database tắt **ngay lập tức**! Tất cả các giao dịch chưa commit sẽ bị Rollback tự động. Các session đang kết nối bị đẩy ra ngoài ngay.

---

## 🚀 Bước 3: Thử nghiệm các chế độ STARTUP (Khởi động Database)

Khởi động Oracle Database giống như khởi động một chiếc máy tính, phải qua nhiều giai đoạn: BIOS -> Load OS -> Login. Trong Oracle, tương ứng là: **NOMOUNT -> MOUNT -> OPEN**.

### 3.1. Khởi động từng nấc
Đảm bảo database đang tắt. Tại cửa sổ `SYSDBA`, gõ:
```sql
-- Khởi động lên mức NOMOUNT (Chỉ đọc file cấu hình init/spfile, cấp phát RAM - SGA và bật các tiến trình ngầm)
STARTUP NOMOUNT;

-- Nâng lên mức MOUNT (Đọc Control File để biết các file dữ liệu nằm ở đâu)
ALTER DATABASE MOUNT;

-- Nâng lên mức OPEN (Mở các Datafiles, cho phép user bình thường kết nối)
ALTER DATABASE OPEN;
```
> 💡 **Mẹo:** Ở mỗi nấc (Nomount, Mount), nếu bạn dùng user `SYSTEM` kết nối vào, bạn sẽ nhận lỗi `ORA-01033: ORACLE initialization or shutdown in progress`. Chỉ khi Database ở trạng thái **OPEN**, user bình thường mới vào được.

### 3.2. Khởi động gộp
Thay vì gõ từng lệnh, bạn có thể dừng ở một mức cụ thể:
```sql
SHUTDOWN IMMEDIATE;

-- Lệnh này sẽ tự động đi qua Nomount và dừng lại ở Mount
STARTUP MOUNT; 
```

---

## 🧹 Bước 4: Dọn dẹp (Cleanup)

Luôn nhớ dọn dẹp "rác" sau khi thực hành xong nhé!
Tại cửa sổ `SYSTEM`:
```sql
sqlplus system/ABcd##1234
DROP TABLE test_shutdown;
```

---

## 📝 Tổng kết
Qua bài thực hành này, bạn đã tự tay điều khiển được nhịp đập của Oracle Database:
- **SHUTDOWN IMMEDIATE** là người bạn thân thiết nhất của DBA khi cần tắt DB an toàn và nhanh chóng.
- **STARTUP MOUNT** rất hữu ích khi bạn cần bảo trì database (như phục hồi dữ liệu) mà không muốn user kết nối vào.
- File **Alert Log** luôn là nơi bạn cần nhìn vào đầu tiên để biết Database đang làm gì ở phía sau.

## ❓ Câu hỏi ôn tập

**1. Nếu bạn đang nâng cấp hệ thống và không muốn user kết nối vào phá hỏng dữ liệu, bạn sẽ khởi động Database ở chế độ nào?**
> **Trả lời:**
> Bạn có 2 lựa chọn tùy mức độ nâng cấp:
> - **Cách 1 (Bảo trì nội bộ cơ bản / Patching):** Khởi động ở chế độ hạn chế (`STARTUP RESTRICT;`). Ở chế độ này database ở trạng thái OPEN nhưng chỉ những ai có quyền `RESTRICTED SESSION` (như DBA) mới đăng nhập được, mọi user thông thường sẽ bị từ chối kết nối.
> - **Cách 2 (Nâng cấp cấu trúc file / Recovery):** Khởi động ở chế độ `STARTUP MOUNT;`. Ở chế độ này Datafiles chưa được mở, hoàn toàn không có bất kỳ user nào truy cập được bảng dữ liệu.

**2. Sự khác biệt lớn nhất giữa `SHUTDOWN NORMAL` và `SHUTDOWN IMMEDIATE` là gì?**
> **Trả lời:**
> - `SHUTDOWN NORMAL`: Oracle sẽ kiên nhẫn **chờ cho đến khi tất cả người dùng tự nguyện ngắt kết nối (disconnect)** khỏi hệ thống rồi mới tiến hành tắt DB. Nếu có một người dùng để quên session qua đêm thì database sẽ treo vĩnh viễn ở trạng thái chờ.
> - `SHUTDOWN IMMEDIATE`: Oracle **lập tức ngắt kết nối** tất cả người dùng, rollback các transaction dở dang và tắt database ngay lập tức. Đây là lựa chọn tiêu chuẩn và phổ biến nhất của DBA trong mọi tình huống bảo trì.

---

*Chúc các bạn thực hành vui vẻ và không bao giờ phải dùng đến SHUTDOWN ABORT nhé!*


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/17-thuc-hanh-khoi-dong-tat-db.md`
