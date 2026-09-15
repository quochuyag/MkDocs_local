---
title: 'Bài 31: Thực hành - Quản lý Bộ nhớ Oracle Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/31-thuc-hanh-quan-ly-bo-nho.md
---

# Bài 31: Thực hành - Quản lý Bộ nhớ Oracle Database

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ:
- Cấu hình **Automatic Memory Management (AMM)** và hiểu giới hạn của nó trên Linux.
- Cấu hình **Automatic Shared Memory Management (ASMM)** theo phương pháp được khuyến nghị.
- Sử dụng **Memory Advisors** để xem đề xuất tối ưu bộ nhớ.

---

## Điều kiện tiên quyết
Máy ảo `srv1` với CDB database đang chạy (6GB RAM).

---

## Phần A: Cấu hình Automatic Memory Management (AMM)

> ⚠️ **Lưu ý thực tế:** AMM chỉ phù hợp khi server có RAM <= 4GB. Trên Linux, AMM bị giới hạn bởi kích thước `/dev/shm` (tmpfs).

### Bước 1-3: Kiểm tra cấu hình hiện tại

```bash
sqlplus / as sysdba
```

```sql
-- Kiểm tra MEMORY_TARGET và MEMORY_MAX_TARGET
-- Hiện tại cả 2 đều = 0 (AMM bị tắt khi tạo DB)
SHOW PARAMETER MEMORY_TARGET
SHOW PARAMETER MEMORY_MAX_TARGET
```

### Bước 4: Đặt MEMORY_TARGET = 3200M (trong SPFILE)

```sql
-- AMM cần SCOPE=SPFILE vì đây là static parameter (cần restart)
ALTER SYSTEM SET MEMORY_TARGET     = 3200M SCOPE = SPFILE;
ALTER SYSTEM SET MEMORY_MAX_TARGET = 3200M SCOPE = SPFILE;

exit
```

### Bước 5-7: Tắt auto-restart và shutdown VM

```bash
# Tắt auto-start database (để kiểm tra thủ công sau restart)
vi /etc/oratab
# Đổi Y thành N cho dòng database

# Tắt máy để thay đổi RAM trong VirtualBox
su - root
shutdown -h now
```

### Bước 8-9: Tăng RAM VM lên 4GB

Trong Oracle VirtualBox:
**Settings → System → Motherboard → Base Memory: 4096 MB → OK**

Sau đó khởi động lại VM.

### Bước 10-12: Thử startup database (sẽ gặp lỗi)

```bash
sqlplus / as sysdba
STARTUP
```

**Lỗi dự kiến:**
```
ORA-00845: MEMORY_TARGET not supported on this system
```

> 💡 **Nguyên nhân lỗi:** Trên Linux, AMM dùng `/dev/shm` (tmpfs). Kích thước `/dev/shm` mặc định chỉ là 1.8GB - **nhỏ hơn** `MEMORY_TARGET = 3200M` → Oracle từ chối khởi động.

### Bước 13-14: Kiểm tra kích thước `/dev/shm`

```bash
exit   # Thoát SQL*Plus
df -h  # Xem kích thước /dev/shm (~1.8G)
```

### Bước 15-16: Tăng kích thước `/dev/shm` tạm thời

```bash
su - root

# Tăng /dev/shm lên 3200MB (thay đổi tạm thời, mất sau reboot)
umount tmpfs
mount -t tmpfs shmfs -o size=3200m /dev/shm

# Quay lại user oracle và khởi động DB
su - oracle
sqlplus / as sysdba
startup
```

### Bước 17: Xem phân bổ bộ nhớ theo AMM

```sql
col COMPONENT format a22

SELECT COMPONENT,
       CURRENT_SIZE/1024/1024       CURRENT_SIZE_MB,
       USER_SPECIFIED_SIZE/1024/1024 USER_SPECIFIED_MB
FROM V$MEMORY_DYNAMIC_COMPONENTS
WHERE CURRENT_SIZE <> 0;
```

> 💡 **Quan sát:** Tổng của "SGA Target" + "PGA Target" ≈ 3200MB. Oracle tự phân chia.

### Bước 18: Xem SPFILE hiện tại

```sql
-- Oracle lưu các giá trị hiện tại vào SPFILE để dùng khi restart
HOST head -n 15 $ORACLE_HOME/dbs/spfileoradb.ora
```

### Bước 19: Xem Memory Advisor

