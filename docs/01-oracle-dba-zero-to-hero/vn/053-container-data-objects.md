---
title: 'Bài 53: Truy vấn Container Data Objects'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/53-container-data-objects.md
---

# Bài 53: Truy vấn Container Data Objects

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu Container Data Objects là gì
- Thiết lập thuộc tính `CONTAINER_DATA` cho Common User
- Truy vấn thông tin về `CONTAINER_DATA` trong môi trường Multitenant
- Xóa thuộc tính `CONTAINER_DATA` cho user

---

## 1. Container Data Objects là gì?

**Container Data Objects** là các **tables hoặc views** chứa dữ liệu thuộc nhiều containers khác nhau trong CDB.

### Ví dụ điển hình

| View | Loại | Dữ liệu từ |
|------|------|-----------|
| `V$SESSION` | Dynamic Performance View (V$) | Tất cả PDBs |
| `CDB_USERS` | CDB_ view | Tất cả PDBs |
| `DBA_HIST_*` | AWR history views | Tất cả PDBs |

### Nhận biết Container Data Objects

Các Container Data Objects có cột **`CON_ID`** để xác định container của mỗi row:

| `CON_ID` | Container tương ứng |
|---------|-------------------|
| `0` | Toàn bộ CDB (dữ liệu không thuộc container cụ thể) |
| `1` | Root container (CDB$ROOT) |
| `2` | Seed PDB (PDB$SEED) |
| `3+` | User-created PDBs, Application Roots, Application Seeds |

```sql
-- Tìm tất cả views là Container Data Objects
SELECT VIEW_NAME FROM CDB_VIEWS WHERE CONTAINER_DATA = 'Y';

-- Tìm tất cả tables là Container Data Objects
SELECT TABLE_NAME FROM CDB_TABLES WHERE CONTAINER_DATA = 'YES';
```

---

## 2. Hành vi mặc định khi truy vấn Container Data Objects

**Mặc định**, khi một Common User truy vấn Container Data Object:
- Chỉ thấy dữ liệu của **container hiện tại** (container đang kết nối)
- Muốn xem dữ liệu của PDB khác → phải kết nối trực tiếp vào PDB đó

```sql
-- C##USER1 kết nối Root, chỉ thấy dữ liệu Root
conn C##USER1/pass@CDB1
SELECT USERNAME, CON_ID FROM CDB_USERS;
-- Chỉ thấy users của Root (CON_ID=1)

-- Muốn xem users của PDB1 → phải đổi container
ALTER SESSION SET CONTAINER = PDB1;
SELECT USERNAME, CON_ID FROM CDB_USERS;
-- Bây giờ thấy users của PDB1
```

---

## 3. Thiết lập CONTAINER_DATA cho Common User

Để Common User có thể thấy dữ liệu từ **nhiều containers cùng lúc** mà không cần chuyển container, cần thiết lập thuộc tính `CONTAINER_DATA`.

### 3.1 Cho phép xem tất cả PDBs

```sql
-- Cấp quyền xem dữ liệu TẤT CẢ containers
ALTER USER C##USER1 SET CONTAINER_DATA = ALL CONTAINER=CURRENT;

-- Kiểm tra: bây giờ khi kết nối Root, thấy dữ liệu từ tất cả PDBs
conn C##USER1/pass@CDB1
SELECT USERNAME, CON_ID FROM CDB_USERS WHERE ORACLE_MAINTAINED='N';
-- Thấy cả users của Root, PDB1, PDB2...
```

### 3.2 Cho phép xem chỉ một số PDBs cụ thể

```sql
-- Chỉ được xem Root và PDB1 (Root phải luôn được bao gồm)
ALTER USER C##USER1 SET CONTAINER_DATA = (CDB$ROOT, PDB1)
CONTAINER=CURRENT;
```

### 3.3 Quay về hành vi mặc định

```sql
ALTER USER C##USER1 SET CONTAINER_DATA = DEFAULT CONTAINER=CURRENT;
```

