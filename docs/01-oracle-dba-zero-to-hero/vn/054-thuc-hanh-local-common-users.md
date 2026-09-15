---
title: 'Bài 54: Thực hành - Quản lý Local và Common Users trong CDB'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/54-thuc-hanh-local-common-users.md
---

# Bài 54: Thực hành - Quản lý Local và Common Users trong CDB

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ kiểm chứng các nguyên tắc quản lý người dùng và vai trò (Users & Roles) trong mô hình Multitenant (CDB & PDB):
- Quản lý Common Users ở Root và các PDB.
- Quản lý Local Users trong phạm vi từng PDB cụ thể.
- Quản lý Common Roles và Local Roles.
- Cấp quyền (Privileges) theo phạm vi Common (`CONTAINER=ALL`) hoặc Local (`CONTAINER=CURRENT`).
- Giới hạn quyền xem dữ liệu PDB của Common User (`CONTAINER_DATA`).

---

## Điều kiện tiên quyết
- Máy ảo `srv1` chạy Oracle Linux 7, đã khởi động database ở chế độ **CDB** (Container Database).

---

## Phần 1: Quản lý Common Users

### Bước 1–3: Kiểm tra CDB và tạo thêm PDB2
```bash
# Đăng nhập máy chủ srv1 bằng tài khoản oracle qua SSH/Putty
sqlplus / as sysdba
```

```sql
-- Kiểm tra xem database hiện tại có phải là CDB không
SELECT CDB FROM V$DATABASE;
-- Kết quả: YES

-- Tạo PDB mới tên PDB2 từ seed container (PDB$SEED)
CREATE PLUGGABLE DATABASE PDB2
  ADMIN USER pdb2admin IDENTIFIED BY ABcd##1234
  STORAGE (MAXSIZE 2G);

-- Mở PDB2 ở chế độ READ WRITE
ALTER PLUGGABLE DATABASE PDB2 OPEN;
```

### Bước 4: Xem danh sách Common Users hiện có
```sql
SET PAGESIZE 80
COL USERNAME FORMAT A30
SELECT DISTINCT USERNAME, ORACLE_MAINTAINED
FROM CDB_USERS 
WHERE COMMON = 'YES'
ORDER BY 1;
```
> **Quan sát:** Trong database mới tạo, toàn bộ common users đều có `ORACLE_MAINTAINED = 'Y'` (do Oracle tự tạo và quản lý như `SYS`, `SYSTEM`, `AUDSYS`...).

### Bước 5–6: Tạo Common User và cấp quyền Common
```sql
-- Tạo Common User C##USER1 (tiền tố C## là bắt buộc khi ở Root)
CREATE USER C##USER1 IDENTIFIED BY ABcd##1234 CONTAINER=ALL;

-- Cấp quyền CREATE SESSION trên phạm vi toàn bộ CDB
GRANT CREATE SESSION TO C##USER1 CONTAINER=ALL;

-- Kiểm tra kết nối vào Root Container
CONNECT C##USER1/ABcd##1234
SHOW CON_NAME; -- Kết quả: CDB$ROOT

-- Kiểm tra kết nối xuyên sang PDB2 bằng Easy Connect
CONNECT C##USER1/ABcd##1234@//srv1/pdb2.localdomain
SHOW CON_NAME; -- Kết quả: PDB2
```
> **Kết luận:** Common User được cấp quyền `CONTAINER=ALL` có thể kết nối vào cả Root lẫn bất kỳ PDB nào trong hệ thống.

### Bước 7: Thử tạo Local User tại Root Container (Thất bại)
```sql
CONNECT / as sysdba
CREATE USER LUSER1 IDENTIFIED BY ABcd##1234 CONTAINER=CURRENT;
```
> ❌ **Lỗi:** `ORA-65096: invalid common user or role name` hoặc `ORA-65049`. Bạn **không thể tạo Local User trong Root Container** (`CDB$ROOT`).

### Bước 8–10: Cấp quyền Local cho Common User
```sql
-- Tạo common user C##USER2
CREATE USER C##USER2 IDENTIFIED BY ABcd##1234 CONTAINER=ALL;

-- Cấp quyền CREATE SESSION nhưng chỉ ở mức LOCAL (mặc định CONTAINER=CURRENT tại Root)
GRANT CREATE SESSION TO C##USER2;

-- Thử kết nối sang PDB2
CONNECT C##USER2/ABcd##1234@//srv1/pdb2.localdomain
-- ❌ Lỗi ORA-01045: user C##USER2 lacks CREATE SESSION privilege (vì quyền chỉ cấp tại Root!)

-- Kết nối vào Root
CONNECT C##USER2/ABcd##1234@//srv1/oradb.localdomain
-- ✅ Thành công!

-- Dọn dẹp C##USER2
CONNECT / as sysdba
DROP USER C##USER2;
```

