---
title: 'Bài 30: Quản lý Bộ nhớ Oracle Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/30-quan-ly-bo-nho-database.md
---

# Bài 30: Quản lý Bộ nhớ Oracle Database

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Hiểu 3 phương pháp quản lý bộ nhớ Oracle: **AMM**, **ASMM**, và **Manual**.
- Biết cách bật và cấu hình từng phương pháp.
- Giám sát và điều chỉnh bộ nhớ bằng các **Memory Advisors**.
- Biết quy tắc phân bổ bộ nhớ ban đầu hợp lý.

---

## 1. Ba phương pháp quản lý bộ nhớ

| Phương pháp | Tham số chính | Oracle quản lý gì | Phù hợp khi |
|------------|--------------|-------------------|------------|
| **AMM** (Automatic Memory Management) | `MEMORY_TARGET` | SGA + PGA toàn bộ | Server <= 4GB RAM; Linux dùng tmpfs |
| **ASMM** (Automatic Shared Memory Management) | `SGA_TARGET` + `PGA_AGGREGATE_TARGET` | Các thành phần SGA; PGA riêng | Được khuyến nghị cho production |
| **Manual** | Từng tham số riêng lẻ | Không tự động | Kiểm soát tuyệt đối (hiếm dùng) |

---

## 2. Automatic Memory Management (AMM)

### 2.1. Cơ chế

- Bạn chỉ cần đặt **một con số**: `MEMORY_TARGET`.
- Oracle tự phân chia con số này thành SGA và PGA sao cho phù hợp nhất với tải hiện tại.
- Khi workload thay đổi (ban ngày OLTP, ban đêm batch), Oracle **tự điều chỉnh** tỷ lệ SGA/PGA.

**Ví dụ thực tế:**
```
MEMORY_TARGET = 400MB
MEMORY_MAX_TARGET = 500MB

→ Ban ngày (nhiều user OLTP):  SGA = 300MB, PGA = 100MB
→ Ban đêm (batch processing): SGA = 200MB, PGA = 200MB (cần nhiều sort)
```

### 2.2. Điều kiện sử dụng AMM

- Tổng RAM server phải **<= 4GB** (Oracle không khuyến nghị AMM cho server RAM lớn).
- Trên **Linux**: AMM không thể vượt quá kích thước `tmpfs` (`/dev/shm`). Nếu AMM lớn hơn `tmpfs`, Oracle báo lỗi khi startup.

### 2.3. Bật AMM

```sql
-- Bước 1: Xem giá trị MEMORY_MAX_TARGET hiện tại
SHOW PARAMETER MEMORY_MAX_TARGET

-- Bước 2a: Nếu MEMORY_TARGET mới <= MEMORY_MAX_TARGET hiện tại → có thể thay đổi ngay
ALTER SYSTEM SET MEMORY_TARGET = 400M SCOPE = BOTH;

-- Bước 2b: Nếu MEMORY_TARGET mới > MEMORY_MAX_TARGET → phải sửa SPFILE và restart
ALTER SYSTEM SET MEMORY_MAX_TARGET = 500M SCOPE = SPFILE;
ALTER SYSTEM SET MEMORY_TARGET    = 400M SCOPE = SPFILE;
-- Sau đó restart instance
SHUTDOWN IMMEDIATE
STARTUP
```

> 💡 **MEMORY_MAX_TARGET:** Ngưỡng tối đa không thể vượt qua, ngăn DBA vô tình set MEMORY_TARGET quá lớn. Nên đặt bằng tổng RAM khả dụng tối đa ngay khi tạo DB.

---

## 3. Automatic Shared Memory Management (ASMM) - Được khuyến nghị

### 3.1. Cơ chế

- Bạn đặt **SGA_TARGET** và **PGA_AGGREGATE_TARGET** riêng biệt.
- Oracle tự phân chia `SGA_TARGET` cho các thành phần: Buffer Cache, Shared Pool, Large Pool, Java Pool, Streams Pool.
- PGA được quản lý riêng qua `PGA_AGGREGATE_TARGET`.

**Ví dụ:**
```
SGA_TARGET = 2400MB → Oracle tự chia:
  Buffer Cache = 1800MB
  Shared Pool  =  500MB
  Large Pool   =   50MB
  ...

PGA_AGGREGATE_TARGET = 800MB (tổng PGA cho tất cả sessions)
```

### 3.2. Ưu điểm so với AMM