> **Lưu ý**: `CONTAINER=CURRENT` trong lệnh `ALTER USER` chỉ định đây là thao tác thực hiện trong container hiện tại (Root). Đây là cú pháp bắt buộc.

---

## 4. Thêm và Xóa PDB khỏi CONTAINER_DATA Attributes

```sql
-- Thêm PDB3 vào danh sách containers C##USER1 được xem
ALTER USER C##USER1 ADD CONTAINER_DATA = (PDB3) CONTAINER=CURRENT;

-- Xóa PDB3 khỏi danh sách
ALTER USER C##USER1 REMOVE CONTAINER_DATA = (PDB3) CONTAINER=CURRENT;

-- CẢNH BÁO: SET overwrites toàn bộ danh sách cũ!
-- Lệnh này THAY THẾ tất cả settings hiện tại bằng danh sách mới
ALTER USER C##USER1 SET CONTAINER_DATA = (CDB$ROOT, PDB1, PDB2)
CONTAINER=CURRENT;
```

---

## 5. Thiết lập CONTAINER_DATA cho Object cụ thể

Thay vì cấp quyền xem toàn bộ, có thể giới hạn chỉ cho phép xem **một object cụ thể** từ một số containers:

```sql
-- C##USER2 chỉ được xem V$SESSION từ Root và PDB1
ALTER USER C##USER2
  SET CONTAINER_DATA = (CDB$ROOT, PDB1)
  FOR sys.V_$SESSION
  CONTAINER=CURRENT;
```

### Kết quả sau khi thiết lập

```sql
conn C##USER2/pass@CDB1

-- Truy vấn qua sys.V_$SESSION: thấy cả Root và PDB1
SELECT USERNAME, CON_ID FROM sys.V_$SESSION;
-- USERNAME   CON_ID
-- -------    ------
-- SYS             0
-- C##USER2        1    (Root)
-- SYS             3    (PDB1)

-- Truy vấn qua synonym V$SESSION: tương tự
SELECT USERNAME, CON_ID FROM V$SESSION;
```

---

## 6. Xem thông tin CONTAINER_DATA đã thiết lập

```sql
SELECT USERNAME, DEFAULT_ATTR, OWNER, OBJECT_NAME,
       ALL_CONTAINERS, CONTAINER_NAME
FROM CDB_CONTAINER_DATA
ORDER BY USERNAME, OBJECT_NAME;
```

**Ví dụ kết quả:**

```
USERNAME   DEFAULT OWNER  OBJECT_NAME    ALL  CONTAINER_NAME
--------   ------- -----  -----------    ---  --------------
C##USER2   N       SYS    V_$SESSION     N    CDB$ROOT
C##USER2   N       SYS    V_$SESSION     N    PDB1
SYS        Y                             Y
SYSTEM     Y                             Y
```

| Cột | Ý nghĩa |
|-----|---------|
| `DEFAULT_ATTR` | `Y` = dùng default behavior, `N` = có thiết lập cụ thể |
| `ALL_CONTAINERS` | `Y` = có thể xem tất cả containers |
| `OBJECT_NAME` | Nếu có → thiết lập cho object cụ thể đó |
| `CONTAINER_NAME` | Container được phép xem |

---

## 7. Xóa CONTAINER_DATA Attributes

### Xóa tất cả PDB-level attributes (không xóa object-level)

```sql
ALTER USER C##USER2 SET CONTAINER_DATA = DEFAULT CONTAINER=CURRENT;
-- Xóa tất cả PDB-level settings, quay về default behavior
-- Nhưng KHÔNG xóa object-level settings (ví dụ: FOR V_$SESSION)
```

### Xóa object-level attributes

```sql
-- Xóa setting cho object V_$SESSION cụ thể
ALTER USER C##USER2 SET CONTAINER_DATA = DEFAULT
  FOR V_$SESSION
  CONTAINER=CURRENT;
```

---

## Tổng kết

