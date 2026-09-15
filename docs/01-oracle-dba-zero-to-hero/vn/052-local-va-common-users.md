---
title: 'Bài 52: Quản lý Local và Common Users trong CDB'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/52-local-va-common-users.md
---

# Bài 52: Quản lý Local và Common Users trong CDB

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Phân biệt Local Users và Common Users trong CDB
- Tạo Common Users và Local Users
- Cấp privileges theo kiểu Common và Local
- Phân biệt Common Roles và Local Roles

---

## 1. Kiến trúc CDB và Users

Trong **Container Database (CDB)**, Oracle có hai loại users hoàn toàn khác nhau:

```
CDB (Root Container: CDB$ROOT)
├── PDB$SEED (Seed PDB)
├── PDB1
│   ├── Local User: pdb1_user1  ← chỉ biết trong PDB1
│   └── Common User: C##ADMIN   ← biết ở MỌI container
├── PDB2
│   ├── Local User: pdb2_user2  ← chỉ biết trong PDB2
│   └── Common User: C##ADMIN   ← cùng user với PDB1
└── Root
    └── Common User: C##ADMIN   ← tạo ở đây
```

---

## 2. Local Users

**Local User** là user được tạo **trong một PDB cụ thể** và chỉ tồn tại trong PDB đó.

### Đặc điểm

| Đặc điểm | Chi tiết |
|---------|---------|
| Nơi tạo | Kết nối đến PDB rồi tạo |
| Phạm vi | Chỉ biết trong PDB được tạo |
| Kết nối | Chỉ kết nối được đến PDB nơi nó được tạo |
| Tạo trong Root | ❌ Không thể |
| Tiền tố bắt buộc | Không bắt buộc (tên tự do) |

### Tạo Local User

```sql
-- Kết nối đến PDB trước
conn system/ABcd##1234@//srv1/pdb1.localdomain

-- Tạo local user (tự động là local vì đang kết nối PDB)
CREATE USER pdb1_app_user IDENTIFIED BY "AppPass##1"
  DEFAULT TABLESPACE users
  [CONTAINER=CURRENT];  -- tùy chọn, mặc định đã là CURRENT
```

### Xem thông tin Local Users

```sql
-- Cột COMMON = 'NO' → là local user
SELECT USERNAME, COMMON, CON_ID
FROM CDB_USERS
WHERE ORACLE_MAINTAINED = 'N';
```

---

## 3. Common Users

**Common User** được tạo trong **Root Container** và **tự động biết** ở tất cả PDBs (hiện tại và tương lai).

### Đặc điểm

| Đặc điểm | Chi tiết |
|---------|---------|
| Nơi tạo | Phải kết nối Root (CDB$ROOT) mới tạo được |
| Phạm vi | Biết ở **tất cả** PDBs và Root |
| Kết nối | Có thể kết nối đến bất kỳ PDB nào (nếu có privilege) |
| Tiền tố | **Bắt buộc** có tiền tố theo `COMMON_USER_PREFIX` (mặc định `C##`) |
| Tham số | `COMMON_USER_PREFIX` (mặc định: `C##`) |

### Tạo Common User

```sql
-- Phải đang kết nối Root
conn / as sysdba  -- hoặc conn sys@cdb1 as sysdba

-- Tạo common user (tiền tố C## bắt buộc)
CREATE USER C##ADMIN IDENTIFIED BY "AdminPass##1"
  [CONTAINER=ALL];  -- tùy chọn, đây là mặc định khi ở Root
```

> **Chú ý**: Dù Common User "biết" ở tất cả PDBs, nó vẫn cần được **cấp privilege để kết nối** vào từng PDB. Chỉ biết ≠ Có quyền.

### Cấp quyền đăng nhập PDB cho Common User

```sql
-- Kết nối Root, cấp CREATE SESSION cục bộ cho PDB1
ALTER SESSION SET CONTAINER = PDB1;
GRANT CREATE SESSION TO C##ADMIN;

-- Hoặc kết nối trực tiếp PDB
CONNECT SYSTEM@pdb1
GRANT CREATE SESSION TO C##ADMIN;
```

---

