---
title: 'Bài 50: Quản lý User Profiles'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/50-quan-ly-user-profiles.md
---

# Bài 50: Quản lý User Profiles

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Mô tả lợi ích của User Profiles
- Mô tả các tham số Password trong User Profiles
- Giải thích vòng đời thay đổi mật khẩu
- Mô tả các tham số Resource Limit trong Profiles
- Tạo và gán User Profiles
- Bật chức năng kiểm tra độ phức tạp mật khẩu
- Truy vấn thông tin về Profiles
- Hiểu Gradual Password Rollover cho ứng dụng

---

## 1. User Profile là gì?

**User Profile** là một tập hợp các **giới hạn tài nguyên và chính sách mật khẩu** gán cho database users.

Mỗi user luôn có một profile — nếu không chỉ định thì dùng profile **DEFAULT**.

### Hai nhóm tham số trong Profile

```
User Profile
├── Password Management Policy
│   ├── Thời hạn mật khẩu (PASSWORD_LIFE_TIME, PASSWORD_GRACE_TIME)
│   ├── Bảo vệ tài khoản (FAILED_LOGIN_ATTEMPTS, PASSWORD_LOCK_TIME)
│   ├── Tái sử dụng mật khẩu (PASSWORD_REUSE_MAX, PASSWORD_REUSE_TIME)
│   ├── Tài khoản không hoạt động (INACTIVE_ACCOUNT_TIME)
│   └── Kiểm tra độ phức tạp (PASSWORD_VERIFY_FUNCTION)
└── Resource Limits
    ├── CPU (CPU_PER_SESSION, CPU_PER_CALL)
    ├── Session (SESSIONS_PER_USER, CONNECT_TIME, IDLE_TIME)
    ├── I/O (LOGICAL_READS_PER_SESSION, LOGICAL_READS_PER_CALL)
    └── Bộ nhớ (PRIVATE_SGA, COMPOSITE_LIMIT)
```

---

## 2. Tham số Password trong Profile

### Bảng tham số Password (DEFAULT profile)

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| `INACTIVE_ACCOUNT_TIME` | UNLIMITED | Số ngày không đăng nhập trước khi tự động **lock** tài khoản |
| `FAILED_LOGIN_ATTEMPTS` | 10 | Số lần đăng nhập sai tối đa trước khi **lock** tài khoản |
| `PASSWORD_LOCK_TIME` | 1 (ngày) | Thời gian bị lock sau khi vượt `FAILED_LOGIN_ATTEMPTS` (có thể dùng phân số: `1/24` = 1 giờ) |
| `PASSWORD_LIFE_TIME` | 180 (ngày) | Thời gian tối đa được dùng một mật khẩu |
| `PASSWORD_GRACE_TIME` | 7 (ngày) | Số ngày gia hạn cảnh báo sau khi mật khẩu hết hạn |
| `PASSWORD_REUSE_MAX` | UNLIMITED | Số lần phải đổi mật khẩu trước khi có thể dùng lại mật khẩu cũ |
| `PASSWORD_REUSE_TIME` | UNLIMITED | Số ngày phải đợi trước khi có thể dùng lại mật khẩu cũ |
| `PASSWORD_VERIFY_FUNCTION` | NULL | Hàm PL/SQL kiểm tra độ phức tạp mật khẩu |

```sql
-- Xem cài đặt của DEFAULT profile
SELECT RESOURCE_NAME, LIMIT
FROM DBA_PROFILES
WHERE PROFILE = 'DEFAULT' AND RESOURCE_TYPE = 'PASSWORD';
```

---

## 3. Vòng đời thay đổi mật khẩu (Password Change Lifecycle)

```
Ngày 0          Ngày 180           Ngày 187         Sau ngày 187
(Đổi pass)    (Hết PASSWORD_LIFE_TIME) (Hết GRACE_TIME)
    │               │                   │                │
    ▼               ▼                   ▼                ▼
  OPEN ──────► EXPIRED(GRACE) ──────► EXPIRED ──────► Bị khoá

Lúc OPEN:       Đăng nhập bình thường, không cảnh báo
Lúc GRACE:      Vẫn đăng nhập được + cảnh báo ORA-28002
Lúc EXPIRED:    BẮT BUỘC đổi mật khẩu (ORA-28001), một số app không tương thích!
Sau EXPIRED:    Tài khoản bị khoá nếu có PASSWORD_LOCK_TIME
```

### Các lỗi thường gặp

