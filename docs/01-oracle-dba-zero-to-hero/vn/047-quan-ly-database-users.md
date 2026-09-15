---
title: 'Bài 47: Quản lý Database Users (Người dùng Database)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/47-quan-ly-database-users.md
---

# Bài 47: Quản lý Database Users (Người dùng Database)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Mô tả database users và schemas
- Mô tả các tài khoản được định nghĩa sẵn (predefined accounts)
- Tạo database user với database authentication
- Chuyển đổi user thành schema-only account
- Quản lý tablespace quotas cho users
- Xóa database users

---

## 1. Database User là gì?

Một **database user (account)** đại diện cho:
- Một người (developer, DBA, analyst)
- Một thiết bị (ứng dụng, middleware)
- Một nhóm người dùng

### 1.1 Thuộc tính của mỗi Database User

| Thuộc tính | Mô tả |
|-----------|-------|
| **Username** | Tối đa 30 bytes, không có ký tự đặc biệt, bắt đầu bằng chữ cái |
| **Authentication method** | Cách xác thực (password, OS, network...) |
| **Default tablespace** | Tablespace mặc định để lưu objects |
| **Temporary tablespace** | Tablespace tạm cho sort, hash... |
| **User profile** | Chính sách bảo mật (giới hạn đăng nhập, mật khẩu...) |
| **Consumer group** | Nhóm phân bổ tài nguyên (Resource Manager) |
| **Account status** | `OPEN`, `LOCKED`, `EXPIRED` hoặc kết hợp |

> **Lưu ý**: Trong CDB, application users được tạo trong **PDB**, không phải CDB Root.

---

## 2. Database Schema

**Schema** là tập hợp các database objects thuộc sở hữu của một user:
- Cùng tên với username
- Bao gồm: Tables, Indexes, Views, Synonyms, DB Links, Procedures, Sequences...

```
Ví dụ:
User: HR  →  Schema: HR
                  ├── Tables: EMPLOYEES, DEPARTMENTS...
                  ├── Indexes: EMP_ID_IDX, DEPT_NAME_IDX...
                  ├── Views: EMP_DETAILS_VIEW...
                  └── Procedures: ADD_EMPLOYEE...
```

---

## 3. Phương thức xác thực (Authentication Methods)

| Phương thức | Mô tả |
|------------|-------|
| **Database (Password)** | Xác thực qua username/password lưu trong Data Dictionary |
| **Operating System (OS)** | Oracle ủy thác xác thực cho OS |
| **Password File** | Dành cho users có quyền SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM |
| **Network** | Oracle Internet Directory, Windows Active Directory, SSL, Kerberos, RADIUS, PKI |

---

## 4. Tài khoản được định nghĩa sẵn (Predefined Accounts)

Oracle tạo sẵn một số tài khoản khi cài database:

| Loại | Ví dụ |
|------|-------|
| **Administrative** | SYS, SYSTEM, SYSBACKUP, SYSDG, SYSKM, SYSRAC, SYSMAN, DBSNMP |
| **Sample Schema** | HR (Human Resources), SH (Sales History), OE (Order Entry) |
| **Internal** | Nhiều tài khoản hệ thống nội bộ |

```sql
-- Xem tất cả tài khoản được Oracle duy trì
SELECT USERNAME, ACCOUNT_STATUS, AUTHENTICATION_TYPE
FROM DBA_USERS
WHERE ORACLE_MAINTAINED = 'Y'
ORDER BY USERNAME;
```

> **Lưu ý bảo mật**: Tất cả predefined accounts (trừ SYS và SYSTEM) nên ở trạng thái **LOCKED** trong môi trường production.

---

## 5. Tạo Database User

### 5.1 Cú pháp cơ bản

```sql
CREATE USER <username> IDENTIFIED BY <password>
  [DEFAULT TABLESPACE <tên_tablespace>]
  [TEMPORARY TABLESPACE <tên_temp_tablespace>]
  [PROFILE <tên_profile>]
  [QUOTA <kích_thước> ON <tablespace>]
  [ACCOUNT LOCK | UNLOCK];
```

### 5.2 Ví dụ tạo user

