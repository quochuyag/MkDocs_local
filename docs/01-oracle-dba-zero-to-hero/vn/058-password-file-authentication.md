---
title: 'Bài 58: Xác thực bằng Password File (Using Password File Authentication)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/58-password-file-authentication.md
---

# Bài 58: Xác thực bằng Password File (Using Password File Authentication)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu rõ mục đích và tầm quan trọng của Password File trong Oracle Database.
- Xác định vị trí và quy ước đặt tên của Password File trên Linux và Windows.
- Sử dụng tiện ích `orapwd` để tạo và cấu hình Password File.
- Cấu hình tham số khởi tạo `REMOTE_LOGIN_PASSWORDFILE`.
- Quản trị danh sách người dùng được lưu trong Password File (`V$PWFILE_USERS`).
- Xử lý quy trình đồng bộ lại mật khẩu khi Password File bị mất hoặc hỏng.

---

## 1. Password File là gì và tại sao lại cần?

Trong hoạt động bình thường, mật khẩu của người dùng được lưu dưới dạng hash mã hóa bên trong bảng từ điển dữ liệu `SYS.USER$` (nằm trong các datafiles của `SYSTEM` tablespace).

Tuy nhiên, **khi Database chưa được mở (Database bị tắt, hoặc đang ở NOMOUNT, MOUNT)**:
- Không thể đọc bảng `SYS.USER$`.
- Nếu quản trị viên kết nối **từ xa qua mạng** (từ máy trạm client bằng Oracle Net / TNS Listener), cơ chế xác thực OS cục bộ không thể áp dụng được.

$\rightarrow$ **Giải pháp:** Oracle sử dụng một file nhị phân độc lập lưu trữ tại tầng hệ điều hành gọi là **Password File**. File này chứa mật khẩu của tài khoản `SYS` và các tài khoản được cấp đặc quyền quản trị cấp cao (`SYSDBA`, `SYSOPER`, `SYSBACKUP`, `SYSDG`, `SYSKM`).

---

## 2. Vị trí và Quy ước đặt tên Password File

| Hệ điều hành | Đường dẫn và Tên file mặc định |
| :--- | :--- |
| **Linux / Unix** | `$ORACLE_HOME/dbs/orapw<ORACLE_SID>` |
| **Windows** | `%ORACLE_HOME%\database\PWD<ORACLE_SID>.ora` |

*Ví dụ:* Nếu `ORACLE_SID = oradb` trên Linux, file sẽ là `$ORACLE_HOME/dbs/orapworadb`.

---

## 3. Tạo Password File bằng tiện ích `orapwd`

Oracle cung cấp công cụ dòng lệnh **`orapwd`** nằm trong thư mục `$ORACLE_HOME/bin`.

### Cú pháp lệnh `orapwd`:
```bash
orapwd FILE=<file_name> PASSWORD=<sys_password> [FORCE={y|n}] [FORMAT={12.2|12}]
```

> ⚠️ **Lưu ý cú pháp:** Tuyệt đối **không được có khoảng trắng** xung quanh dấu bằng (`=`).

### Ví dụ tạo thực tế:
```bash
# Đăng nhập bằng user oracle trên Linux:
orapwd FILE=$ORACLE_HOME/dbs/orapworadb PASSWORD=ABcd##1234 FORCE=y FORMAT=12.2
```
- `FORCE=y`: Cho phép ghi đè nếu password file cũ đã tồn tại.
- `FORMAT=12.2`: Định dạng mật khẩu bảo mật cao từ Oracle 12c Release 2 trở lên (mặc định hỗ trợ chữ hoa/thường và các hàm băm SHA-2).

---

## 4. Tham số `REMOTE_LOGIN_PASSWORDFILE`

Tham số khởi tạo này quy định mức độ cho phép sử dụng Password File để xác thực các kết nối quản trị từ xa qua mạng:

| Giá trị | Ý nghĩa |
| :--- | :--- |
| **`EXCLUSIVE`**<br>*(Mặc định & Khuyến nghị)* | Password File được sử dụng độc quyền cho **duy nhất một Database Instance**. Cho phép thêm, sửa, xóa user và đổi mật khẩu quản trị trực tiếp trong database. |
| **`SHARED`** | Password File có thể được dùng chung bởi nhiều Database Instances trên cùng máy chủ (hoặc các node trong cụm RAC). Ở chế độ này, file ở dạng **Read-Only**: không thể đổi mật khẩu `SYS` và không thể gán quyền quản trị cho user mới. |
| **`NONE`** | **Vô hiệu hóa hoàn toàn Password File**. Tuyệt đối không cho phép bất kỳ ai kết nối bằng quyền quản trị từ xa qua mạng. Mọi thao tác quản trị bắt buộc phải thực hiện tại chỗ trên máy chủ thông qua OS Authentication. |

```sql
-- Kiểm tra giá trị hiện tại:
SHOW PARAMETER REMOTE_LOGIN_PASSWORDFILE;

-- Thay đổi sang EXCLUSIVE (yêu cầu restart DB vì đây là static parameter):
ALTER SYSTEM SET REMOTE_LOGIN_PASSWORDFILE = EXCLUSIVE SCOPE=SPFILE;
```

---

## 5. Tra cứu và Quản trị người dùng trong Password File

### 5.1. Tra cứu thông tin file và người dùng
```sql
-- Xem đường dẫn chính xác của password file mà instance đang nạp:
SELECT FILE_NAME, FORMAT FROM V$PASSWORDFILE_INFO;

-- Xem danh sách tất cả các user đang có mật khẩu trong password file:
COL USERNAME FORMAT A20
SELECT USERNAME, SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM, ACCOUNT_STATUS
FROM V$PWFILE_USERS;
```

