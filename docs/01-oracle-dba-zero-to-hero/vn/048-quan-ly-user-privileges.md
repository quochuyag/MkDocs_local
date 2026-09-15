---
title: 'Bài 48: Quản lý User Privileges (Quyền người dùng)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/48-quan-ly-user-privileges.md
---

# Bài 48: Quản lý User Privileges (Quyền người dùng)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Phân biệt System Privileges và Object Privileges
- Quản lý System Privileges (GRANT / REVOKE)
- Quản lý Object Privileges (GRANT / REVOKE)
- Hiểu hiệu ứng cascade khi thu hồi quyền

---

## 1. Tổng quan về Privileges

Oracle có **3 loại quyền** chính:

| Loại | Mô tả | Ví dụ |
|------|-------|-------|
| **System Privilege** | Cho phép thực hiện hành động nhất định **trong database** | CREATE TABLE, CREATE SESSION, DROP ANY TABLE |
| **Object Privilege** | Cho phép thực hiện hành động nhất định **trên một object cụ thể** | SELECT on HR.EMPLOYEES, INSERT on HR.DEPARTMENTS |
| **Administrative Privilege** | Dành cho quản trị đặc biệt | SYSDBA, SYSOPER, SYSBACKUP |

---

## 2. System Privileges

### 2.1 Một số System Privileges phổ biến

| System Privilege | Mô tả |
|----------------|-------|
| `CREATE SESSION` | Cho phép đăng nhập vào database |
| `CREATE TABLE` | Tạo bảng trong schema của mình |
| `CREATE ANY TABLE` | Tạo bảng trong schema của **bất kỳ user nào** |
| `ALTER ANY TABLE` | Alter bảng của bất kỳ user nào |
| `DROP ANY TABLE` | Xóa bảng của bất kỳ user nào |
| `CREATE PROCEDURE` | Tạo procedure/function/package |
| `GRANT ANY PRIVILEGE` | Cấp bất kỳ system privilege nào |

```sql
-- Xem danh sách tất cả System Privileges
SELECT PRIVILEGE, NAME FROM SYSTEM_PRIVILEGE_MAP ORDER BY NAME;
```

### 2.2 Ai có thể GRANT/REVOKE System Privileges?

- User có **`GRANT ANY PRIVILEGE`** system privilege
- User được cấp quyền cụ thể đó kèm **`WITH ADMIN OPTION`**

### 2.3 Cú pháp GRANT System Privilege

```sql
GRANT <system_privilege>
TO <grantee>
[WITH ADMIN OPTION]
[CONTAINER = CURRENT | ALL];
```

**Ví dụ thực tế:**

```sql
-- Cấp quyền tối thiểu cho application user
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW,
      ALTER SESSION, CREATE SEQUENCE, CREATE SYNONYM,
      CREATE DATABASE LINK TO app_user;

-- Cấp quyền cho replication tool
GRANT CREATE ANY PROCEDURE TO ogg;
GRANT SELECT ANY TABLE TO ogg;

-- Cấp ALL PRIVILEGES (dùng cẩn thận!)
GRANT ALL PRIVILEGES TO dba_user;
```

> **Lưu ý `GRANT ALL PRIVILEGES`**: Cấp tất cả system privileges **ngoại trừ**: `SELECT ANY DICTIONARY`, `ALTER DATABASE LINK`, `ALTER PUBLIC DATABASE LINK`, và `ADMINISTER KEY MANAGEMENT`. **Tránh dùng trong production** — hãy dùng Roles thay thế.

### 2.4 GRANT kết hợp tạo/đổi mật khẩu user

Từ Oracle 12c, có thể kết hợp GRANT và tạo/đổi password:

```sql
-- Nếu user chưa tồn tại → tự động tạo
-- Nếu đã tồn tại → đổi mật khẩu
GRANT ALL PRIVILEGES TO scott IDENTIFIED BY "ABcd##1234";
```

