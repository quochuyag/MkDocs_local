---
title: 'Bài 49: Quản lý Roles (Vai trò)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/49-quan-ly-roles.md
---

# Bài 49: Quản lý Roles (Vai trò)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu mục đích và lợi ích của Roles
- Liệt kê các Predefined Roles
- Tạo và sử dụng Roles
- Sử dụng Password-Protected Roles
- Hiểu PUBLIC Role
- Xóa Roles
- Truy vấn thông tin về Roles và Privileges
- Áp dụng hướng dẫn sử dụng Roles hiệu quả

---

## 1. Vấn đề khi không dùng Roles

Giả sử có 3 nhân viên HR (Bob, Zak, Emily) cùng cần các quyền:
- SELECT, INSERT, UPDATE ON EMPLOYEES
- SELECT, INSERT, UPDATE ON JOBS
- CREATE SESSION

**Không dùng Roles**: Phải `GRANT` từng quyền riêng lẻ cho từng người → **9 lệnh GRANT**. Khi có nhân viên mới hoặc thay đổi quyền, phải sửa từng người.

**Dùng Roles**: Tạo 1 role `HR_STAFF`, gán đủ quyền vào role, rồi chỉ cần `GRANT HR_STAFF TO Bob, Zak, Emily` → **3 lệnh GRANT**. Thêm quyền mới chỉ cần sửa role, tự động áp dụng cho tất cả.

---

## 2. Role là gì?

**Role** là một **nhóm privileges** có thể được cấp cho users hoặc các roles khác.

### Lợi ích của Roles

| Lợi ích | Mô tả |
|---------|-------|
| **Quản lý dễ dàng hơn** | Gán nhiều quyền cùng lúc qua một lệnh GRANT |
| **Quản lý động** | Thêm/bớt quyền trong role → tự động áp dụng cho tất cả users có role đó |
| **Kiểm soát linh hoạt** | Có thể enable/disable role cho từng session |

### Đặc điểm của Roles

- Tên role phải **unique** trong database — khác tất cả usernames
- Role **không thuộc schema** nào (không có owner)
- Một user có thể được cấp **nhiều roles**
- Roles có thể được cấp cho roles khác (role lồng nhau)

---

## 3. Predefined Roles

Oracle tạo sẵn một số roles khi cài database:

| Role | Privileges bao gồm |
|------|--------------------|
| **CONNECT** | CREATE SESSION |
| **DBA** | Hầu hết system privileges + nhiều roles khác. **Không cấp cho non-DBA!** |
| **RESOURCE** | CREATE CLUSTER, CREATE INDEXTYPE, CREATE OPERATOR, CREATE PROCEDURE, CREATE SEQUENCE, CREATE TABLE, CREATE TRIGGER, CREATE TYPE |
| **SCHEDULER_ADMIN** | CREATE ANY JOB, CREATE EXTERNAL JOB, CREATE JOB, EXECUTE ANY CLASS, EXECUTE ANY PROGRAM, MANAGE SCHEDULER |
| **SELECT_CATALOG_ROLE** | Không có system privilege; hơn 1,700 object privileges trên Data Dictionary |

```sql
-- Xem tất cả predefined roles (do Oracle duy trì)
SELECT ROLE, ORACLE_MAINTAINED
FROM DBA_ROLES
WHERE ORACLE_MAINTAINED = 'Y'
ORDER BY ROLE;
```

> **Lưu ý**: Từ Oracle 12c, role `CONNECT` chỉ còn `CREATE SESSION`. Trong quá khứ nó có nhiều quyền hơn — đừng nhầm với phiên bản cũ!

---

## 4. Tạo và sử dụng Roles

### 4.1 Quy trình 3 bước

```
Bước 1: Tạo Role
Bước 2: Gán Privileges vào Role
Bước 3: Gán Role cho Users
```

### 4.2 Các loại xác thực Role

| Loại | Mô tả |
|------|-------|
| **Non-authorized** | Role có thể dùng ngay, không cần xác thực |
| **Database (Password)** | Phải nhập password để enable role |
| **External** | Xác thực bởi nguồn bên ngoài |
| **OS** | Xác thực bởi hệ điều hành |

### 4.3 Cú pháp tạo Role

```sql
-- Tạo role không cần xác thực (phổ biến nhất)
CREATE ROLE hr_staff_role;

-- Tạo role có password bảo vệ
CREATE ROLE payroll_role IDENTIFIED BY "PayPass##1";
```

### 4.4 Gán Privileges vào Role

```sql
-- Gán system privilege vào role
GRANT CREATE SESSION TO hr_staff_role;
GRANT CREATE SYNONYM TO hr_staff_role;

-- Gán object privilege vào role
GRANT SELECT, INSERT, UPDATE ON HR.EMPLOYEES TO hr_staff_role;
GRANT SELECT, INSERT, UPDATE ON HR.DEPARTMENTS TO hr_staff_role;

-- Gán role khác vào role (role lồng nhau)
GRANT connect TO hr_staff_role;
```