| Lỗi | Tình huống |
|-----|-----------|
| `ORA-28002: password will expire in n days` | Đang trong giai đoạn GRACE |
| `ORA-28001: password has expired` | Mật khẩu đã hết hạn hoàn toàn |
| `ORA-28000: account is locked` | Tài khoản bị khóa (quá FAILED_LOGIN_ATTEMPTS) |

> **Lưu ý thực tế**: Một số ứng dụng cũ **không tương thích** với giai đoạn GRACE (không xử lý được yêu cầu đổi mật khẩu). Cần test kỹ hoặc dùng `INACTIVE_ACCOUNT_TIME=UNLIMITED` + quản lý thủ công.

---

## 4. Tham số Resource Limit trong Profile

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| `SESSIONS_PER_USER` | UNLIMITED | Số session đồng thời tối đa của user |
| `CPU_PER_SESSION` | UNLIMITED | Giới hạn CPU cho toàn session (đơn vị: 1/100 giây) |
| `CPU_PER_CALL` | UNLIMITED | Giới hạn CPU cho mỗi call (parse/execute/fetch) |
| `CONNECT_TIME` | UNLIMITED | Thời gian tối đa của một session (phút) |
| `IDLE_TIME` | UNLIMITED | Thời gian idle tối đa trong session (phút) |
| `LOGICAL_READS_PER_SESSION` | UNLIMITED | Số data blocks tối đa đọc trong session |
| `LOGICAL_READS_PER_CALL` | UNLIMITED | Số data blocks tối đa đọc trong mỗi call |
| `PRIVATE_SGA` | UNLIMITED | Không gian SGA riêng tối đa cho session |
| `COMPOSITE_LIMIT` | UNLIMITED | Tổng chi phí tài nguyên (service units) |

> **Thực tế**: Resource limits ít được dùng trong Oracle Database thông thường. Thay vào đó, **Oracle Database Resource Manager** cung cấp kiểm soát tài nguyên tinh tế và linh hoạt hơn.

---

## 5. Tạo và sử dụng Profile

### 5.1 Tạo Profile

```sql
-- Cần có system privilege CREATE PROFILE
CREATE PROFILE emp_prof LIMIT
  -- Password parameters
  FAILED_LOGIN_ATTEMPTS    6
  PASSWORD_LIFE_TIME       60       -- 60 ngày
  PASSWORD_REUSE_TIME      60       -- Không dùng lại trong 60 ngày
  PASSWORD_REUSE_MAX       5        -- Phải đổi 5 lần mới dùng lại
  PASSWORD_LOCK_TIME       1/24     -- Lock 1 giờ (1/24 ngày)
  PASSWORD_GRACE_TIME      10       -- 10 ngày gia hạn
  PASSWORD_VERIFY_FUNCTION DEFAULT  -- Dùng hàm của DEFAULT profile
  -- Resource parameters
  SESSIONS_PER_USER        UNLIMITED
  CPU_PER_SESSION          UNLIMITED
  CONNECT_TIME             50       -- 50 phút tối đa mỗi session
  LOGICAL_READS_PER_SESSION DEFAULT
  COMPOSITE_LIMIT          7500000;
```

### 5.2 Gán Profile cho User

```sql
-- Gán khi tạo user
CREATE USER developer1
  IDENTIFIED BY "DevPass##1"
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA 500K ON users
  PROFILE emp_prof;

-- Gán cho user đã tồn tại
ALTER USER hr PROFILE emp_prof;

-- Kiểm tra profile hiện tại của user
SELECT USERNAME, PROFILE FROM DBA_USERS WHERE USERNAME = 'HR';
```

### 5.3 Sửa đổi Profile

```sql
ALTER PROFILE hr_prof LIMIT
  FAILED_LOGIN_ATTEMPTS  10
  PASSWORD_LOCK_TIME     15/1440   -- Lock 15 phút
  INACTIVE_ACCOUNT_TIME  30;       -- Lock sau 30 ngày không dùng
```

---

## 6. Profile ORA_STIG_PROFILE

Oracle cung cấp profile `ORA_STIG_PROFILE` tuân thủ **Security Technical Implementation Guide (STIG)** — tiêu chuẩn bảo mật của Bộ Quốc phòng Mỹ:

```sql
SELECT RESOURCE_NAME, LIMIT
FROM DBA_PROFILES
WHERE PROFILE = 'ORA_STIG_PROFILE';
```