### 2.5 REVOKE System Privilege

```sql
REVOKE <system_privilege> FROM <grantee> [CONTAINER = CURRENT | ALL];

-- Ví dụ
REVOKE CREATE DATABASE LINK, CREATE TABLE FROM hr;
```

> **Hiệu lực ngay lập tức**: Revoke có hiệu lực ngay, kể cả với session đang hoạt động.

---

## 3. WITH ADMIN OPTION và Cascading Effects

### 3.1 WITH ADMIN OPTION

Khi cấp system privilege kèm `WITH ADMIN OPTION`, grantee có thể **tiếp tục cấp** quyền đó cho người khác:

```sql
-- DBA cấp cho Zak kèm ADMIN OPTION
GRANT CREATE TABLE TO zak WITH ADMIN OPTION;

-- Zak có thể cấp tiếp cho Emily
GRANT CREATE TABLE TO emily;  -- Zak có thể làm điều này
```

### 3.2 Không có Cascading khi REVOKE System Privilege

```
DBA ──GRANT CREATE TABLE WITH ADMIN OPTION──► Zak
                                               │
                                               └──GRANT CREATE TABLE──► Emily

DBA ──REVOKE CREATE TABLE FROM Zak──► Zak mất quyền
                                       Emily VẪN GIỮ quyền! (không cascade)
```

> **Quan trọng**: Thu hồi System Privilege từ Zak **KHÔNG** tự động thu hồi từ Emily (dù Emily được cấp bởi Zak). Đây là **sự khác biệt cơ bản** với Object Privilege.

---

## 4. Object Privileges

### 4.1 Object Privileges là gì?

Quyền thực hiện hành động cụ thể trên một **object cụ thể** (bảng, view, procedure...):

| Object Type | Object Privileges có sẵn |
|------------|------------------------|
| Table / View | SELECT, INSERT, UPDATE, DELETE, ALTER, INDEX, REFERENCES, READ |
| Sequence | SELECT, ALTER |
| Procedure/Function | EXECUTE |
| Directory | READ, WRITE |

> **Lưu ý**: Một số object **không có** object privilege: Indexes, Triggers, Database Links.

### 4.2 Ai có thể GRANT/REVOKE Object Privileges?

- **Owner** của object
- User có **`GRANT ANY OBJECT PRIVILEGE`** system privilege
- User được cấp privilege với **`WITH GRANT OPTION`**

### 4.3 Cú pháp GRANT/REVOKE Object Privilege

```sql
-- GRANT Object Privilege
GRANT <object_priv> ON <object> TO <grantee>
[WITH GRANT OPTION]
[CONTAINER = CURRENT | ALL];

-- REVOKE Object Privilege
REVOKE <object_priv> ON <object> FROM <grantee>
[CASCADE CONSTRAINTS]
[CONTAINER = CURRENT | ALL];
```

**Ví dụ:**

```sql
-- Cấp nhiều quyền trên bảng EMPLOYEES
GRANT SELECT, INSERT, UPDATE, DELETE ON HR.EMPLOYEES TO scott;

-- Chỉ cấp quyền UPDATE trên một số cột
GRANT UPDATE (FIRST_NAME, LAST_NAME) ON HR.EMPLOYEES TO scott;

-- Cấp tất cả object privileges
GRANT ALL ON HR.EMPLOYEES TO scott;

-- Revoke một số quyền
REVOKE DELETE, INDEX ON HR.EMPLOYEES FROM scott;

-- Revoke tất cả
REVOKE ALL ON HR.EMPLOYEES FROM scott;
```

---

## 5. Phân biệt READ và SELECT

Từ Oracle 12c, có hai quyền để **đọc dữ liệu**:

| Quyền | Chỉ SELECT | LOCK TABLE EXCLUSIVE | SELECT FOR UPDATE |
|-------|-----------|---------------------|-----------------|
| `READ` | ✅ | ❌ | ❌ |
| `SELECT` | ✅ | ✅ | ✅ |

