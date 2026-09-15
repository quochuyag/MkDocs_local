---
title: 'Bài 51: Thực hành - Quản lý Users và User Security'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/51-thuc-hanh-quan-ly-users-security.md
---

# Bài 51: Thực hành - Quản lý Users và User Security

## Mục tiêu thực hành
Thực hành các nhiệm vụ phổ biến khi quản lý database users và bảo mật:
- Tạo users, roles và gán privileges
- Dùng Synonyms để truy cập objects của schema khác
- Kiểm tra sự khác biệt giữa SELECT và READ privileges
- Kiểm tra Schema-Only Accounts
- Kiểm tra Password-Protected Roles
- Quản lý Tablespace Quotas
- Quản lý User Profiles và Password Settings

---

## Điều kiện tiên quyết
Máy ảo `srv1` được restore từ snapshot **non-CDB** database.

---

## Phần 1: Tạo Users, Roles và Gán Privileges

### Bước 1–6: Khởi động và xác nhận non-CDB database

```bash
# Putty vào srv1 với user oracle
sqlplus / as sysdba
SELECT CDB FROM V$DATABASE;
-- Kết quả mong đợi: NO (non-CDB)
```

### Bước 7: Kết nối với SYS

```sql
conn / as sysdba
```

### Bước 8: Tạo 2 user accounts

```sql
-- HR_OFFICER: đọc và cập nhật dữ liệu HR
CREATE USER HR_OFFICER IDENTIFIED BY ABcd##1234 DEFAULT TABLESPACE USERS;

-- HR_REPORTER: chỉ đọc dữ liệu HR (không sửa)
CREATE USER HR_REPORTER IDENTIFIED BY ABcd##1234 DEFAULT TABLESPACE USERS;
```

### Bước 9: Tạo 2 roles tương ứng

```sql
CREATE ROLE HR_OFFICER_ROLE;
CREATE ROLE HR_REPORTER_ROLE;
```

### Bước 10: Xác nhận roles được tạo

```sql
col ROLE for a18
SELECT ROLE, PASSWORD_REQUIRED, AUTHENTICATION_TYPE
FROM DBA_ROLES
WHERE ROLE IN ('HR_OFFICER_ROLE', 'HR_REPORTER_ROLE');
```

### Bước 11: Gán privileges vào roles

```sql
-- HR_OFFICER_ROLE: system privileges + object privileges (SELECT/INSERT/UPDATE)
GRANT CREATE SESSION, CREATE SYNONYM TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.REGIONS     TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.COUNTRIES   TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.LOCATIONS   TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.DEPARTMENTS TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.JOBS        TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.EMPLOYEES   TO HR_OFFICER_ROLE;
GRANT SELECT, INSERT, UPDATE ON HR.JOB_HISTORY TO HR_OFFICER_ROLE;

-- HR_REPORTER_ROLE: chỉ có READ (không SELECT để không thể lock rows)
GRANT CREATE SESSION, CREATE SYNONYM TO HR_REPORTER_ROLE;
GRANT READ ON HR.REGIONS     TO HR_REPORTER_ROLE;
GRANT READ ON HR.COUNTRIES   TO HR_REPORTER_ROLE;
GRANT READ ON HR.LOCATIONS   TO HR_REPORTER_ROLE;
GRANT READ ON HR.DEPARTMENTS TO HR_REPORTER_ROLE;
GRANT READ ON HR.JOBS        TO HR_REPORTER_ROLE;
GRANT READ ON HR.EMPLOYEES   TO HR_REPORTER_ROLE;
GRANT READ ON HR.JOB_HISTORY TO HR_REPORTER_ROLE;
```

### Bước 12: Xác nhận privileges đã gán

```sql
col GRANTEE for a20
SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS
WHERE GRANTEE IN ('HR_OFFICER_ROLE', 'HR_REPORTER_ROLE') ORDER BY 1,2;

SELECT GRANTEE, PRIVILEGE FROM DBA_TAB_PRIVS
WHERE GRANTEE IN ('HR_OFFICER_ROLE', 'HR_REPORTER_ROLE') ORDER BY 1,2;
```

### Bước 13: Gán roles cho users

```sql
GRANT HR_OFFICER_ROLE TO HR_OFFICER;
GRANT HR_REPORTER_ROLE TO HR_REPORTER;
```

### Bước 14: Xác nhận roles được gán

```sql
col GRANTED_ROLE for a20
SELECT GRANTEE, GRANTED_ROLE FROM DBA_ROLE_PRIVS
WHERE GRANTEE IN ('HR_OFFICER', 'HR_REPORTER') ORDER BY 1,2;
```

### Bước 15: Kiểm tra HR_OFFICER có thể truy cập HR tables