## 4. Cách cấp Privileges: Local Grant vs Common Grant

### 4.1 Local Grant

Privilege chỉ có hiệu lực trong **một PDB cụ thể**:

```sql
-- Cấp CREATE SESSION chỉ cho PDB1
ALTER SESSION SET CONTAINER = PDB1;
GRANT CREATE SESSION TO pdb1_user1 [CONTAINER=CURRENT];

-- Cách khác: kết nối thẳng vào PDB
CONNECT SYSTEM@pdb1
GRANT CREATE SESSION TO pdb1_user1;

-- Cấp local cho Common User trong PDB1
GRANT CREATE SESSION TO C##ADMIN [CONTAINER=CURRENT];
-- → C##ADMIN chỉ có CREATE SESSION trong PDB1
```

### 4.2 Common Grant

Privilege có hiệu lực **trong tất cả PDBs**:

```sql
-- Phải kết nối Root + grantor phải là Common User
CONNECT SYSTEM@CDB1  -- System là common user trong CDB

GRANT CREATE TABLE TO C##ADMIN CONTAINER=ALL;
-- → C##ADMIN có CREATE TABLE trong TẤT CẢ PDBs
```

### Quy tắc cấp quyền

| Tình huống | Local Grant | Common Grant |
|-----------|------------|-------------|
| Local User → Local User | ✅ | ❌ |
| Common User → Local User (tại PDB) | ✅ | ❌ |
| Common User → Common User | ✅ (chỉ PDB hiện tại) | ✅ (tất cả PDBs) |
| Local User → Common User | ✅ (chỉ PDB hiện tại) | ❌ |

> **Best Practice**: Không pha trộn Local và Common privileges cho cùng một user — tạo nhầm lẫn và khó quản lý.

---

## 5. Common Roles và Local Roles

### Local Role

- Được tạo trong một PDB
- Chỉ dùng được trong PDB đó
- Có thể được tạo bởi bất kỳ user nào có quyền `CREATE ROLE`

```sql
-- Kết nối PDB trước
CONNECT system@pdb1
CREATE ROLE pdb1_app_role [CONTAINER=CURRENT];
```

### Common Role

- Được tạo trong Root
- Biết ở tất cả PDBs
- Chỉ có thể tạo bởi **Common User**
- Phải có tiền tố `C##`

```sql
-- Kết nối Root
CONNECT / as sysdba
CREATE ROLE C##SEC_ADMIN CONTAINER=ALL;
```

### Quan trọng: Common Role được cấp Local

Khi grant một **Common Role** cho user tại một PDB cụ thể → role đó chỉ có hiệu lực **trong PDB đó**:

```sql
-- Grant C##SEC_ADMIN cho user tại PDB1
CONNECT system@pdb1
GRANT C##SEC_ADMIN TO pdb1_user1;
-- → pdb1_user1 có privileges của C##SEC_ADMIN CHỈ trong PDB1
```

---

## 6. Dictionary Views cho CDB

| View | Mô tả | Cột quan trọng |
|------|-------|--------------|
| `CDB_USERS` | Tất cả users trong CDB | `COMMON` (YES=Common, NO=Local) |
| `CDB_ROLES` | Tất cả roles trong CDB | `COMMON` (YES=Common, NO=Local) |
| `CDB_ROLE_PRIVS` | Roles được cấp cho users/roles | `COMMON` (cách grant) |
| `CDB_SYS_PRIVS` | System privileges trong CDB | `COMMON` (cách grant) |
| `CDB_TAB_PRIVS` | Object privileges trong CDB | `COMMON` (cách grant) |

```sql
-- Xem tất cả non-system users với thông tin Common/Local
SELECT USERNAME, COMMON, CON_ID, DEFAULT_TABLESPACE
FROM CDB_USERS
WHERE ORACLE_MAINTAINED = 'N'
ORDER BY CON_ID, USERNAME;

-- Kiểm tra một user là common hay local
SELECT USERNAME, COMMON FROM CDB_USERS WHERE USERNAME = 'C##ADMIN';
-- COMMON = YES → Common User
```

---

## 7. Tham số COMMON_USER_PREFIX