### 5.2. Thêm và Xóa user khỏi Password File
Khi tham số `REMOTE_LOGIN_PASSWORDFILE = EXCLUSIVE`, bạn chỉ cần thực hiện lệnh `GRANT` hoặc `REVOKE` đặc quyền quản trị, Oracle sẽ **tự động cập nhật vào Password File**:
```sql
-- Cấp quyền SYSDBA cho user HR:
GRANT SYSDBA TO hr;
-- Ngay lập tức HR sẽ xuất hiện trong view V$PWFILE_USERS!

-- Đổi mật khẩu của user quản trị:
ALTER USER hr IDENTIFIED BY "NewHrPass##123";
-- Mật khẩu mới tự động đồng bộ sang password file!

-- Thu hồi quyền:
REVOKE SYSDBA FROM hr;
-- HR tự động bị xóa khỏi password file!
```

---

## 6. Quy trình Cứu hộ khi bị Mất hoặc Hỏng Password File

Nếu vô tình xóa nhầm hoặc file `orapworadb` bị hỏng đĩa, các kết nối từ xa của DBA bằng `AS SYSDBA` sẽ bị lỗi `ORA-01031` hoặc `ORA-01017`.

**Quy trình khôi phục và đồng bộ lại:**
1. **Bước 1:** Đăng nhập trực tiếp trên máy chủ bằng OS Authentication:
   ```bash
   sqlplus / as sysdba
   ```
2. **Bước 2:** Tra cứu danh sách các user quản trị hiện có trong hệ thống:
   ```sql
   SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS 
   WHERE PRIVILEGE IN ('SYSDBA', 'SYSOPER', 'SYSBACKUP');
   ```
3. **Bước 3:** Tạo lại Password File mới bằng lệnh `orapwd`:
   ```bash
   orapwd FILE=$ORACLE_HOME/dbs/orapworadb PASSWORD=MasterSysPass##1 FORCE=y
   ```
4. **Bước 4:** Đồng bộ lại các user quản trị khác bằng cách `REVOKE` rồi `GRANT` lại:
   ```sql
   REVOKE SYSBACKUP FROM backup_user;
   GRANT SYSBACKUP TO backup_user;
   ```
5. **Bước 5:** Kiểm tra lại view `V$PWFILE_USERS` để đảm bảo danh sách đã đầy đủ.

---

## Câu hỏi ôn tập

**1. Trong trường hợp nào thì bắt buộc phải có Password File, không thể dùng xác thực Database Authentication hay OS Authentication thông thường?**
> **Trả lời:**
> Bắt buộc phải có Password File khi người quản trị kết nối **từ xa qua mạng** (Remote Connection - thông qua TNS Listener mạng) để thực hiện các thao tác quản trị cấp cao (`STARTUP`, `SHUTDOWN`, `RECOVER`) trong lúc **Database đang tắt hoặc chưa mở**. Khi đó Data Dictionary chưa đọc được và OS Authentication cục bộ không thể truyền qua kết nối TCP/IP không tin cậy.

**2. Tên file và thư mục mặc định của Password File trên Linux cho database có SID là `oradb` là gì?**
> **Trả lời:**
> Đường dẫn và tên file mặc định là:
> **`$ORACLE_HOME/dbs/orapworadb`**
> (Gồm tiền tố cố định `orapw` ghép nối liền với giá trị của biến môi trường `$ORACLE_SID`).

**3. Sự khác nhau giữa giá trị `EXCLUSIVE` và `NONE` của tham số `REMOTE_LOGIN_PASSWORDFILE` là gì?**
> **Trả lời:**
> - `EXCLUSIVE`: Cho phép sử dụng Password File dành riêng cho database này, cho phép DBA kết nối quản trị từ xa qua mạng, và cho phép tự động thêm/sửa mật khẩu của các user quản trị trong file.
> - `NONE`: Vô hiệu hóa hoàn toàn Password File. Mọi nỗ lực kết nối từ xa bằng quyền quản trị (`AS SYSDBA`) qua mạng đều bị từ chối thẳng thừng. Mọi tác vụ quản trị bắt buộc phải vào trực tiếp server để chạy qua OS Authentication.

**4. Tại sao khi chạy lệnh `orapwd`, nếu bạn gõ `FILE = orapw` (có khoảng trắng quanh dấu `=`) thì lệnh sẽ báo lỗi?**
> **Trả lời:**
> Tiện ích dòng lệnh `orapwd` của Oracle sử dụng bộ phân tích cú pháp nghiêm ngặt (Strict Parameter Parser). Cú pháp bắt buộc của nó yêu cầu định dạng `KEYWORD=VALUE` liền nhau không chứa bất kỳ ký tự khoảng trắng (space) nào quanh dấu bằng, nếu có khoảng trắng nó sẽ coi đó là các đối số không hợp lệ và báo lỗi cú pháp.

**5. View nào trong Oracle Database dùng để kiểm tra danh sách tất cả các tài khoản hiện đang được lưu trong Password File?**
> **Trả lời:**
> Đó là Dynamic Performance View **`V$PWFILE_USERS`**.
> View này hiển thị rõ tên tài khoản (`USERNAME`), các cột cờ đánh dấu quyền hạn (`SYSDBA`, `SYSOPER`, `SYSBACKUP`, `SYSDG`, `SYSKM`, `SYSRAC`) và trạng thái tài khoản (`ACCOUNT_STATUS`).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/58-password-file-authentication.md`
