---
title: 'Bài 57: Xác thực cấp Hệ điều hành (Using OS Authentication)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/57-os-authentication.md
---

# Bài 57: Xác thực cấp Hệ điều hành (Using OS Authentication)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu cơ chế xác thực cấp Hệ điều hành (**OS Authentication**) trong Oracle Database.
- Nắm vững các nhóm người dùng OS (OS Groups) quản lý các quyền quản trị trên Linux và Windows.
- Cấp quyền quản trị database cho tài khoản hệ điều hành thông qua cơ chế thành viên nhóm (Group Membership).
- Hiểu cách tạo tài khoản người dùng thông thường xác thực qua OS (`IDENTIFIED EXTERNALLY`).
- Nhận thức được các lưu ý bảo mật cốt tử khi triển khai xác thực OS.

---

## 1. Cơ chế Xác thực trong Oracle Database

Khi một người dùng kết nối tới Oracle Database, hệ thống có thể xác thực danh tính qua các phương thức:
1. **Database Authentication:** Xác thực dựa vào Username & Password lưu trong từ điển dữ liệu (Data Dictionary).
2. **OS Authentication:** Hệ điều hành chứng thực danh tính người dùng (đã đăng nhập thành công vào OS), Database tin tưởng hoàn toàn vào OS và cho phép truy cập **không cần nhập mật khẩu**.
3. **Password File Authentication:** Dùng file nhị phân lưu mật khẩu quản trị trên đĩa.
4. **Network / Enterprise Authentication:** Dùng SSL/TLS, Kerberos, Microsoft Active Directory (LDAP/OID).

---

## 2. Xác thực OS dành cho Quản trị viên (Administrative OS Authentication)

Đây là phương thức mà DBA thường xuyên sử dụng nhất:
```bash
# Đăng nhập trực tiếp trên máy chủ Linux mà không cần mật khẩu:
sqlplus / as sysdba
```

### 2.1. Nguyên lý hoạt động
Oracle kiểm tra xem tài khoản người dùng OS đang chạy lệnh `sqlplus` có phải là **thành viên của một nhóm OS đặc biệt** được chỉ định lúc cài đặt Oracle hay không. Nếu thuộc nhóm đó, Oracle cấp quyền quản trị tương ứng ngay lập tức.

### 2.2. Bảng ánh xạ OS Groups trên Linux và Windows

| Đặc quyền | Nhóm OS trên Linux (Mặc định) | Nhóm OS trên Windows | Schema mặc định |
| :--- | :--- | :--- | :---: |
| **SYSDBA** | `dba` | `ORA_DBA` | `SYS` |
| **SYSOPER** | `oper` | `ORA_OPER` | `PUBLIC` |
| **SYSBACKUP** | `backupdba` | `ORA_HOMENAME_SYSBACKUP` | `SYSBACKUP` |
| **SYSDG** | `dgdba` | `ORA_HOMENAME_SYSDG` | `SYSDG` |
| **SYSKM** | `kmdba` | `ORA_HOMENAME_SYSKM` | `SYSKM` |
| **SYSRAC** | `racdba` | `ORA_HOMENAME_SYSRAC` | `SYSRAC` |

### 2.3. Cách cấp quyền quản trị cho một User OS (Linux)
Giả sử bạn muốn cấp quyền `SYSOPER` cho kỹ sư vận hành có tài khoản Linux là `operator1`:

```bash
# Thực hiện bằng tài khoản root:
usermod -aG oper operator1

# Kiểm tra nhóm của user:
id operator1
# Kết quả: uid=1002(operator1) gid=1002(operator1) groups=1002(operator1),1005(oper)
```

Bây giờ `operator1` đăng nhập vào Linux và kết nối:
```bash
su - operator1
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export ORACLE_SID=oradb
export PATH=$PATH:$ORACLE_HOME/bin

sqlplus / as sysoper
# Kết quả: Connected to: Oracle Database 19c...
```
Nếu `operator1` cố gõ `sqlplus / as sysdba`, Oracle sẽ từ chối ngay với lỗi:
`ORA-01031: insufficient privileges` (vì `operator1` không thuộc nhóm `dba`).

---

## 3. Xác thực OS cho Người dùng thông thường (Non-Administrative Users)

Oracle cho phép tạo các tài khoản người dùng bình thường không cần mật khẩu, đăng nhập thông qua xác thực OS.

### 3.1. Tham số `OS_AUTHENT_PREFIX`
- Mặc định tham số này có giá trị là **`OPS$`**.
- Khi một user OS tên là `sam` muốn đăng nhập, Oracle sẽ tìm một database user có tên là:
  `<OS_AUTHENT_PREFIX><OS_USERNAME>` $\rightarrow$ **`OPS$SAM`**.

