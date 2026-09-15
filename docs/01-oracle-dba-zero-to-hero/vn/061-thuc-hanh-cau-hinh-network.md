---
title: 'Bài 61: Thực hành - Cấu hình Môi trường Mạng Oracle Network'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/61-thuc-hanh-cau-hinh-network.md
---

# Bài 61: Thực hành - Cấu hình Môi trường Mạng Oracle Network

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ thực hiện các thao tác quản trị mạng Oracle trong môi trường thực tế:
- Kiểm tra và thiết lập biến môi trường `$TNS_ADMIN`.
- Cấu hình phương thức phân giải tên **Easy Connect** và **Local Naming** trong `tnsnames.ora`.
- Kiểm soát thứ tự ưu tiên các phương pháp phân giải tên qua file `sqlnet.ora`.
- Vận hành và giám sát Listener bằng tiện ích dòng lệnh **`lsnrctl`**.
- Cấu hình Đăng ký Dịch vụ Tĩnh (**Static Service Registration**) trong `listener.ora`.
- Sử dụng tiện ích **`tnsping`** để đo độ trễ và kiểm tra đường truyền mạng.

---

## Sơ đồ Thực hành Cấu hình Mạng

![Network Configuration Practice](104-107-practice-configuring-oracle-network-environment/images/practice-configuring-oracle-01.png)

---

## Phần 1: Khám phá File Cấu hình Mạng và Biến `$TNS_ADMIN`

### Bước 1–4: Kiểm tra và thiết lập `$TNS_ADMIN`
Đăng nhập máy chủ `srv1` bằng user `oracle`:
```bash
# Kiểm tra biến TNS_ADMIN hiện tại:
echo $TNS_ADMIN
# Mặc định biến này rỗng. Các file nằm tại $ORACLE_HOME/network/admin

# Xem các file cấu hình mặc định:
ls -la $ORACLE_HOME/network/admin
# Sẽ thấy: listener.ora, tnsnames.ora, sqlnet.ora

# Thiết lập TNS_ADMIN vào .bash_profile để tiện quản trị:
echo "export TNS_ADMIN=\$ORACLE_HOME/network/admin" >> ~/.bash_profile
source ~/.bash_profile
echo $TNS_ADMIN
```

### Bước 5–6: Xem nội dung `listener.ora` và `tnsnames.ora`
```bash
cat $TNS_ADMIN/listener.ora
```
*Nội dung mẫu:*
```text
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = srv1.localdomain)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )
```

```bash
cat $TNS_ADMIN/tnsnames.ora
```
*Nội dung mẫu:*
```text
ORADB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = srv1.localdomain)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = oradb.localdomain)
    )
  )
```

---

## Phần 2: Thử nghiệm Kết nối Easy Connect và Local Naming

### Bước 7: Kết nối bằng Easy Connect (Không cần cấu hình file)
```bash
# Kết nối vào Root CDB:
sqlplus sys/ABcd##1234@//srv1/oradb.localdomain as sysdba

# Kết nối vào PDB1:
sqlplus hr/ABcd##1234@//srv1:1521/pdb1.localdomain
```

### Bước 8: Thêm TNS Alias cho PDB1 vào `tnsnames.ora`
Chỉnh sửa file `$TNS_ADMIN/tnsnames.ora` bằng `vi`:
```text
PDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = srv1.localdomain)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = pdb1.localdomain)
    )
  )
```

Kiểm tra kết nối bằng Local Naming:
```bash
# Đo độ trễ tới listener qua alias:
tnsping PDB1

# Đăng nhập bằng tên bí danh ngắn gọn:
sqlplus hr/ABcd##1234@PDB1
```

---

## Phần 3: Kiểm soát Phương pháp Phân giải Tên bằng `sqlnet.ora`

Mở file `$TNS_ADMIN/sqlnet.ora`:
```text
# Chỉ cho phép phân giải tên bằng TNSNAMES, sau đó đến EZCONNECT:
NAMES.DIRECTORY_PATH= (TNSNAMES, EZCONNECT)
```

Thử nghiệm:
1. Nếu bạn xóa `EZCONNECT` khỏi danh sách:
   ```text
   NAMES.DIRECTORY_PATH= (TNSNAMES)
   ```
2. Thử chạy lại lệnh Easy Connect:
   ```bash
   sqlplus hr/ABcd##1234@//srv1/pdb1.localdomain
   # ❌ Sẽ bị lỗi ORA-12154: TNS:could not resolve the connect identifier!
   ```
3. Khôi phục lại cấu hình chuẩn:
   ```text
   NAMES.DIRECTORY_PATH= (TNSNAMES, EZCONNECT)
   ```

---

## Phần 4: Điều khiển và Giám sát Listener bằng `lsnrctl`

```bash
# 1. Kiểm tra trạng thái chi tiết của Listener:
lsnrctl status
```
*Kết quả quan trọng cần chú ý:*
- **Listening Endpoints Summary:** Giao thức TCP trên cổng 1521.
- **Services Summary:** Danh sách các database services và trạng thái `READY` (đăng ký động từ `LREG`).