```sql
set linesize 180
-- Với AMM: dùng V$MEMORY_TARGET_ADVICE
SELECT * FROM V$MEMORY_TARGET_ADVICE ORDER BY MEMORY_SIZE;
```

> ℹ️ Vì DB chưa có workload thực tế, Advisor chưa có dữ liệu đủ để tư vấn chính xác.

### Bước 20-23: Dọn dẹp - Khôi phục về snapshot CDB

1. Shutdown VM `srv1`.
2. Trong VirtualBox: Restore từ snapshot **"oradb CDB database"**.
3. Xác nhận RAM trở về 6GB.
4. Khởi động VM và kết nối Putty.

---

## Phần B: Cấu hình Automatic Shared Memory Management (ASMM)

### Bước 25-26: Tính toán phân bổ bộ nhớ

```bash
free -h   # Xem tổng RAM: ~5.6GB
```

**Công thức phân bổ:**
```
DB memory    = 70% × 5.6GB ≈ 3.9GB
SGA_TARGET   = 60% × 3.9GB ≈ 2.3GB → làm tròn 2408MB
PGA_TARGET   = 40% × 3.9GB ≈ 1.5GB → 1500MB
```

### Bước 27: Xác nhận AMM đã tắt

```bash
sqlplus / as sysdba
```

```sql
-- MEMORY_TARGET phải = 0 để bật ASMM
SHOW PARAMETER MEMORY_TARGET
```

### Bước 28: Đặt SGA_MAX_SIZE và restart

```sql
-- SGA_MAX_SIZE là giới hạn tối đa của SGA (static parameter)
-- Đặt cao hơn SGA_TARGET để sau này có thể tăng SGA mà không cần restart
ALTER SYSTEM SET SGA_MAX_SIZE = 4096M SCOPE = SPFILE;

-- Restart để áp dụng SGA_MAX_SIZE
SHUTDOWN IMMEDIATE
STARTUP
```

### Bước 29-30: Đặt SGA_TARGET và PGA_AGGREGATE_TARGET

```sql
-- Đặt SGA_TARGET (dynamic - không cần restart)
ALTER SYSTEM SET SGA_TARGET = 2408M SCOPE = BOTH;

-- PGA_AGGREGATE_TARGET đôi khi có lỗi khi set SCOPE=BOTH
-- Nếu gặp lỗi ORA-00855, dùng SCOPE=SPFILE và restart
ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 1500M SCOPE = BOTH;
-- Nếu lỗi:
-- ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 1500M SCOPE = SPFILE;
-- SHUTDOWN IMMEDIATE
-- STARTUP
```

### Bước 31: Xem phân bổ bộ nhớ theo ASMM

```sql
col COMPONENT format a22

SELECT COMPONENT,
       CURRENT_SIZE/1024/1024       CURRENT_SIZE_MB,
       USER_SPECIFIED_SIZE/1024/1024 USER_SPECIFIED_MB
FROM V$MEMORY_DYNAMIC_COMPONENTS
WHERE CURRENT_SIZE <> 0;
```

**Đọc kết quả:**
- `USER_SPECIFIED_SIZE = 0` → Oracle tự quản lý (auto-tuned).
- `USER_SPECIFIED_SIZE > 0` → DBA đặt thủ công (user-specified).

### Bước 32-33: Kiểm tra Memory Advisors

```sql
-- Advisor cho AMM (không hoạt động khi AMM tắt)
SELECT * FROM V$MEMORY_TARGET_ADVICE ORDER BY MEMORY_SIZE;
-- Kết quả: không có dữ liệu (AMM bị tắt)

-- Advisor cho ASMM
SELECT SGA_SIZE, SGA_SIZE_FACTOR, ESTD_DB_TIME, ESTD_DB_TIME_FACTOR
FROM V$SGA_TARGET_ADVICE
ORDER BY SGA_SIZE;
-- Kết quả: các gợi ý tối ưu SGA_TARGET
```

### Bước 34: Dọn dẹp

Shutdown VM và restore từ CDB snapshot để trở về cấu hình ban đầu.

---

## Bảng tổng kết AMM vs ASMM

| | AMM | ASMM |
|-|-----|------|
| Tham số chính | `MEMORY_TARGET` | `SGA_TARGET` + `PGA_AGGREGATE_TARGET` |
| Oracle quản lý | SGA + PGA | Thành phần trong SGA |
| Giới hạn Linux | `/dev/shm` phải >= `MEMORY_TARGET` | Không bị giới hạn bởi tmpfs |
| Khuyến nghị | Server < 4GB RAM | **Production** (được khuyến nghị) |
| Advisor | `V$MEMORY_TARGET_ADVICE` | `V$SGA_TARGET_ADVICE` |

