---
title: 'Bài 56: Tài khoản và Đặc quyền Quản trị (Administrative Accounts and Privileges)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/56-tai-khoan-va-dac-quyen-quan-tri.md
---

# Bài 56: Tài khoản và Đặc quyền Quản trị (Administrative Accounts and Privileges)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Phân biệt các tài khoản quản trị tích hợp sẵn (`SYS`, `SYSTEM`, `SYSBACKUP`, `SYSDG`, `SYSKM`, `SYSRAC`).
- Phân biệt các đặc quyền quản trị cấp cao (`SYSDBA`, `SYSOPER`, `SYSBACKUP`...).
- Hiểu khái niệm Schema mặc định khi đăng nhập bằng đặc quyền quản trị.
- Hiểu rõ sự khác biệt giữa hai tài khoản quản trị cốt lõi `SYS` và `SYSTEM`.
- Nắm vững nguyên tắc phân tách nhiệm vụ (Role Separation).

---

## 1. Khái niệm Đặc quyền Quản trị (Administrative Privileges)

Trong Oracle, **Administrative Privileges** là những đặc quyền tối thượng cho phép thực hiện các thao tác quản trị vòng đời hệ thống ngay cả khi **Database chưa được mở (chưa OPEN)**, ví dụ như khởi động (`STARTUP`), tắt (`SHUTDOWN`), phục hồi sau sự cố (`RECOVER`).

> ⚠️ **Điểm cốt tử:**
> - Administrative Privileges **không thể gán vào Role** thông thường.
> - Chúng bắt buộc phải được cấp trực tiếp cho User bằng lệnh `GRANT <privilege> TO <user>;`.
> - Khi đăng nhập bằng quyền quản trị, bạn phải chỉ định rõ từ khóa tương ứng:
>   `CONNECT username/password AS SYSDBA;`

---

## 2. Bảng tổng hợp các Đặc quyền Quản trị

| Đặc quyền | Mục đích & Quyền hạn chính | Schema mặc định khi đăng nhập | Nơi lưu mật khẩu |
| :--- | :--- | :---: | :---: |
| **SYSDBA** | Quyền lực tối cao: Mở/tắt DB, tạo/xóa DB, xem và sửa đổi **toàn bộ dữ liệu** của mọi user. | `SYS` | Password File |
| **SYSOPER** | Vận hành hàng ngày: `STARTUP`, `SHUTDOWN`, `ALTER DATABASE MOUNT/OPEN`, Backup/Recovery cơ bản. **Không được xem dữ liệu người dùng**. | `PUBLIC` | Password File |
| **SYSBACKUP** | Chuyên trách sao lưu & khôi phục bằng RMAN. Không có quyền xem dữ liệu bảng người dùng. | `SYSBACKUP` | DB + Password File |
| **SYSDG** | Quản trị Oracle Data Guard (Broker, Switchover, Failover). | `SYSDG` | DB + Password File |
| **SYSKM** | Quản trị mã hóa Transparent Data Encryption (TDE) và Keystore/Wallet. | `SYSKM` | DB + Password File |
| **SYSRAC** | Dành riêng cho Clusterware quản lý cụm Oracle Real Application Clusters (RAC). | `SYSRAC` | DB + Password File |

---

## 3. Khái niệm Schema mặc định khi đăng nhập bằng quyền quản trị

Khi bạn kết nối kèm theo mệnh đề `AS <administrative_privilege>`, Oracle sẽ tự động chuyển ngữ cảnh của phiên làm việc (Session) sang Schema mặc định của đặc quyền đó:

```bash
# Đăng nhập bằng tài khoản C##ADAM với quyền SYSDBA:
sqlplus c##adam/ABcd##1234 as sysdba
SQL> show user;
USER is "SYS"    <--- Chuyển sang schema SYS!

# Đăng nhập bằng tài khoản C##ADAM với quyền SYSOPER:
sqlplus c##adam/ABcd##1234 as sysoper
SQL> show user;
USER is "PUBLIC" <--- Chuyển sang schema PUBLIC!

# Đăng nhập thông thường (không kèm AS):
sqlplus c##adam/ABcd##1234
SQL> show user;
USER is "C##ADAM"
```

---

## 4. So sánh chuyên sâu giữa tài khoản `SYS` và `SYSTEM`

Đây là câu hỏi phỏng vấn kinh điển dành cho mọi ứng viên Oracle DBA:

| Tiêu chí | Tài khoản `SYS` | Tài khoản `SYSTEM` |
| :--- | :--- | :--- |
| **Vai trò** | "Chúa tể" của Database (Superuser). | Quản trị viên đối tượng thông thường. |
| **Sở hữu** | Sở hữu **Data Dictionary** (`SYS.TAB$`, `SYS.OBJ$`), AWR, siêu dữ liệu cốt lõi. | Sở hữu các bảng phục vụ công cụ bổ trợ (`AQ`, `MGMT`). |
| **Đặc quyền** | Tự động có quyền **`SYSDBA`** và mọi quyền kèm `WITH ADMIN OPTION`. | Được gán sẵn role **`DBA`**, nhưng **KHÔNG có quyền `SYSDBA`**. |
| **Khả năng STARTUP / SHUTDOWN** | ✅ Có thể bật và tắt database. | ❌ Không thể bật hoặc tắt database. |
| **Cứu hộ phục hồi (Recovery)** | ✅ Có thể thực hiện phục hồi cơ sở dữ liệu. | ❌ Không thể thực hiện khôi phục DB. |
| **Cách đăng nhập** | Bắt buộc phải có: `AS SYSDBA` (hoặc `AS SYSOPER`). | Đăng nhập bình thường: `CONNECT system/password;`. |
| **Lưu trữ mật khẩu** | Lưu trong **Password File** (để xác thực khi DB tắt). | Lưu trong **Data Dictionary** (bảng `SYS.USER$`). |