```bash
# 2. Dừng Listener:
lsnrctl stop

# 3. Thử kết nối khi Listener tắt:
sqlplus hr/ABcd##1234@PDB1
# ❌ Lỗi ORA-12541: TNS:no listener!

# 4. Bật lại Listener:
lsnrctl start

# 5. Ép buộc Database Instance đăng ký ngay với Listener mà không cần đợi:
sqlplus / as sysdba
SQL> ALTER SYSTEM REGISTER;
SQL> exit;

lsnrctl status
# Các dịch vụ lập tức chuyển sang trạng thái READY.
```

---

## Phần 5: Cấu hình Đăng ký Tĩnh (Static Registration) trong `listener.ora`

Mở file `$TNS_ADMIN/listener.ora` và thêm khối `SID_LIST_LISTENER`:
```text
SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = oradb.localdomain)
      (ORACLE_HOME = /u01/app/oracle/product/19.3.0/dbhome_1)
      (SID_NAME = oradb)
    )
  )
```

Nạp lại cấu hình mà không làm gián đoạn các kết nối hiện tại:
```bash
lsnrctl reload
lsnrctl status
```
> **Quan sát:** Trong danh sách dịch vụ của `lsnrctl status`, bạn sẽ thấy dịch vụ `oradb.localdomain` có trạng thái là **`UNKNOWN`** bên cạnh các trạng thái `READY`. Điều này xác nhận việc Đăng ký Tĩnh đã thành công hoàn hảo!

---

## Câu hỏi ôn tập

**1. Khi bạn thực hiện lệnh `lsnrctl reload`, các kết nối người dùng hiện tại có bị ngắt không?**
> **Trả lời:**
> **Hoàn toàn KHÔNG bị ngắt.** Lệnh `lsnrctl reload` chỉ yêu cầu tiến trình Listener đọc lại nội dung của file cấu hình `listener.ora` vào bộ nhớ để cập nhật các tham số mới. Tất cả các phiên làm việc của người dùng đang kết nối trực tiếp với Server Process sẽ tiếp tục hoạt động bình thường mà không hề bị ảnh hưởng.

**2. Lỗi `ORA-12154: TNS:could not resolve the connect identifier specified` thường xuất phát từ những nguyên nhân nào?**
> **Trả lời:**
> Lỗi này xuất phát từ việc Oracle Client không tìm thấy tên dịch vụ trong danh bạ mạng:
> - Gõ sai chính tả tên TNS Alias (ví dụ gõ `@PBD1` thay vì `@PDB1`).
> - File `tnsnames.ora` chưa được khai báo alias đó, hoặc file bị đặt sai thư mục (sai `$TNS_ADMIN`).
> - File `sqlnet.ora` có cấu hình `NAMES.DEFAULT_DOMAIN` khiến Oracle tự động nối thêm đuôi domain vào tên alias gây sai lệch.
> - Cú pháp trong file `tnsnames.ora` bị lỗi (thừa/thiếu dấu ngoặc đơn, sai thụt dòng).

**3. Tại sao sau khi chạy lệnh `lsnrctl start`, bạn gõ `lsnrctl status` ngay thì lại chưa thấy xuất hiện các dịch vụ database?**
> **Trả lời:**
> Vì dịch vụ được đăng ký theo cơ chế **Đăng ký Động (Dynamic Registration)** bởi tiến trình `LREG`. Tiến trình này hoạt động theo chu kỳ (mặc định gửi tín hiệu mỗi 60 giây). Khi Listener vừa bật lên, `LREG` chưa kịp đến chu kỳ gửi gói tin đăng ký. Để không phải đợi, DBA có thể vào `sqlplus` và gõ lệnh **`ALTER SYSTEM REGISTER;`** để ép buộc tiến trình `LREG` đăng ký ngay lập tức.

**4. Lỗi `ORA-12541: TNS:no listener` có ý nghĩa gì và cách khắc phục ra sao?**
> **Trả lời:**
> - Ý nghĩa: Máy trạm kết nối thành công đến địa chỉ IP của máy chủ nhưng **không có tiến trình Listener nào đang lắng nghe trên cổng mạng đó (cổng 1521)**.
> - Cách khắc phục: Đăng nhập vào máy chủ Database Server bằng SSH/Terminal và kiểm tra/khởi động Listener bằng lệnh `lsnrctl status` và `lsnrctl start`. Ngoài ra cần kiểm tra Firewall (iptables/firewalld) trên máy chủ có đang chặn cổng 1521 hay không.

**5. Tham số `NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)` trong file `sqlnet.ora` quy định điều gì?**
> **Trả lời:**
> Tham số này quy định **danh sách và thứ tự ưu tiên của các phương thức phân giải tên**:
> - Khi người dùng truyền vào một chuỗi kết nối (`CONNECT user/pass@alias`), Oracle Net sẽ tra cứu trong file cục bộ `tnsnames.ora` trước (`TNSNAMES`).
> - Nếu không tìm thấy trong file `tnsnames.ora`, Oracle mới thử tiếp phương thức phân giải chuỗi kết nối trực tiếp `EZCONNECT`. Các phương thức không nằm trong danh sách sẽ bị vô hiệu hóa.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/61-thuc-hanh-cau-hinh-network.md`