---

## Tóm tắt bài thực hành

1. **AMM trên Linux:** Phải đảm bảo `/dev/shm` >= `MEMORY_TARGET`, nếu không Oracle báo `ORA-00845`.
2. **ASMM được khuyến nghị** cho môi trường production vì kiểm soát tốt hơn.
3. `SGA_MAX_SIZE` là **static** (cần restart), `SGA_TARGET` là **dynamic** (thay đổi ngay).
4. Memory Advisor (`V$SGA_TARGET_ADVICE`) chỉ cho kết quả chính xác sau khi DB chạy với workload thực tế.

---

## Câu hỏi ôn tập

**1. Tại sao Oracle báo lỗi `ORA-00845` khi khởi động với AMM trên Linux?**
> **Trả lời:**
> Lỗi `ORA-00845: MEMORY_TARGET not supported on this system` xảy ra khi giá trị của tham số `MEMORY_TARGET` (hoặc `MEMORY_MAX_TARGET`) được cấu hình **lớn hơn dung lượng của hệ thống file chia sẻ ảo `/dev/shm` (shmfs / tmpfs)** trên Linux. Để khắc phục, bạn phải dùng tài khoản `root` tăng dung lượng của `/dev/shm` (ví dụ: `mount -o remount,size=4G /dev/shm` và cập nhật vào `/etc/fstab`), hoặc giảm `MEMORY_TARGET` xuống thấp hơn dung lượng `/dev/shm`.

**2. Bạn muốn tăng `SGA_TARGET` từ 2GB lên 3GB. Bạn cần làm gì nếu `SGA_MAX_SIZE = 2.5GB`?**
> **Trả lời:**
> Vì `SGA_TARGET` không được phép vượt quá giới hạn trần `SGA_MAX_SIZE`, bạn không thể tăng ngay mà phải làm theo 2 bước:
> 1. Tăng `SGA_MAX_SIZE` trong file cấu hình SPFILE:
>    ```sql
>    ALTER SYSTEM SET SGA_MAX_SIZE = 3G SCOPE=SPFILE;
>    ```
> 2. Khởi động lại Database (`SHUTDOWN IMMEDIATE;` rồi `STARTUP;`) để hệ điều hành cấp phát lại vùng nhớ ảo tối đa 3GB cho SGA.
> 3. Sau khi bật lên, thực thi lệnh tăng:
>    ```sql
>    ALTER SYSTEM SET SGA_TARGET = 3G SCOPE=BOTH;
>    ```

**3. Sau khi đặt ASMM, `V$MEMORY_TARGET_ADVICE` trả về kết quả không? Tại sao?**
> **Trả lời:**
> **Không có kết quả (trả về 0 dòng).**
> View `V$MEMORY_TARGET_ADVICE` chỉ hoạt động và sinh dữ liệu gợi ý khi tính năng AMM (Automatic Memory Management) đang được bật (`MEMORY_TARGET > 0`). Khi bạn chuyển sang ASMM (tắt `MEMORY_TARGET = 0`), bộ điều phối AMM ngừng hoạt động, do đó view này sẽ rỗng. Thay vào đó, bạn sẽ tra cứu hai view cố vấn riêng biệt của ASMM là **`V$SGA_TARGET_ADVICE`** và **`V$PGA_TARGET_ADVICE`**.

**4. `USER_SPECIFIED_SIZE = 0` trong `V$MEMORY_DYNAMIC_COMPONENTS` có nghĩa là gì?**
> **Trả lời:**
> Cột `USER_SPECIFIED_SIZE = 0` nghĩa là thành phần bộ nhớ đó (như `buffer cache`, `shared pool`, `large pool`) **hoàn toàn được Oracle tự động điều phối kích thước (Autotuned)** dựa trên thuật toán tối ưu nội bộ của ASMM/AMM mà không bị người quản trị đặt một mức sàn dung lượng tối thiểu nào bằng tay. Nếu bạn đặt `DB_CACHE_SIZE = 500M`, cột này sẽ hiển thị 500M (đóng vai trò là mức tối thiểu mà Oracle không được phép co xuống dưới mức đó).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/31-thuc-hanh-quan-ly-bo-nho.md`