- **Kiểm soát tốt hơn:** DBA biết rõ SGA là bao nhiêu, PGA là bao nhiêu.
- **Phù hợp server RAM lớn** (> 4GB).
- Oracle tự điều chỉnh thành phần bên trong SGA, nhưng DBA kiểm soát tổng.

### 3.3. Bật ASMM (từ AMM chuyển sang)

```sql
-- Bước 1: Tắt AMM (đặt MEMORY_TARGET = 0)
SHOW PARAMETER MEMORY_TARGET
ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE = BOTH;

-- Bước 2: Xem SGA_MAX_SIZE hiện tại
SHOW PARAMETER SGA_MAX_SIZE

-- Bước 3a: Nếu SGA_TARGET mới <= SGA_MAX_SIZE → thay đổi ngay
ALTER SYSTEM SET SGA_TARGET = 2400M SCOPE = BOTH;

-- Bước 3b: Nếu SGA_TARGET mới > SGA_MAX_SIZE → cần SPFILE + restart
ALTER SYSTEM SET SGA_MAX_SIZE = 3000M SCOPE = SPFILE;
ALTER SYSTEM SET SGA_TARGET   = 2400M SCOPE = SPFILE;
SHUTDOWN IMMEDIATE
STARTUP

-- Bước 4: Bật quản lý PGA tự động
ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 800M SCOPE = BOTH;
```

> 💡 **PGA_AGGREGATE_LIMIT:** Giới hạn tuyệt đối cho tổng PGA. Mặc định = 200% của `PGA_AGGREGATE_TARGET`. Nếu PGA vượt quá, Oracle sẽ kill session đang dùng nhiều nhất để giải phóng bộ nhớ.

---

## 4. Manual Shared Memory Management

- Tất cả components phải được đặt thủ công.
- Không có tự động điều chỉnh.
- Chỉ dùng khi cần kiểm soát tuyệt đối (hiếm gặp trong practice hiện đại).

```sql
-- Bước 1: Tắt AMM và ASMM
ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE = BOTH;
ALTER SYSTEM SET SGA_TARGET    = 0 SCOPE = BOTH;

-- Bước 2: Đặt từng thành phần SGA thủ công
ALTER SYSTEM SET DB_CACHE_SIZE      = 1800M SCOPE = BOTH;
ALTER SYSTEM SET SHARED_POOL_SIZE   =  500M SCOPE = BOTH;
ALTER SYSTEM SET LARGE_POOL_SIZE    =   50M SCOPE = BOTH;
ALTER SYSTEM SET JAVA_POOL_SIZE     =   32M SCOPE = BOTH;
ALTER SYSTEM SET STREAMS_POOL_SIZE  =   32M SCOPE = BOTH;
```

---

## 5. Giám sát bộ nhớ

### 5.1. Xem các thành phần bộ nhớ hiện tại

```sql
-- Xem tất cả dynamic memory components và kích thước hiện tại
SELECT COMPONENT, CURRENT_SIZE, USER_SPECIFIED_SIZE
FROM V$MEMORY_DYNAMIC_COMPONENTS
WHERE CURRENT_SIZE <> 0;
```

**Đọc kết quả:**
```
COMPONENT               CURRENT_SIZE  USER_SPECIFIED_SIZE
----------------------  ------------  -------------------
shared pool              536870912    0           ← 512MB, auto-managed
large pool                16777216    0           ← 16MB, auto-managed
SGA Target             2516582400    2516582400   ← 2400MB, user-specified
DEFAULT buffer cache   1811939328    0            ← 1728MB, auto-managed
PGA Target              838860800    838860800    ← 800MB, user-specified
```

- `USER_SPECIFIED_SIZE = 0` → Oracle tự quản lý kích thước.
- `USER_SPECIFIED_SIZE > 0` → DBA đặt thủ công.

### 5.2. Tính bộ nhớ chưa phân bổ

```
Allocated SGA = Buffer Cache + Shared Pool + Large Pool + ... = 2256MB
Unallocated   = SGA_TARGET (2400MB) - Allocated (2256MB) = 144MB
```

Bộ nhớ chưa phân bổ sẵn sàng được Oracle dùng khi cần.

---

## 6. Memory Advisors (Cố vấn bộ nhớ)

Sau khi DB chạy một thời gian, Oracle thu thập thống kê và có thể tư vấn kích thước tối ưu.

### 6.1. Advisor cho AMM: V$MEMORY_TARGET_ADVICE

```sql
SELECT * FROM V$MEMORY_TARGET_ADVICE ORDER BY MEMORY_SIZE;
```