| Lệnh | Mục đích |
|------|---------|
| `SET CONTAINER_DATA=ALL` | Cho phép xem tất cả containers |
| `SET CONTAINER_DATA=(CDB$ROOT,PDB1)` | Chỉ xem Root và PDB1 |
| `ADD CONTAINER_DATA=(PDB3)` | Thêm PDB3 vào danh sách |
| `REMOVE CONTAINER_DATA=(PDB3)` | Xóa PDB3 khỏi danh sách |
| `SET CONTAINER_DATA=DEFAULT` | Quay về hành vi mặc định |
| `SET CONTAINER_DATA=(...) FOR obj` | Áp dụng cho object cụ thể |
| `CDB_CONTAINER_DATA` | Xem tất cả settings đã thiết lập |

> **Lưu ý quan trọng**: Root (`CDB$ROOT`) **phải luôn** được bao gồm trong danh sách khi thiết lập `CONTAINER_DATA` cho một số containers cụ thể. Không thể loại trừ Root khỏi danh sách.

---

## Câu hỏi ôn tập

**Câu 1**: Container Data Objects là gì? Đặc điểm nhận dạng chính của chúng là gì?

> **Trả lời**: Container Data Objects là các **tables hoặc views** trong Oracle CDB chứa dữ liệu từ **nhiều containers khác nhau** (Root, PDBs). Đặc điểm nhận dạng: chúng có cột **`CON_ID`** cho biết dữ liệu thuộc container nào. Ví dụ: `V$SESSION`, `CDB_USERS`, `DBA_HIST_*` views.

**Câu 2**: Mặc định, khi Common User `C##ADMIN` kết nối Root và truy vấn `CDB_USERS`, nó thấy gì?

> **Trả lời**: **Chỉ thấy dữ liệu của Root container** (CON_ID=1). Đây là hành vi mặc định — Common User chỉ thấy dữ liệu của container mình đang kết nối. Để thấy dữ liệu của PDB khác, phải `ALTER SESSION SET CONTAINER=PDB1` hoặc thiết lập `CONTAINER_DATA`.

**Câu 3**: Lệnh nào cho phép `C##USER1` thấy dữ liệu từ tất cả PDBs khi kết nối Root?

> **Trả lời**:
> ```sql
> ALTER USER C##USER1 SET CONTAINER_DATA = ALL CONTAINER=CURRENT;
> ```

**Câu 4**: Sự khác biệt giữa `SET CONTAINER_DATA` và `ADD CONTAINER_DATA` là gì?

> **Trả lời**:
> - `SET CONTAINER_DATA = (list)`: **Thay thế hoàn toàn** danh sách containers hiện tại bằng danh sách mới. Mọi settings cũ bị ghi đè.
> - `ADD CONTAINER_DATA = (PDB3)`: **Thêm** PDB3 vào danh sách hiện tại, giữ nguyên các containers đã có.

**Câu 5**: Tại sao Root (`CDB$ROOT`) phải luôn được bao gồm khi thiết lập `CONTAINER_DATA` cho một số containers cụ thể?

> **Trả lời**: Root là nơi Common User kết nối và thực hiện truy vấn. Nếu loại trừ Root, user sẽ không thể truy vấn dữ liệu của container nào — kể cả Root — vì họ đang đứng trong Root. Oracle bắt buộc Root phải có trong danh sách để đảm bảo user luôn có thể thấy ít nhất dữ liệu của container mình đang kết nối.

**Câu 6**: View nào dùng để xem tất cả `CONTAINER_DATA` attributes đã được thiết lập cho các users trong CDB?

> **Trả lời**: View `CDB_CONTAINER_DATA`:
> ```sql
> SELECT USERNAME, DEFAULT_ATTR, OWNER, OBJECT_NAME, ALL_CONTAINERS, CONTAINER_NAME
> FROM CDB_CONTAINER_DATA
> ORDER BY USERNAME, OBJECT_NAME;
> ```


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/53-container-data-objects.md`