```sql
conn HR_OFFICER/ABcd##1234
SELECT COUNT(*) FROM HR.EMPLOYEES;
-- Kết quả mong đợi: trả về số lượng employees
```

---

## Phần 2: Dùng Synonyms để truy cập Objects

Truy cập qua `HR.EMPLOYEES` mỗi lần bất tiện. Dùng **Synonyms** để gọi trực tiếp tên bảng.

### Bước 16: Tạo synonyms cho HR_OFFICER và HR_REPORTER

```sql
-- HR_OFFICER tạo synonyms
conn HR_OFFICER/ABcd##1234
CREATE SYNONYM REGIONS     FOR HR.REGIONS;
CREATE SYNONYM COUNTRIES   FOR HR.COUNTRIES;
CREATE SYNONYM LOCATIONS   FOR HR.LOCATIONS;
CREATE SYNONYM DEPARTMENTS FOR HR.DEPARTMENTS;
CREATE SYNONYM JOBS        FOR HR.JOBS;
CREATE SYNONYM EMPLOYEES   FOR HR.EMPLOYEES;
CREATE SYNONYM JOB_HISTORY FOR HR.JOB_HISTORY;

-- HR_REPORTER tạo synonyms
conn HR_REPORTER/ABcd##1234
CREATE SYNONYM REGIONS     FOR HR.REGIONS;
CREATE SYNONYM COUNTRIES   FOR HR.COUNTRIES;
CREATE SYNONYM LOCATIONS   FOR HR.LOCATIONS;
CREATE SYNONYM DEPARTMENTS FOR HR.DEPARTMENTS;
CREATE SYNONYM JOBS        FOR HR.JOBS;
CREATE SYNONYM EMPLOYEES   FOR HR.EMPLOYEES;
CREATE SYNONYM JOB_HISTORY FOR HR.JOB_HISTORY;
```

### Bước 17–20: Kiểm tra quyền truy cập

```sql
-- HR_OFFICER truy cập qua synonym
conn HR_OFFICER/ABcd##1234
SELECT COUNT(*) FROM EMPLOYEES;          -- OK
UPDATE EMPLOYEES SET SALARY=SALARY*1 WHERE EMPLOYEE_ID=100;  -- OK
COMMIT;

-- HR_REPORTER đọc được nhưng không được sửa/xóa
conn HR_REPORTER/ABcd##1234
SELECT COUNT(*) FROM EMPLOYEES;          -- OK
DELETE EMPLOYEES WHERE EMPLOYEE_ID=100;  -- LỖI: insufficient privileges
UPDATE EMPLOYEES SET SALARY=SALARY*1 WHERE EMPLOYEE_ID=100;  -- LỖI
```

---

## Phần 3: Tạo User + Gán Role trong một lệnh

### Bước 21: Tạo user mới và gán role cùng lúc

```sql
conn system/ABcd##1234

-- Tạo HR_REPORTER2 với role trong 1 lệnh
GRANT HR_REPORTER_ROLE TO HR_REPORTER2 IDENTIFIED BY ABcd##1234;
```

> Nếu `HR_REPORTER2` chưa tồn tại → Oracle tự tạo user với password đó. Nếu đã tồn tại → đổi password và gán role.

### Bước 22: Xác nhận HR_REPORTER2 có quyền

```sql
conn HR_REPORTER2/ABcd##1234
SELECT COUNT(*) FROM HR.EMPLOYEES;  -- OK (dùng schema prefix)
```

---

## Phần 4: Khác biệt giữa SELECT và READ Privileges

### Bước 23: HR_REPORTER không thể lock rows (chỉ có READ)

```sql
conn HR_REPORTER/ABcd##1234
SELECT EMPLOYEE_ID FROM EMPLOYEES FOR UPDATE;
-- LỖI: ORA-01031: insufficient privileges
-- READ không cho phép FOR UPDATE (lock rows)!
```

### Bước 24: HR_OFFICER có thể lock rows (có SELECT)

```sql
conn HR_OFFICER/ABcd##1234
SELECT EMPLOYEE_ID FROM EMPLOYEES FOR UPDATE;
-- OK: lock thành công
ROLLBACK;  -- Giải phóng lock
```

> **Tổng kết**: `READ` = chỉ đọc thuần túy. `SELECT` = đọc + khả năng lock rows với `FOR UPDATE` hoặc `LOCK TABLE IN EXCLUSIVE MODE`.

---

## Phần 5: Schema-Only Accounts

### Bước 25–28: Chuyển HR thành Schema-Only Account