| Tham số | Giá trị STIG | So với DEFAULT |
|---------|-------------|----------------|
| IDLE_TIME | 15 | Nghiêm ngặt hơn (DEFAULT: UNLIMITED) |
| FAILED_LOGIN_ATTEMPTS | 3 | Nghiêm ngặt hơn (DEFAULT: 10) |
| PASSWORD_LIFE_TIME | 60 | Nghiêm ngặt hơn (DEFAULT: 180) |
| PASSWORD_REUSE_TIME | 365 | Nghiêm ngặt hơn (DEFAULT: UNLIMITED) |
| PASSWORD_LOCK_TIME | UNLIMITED | Khóa vĩnh viễn! |
| PASSWORD_VERIFY_FUNCTION | ORA12C_STIG_VERIFY_FUNCTION | Phức tạp hơn |
| INACTIVE_ACCOUNT_TIME | 35 | Nghiêm ngặt hơn (DEFAULT: UNLIMITED) |

---

## 7. Password Complexity Verification Functions

Oracle cung cấp 4 hàm kiểm tra độ phức tạp mật khẩu, từ thấp đến cao:

| Hàm | Yêu cầu |
|-----|---------|
| `verify_function_11G` | Tương thích Oracle 11g |
| `ora12c_verify_function` | Yêu cầu cơ bản của Oracle 12c |
| `ora12c_strong_verify_function` | Yêu cầu mạnh hơn |
| `ora12c_stig_verify_function` | Nghiêm ngặt nhất (STIG) |

### Yêu cầu của `ora12c_stig_verify_function`
- Tối thiểu **15 ký tự**
- Có ít nhất **1 chữ hoa và 1 chữ thường**
- Có ít nhất **1 chữ số**
- Có ít nhất **1 ký tự đặc biệt**
- Khác mật khẩu cũ ít nhất **8 ký tự**

### Cách bật Password Verification

```sql
-- Bước 1: Tạo các hàm (nếu chưa có)
@$ORACLE_HOME/rdbms/admin/catpvf.sql

-- Bước 2: Cấp quyền EXECUTE cho users
GRANT EXECUTE ON ora12c_strong_verify_function TO PUBLIC;

-- Bước 3: Gán hàm vào profile
ALTER PROFILE default LIMIT
  PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function;
```

> **Lưu ý**: Verification functions áp dụng cho **non-SYS users**. SYS luôn có thể đặt mật khẩu bất kỳ.

---

## 8. Gradual Password Rollover (19.12+)

**Vấn đề**: Khi đổi password của database account dùng bởi ứng dụng → ứng dụng bị lỗi kết nối ngay lập tức → downtime.

**Giải pháp**: `PASSWORD_ROLLOVER_TIME` cho phép cả **password cũ và mới đều hoạt động** trong một khoảng thời gian chuyển tiếp.

```sql
-- Bật Gradual Password Rollover (1 giờ chuyển tiếp)
ALTER PROFILE hr_profile LIMIT PASSWORD_ROLLOVER_TIME 1/24;

-- Giá trị: tối thiểu 1 giờ (1/24), tối đa 60 ngày
-- Tắt: đặt về 0
ALTER PROFILE hr_profile LIMIT PASSWORD_ROLLOVER_TIME 0;
```

**Quy trình đổi password không downtime:**
1. DBA đổi password: `ALTER USER app_user IDENTIFIED BY new_pass`
2. `DBA_USERS.ACCOUNT_STATUS` = `'OPEN & IN ROLLOVER'`
3. Password cũ vẫn hoạt động trong `PASSWORD_ROLLOVER_TIME`
4. Admin cập nhật cấu hình ứng dụng với password mới
5. Sau `PASSWORD_ROLLOVER_TIME`, password cũ hết hiệu lực

---

## 9. Dictionary Views về Profiles

| View | Cột quan trọng | Mô tả |
|------|---------------|-------|
| `DBA_PROFILES` | PROFILE, RESOURCE_NAME, RESOURCE_TYPE, LIMIT | Tất cả profiles |
| `DBA_USERS` | USERNAME, PROFILE, EXPIRY_DATE, LOCK_DATE, LAST_LOGIN, ACCOUNT_STATUS | Thông tin user |
| `USER_PASSWORD_LIMITS` | RESOURCE_NAME, LIMIT | Password params của user hiện tại |
| `USER_RESOURCE_LIMITS` | RESOURCE_NAME, LIMIT | Resource limits của user hiện tại |