---

## Phần 2: Quản lý Local Users

### Bước 11–12: Tạo Local User trong PDB2
```sql
CONNECT / as sysdba
ALTER SESSION SET CONTAINER = PDB2;

-- Tạo local user LUSER2
CREATE USER LUSER2 IDENTIFIED BY ABcd##1234;
GRANT CREATE SESSION TO LUSER2;

-- Kiểm tra danh sách local users
COL PDB_NAME FORMAT A10
SELECT U.USERNAME, P.PDB_NAME
FROM CDB_USERS U, CDB_PDBS P
WHERE U.CON_ID = P.CON_ID AND U.COMMON = 'NO'
ORDER BY 2, 1;
```

### Bước 13: Thử tạo Common User từ trong PDB (Thất bại)
```sql
-- Đang ở session PDB2:
CREATE USER C##USER2 IDENTIFIED BY ABcd##1234 CONTAINER=ALL;
```
> ❌ **Lỗi:** `ORA-65050: Common DDL statements are not allowed in a pluggable database`. Common User chỉ có thể được tạo khi đang đứng ở `CDB$ROOT`.

### Bước 14: Thử kết nối Local User sang container khác
```sql
-- LUSER2 kết nối PDB2: THÀNH CÔNG
CONNECT LUSER2/ABcd##1234@//srv1/pdb2.localdomain

-- LUSER2 kết nối PDB1 hoặc Root: THẤT BẠI
CONNECT LUSER2/ABcd##1234@//srv1/oradb.localdomain
-- ❌ Lỗi: ORA-01017 (user không hề tồn tại ở Root hay PDB khác).
```

---

## Phần 3: Quản lý Common Roles và Local Roles

### Bước 15–18: Tạo Common Role và Local Role
```sql
-- 1. Tạo Common Role tại Root
CONNECT / as sysdba
CREATE ROLE C##ROLE1 CONTAINER=ALL;

-- 2. Tạo Local Role tại PDB2
ALTER SESSION SET CONTAINER = PDB2;
CREATE ROLE LROLE_PDB2;

-- Kiểm tra danh sách roles
COL ROLE FORMAT A20
SELECT ROLE, COMMON, CON_ID FROM CDB_ROLES 
WHERE ROLE IN ('C##ROLE1', 'LROLE_PDB2');
```

### Bước 19–25: Gán Role Common và Local
```sql
-- Gán Common Role cho Common User trên phạm vi toàn bộ CDB
CONNECT / as sysdba
GRANT C##ROLE1 TO C##USER1 CONTAINER=ALL;

-- Kiểm tra session roles khi C##USER1 đăng nhập vào Root và PDB2
CONNECT C##USER1/ABcd##1234
SELECT * FROM SESSION_ROLES; -- Có C##ROLE1

CONNECT C##USER1/ABcd##1234@//srv1/pdb2.localdomain
SELECT * FROM SESSION_ROLES; -- Có C##ROLE1

-- Gán Common Role C##ROLE1 cho Local User LUSER2 trong PDB2 (Chỉ có hiệu lực Local)
CONNECT SYSTEM/ABcd##1234@//srv1/pdb2.localdomain
GRANT C##ROLE1 TO LUSER2;

CONNECT LUSER2/ABcd##1234@//srv1/pdb2.localdomain
SELECT * FROM SESSION_ROLES; -- LUSER2 có C##ROLE1 trong PDB2
```

---

## Phần 4: Cấp Privileges theo dạng Common hoặc Local