```sql
conn / as sysdba

-- Xác nhận HR không có quyền admin
SELECT USERNAME, SYSDBA, SYSOPER FROM V$PWFILE_USERS WHERE USERNAME = 'HR';
-- Kết quả: không có dòng nào (HR không phải admin)

-- Chuyển HR thành schema-only
ALTER USER HR NO AUTHENTICATION;

-- HR không thể đăng nhập nữa
conn hr/ABcd##1234
-- LỖI: ORA-01017: invalid username/password; logon denied

-- Nhưng HR_OFFICER vẫn truy cập được objects của HR
conn HR_OFFICER/ABcd##1234
UPDATE EMPLOYEES SET SALARY=SALARY*1 WHERE EMPLOYEE_ID=100;
COMMIT;
-- OK: schema-only không ảnh hưởng đến privileges đã cấp
```

> **Ý nghĩa**: Schema-only account là best practice cho **application owner schema** — ngăn đăng nhập trực tiếp nhưng objects vẫn hoạt động bình thường.

---

## Phần 6: Password-Protected Roles

### Bước 29: Kiểm tra SQL92_SECURITY

```sql
conn / as sysdba
SHOW PARAMETER SQL92_SECURITY;
-- Giá trị: TRUE → cần SELECT kèm UPDATE/DELETE
```

### Bước 30–34: Tạo và kiểm tra password-protected role

```sql
-- Tạo role với password
CREATE ROLE EMP_UPDATE_R IDENTIFIED BY ABcd##1234;

-- Cấp SELECT + UPDATE (SQL92_SECURITY=TRUE nên cần SELECT)
GRANT SELECT, UPDATE ON HR.EMPLOYEES TO EMP_UPDATE_R;

-- Gán role cho HR_REPORTER nhưng KHÔNG là default role
GRANT EMP_UPDATE_R TO HR_REPORTER;
ALTER USER HR_REPORTER DEFAULT ROLE ALL EXCEPT EMP_UPDATE_R;

-- HR_REPORTER chưa enable role → không thể UPDATE
conn HR_REPORTER/ABcd##1234
UPDATE EMPLOYEES SET SALARY=SALARY*1 WHERE EMPLOYEE_ID=100;
-- LỖI: insufficient privileges (role chưa enable)

-- Enable role với password → bây giờ UPDATE được
SET ROLE EMP_UPDATE_R IDENTIFIED BY ABcd##1234;
UPDATE EMPLOYEES SET SALARY=SALARY*1 WHERE EMPLOYEE_ID=100;
COMMIT;
-- OK!
```

---

## Phần 7: Quản lý Tablespace Quotas

### Bước 36–43: Kiểm tra giới hạn quota

```sql
conn / as sysdba

-- Tạo tablespace 50MB (không autoextend)
CREATE TABLESPACE SAMPLE_TBS DATAFILE
  '/u01/app/oracle/oradata/ORADB/sampletbs.dbf' SIZE 50M AUTOEXTEND OFF;

-- Tạo user với quota 5MB
CREATE USER USER1 IDENTIFIED BY ABcd##1234
  DEFAULT TABLESPACE SAMPLE_TBS
  QUOTA 5M ON SAMPLE_TBS;
GRANT CREATE SESSION, CREATE TABLE TO USER1;

-- Thử INSERT quá quota → lỗi ORA-01536
conn user1/ABcd##1234
CREATE TABLE TEST (PID NUMBER, PNAME VARCHAR2(20));
BEGIN
  FOR I IN 1..1000000 LOOP
    INSERT INTO TEST VALUES (I, DBMS_RANDOM.STRING('x',20));
  END LOOP;
END;
/
-- LỖI: ORA-01536: space quota exceeded for tablespace 'SAMPLE_TBS'

-- DBA tăng quota
conn / as sysdba
ALTER USER USER1 QUOTA UNLIMITED ON SAMPLE_TBS;

-- Chạy lại → lần này thất bại vì tablespace đầy (50M), không phải quota
-- LỖI: ORA-01653: unable to extend table...

-- Resize datafile lên 150M
ALTER DATABASE DATAFILE '/u01/app/oracle/oradata/ORADB/sampletbs.dbf' RESIZE 150M;

-- Thử lại → thành công!
```

---

## Phần 8: Quản lý Password Settings với User Profiles

### Bước 44–53: Test ORA_STIG_PROFILE