```sql
-- Tạo user cơ bản
CREATE USER app_user IDENTIFIED BY "SecurePass##2024"
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp;

-- Tạo user với nhiều tùy chọn
CREATE USER hr_dev
  IDENTIFIED BY "DevPass##123"
  DEFAULT TABLESPACE hr_data
  TEMPORARY TABLESPACE temp
  QUOTA 500M ON hr_data
  QUOTA 100M ON hr_idx
  PROFILE developer_profile
  ACCOUNT UNLOCK;
```

> **Lưu ý về password**:
> - Mặc định **phân biệt chữ hoa/chữ thường** (case-sensitive)
> - Tối đa 30 bytes
> - Nên đặt trong dấu nháy kép nếu có ký tự đặc biệt

### 5.3 Cấp quyền tối thiểu sau khi tạo user

Sau khi tạo user, cần cấp ít nhất quyền `CREATE SESSION` để user có thể đăng nhập:

```sql
GRANT CREATE SESSION TO app_user;
```

---

## 6. Chỉnh sửa thuộc tính User

```sql
-- Khóa/mở khóa tài khoản
ALTER USER hr ACCOUNT LOCK;
ALTER USER hr ACCOUNT UNLOCK;

-- Đặt lại mật khẩu
ALTER USER hr IDENTIFIED BY "NewPass##123";

-- Thay đổi default tablespace
ALTER USER hr DEFAULT TABLESPACE hr_data2;

-- Thay đổi temporary tablespace
ALTER USER hr TEMPORARY TABLESPACE temp2;

-- Đổi profile
ALTER USER hr PROFILE senior_developer;
```

---

## 7. Schema-Only Accounts

**Schema-Only Account** là một schema **không có password** để đăng nhập trực tiếp. Đây là mô hình bảo mật tốt cho tài khoản owner của ứng dụng:

### 7.1 Tại sao cần Schema-Only?

- Ngăn chặn đăng nhập trực tiếp vào schema owner (giảm rủi ro bảo mật)
- Objects trong schema được quản lý thông qua:
  - User DBA (thay đổi thủ công)
  - Proxy user (kết nối qua một user khác)
  - Tạm thời chuyển lại thành password account khi cần bảo trì

### 7.2 Cú pháp

```sql
-- Tạo schema-only account
CREATE USER app_schema NO AUTHENTICATION
  DEFAULT TABLESPACE app_data;

-- Chuyển user hiện có thành schema-only
ALTER USER hr NO AUTHENTICATION;

-- Kiểm tra: STATUS sẽ là 'NONE'
SELECT USERNAME, AUTHENTICATION_TYPE, ACCOUNT_STATUS
FROM DBA_USERS
WHERE USERNAME = 'APP_SCHEMA';
```

---

## 8. Quản lý Tablespace Quota

**Quota** là lượng không gian tối đa mà một user có thể sử dụng trong một tablespace.

### 8.1 Vấn đề khi không có quota

Nếu user không có quota trong tablespace default, họ **không thể tạo objects** (dù tablespace còn đầy chỗ trống):

```
ORA-1536: space quota exceeded for tablespace 'USERS'
```

### 8.2 Đặt quota khi tạo user

```sql
CREATE USER scott
  IDENTIFIED BY "ScottPass##1"
  DEFAULT TABLESPACE data_ts
  QUOTA 500M ON data_ts
  QUOTA 100M ON index_ts;
```

### 8.3 Thay đổi quota cho user hiện có

```sql
-- Đặt quota cụ thể
ALTER USER scott QUOTA 1000M ON data_ts;

-- Quota không giới hạn trên một tablespace
ALTER USER scott QUOTA UNLIMITED ON data_ts;

-- Cấp quyền UNLIMITED TABLESPACE (tất cả tablespace)
GRANT UNLIMITED TABLESPACE TO scott;
```

> **Lưu ý**: Quyền `UNLIMITED TABLESPACE` là **system privilege**, cho phép user dùng không gian không giới hạn trong **tất cả** tablespace (ngoại trừ TEMP). Không nên cấp tùy tiện.

### 8.4 Xem thông tin quota

```sql
-- Xem quota của tất cả user (cần DBA)
SELECT USERNAME, TABLESPACE_NAME, BYTES/1024/1024 USED_MB,
       DECODE(MAX_BYTES, -1, 'UNLIMITED', MAX_BYTES/1024/1024) MAX_MB
FROM DBA_TS_QUOTAS;

-- Xem quota của user hiện tại
SELECT TABLESPACE_NAME, BYTES/1024/1024 USED_MB,
       DECODE(MAX_BYTES, -1, 'UNLIMITED', MAX_BYTES/1024/1024) MAX_MB
FROM USER_TS_QUOTAS;
```