### 4.5 Gán Role cho User

```sql
-- Gán role cho user
GRANT hr_staff_role TO bob;
GRANT hr_staff_role TO zak;
GRANT hr_staff_role TO emily;
```

---

## 5. Quản lý Default Roles của User

**Default Role** là role tự động được **enable** khi user đăng nhập tạo session.

```sql
-- Mặc định: tất cả roles được gán đều là default roles
-- Để thay đổi default roles:

-- Đặt chỉ một số roles là default
ALTER USER scott DEFAULT ROLE hr_staff_role, connect;

-- Đặt tất cả roles NGOẠI TRỪ một số
ALTER USER scott DEFAULT ROLE ALL EXCEPT payroll_role;

-- Không có role nào là default
ALTER USER scott DEFAULT ROLE NONE;
```

> **Lưu ý**: Không thể set default roles trong lệnh `CREATE USER`. Phải tạo user trước, gán role, rồi mới dùng `ALTER USER ... DEFAULT ROLE`.

---

## 6. Password-Protected Roles

Dùng khi muốn đảm bảo role chỉ được enable **từ trong ứng dụng**, không phải từ bất kỳ session nào.

### Quy trình thiết lập

```sql
-- Bước 1: Tạo role với password
CREATE ROLE payroll_role IDENTIFIED BY "PayPass##1";

-- Bước 2: Gán quyền vào role
GRANT SELECT, UPDATE ON HR.PAYROLL TO payroll_role;

-- Bước 3: Gán role cho user nhưng KHÔNG cho nó là default role
GRANT payroll_role TO scott;
ALTER USER scott DEFAULT ROLE ALL EXCEPT payroll_role;
```

### Enable Role trong session

```sql
-- Cách 1: Trong SQL*Plus
SET ROLE payroll_role IDENTIFIED BY "PayPass##1";

-- Cách 2: Trong PL/SQL (ứng dụng dùng cách này)
BEGIN
  DBMS_SESSION.SET_ROLE('payroll_role IDENTIFIED BY "PayPass##1"');
END;
/

-- Tắt role
SET ROLE ALL EXCEPT payroll_role;
-- hoặc
SET ROLE NONE;
```

> **Ứng dụng thực tế**: Ứng dụng payroll tự động gọi `SET ROLE payroll_role IDENTIFIED BY ...` sau khi login, người dùng bình thường không biết password nên không thể tự enable role đó.

---

## 7. PUBLIC Role

**PUBLIC** là role đặc biệt mà **mọi database user** đều tự động có.

- Khi cấp privilege cho PUBLIC → tất cả users đều có quyền đó
- **Không xuất hiện** trong `DBA_ROLES` và `SESSION_ROLES`
- **Không thể DROP** role PUBLIC

```sql
-- Ví dụ: cấp SELECT cho PUBLIC (mọi user đều có thể SELECT)
GRANT SELECT ON HR.PUBLIC_INFO TO PUBLIC;

-- Thu hồi
REVOKE SELECT ON HR.PUBLIC_INFO FROM PUBLIC;
```

> ⚠️ **Cảnh báo**: Cấp privilege cho PUBLIC rất nguy hiểm — tất cả users hiện tại và tương lai đều có quyền đó. Chỉ dùng khi thực sự cần thiết và chắc chắn an toàn.

---

## 8. Xóa Role

```sql
DROP ROLE hr_staff_role;
```

**Điều kiện**:
- Cần có `DROP ANY ROLE` system privilege, hoặc được cấp role đó kèm `ADMIN OPTION`
- Role PUBLIC **không thể DROP**
- Khi DROP user, các role do user đó tạo ra **không bị xóa theo**

---

## 9. Dictionary Views về Roles và Privileges

| View | Mô tả |
|------|-------|
| `DBA_ROLES` | Tất cả roles trong database (không có cột OWNER) |
| `DBA_ROLE_PRIVS` | Roles được cấp cho users và roles khác |
| `ROLE_ROLE_PRIVS` | Roles được cấp cho roles (accessible by current user) |
| `ROLE_SYS_PRIVS` | System privileges được cấp cho roles |
| `ROLE_TAB_PRIVS` | Object privileges được cấp cho roles |
| `SESSION_ROLES` | Roles đang được enable trong session hiện tại |
| `DBA_SYS_PRIVS` | System privileges của users và roles |
| `DBA_TAB_PRIVS` | Object privileges trong database |

```sql
-- Xem roles trong database
SELECT ROLE, PASSWORD_REQUIRED, AUTHENTICATION_TYPE
FROM DBA_ROLES WHERE ORACLE_MAINTAINED = 'N';

-- Xem roles được gán cho user SCOTT
SELECT GRANTED_ROLE, DEFAULT_ROLE, ADMIN_OPTION
FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'SCOTT';

-- Xem system privileges của một role
SELECT PRIVILEGE FROM ROLE_SYS_PRIVS WHERE ROLE = 'HR_STAFF_ROLE';

-- Xem roles đang active trong session hiện tại
SELECT * FROM SESSION_ROLES;
```