```sql
-- Chỉ cho phép đọc (không lock)
GRANT READ ON HR.EMPLOYEES TO scott;

-- Cho phép đọc + lock
GRANT SELECT ON HR.EMPLOYEES TO scott;
```

> **Best Practice**: Dùng `READ` cho report users/BI tools — họ chỉ cần đọc dữ liệu, không cần lock.

---

## 6. SQL92_SECURITY và UPDATE/DELETE

Từ Oracle 12.2, khi tham số `SQL92_SECURITY = TRUE` (mặc định):

- Cấp **chỉ UPDATE hoặc chỉ DELETE** là **không đủ** — grantee vẫn không thể thực hiện
- Phải cấp thêm **SELECT** hoặc **READ**:

```sql
-- Không đủ (grantee không thể UPDATE):
GRANT UPDATE ON HR.EMPLOYEES TO scott;

-- Vẫn không đủ (READ không cho phép SELECT FOR UPDATE):
GRANT READ, UPDATE ON HR.EMPLOYEES TO scott;

-- Đúng (SELECT + UPDATE):
GRANT SELECT, UPDATE ON HR.EMPLOYEES TO scott;
```

---

## 7. WITH GRANT OPTION và Cascading Effects

### 7.1 WITH GRANT OPTION

```sql
-- Owner cấp cho Zak kèm GRANT OPTION
GRANT SELECT ON HR.EMPLOYEES TO zak WITH GRANT OPTION;

-- Zak có thể cấp tiếp cho Emily
GRANT SELECT ON HR.EMPLOYEES TO emily;
```

### 7.2 Cascading REVOKE — KHÁC với System Privilege!

```
HR ──GRANT SELECT WITH GRANT OPTION──► Zak
                                        │
                                        └──GRANT SELECT──► Emily

HR ──REVOKE SELECT FROM Zak──► Zak mất quyền
                                Emily CŨNG mất quyền! (cascade!)
```

> **Quan trọng**: Thu hồi Object Privilege **CÓ CASCADING EFFECT** — khi Zak mất quyền, Emily tự động mất theo!

### So sánh Cascading Effect

| Loại Privilege | REVOKE từ user gốc | Cascade đến user nhận lại? |
|--------------|-------------------|--------------------------|
| **System Privilege** | Zak mất | Emily **GIỮ** quyền |
| **Object Privilege** | Zak mất | Emily **MẤT** quyền (cascade) |

---

## 8. Views tra cứu Privileges

| View | Mô tả |
|------|-------|
| `DBA_SYS_PRIVS` | System privileges được cấp cho users và roles |
| `USER_SYS_PRIVS` | System privileges của user hiện tại |
| `DBA_TAB_PRIVS` | Tất cả object grants trong database |
| `USER_TAB_PRIVS` | Object grants có liên quan đến user hiện tại (owner, grantor, hoặc grantee) |
| `USER_TAB_PRIVS_MADE` | Object grants **đã cấp** bởi user hiện tại |
| `USER_TAB_PRIVS_RECD` | Object grants **được nhận** bởi user hiện tại |

```sql
-- Xem system privileges của HR
SELECT PRIVILEGE, ADMIN_OPTION FROM DBA_SYS_PRIVS WHERE GRANTEE = 'HR';

-- Xem object privileges trên bảng EMPLOYEES
SELECT GRANTEE, PRIVILEGE, GRANTABLE FROM DBA_TAB_PRIVS
WHERE TABLE_NAME = 'EMPLOYEES' AND OWNER = 'HR';
```

---

## Tổng kết