### 3.2. Quy trình tạo OS User trong Non-CDB
```bash
# 1. Tạo user OS (bằng root)
useradd sam
passwd sam

# 2. Đăng nhập database và tạo user tương ứng
sqlplus / as sysdba
```
```sql
SHOW PARAMETER OS_AUTHENT_PREFIX; -- Mặc định: OPS$

-- Tạo user với mệnh đề IDENTIFIED EXTERNALLY
CREATE USER ops$sam IDENTIFIED EXTERNALLY;
GRANT CREATE SESSION, RESOURCE TO ops$sam;
```

```bash
# 3. Chuyển sang user sam trên OS và đăng nhập database:
su - sam
sqlplus /
# Kết quả: Đăng nhập thành công với user OPS$SAM mà không cần gõ mật khẩu!
```

> ⚠️ **Khuyến cáo thực tế:** Xác thực OS cho người dùng thông thường (`IDENTIFIED EXTERNALLY`) **hầu như không được dùng trong môi trường Production hiện đại** vì khó quản lý tài khoản đồng bộ giữa OS và Database, đồng thời tiềm ẩn nhiều nguy cơ bảo mật nếu máy chủ bị xâm nhập.

---

## 4. Cảnh báo bảo mật tối quan trọng với DBA

1. **Người quản trị OS (Root) chính là Chúa tể:**
   Bất kỳ ai có quyền `root` trên máy chủ Linux đều có thể tự thêm mình vào nhóm `dba` (`usermod -aG dba ...`) hoặc gõ lệnh `su - oracle` để vào database với quyền `SYSDBA` mà không cần biết mật khẩu database!
2. **Ngăn chặn xác thực từ xa:**
   Luôn đảm bảo tham số `REMOTE_OS_AUTHENT = FALSE` để ngăn chặn kẻ tấn công trên mạng giả mạo danh tính tài khoản OS nhằm truy cập vào database.

---

## Câu hỏi ôn tập

**1. Một kỹ sư IT đăng nhập vào máy chủ Linux bằng tài khoản `oracle` và gõ `sqlplus sys/mat_khau_sai as sysdba`. Kết quả kết nối sẽ ra sao? Giải thích.**
> **Trả lời:**
> Kết nối **VẪN THÀNH CÔNG** bình thường!
> Giải thích: Khi bạn chạy SQL*Plus cục bộ trên máy chủ Linux (Local Connection - không thông qua TNS Listener mạng), cơ chế **Xác thực Hệ điều hành (OS Authentication) luôn có độ ưu tiên cao hơn (Supersedes) cơ chế xác thực mật khẩu**. Do user `oracle` trên OS thuộc nhóm `dba`, Oracle lập tức công nhận quyền `SYSDBA` và bỏ qua hoàn toàn chuỗi username/password mà bạn vừa gõ.

**2. Để một tài khoản người dùng trên hệ điều hành Windows có thể đăng nhập vào database bằng quyền `SYSDBA` không cần mật khẩu, tài khoản đó phải là thành viên của nhóm nào?**
> **Trả lời:**
> Tài khoản Windows đó bắt buộc phải được thêm vào nhóm người dùng cục bộ (Local Group) có tên là **`ORA_DBA`** (hoặc nhóm domain tương ứng nếu máy chủ tham gia Windows Domain).

**3. Mệnh đề `IDENTIFIED EXTERNALLY` khi tạo người dùng trong database có ý nghĩa gì?**
> **Trả lời:**
> Mệnh đề này khai báo với Oracle rằng tài khoản này **không lưu mật khẩu trong cơ sở dữ liệu**. Việc xác thực danh tính hoàn toàn được ủy quyền cho một nguồn bên ngoài cơ sở dữ liệu đảm nhiệm — cụ thể ở đây là hệ điều hành máy chủ (OS Authentication), hoặc dịch vụ thư mục mạng bên ngoài.

**4. Tại sao trên hệ thống Linux, người có quyền `root` có thể dễ dàng chiếm đoạt toàn quyền cơ sở dữ liệu Oracle?**
> **Trả lời:**
> Vì tài khoản `root` là tài khoản quản trị tối cao của hệ điều hành. `root` có thể xem/sửa mọi file trên máy chủ, có thể dùng lệnh `su - oracle` để chuyển sang tài khoản chủ sở hữu phần mềm Oracle mà không cần mật khẩu, hoặc dùng lệnh `usermod -aG dba <user>` để đưa bất kỳ ai vào nhóm `dba`. Khi đã ở trong nhóm `dba`, họ chỉ cần gõ `sqlplus / as sysdba` là có toàn quyền trên toàn bộ dữ liệu.

**5. Lệnh nào trong Linux dùng để kiểm tra xem một user OS hiện đang thuộc những nhóm nào?**
> **Trả lời:**
> Sử dụng lệnh **`id <username>`** hoặc lệnh **`groups <username>`**.
> Ví dụ: `id oracle` sẽ hiển thị rõ UID, GID chính (`oinstall`) và danh sách các nhóm phụ (`dba`, `oper`, `backupdba`...).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/57-os-authentication.md`