---

## 10. Hướng dẫn sử dụng Roles

| Hướng dẫn | Chi tiết |
|-----------|---------|
| **Ưu tiên Roles** | Dùng roles thay vì direct grant — dễ quản lý hơn |
| **Đơn giản hóa** | Cấu trúc phân quyền càng đơn giản càng tốt |
| **Least Privilege** | Chỉ cấp quyền tối thiểu cần thiết để làm việc |
| **Ghi chép** | Tài liệu hóa cấu trúc roles và mục đích từng role |
| **Định kỳ review** | Hệ thống owner cần review quyền định kỳ |
| **Tách DBA và Developer** | DBA role khác với developer role — không dùng DBA role cho developer |
| **Audit policy** | Phải có chính sách audit phù hợp |

---

## Tổng kết

| Lệnh | Mục đích |
|------|---------|
| `CREATE ROLE name` | Tạo role không có xác thực |
| `CREATE ROLE name IDENTIFIED BY pass` | Tạo role với password |
| `GRANT priv TO role` | Cấp privilege vào role |
| `GRANT role TO user` | Cấp role cho user |
| `ALTER USER ... DEFAULT ROLE ...` | Thiết lập default roles |
| `SET ROLE role IDENTIFIED BY pass` | Enable password-protected role |
| `DROP ROLE name` | Xóa role |
| `SESSION_ROLES` | Xem roles đang active |
| `DBA_ROLE_PRIVS` | Xem roles được cấp |

---

## Câu hỏi ôn tập

**Câu 1**: Role khác gì so với việc cấp trực tiếp privilege cho user (direct grant)?

> **Trả lời**: Role là **nhóm privileges** có thể gán cho nhiều users cùng lúc:
> - **Direct grant**: Phải GRANT từng quyền cho từng user → khó quản lý khi nhiều user
> - **Role**: GRANT vào role một lần → gán role cho nhiều users → thay đổi quyền chỉ cần sửa role, tự áp dụng cho tất cả users có role đó
>
> Role còn cho phép **enable/disable linh hoạt** trong session (đặc biệt hữu ích với password-protected roles).

**Câu 2**: Role `CONNECT` hiện tại (Oracle 12c+) bao gồm những privileges gì?

> **Trả lời**: Từ Oracle 12c, role `CONNECT` chỉ còn **duy nhất một privilege**: `CREATE SESSION`. Trong các phiên bản cũ hơn nó có nhiều quyền hơn, nhưng đã bị thu hẹp để tăng bảo mật.

**Câu 3**: Tại sao không thể set default roles trong lệnh `CREATE USER`?

> **Trả lời**: Oracle **không cho phép** set default roles trong `CREATE USER` vì các roles chưa được gán cho user tại thời điểm tạo. Phải thực hiện theo thứ tự:
> 1. `CREATE USER ...`
> 2. `GRANT role TO user`
> 3. `ALTER USER ... DEFAULT ROLE ...`

**Câu 4**: Password-Protected Role được dùng trong trường hợp nào? Cách enable nó trong PL/SQL?

> **Trả lời**: Dùng khi muốn đảm bảo role chỉ được enable **từ ứng dụng**, không thể enable tùy ý từ SQL*Plus. Thiết lập bằng cách:
> 1. `CREATE ROLE payroll_role IDENTIFIED BY "pass"`
> 2. `ALTER USER scott DEFAULT ROLE ALL EXCEPT payroll_role`
>
> Enable trong PL/SQL:
> ```sql
> BEGIN
>   DBMS_SESSION.SET_ROLE('payroll_role IDENTIFIED BY "pass"');
> END;
> /
> ```

**Câu 5**: PUBLIC role là gì? Tại sao cần thận trọng khi cấp privilege cho PUBLIC?

> **Trả lời**: PUBLIC là role đặc biệt mà **mọi database user đều tự động có**. Khi cấp privilege cho PUBLIC, privilege đó áp dụng cho **tất cả users hiện tại và tương lai** — kể cả users được tạo sau này. Điều này tạo ra rủi ro bảo mật lớn nếu cấp nhầm quyền nhạy cảm. Chỉ dùng cho dữ liệu/đối tượng thực sự công khai.

**Câu 6**: View nào dùng để xem các roles đang được **enable** trong session hiện tại?

> **Trả lời**: View `SESSION_ROLES` liệt kê tất cả roles đang active trong session hiện tại:
> ```sql
> SELECT ROLE FROM SESSION_ROLES;
> ```
> Lưu ý: PUBLIC role **không xuất hiện** trong `SESSION_ROLES` dù user luôn có nó.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/49-quan-ly-roles.md`