---

## 9. Xóa Database User

```sql
-- Xóa user (không có objects)
DROP USER scott;

-- Xóa user và tất cả objects của user (CASCADE)
DROP USER scott CASCADE;
```

> **Cảnh báo**:
> - Nếu user còn objects và không dùng CASCADE → Oracle trả lỗi
> - `DROP USER CASCADE` xóa **không thể hoàn tác** tất cả objects của user
> - User đang kết nối không thể bị DROP — phải disconnect trước
> - **Suy nghĩ kỹ trước khi DROP!**

---

## Tổng kết

| Lệnh | Mục đích |
|------|---------|
| `CREATE USER` | Tạo user mới |
| `ALTER USER ... ACCOUNT LOCK/UNLOCK` | Khóa/mở khóa tài khoản |
| `ALTER USER ... IDENTIFIED BY` | Đổi mật khẩu |
| `ALTER USER ... NO AUTHENTICATION` | Chuyển thành Schema-Only |
| `ALTER USER ... QUOTA ... ON` | Đặt quota tablespace |
| `DROP USER [CASCADE]` | Xóa user |
| `DBA_USERS` | Thông tin tất cả users |
| `DBA_TS_QUOTAS` | Thông tin quota tablespace |

---

## Câu hỏi ôn tập

**Câu 1**: Sự khác biệt giữa **Database User** và **Schema** là gì?

> **Trả lời**: **Database User** là tài khoản dùng để đăng nhập vào database, có phương thức xác thực, password, tablespace quota... **Schema** là **tập hợp objects** (tables, indexes, views...) được sở hữu bởi user đó, có cùng tên với username. Một user luôn có một schema tương ứng.

**Câu 2**: Sau khi tạo user mới, user có thể đăng nhập ngay được không? Nếu không, cần làm gì?

> **Trả lời**: **Không**. User mới tạo không có quyền nào cả — kể cả quyền `CREATE SESSION` (quyền đăng nhập). Cần cấp ít nhất:
> ```sql
> GRANT CREATE SESSION TO new_user;
> ```

**Câu 3**: Schema-Only Account là gì và khi nào nên dùng?

> **Trả lời**: Schema-Only Account là tài khoản **không có password để đăng nhập trực tiếp** (khai báo bằng `NO AUTHENTICATION`). Nên dùng cho **tài khoản owner của ứng dụng** — ngăn chặn đăng nhập trực tiếp nhưng vẫn cho phép quản lý objects thông qua DBA hoặc proxy user.

**Câu 4**: Lỗi `ORA-1536: space quota exceeded` xảy ra khi nào? Cách khắc phục?

> **Trả lời**: Lỗi này xảy ra khi user cố tạo/mở rộng object nhưng đã vượt quá quota được cấp trong tablespace đó. Khắc phục bằng cách tăng quota:
> ```sql
> ALTER USER scott QUOTA 2G ON data_ts;
> -- hoặc
> ALTER USER scott QUOTA UNLIMITED ON data_ts;
> ```

**Câu 5**: Tại sao không nên dùng `GRANT UNLIMITED TABLESPACE TO <user>` một cách tùy tiện?

> **Trả lời**: `UNLIMITED TABLESPACE` là **system privilege** cho phép user dùng không gian không giới hạn trong **TẤT CẢ** tablespace. Điều này có thể khiến user (vô tình hoặc cố ý) lấp đầy tablespace quan trọng như SYSTEM, SYSAUX, UNDO... gây ảnh hưởng toàn bộ hệ thống. Tốt hơn nên dùng `QUOTA UNLIMITED ON <specific_tablespace>` để kiểm soát chặt hơn.

**Câu 6**: Câu lệnh nào để xem tất cả tài khoản được Oracle tạo sẵn và duy trì?

> **Trả lời**:
> ```sql
> SELECT USERNAME, ACCOUNT_STATUS FROM DBA_USERS
> WHERE ORACLE_MAINTAINED = 'Y'
> ORDER BY USERNAME;
> ```


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/47-quan-ly-database-users.md`