| MEMORY_SIZE | MEMORY_SIZE_FACTOR | ESTD_DB_TIME | ESTD_DB_TIME_FACTOR |
|-------------|-------------------|--------------|---------------------|
| 180 | 0.5 | 458 | 1.344 |
| 270 | 0.75 | 367 | 1.076 |
| **360** | **1** | **341** | **1** (baseline) |
| 450 | 1.25 | 335 | 0.981 |
| 540 | 1.5 | 335 | 0.981 |

> 💡 **Đọc kết quả:** MEMORY_SIZE_FACTOR = 1 là kích thước hiện tại. Tăng lên 1.25 (450MB) giúp giảm DB Time 2%, không đáng kể → không cần tăng thêm.

### 6.2. Advisor cho ASMM: V$SGA_TARGET_ADVICE

```sql
SELECT SGA_SIZE, SGA_SIZE_FACTOR, ESTD_DB_TIME, ESTD_DB_TIME_FACTOR
FROM V$SGA_TARGET_ADVICE
ORDER BY SGA_SIZE;
```

---

## 7. Quy tắc phân bổ bộ nhớ ban đầu (Best Practice)

> 💡 Oracle khuyến nghị dùng **ASMM** khi server có >= 4GB RAM.

**Công thức đề xuất:**

```
Bước 1: Tổng RAM khả dụng = RAM máy chủ × 70%
         (Để lại 30% cho OS và các process khác)

Bước 2: Phân bổ tùy theo loại workload:
  - OLTP:      SGA_TARGET = 60% × RAM_kha_dung
               PGA = 40%
  - Warehouse: SGA_TARGET = 70% × RAM_kha_dung
               PGA = 30%

Bước 3: Sau vài ngày chạy thực tế → Tra V$SGA_TARGET_ADVICE
         và điều chỉnh cho phù hợp.
```

**Ví dụ cho server 16GB RAM chạy OLTP:**
```
RAM khả dụng = 16 × 70% = 11.2GB
SGA_TARGET   = 11.2 × 60% ≈ 6.7GB → làm tròn 7GB
PGA          = 11.2 × 40% ≈ 4.5GB → làm tròn 4GB
```

---

## 8. Buffer Cache: Keep và Recycle Pools

Ngoài Buffer Cache mặc định (DEFAULT pool), còn có:

| Pool | Tham số | Mục đích |
|------|---------|---------|
| **KEEP pool** | `DB_KEEP_CACHE_SIZE` | Giữ các block thường xuyên dùng (hot tables). |
| **RECYCLE pool** | `DB_RECYCLE_CACHE_SIZE` | Cho các bảng lớn, chỉ đọc một lần (không muốn chiếm DEFAULT pool). |
| **nK pool** | `DB_nK_CACHE_SIZE` | Cho tablespace có block size khác chuẩn (ví dụ 8K, 16K). |

---

## 9. Tóm tắt bài học

| Phương pháp | Khi nào dùng | Tham số chính |
|------------|-------------|--------------|
| **AMM** | Server nhỏ (<= 4GB), đơn giản | `MEMORY_TARGET` |
| **ASMM** ⭐ Khuyến nghị | Production, server lớn | `SGA_TARGET` + `PGA_AGGREGATE_TARGET` |
| **Manual** | Kiểm soát tuyệt đối | Từng tham số riêng lẻ |

**Quy tắc phân bổ ban đầu:**
- Để lại 30% RAM cho OS.
- OLTP: SGA 60%, PGA 40%.
- Warehouse: SGA 70%, PGA 30%.
- Sau vài ngày dùng Memory Advisor để tinh chỉnh.

---

## 10. Câu hỏi ôn tập

**1. Sự khác biệt giữa AMM và ASMM là gì? Oracle khuyến nghị phương pháp nào?**
> **Trả lời:**
> - **AMM (Automatic Memory Management):** Oracle tự động quản lý và phân bổ linh hoạt tổng dung lượng bộ nhớ giữa cả **SGA và PGA** thông qua tham số duy nhất `MEMORY_TARGET` (và `MEMORY_MAX_TARGET`).
> - **ASMM (Automatic Shared Memory Management):** Bạn cố định riêng dung lượng tối đa cho SGA (`SGA_TARGET`) và riêng cho PGA (`PGA_AGGREGATE_TARGET`). Bên trong SGA, Oracle tự động co giãn giữa Buffer Cache, Shared Pool, Large Pool, Java Pool.
> - **Khuyến nghị:** Oracle khuyến nghị sử dụng **ASMM** (hoặc cấu hình kết hợp HugePages trên Linux) cho các môi trường Enterprise Production. AMM không được khuyến khích cho database lớn vì nó không tương thích với Linux HugePages.