```sql
conn / as sysdba

-- Xem các profiles
SELECT DISTINCT PROFILE FROM DBA_PROFILES;

-- So sánh DEFAULT và ORA_STIG_PROFILE
SELECT RESOURCE_NAME, LIMIT FROM DBA_PROFILES
WHERE RESOURCE_TYPE = 'PASSWORD' AND PROFILE = 'DEFAULT';

SELECT RESOURCE_NAME, LIMIT FROM DBA_PROFILES
WHERE RESOURCE_TYPE = 'PASSWORD' AND PROFILE = 'ORA_STIG_PROFILE';

-- Tạo user với ORA_STIG_PROFILE - password ngắn sẽ bị từ chối
CREATE USER USER1 IDENTIFIED BY ABcd##1234 PROFILE ORA_STIG_PROFILE;
-- LỖI: password không đủ độ phức tạp (STIG yêu cầu 15+ ký tự)

-- Tạo với password dài hơn
CREATE USER USER1 IDENTIFIED BY ABcd##012346789 PROFILE ORA_STIG_PROFILE;
GRANT CREATE SESSION TO USER1;

-- Thử đăng nhập sai 3 lần → bị lock ngay! (STIG: FAILED_LOGIN_ATTEMPTS=3)
-- conn user1/wrong (lần 1) → lần 2 → lần 3 → lần 4: ORA-28000: account is locked

-- Mở khóa tài khoản
conn / as sysdba
ALTER USER USER1 ACCOUNT UNLOCK;

-- Đăng nhập với đúng password
conn USER1/ABcd##012346789  -- OK!
```

---

## Dọn dẹp

```sql
conn / as sysdba
DROP USER HR_OFFICER CASCADE;
DROP USER HR_REPORTER CASCADE;
DROP USER HR_REPORTER2 CASCADE;
DROP USER USER1;
DROP ROLE HR_REPORTER_ROLE;
DROP ROLE HR_OFFICER_ROLE;
DROP ROLE EMP_UPDATE_R;
DROP TABLESPACE SAMPLE_TBS INCLUDING CONTENTS AND DATAFILES;
```

---

## Câu hỏi ôn tập

**Câu 1**: Trong thực hành này, tại sao HR_REPORTER được cấp `READ` thay vì `SELECT`?

> **Trả lời**: Vì HR_REPORTER chỉ cần **đọc báo cáo** — không cần lock rows. Quyền `READ` ngăn user thực hiện `SELECT ... FOR UPDATE` (lock rows), giảm rủi ro gây ra lock contention trong database. `SELECT` mới cho phép lock rows.

**Câu 2**: Lệnh `GRANT HR_REPORTER_ROLE TO HR_REPORTER2 IDENTIFIED BY ABcd##1234` có tác dụng gì nếu `HR_REPORTER2` chưa tồn tại?

> **Trả lời**: Oracle sẽ **tự động tạo user `HR_REPORTER2`** với password `ABcd##1234` rồi đồng thời gán role `HR_REPORTER_ROLE`. Đây là cú pháp shorthand kết hợp tạo/đổi password và gán role trong một lệnh.

**Câu 3**: Sau khi chuyển HR thành Schema-Only (`ALTER USER HR NO AUTHENTICATION`), HR_OFFICER có còn truy cập được tables trong schema HR không?

> **Trả lời**: **Có**, HR_OFFICER vẫn truy cập bình thường. Schema-Only chỉ ngăn **đăng nhập trực tiếp** vào account HR — nó không thu hồi bất kỳ privilege nào đã cấp cho các users khác trên objects của HR.

**Câu 4**: Trong bước kiểm tra Password-Protected Role, tại sao phải dùng `GRANT SELECT, UPDATE` thay vì chỉ `GRANT UPDATE`?

> **Trả lời**: Vì tham số `SQL92_SECURITY = TRUE` (mặc định từ Oracle 12.2). Khi bật, quyền `UPDATE` (hoặc `DELETE`) **không có hiệu lực** trừ khi grantee cũng có quyền `SELECT` trên cùng bảng. Phải cấp cả hai: `GRANT SELECT, UPDATE ON HR.EMPLOYEES TO EMP_UPDATE_R`.

**Câu 5**: Sự khác biệt giữa lỗi `ORA-01536` và `ORA-01653` trong phần thực hành quota là gì?

> **Trả lời**:
> - `ORA-01536: space quota exceeded`: User đã dùng hết **quota được cấp** (5M) — vẫn còn không gian trong tablespace. Giải pháp: tăng quota của user.
> - `ORA-01653: unable to extend table`: Tablespace **đã đầy** hoàn toàn — không đủ không gian vật lý. Giải pháp: thêm datafile hoặc resize datafile hiện có.

**Câu 6**: Tại sao tạo user với `ORA_STIG_PROFILE` và password `ABcd##1234` bị lỗi?

> **Trả lời**: `ORA_STIG_PROFILE` dùng `ora12c_stig_verify_function` — hàm kiểm tra yêu cầu mật khẩu **tối thiểu 15 ký tự**. Password `ABcd##1234` chỉ có 10 ký tự → không đủ. Phải dùng password dài hơn như `ABcd##012346789` (15 ký tự).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/51-thuc-hanh-quan-ly-users-security.md`