```sql
CONNECT SYSTEM/ABcd##1234

-- Cấp quyền CREATE TABLE và UNLIMITED TABLESPACE cho C##USER1 trên tất cả PDB
GRANT CREATE TABLE, UNLIMITED TABLESPACE TO C##USER1 CONTAINER=ALL;

-- Cấp quyền CREATE SEQUENCE cho C##USER1 CHỈ TRONG ROOT
GRANT CREATE SEQUENCE TO C##USER1 CONTAINER=CURRENT;

-- Xem chi tiết trong CDB_SYS_PRIVS
SELECT GRANTEE, PRIVILEGE, COMMON, CON_ID
FROM CDB_SYS_PRIVS
WHERE GRANTEE = 'C##USER1'
ORDER BY 1, 2;
```
> **Nguyên tắc vàng:** Bản thân Privilege không có khái niệm "Common" hay "Local". Thuộc tính Common/Local phụ thuộc vào **mệnh đề `CONTAINER=ALL` hay `CONTAINER=CURRENT`** khi thực hiện lệnh `GRANT`.

---

## Phần 5: Dọn dẹp môi trường thực hành

```sql
CONNECT / as sysdba
DROP USER C##USER1 CASCADE;
ALTER SESSION SET CONTAINER = PDB2;
DROP USER LUSER2 CASCADE;
DROP ROLE LROLE_PDB2;

CONNECT / as sysdba
DROP ROLE C##ROLE1;
ALTER PLUGGABLE DATABASE PDB2 CLOSE;
DROP PLUGGABLE DATABASE PDB2 INCLUDING DATAFILES;
```

---

## Câu hỏi ôn tập

**1. Nếu một Common User được tạo ở Root nhưng chỉ được gán `GRANT CREATE SESSION TO c##user1;` (không có CONTAINER=ALL), user này có thể đăng nhập vào PDB1 được không?**
> **Trả lời:**
> **Không thể đăng nhập vào PDB1.** Khi không chỉ định `CONTAINER=ALL`, lệnh `GRANT` mặc định có giá trị `CONTAINER=CURRENT`. Do lệnh được chạy ở Root, quyền `CREATE SESSION` chỉ có hiệu lực cục bộ trong Root container (`CDB$ROOT`). Khi cố kết nối vào PDB1, hệ thống sẽ báo lỗi `ORA-01045: user lacks CREATE SESSION privilege`.

**2. Tại sao câu lệnh `CREATE USER LUSER1 IDENTIFIED BY pass;` lại báo lỗi khi chạy tại `CDB$ROOT`?**
> **Trả lời:**
> Vì trong Root Container (`CDB$ROOT`), Oracle **nghiêm cấm tạo Local User**. Mọi user được tạo ở Root bắt buộc phải là Common User và phải có tên bắt đầu bằng tiền tố quy định trong tham số `COMMON_USER_PREFIX` (mặc định là `C##` hoặc `c##`).

**3. Local User trong PDB1 có thể được cấp một Common Role (như `C##ROLE1`) không? Phạm vi hiệu lực của role đó ra sao?**
> **Trả lời:**
> **Được phép.** Common Role có thể được cấp cho cả Common User lẫn Local User. Tuy nhiên, khi cấp cho Local User trong PDB1, quyền hạn của Common Role đó **chỉ có hiệu lực cục bộ duy nhất bên trong PDB1**. Local User không thể dùng role đó ở bất kỳ nơi nào khác ngoài PDB1.

**4. Lệnh `REVOKE C##ROLE1 FROM C##USER1 CONTAINER=ALL;` có thu hồi luôn quyền được gán ở mức `CONTAINER=CURRENT` không?**
> **Trả lời:**
> **Không.** Thu hồi quyền ở mức Common (`CONTAINER=ALL`) chỉ gỡ bỏ liên kết quyền hạn chung trên toàn cụm. Nếu trước đó user đã từng được cấp thêm quyền đó ở mức Local (`CONTAINER=CURRENT`), quyền Local đó vẫn tồn tại trong từ điển dữ liệu của container tương ứng và phải được thu hồi riêng bằng lệnh `REVOKE ... CONTAINER=CURRENT`.

**5. Điểm khác biệt giữa `CDB_SYS_PRIVS` và `DBA_SYS_PRIVS` khi quản lý quyền hạn của người dùng trong CDB là gì?**
> **Trả lời:**
> - `DBA_SYS_PRIVS`: Chỉ hiển thị các đặc quyền hệ thống có hiệu lực bên trong container hiện tại mà session đang kết nối. Cột `COMMON` cho biết quyền đó được thừa hưởng từ lệnh grant cấp Common (`YES`) hay Local (`NO`).
> - `CDB_SYS_PRIVS`: Hiển thị đặc quyền trên toàn bộ các containers của cả CDB, có thêm cột `CON_ID` để định danh chính xác quyền đó được cấp ở container nào.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/54-thuc-hanh-local-common-users.md`