```sql
-- Xem prefix hiện tại (mặc định: C##)
SHOW PARAMETER COMMON_USER_PREFIX;

-- Thay đổi prefix (không khuyến khích)
ALTER SYSTEM SET COMMON_USER_PREFIX = 'APP_';
```

> **Khuyến nghị**: Giữ nguyên giá trị mặc định `C##`. Nếu cần OS authentication, đảm bảo `COMMON_USER_PREFIX` và `OS_AUTHENT_PREFIX` nhất quán với nhau.

---

## 8. Best Practices

| Nguyên tắc | Chi tiết |
|-----------|---------|
| **Common User** | Dành cho **DBA và Administrators** quản lý toàn CDB |
| **Local User** | Dành cho **Application Schemas** trong từng PDB |
| **Không pha trộn** | Không dùng Common Grants và Local Grants lẫn lộn cho cùng user |
| **Tiền tố C##** | Giữ nguyên, không đổi sang prefix khác |
| **External auth** | Nếu dùng OS auth, đảm bảo `COMMON_USER_PREFIX` match `OS_AUTHENT_PREFIX` |

---

## Tổng kết

| Đặc điểm | Local User/Role | Common User/Role |
|---------|----------------|-----------------|
| Nơi tạo | PDB | Root (CDB$ROOT) |
| Phạm vi biết | Chỉ PDB đó | Tất cả containers |
| Tiền tố | Không bắt buộc | `C##` (mặc định) |
| Local Grant | ✅ | ✅ |
| Common Grant | ❌ | ✅ |
| Xem thông tin | `CDB_USERS`, cột `COMMON=NO` | `CDB_USERS`, cột `COMMON=YES` |

---

## Câu hỏi ôn tập

**Câu 1**: Sự khác biệt chính giữa Local User và Common User trong CDB là gì?

> **Trả lời**:
> - **Local User**: Tạo trong một PDB, chỉ biết và chỉ kết nối được **trong PDB đó**. Không có tiền tố bắt buộc.
> - **Common User**: Tạo trong Root, **biết ở tất cả containers** (Root + tất cả PDBs hiện tại và tương lai). Bắt buộc có tiền tố `C##` (mặc định).

**Câu 2**: Lệnh `CREATE USER pdb_user1 IDENTIFIED BY pass` được chạy khi đang kết nối Root. Kết quả là gì?

> **Trả lời**: Lệnh sẽ **thất bại** với lỗi vì tên `pdb_user1` không có tiền tố `C##`. Khi kết nối Root, Oracle chỉ cho phép tạo Common Users (phải có tiền tố `C##`). Để tạo Local User, phải kết nối vào PDB trước.

**Câu 3**: Common User `C##ADMIN` được tạo trong Root. Khi kết nối PDB1, `C##ADMIN` có thể đăng nhập ngay không?

> **Trả lời**: **Không**. Dù `C##ADMIN` "biết" ở PDB1, nó vẫn cần được **cấp `CREATE SESSION`** trong PDB1:
> ```sql
> CONNECT system@pdb1
> GRANT CREATE SESSION TO C##ADMIN;
> ```

**Câu 4**: Sự khác biệt giữa Local Grant và Common Grant?

> **Trả lời**:
> - **Local Grant**: Privilege chỉ có hiệu lực trong **PDB cụ thể** đang kết nối. Cả Common User và Local User đều có thể thực hiện Local Grant.
> - **Common Grant**: Privilege có hiệu lực trong **tất cả PDBs**. Chỉ **Common User** mới có thể thực hiện Common Grant (cần kết nối Root và dùng `CONTAINER=ALL`).

**Câu 5**: Tại sao nên tách biệt Common Users (cho DBA) và Local Users (cho application)?

> **Trả lời**: Tách biệt theo nguyên tắc **Least Privilege**:
> - DBA cần quản lý toàn CDB → dùng Common User để có phạm vi rộng
> - Application chỉ làm việc trong một PDB → dùng Local User, bị giới hạn trong PDB đó, giảm rủi ro nếu tài khoản bị xâm phạm
> - Dễ kiểm soát và audit hơn khi mỗi loại user có mục đích rõ ràng


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/52-local-va-common-users.md`