**2. Tại sao AMM không phù hợp cho server có RAM lớn (> 4GB)?**
> **Trả lời:**
> - Trên Linux, AMM dựa trên hệ thống file ảo `shmfs` (`/dev/shm`), vốn sử dụng cơ chế trang nhớ mặc định kích thước nhỏ (Standard 4KB Page Size).
> - Với server có RAM lớn (hàng chục đến hàng trăm GB), hệ điều hành sẽ phải duy trì hàng triệu trang nhớ trong Page Table, gây tốn hàng chục GB RAM chỉ để quản lý bảng ánh xạ và làm quá tải bộ đệm CPU TLB (Translation Lookaside Buffer).
> - Server RAM lớn bắt buộc phải dùng **HugePages** (kích thước trang nhớ 2MB hoặc 1GB) để giải phóng CPU. Nhưng **HugePages không tương thích với AMM** (nếu cấu hình HugePages mà bật AMM database sẽ báo lỗi ORA-00845 hoặc không tận dụng được). Do đó bắt buộc phải chuyển sang dùng ASMM.

**3. `SGA_TARGET` và `SGA_MAX_SIZE` khác nhau như thế nào?**
> **Trả lời:**
> - **`SGA_TARGET`:** Là dung lượng bộ nhớ RAM thực tế mà Oracle đang cấp phát cho toàn bộ SGA tại thời điểm hiện tại (Dynamic parameter, có thể tăng giảm trực tiếp khi đang chạy).
> - **`SGA_MAX_SIZE`:** Là giới hạn trần (trần cứng) của vùng nhớ ảo mà Oracle "xí chỗ" trong bảng phân vùng địa chỉ bộ nhớ khi khởi động instance (Static parameter, chỉ đổi được trong SPFILE và cần restart).
> - Quy tắc: `SGA_TARGET` luôn luôn phải **nhỏ hơn hoặc bằng `SGA_MAX_SIZE`**. Bạn có thể tăng `SGA_TARGET` lên bất kỳ lúc nào miễn là không vượt quá `SGA_MAX_SIZE`.

**4. Bạn muốn tăng `SGA_TARGET` từ 2GB lên 4GB, nhưng `SGA_MAX_SIZE` chỉ là 3GB. Bạn phải làm gì?**
> **Trả lời:**
> Bạn không thể tăng trực tiếp `SGA_TARGET=4G` ngay được vì nó sẽ đụng trần `SGA_MAX_SIZE=3G` và báo lỗi `ORA-02097 / ORA-00823`.
> Bạn phải thực hiện theo 2 bước:
> 1. Tăng trần tối đa trong SPFILE trước:
>    ```sql
>    ALTER SYSTEM SET SGA_MAX_SIZE = 4G SCOPE=SPFILE;
>    ```
> 2. Khởi động lại Database (để OS cấp phát lại vùng nhớ ảo tối đa 4GB):
>    ```sql
>    SHUTDOWN IMMEDIATE;
>    STARTUP;
>    ```
> 3. Sau khi khởi động lại, tăng `SGA_TARGET` lên 4GB:
>    ```sql
>    ALTER SYSTEM SET SGA_TARGET = 4G SCOPE=BOTH;
>    ```

**5. Kết quả `V$SGA_TARGET_ADVICE` cho thấy tăng SGA từ 2GB lên 3GB không cải thiện ESTD_DB_TIME. Bạn sẽ quyết định gì?**
> **Trả lời:**
> Bạn **không nên tăng SGA lên 3GB**.
> Kết quả từ Memory Advisor cho thấy 2GB SGA hiện tại đã đáp ứng thừa đủ nhu cầu đệm dữ liệu (Buffer Cache Hit Ratio đã đạt ngưỡng bão hòa, các câu lệnh đã được cache tốt). Việc đổ thêm 1GB RAM vào SGA chỉ gây lãng phí tài nguyên mà không mang lại bất kỳ sự cải thiện nào về tốc độ xử lý cơ sở dữ liệu (`ESTD_DB_TIME`). Bạn nên giữ nguyên SGA ở mức 2GB và để dành lượng RAM đó cho vùng nhớ PGA của các tác vụ tính toán, hoặc cấp cho hệ điều hành / các ứng dụng khác.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/30-quan-ly-bo-nho-database.md`