```sql
-- Xem tất cả profiles và settings của chúng
SELECT PROFILE, RESOURCE_NAME, LIMIT
FROM DBA_PROFILES
ORDER BY PROFILE, RESOURCE_NAME;

-- Xem password expiry date của tất cả users
SELECT USERNAME, PROFILE, ACCOUNT_STATUS,
       EXPIRY_DATE, LOCK_DATE, LAST_LOGIN
FROM DBA_USERS
WHERE ORACLE_MAINTAINED = 'N'
ORDER BY USERNAME;
```

---

## 10. Hướng dẫn sử dụng Profiles

1. **Phân loại users** và tạo profile riêng cho từng loại (DBA, Developer, Application, Reporting)
2. **Triển khai chính sách mật khẩu** — nếu chưa có, hãy tạo một
3. **Schema-only accounts** không cần password policy → dùng NO AUTHENTICATION
4. **Ứng dụng dùng chung account**: cân nhắc Gradual Password Rollover
5. **Resource limits**: Ưu tiên dùng **Oracle Resource Manager** thay vì profile resource limits

---

## Câu hỏi ôn tập

**Câu 1**: Tham số `PASSWORD_LOCK_TIME = 1/24` có nghĩa là gì?

> **Trả lời**: Tài khoản sẽ bị khóa trong **1/24 ngày = 1 giờ** sau khi vượt quá số lần đăng nhập sai (`FAILED_LOGIN_ATTEMPTS`). Oracle cho phép dùng phân số để biểu diễn thời gian dưới 1 ngày.

**Câu 2**: Sự khác biệt giữa `PASSWORD_REUSE_MAX = 5` và `PASSWORD_REUSE_TIME = 60` là gì?

> **Trả lời**:
> - `PASSWORD_REUSE_MAX = 5`: User phải **đổi mật khẩu ít nhất 5 lần** trước khi có thể dùng lại mật khẩu cũ
> - `PASSWORD_REUSE_TIME = 60`: User phải **đợi ít nhất 60 ngày** trước khi có thể dùng lại mật khẩu cũ
>
> Để giới hạn tái sử dụng hoàn toàn, cần set **cả hai** tham số.

**Câu 3**: Khi user nhận được lỗi `ORA-28002`, tài khoản đang ở trạng thái nào? User có thể làm gì?

> **Trả lời**: Tài khoản đang ở trạng thái **`EXPIRED (GRACE)`** — mật khẩu đã hết `PASSWORD_LIFE_TIME` nhưng vẫn trong `PASSWORD_GRACE_TIME`. User **vẫn có thể đăng nhập** nhưng được cảnh báo phải đổi mật khẩu. Sau khi `PASSWORD_GRACE_TIME` hết, tài khoản chuyển sang `EXPIRED` và **bắt buộc** phải đổi mật khẩu mới được vào.

**Câu 4**: Hàm `ora12c_stig_verify_function` yêu cầu mật khẩu như thế nào?

> **Trả lời**: Mật khẩu phải thỏa mãn **tất cả** điều kiện sau:
> - Tối thiểu **15 ký tự**
> - Có ít nhất **1 chữ HOA** và **1 chữ thường**
> - Có ít nhất **1 chữ số (0-9)**
> - Có ít nhất **1 ký tự đặc biệt** (như `@`, `#`, `!`...)
> - Khác mật khẩu trước ít nhất **8 ký tự**

**Câu 5**: `Gradual Password Rollover` giải quyết vấn đề gì? Cách bật tính năng này?

> **Trả lời**: Giải quyết vấn đề **downtime khi đổi mật khẩu** của database account dùng bởi ứng dụng. Khi bật, cả mật khẩu cũ và mới đều hoạt động trong khoảng thời gian chuyển tiếp, giúp admin cập nhật cấu hình ứng dụng mà không gián đoạn dịch vụ.
>
> Cách bật:
> ```sql
> ALTER PROFILE app_profile LIMIT PASSWORD_ROLLOVER_TIME 1; -- 1 ngày
> ```

**Câu 6**: User vừa đăng nhập sai 10 lần (FAILED_LOGIN_ATTEMPTS=10), tài khoản bị lock. DBA muốn mở khóa ngay lập tức mà không cần đợi `PASSWORD_LOCK_TIME`. Làm thế nào?

> **Trả lời**: DBA có thể mở khóa tài khoản ngay bằng lệnh:
> ```sql
> ALTER USER locked_user ACCOUNT UNLOCK;
> ```
> Lệnh này không cần đợi `PASSWORD_LOCK_TIME` hết hạn — mở khóa ngay lập tức.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/50-quan-ly-user-profiles.md`