| Khái niệm | Điểm chính |
|-----------|-----------|
| System Privilege | Hành động trên database (CREATE TABLE, ALTER SESSION...) |
| Object Privilege | Hành động trên object cụ thể (SELECT table, EXECUTE procedure) |
| WITH ADMIN OPTION | Cho phép grantee cấp tiếp system privilege |
| WITH GRANT OPTION | Cho phép grantee cấp tiếp object privilege |
| Revoke System Priv | Không cascade (Emily giữ quyền) |
| Revoke Object Priv | **Có cascade** (Emily mất quyền) |
| SQL92_SECURITY | UPDATE/DELETE cần thêm SELECT privilege |
| READ vs SELECT | READ: chỉ đọc. SELECT: đọc + có thể lock |

---

## Câu hỏi ôn tập

**Câu 1**: Sự khác biệt cơ bản giữa **System Privilege** và **Object Privilege** là gì?

> **Trả lời**:
> - **System Privilege**: Quyền thực hiện hành động **trong database** (không giới hạn vào object cụ thể). Ví dụ: `CREATE TABLE` cho phép tạo bảng trong schema của mình.
> - **Object Privilege**: Quyền thực hiện hành động **trên một object cụ thể**. Ví dụ: `SELECT ON HR.EMPLOYEES` chỉ cho phép SELECT từ bảng EMPLOYEES của schema HR.

**Câu 2**: User A được cấp `CREATE TABLE WITH ADMIN OPTION` và tiếp tục cấp `CREATE TABLE` cho User B. Sau đó DBA thu hồi `CREATE TABLE` từ User A. User B còn giữ quyền không?

> **Trả lời**: **Có**, User B **vẫn giữ** quyền `CREATE TABLE`. Với **System Privilege**, thu hồi **không có cascading effect** — thu hồi từ User A không ảnh hưởng đến User B (dù B được cấp bởi A).

**Câu 3**: User A được cấp `SELECT ON HR.EMPLOYEES WITH GRANT OPTION` và cấp tiếp cho User B. Sau đó HR thu hồi từ User A. User B còn quyền không?

> **Trả lời**: **Không**, User B **mất quyền**. Với **Object Privilege**, thu hồi **có cascading effect** — khi User A mất quyền `SELECT ON HR.EMPLOYEES`, User B (được cấp bởi A) cũng tự động mất theo.

**Câu 4**: Câu lệnh nào cấp quyền SELECT và UPDATE trên bảng HR.EMPLOYEES cho user Scott, đồng thời cho phép Scott tiếp tục cấp các quyền này cho người khác?

> **Trả lời**:
> ```sql
> GRANT SELECT, UPDATE ON HR.EMPLOYEES TO scott WITH GRANT OPTION;
> ```

**Câu 5**: Tại sao câu lệnh sau không đủ để cho phép Scott UPDATE bảng EMPLOYEES (Oracle 12.2+)?
> ```sql
> GRANT UPDATE ON HR.EMPLOYEES TO scott;
> ```

> **Trả lời**: Từ Oracle 12.2, khi `SQL92_SECURITY = TRUE` (mặc định), để thực hiện UPDATE, grantee cần **cả quyền UPDATE lẫn SELECT** trên bảng. Chỉ cấp UPDATE là không đủ. Cần:
> ```sql
> GRANT SELECT, UPDATE ON HR.EMPLOYEES TO scott;
> ```

**Câu 6**: Dùng view nào để xem tất cả object privileges mà user HR đã cấp cho người khác?

> **Trả lời**: Dùng `USER_TAB_PRIVS_MADE` (khi đang kết nối là HR):
> ```sql
> SELECT GRANTEE, TABLE_NAME, PRIVILEGE, GRANTABLE
> FROM USER_TAB_PRIVS_MADE;
> ```
> Hoặc dùng `DBA_TAB_PRIVS` (khi kết nối với tài khoản DBA):
> ```sql
> SELECT GRANTEE, TABLE_NAME, PRIVILEGE FROM DBA_TAB_PRIVS WHERE GRANTOR = 'HR';
> ```


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/48-quan-ly-user-privileges.md`