---

## 5. Nguyên tắc Phân tách Vai trò (Role Separation)

Trong các tổ chức tài chính, ngân hàng và tiêu chuẩn bảo mật quốc tế (PCI-DSS, ISO 27001):
- **Không được dùng chung tài khoản `SYS`** cho tất cả nhân viên IT.
- Triển khai phân tách quyền rõ ràng:
  - Nhân sự phụ trách Backup chỉ được cấp quyền `SYSBACKUP`.
  - Nhân sự phụ trách hạ tầng DR chỉ được cấp quyền `SYSDG`.
  - Nhân sự an ninh thông tin quản lý khóa mã hóa chỉ được cấp quyền `SYSKM`.
  - DBA vận hành ca trực chỉ cần cấp quyền `SYSOPER` để khởi động lại dịch vụ khi cần mà không lo rò rỉ dữ liệu nhạy cảm.

---

## 6. Tra cứu đặc quyền quản trị trong hệ thống

```sql
-- Xem danh sách các user có quyền quản trị được lưu trong Password File:
SELECT USERNAME, SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM, SYSRAC 
FROM V$PWFILE_USERS;

-- Cấp quyền SYSBACKUP cho một user:
CONNECT / as sysdba
CREATE USER c##backup_admin IDENTIFIED BY "BackupPass##123";
GRANT SYSBACKUP TO c##backup_admin CONTAINER=ALL;

-- Thu hồi quyền:
REVOKE SYSBACKUP FROM c##backup_admin CONTAINER=ALL;
```

---

## Câu hỏi ôn tập

**1. Sự khác biệt lớn nhất về mặt quyền hạn dữ liệu giữa `SYSDBA` và `SYSOPER` là gì?**
> **Trả lời:**
> User kết nối với quyền `SYSDBA` có toàn quyền xem, thêm, sửa, xóa **toàn bộ dữ liệu của tất cả người dùng** trong database (`SELECT ANY TABLE`, đọc mọi schema). Ngược lại, user kết nối với quyền `SYSOPER` chỉ được phép thực hiện các thao tác vận hành máy chủ (STARTUP, SHUTDOWN, MOUNT, ARCHIVE LOG, BACKUP cơ bản) và **hoàn toàn KHÔNG có quyền truy vấn dữ liệu bên trong các bảng của người dùng**.

**2. Tại sao mật khẩu của tài khoản `SYS` bắt buộc phải được lưu trong Password File thay vì chỉ lưu trong Data Dictionary?**
> **Trả lời:**
> Khi cơ sở dữ liệu đang tắt (SHUTDOWN) hoặc đang ở trạng thái `NOMOUNT`, các datafiles chứa Data Dictionary (trong `SYSTEM` tablespace) hoàn toàn chưa được mở ra để đọc. Để DBA có thể đăng nhập vào xác thực và thực hiện lệnh `STARTUP`, Oracle bắt buộc phải có một file mật khẩu độc lập nằm ở tầng hệ điều hành (**Password File**) để kiểm tra danh tính của `SYS` trước khi mở database.

**3. Tài khoản `SYSTEM` có thể thực hiện lệnh `SHUTDOWN IMMEDIATE;` được không? Tại sao?**
> **Trả lời:**
> **Không thể.** Mặc định tài khoản `SYSTEM` chỉ được gán role `DBA`, mà role `DBA` không bao gồm các đặc quyền quản trị instance cấp cao như `STARTUP` hay `SHUTDOWN`. Để tắt được database, tài khoản bắt buộc phải kết nối với quyền `AS SYSDBA` hoặc `AS SYSOPER`.

**4. Khi user `SCOTT` được cấp quyền `SYSDBA` và đăng nhập bằng `CONNECT scott/tiger AS SYSDBA;`, kết quả của lệnh `SHOW USER;` sẽ hiển thị tên user nào?**
> **Trả lời:**
> Lệnh `SHOW USER;` sẽ hiển thị là **`USER is "SYS"`**.
> Bởi vì khi đăng nhập kèm đặc quyền quản trị `AS SYSDBA`, Oracle sẽ tự động chuyển ngữ cảnh schema mặc định của phiên làm việc về schema của `SYS`. Mọi bảng tạo ra mà không có tiền tố schema sẽ mặc định thuộc về `SYS`.

**5. Lợi ích của đặc quyền `SYSBACKUP` được giới thiệu từ Oracle 12c là gì?**
> **Trả lời:**
> Đặc quyền `SYSBACKUP` cho phép triển khai nguyên tắc **Phân tách trách nhiệm (Separation of Duties)**: DBA phụ trách sao lưu dữ liệu có đầy đủ toàn bộ quyền cần thiết để chạy công cụ RMAN (kết nối, backup, restore, purge log) mà **không cần phải cấp quyền `SYSDBA`**, từ đó ngăn chặn nhân viên sao lưu đọc trộm các bảng dữ liệu kinh doanh nhạy cảm (thông tin thẻ ngân hàng, tiền gửi, lương nhân viên).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/56-tai-khoan-va-dac-quyen-quan-tri.md`
