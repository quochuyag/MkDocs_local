---
title: 'Bài 46: Thực hành - Nén Bảng (Table Compression)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/46-thuc-hanh-table-compression.md
---

# Bài 46: Thực hành - Nén Bảng (Table Compression)

## Mục tiêu thực hành
Khảo sát thực tế cách Basic Compression và Advanced Compression hoạt động:
- Kiểm chứng Basic Compression không nén INSERT thông thường
- Kiểm chứng Basic Compression nén dữ liệu bulk load (APPEND)
- So sánh tỉ lệ nén với dữ liệu có mức độ trùng lặp khác nhau
- Kiểm chứng Advanced Compression hoạt động với INSERT thông thường

---

## Điều kiện tiên quyết
Máy ảo `srv1` với **CDB** database đang chạy.

---

## Các bước thực hành

### Bước 1: Kết nối srv1 qua Putty với user oracle

### Bước 2: Tạo script hiển thị thống kê bảng

```bash
cat > display_table_stats.sql <<EOL
col TABLE_NAME format a20
SELECT TABLE_NAME, BLOCKS*8 SIZE_KB, COMPRESSION, PCT_FREE
FROM USER_TABLES
WHERE TABLE_NAME IN ('CUST_SOURCE','CUST_BCOMPRESSED','CUST_ACOMPRESSED');
EOL
```

### Bước 3: Kết nối PDB1 với HR

```sql
sqlplus HR/ABcd##1234@//srv1/pdb1.localdomain
```

### Bước 4: Tạo 3 bảng với các kiểu compression khác nhau

```sql
-- Bảng KHÔNG nén (nguồn dữ liệu)
CREATE TABLE CUST_SOURCE (
  CUSTOMER_NO  NUMBER(6),
  FIRST_NAME   VARCHAR2(20),
  LAST_NAME    VARCHAR2(20),
  NOTE1        VARCHAR2(100),
  NOTE2        VARCHAR2(100)
) NOLOGGING PCTFREE 0;

-- Bảng với BASIC Compression
CREATE TABLE CUST_BCOMPRESSED (
  CUSTOMER_NO  NUMBER(6),
  FIRST_NAME   VARCHAR2(20),
  LAST_NAME    VARCHAR2(20),
  NOTE1        VARCHAR2(100),
  NOTE2        VARCHAR2(100)
) ROW STORE COMPRESS BASIC NOLOGGING;

-- Bảng với ADVANCED Compression (PCTFREE=0 để so sánh công bằng)
CREATE TABLE CUST_ACOMPRESSED (
  CUSTOMER_NO  NUMBER(6),
  FIRST_NAME   VARCHAR2(20),
  LAST_NAME    VARCHAR2(20),
  NOTE1        VARCHAR2(100),
  NOTE2        VARCHAR2(100)
) ROW STORE COMPRESS ADVANCED NOLOGGING PCTFREE 0;
```

> **Ghi chú**: Sử dụng Advanced Compression trong production cần license riêng.

---

## Phần 1: Basic Compression với INSERT thông thường (dữ liệu ngẫu nhiên)

### Bước 5: Nạp 100,000 records ngẫu nhiên vào CUST_SOURCE

```sql
INSERT INTO CUST_SOURCE
  SELECT LEVEL AS CUSTOMER_NO,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(10,20))) FIRST_NAME,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(10,20))) LAST_NAME,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(0,100))) NOTE1,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(0,100))) NOTE2
  FROM DUAL
  CONNECT BY LEVEL <= 100000;
COMMIT;

-- Copy sang bảng compressed bằng INSERT thường
INSERT INTO CUST_BCOMPRESSED SELECT * FROM CUST_SOURCE;
COMMIT;

-- Thu thập thống kê
exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_SOURCE')
exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_BCOMPRESSED')
```

### Bước 6: Xem thống kê — INSERT thường KHÔNG được nén

```sql
@ display_table_stats.sql
```

> **Quan sát**: `CUST_SOURCE` và `CUST_BCOMPRESSED` có **cùng kích thước** (SIZE_KB).
>
> **Kết luận**: **Basic Compression KHÔNG nén dữ liệu INSERT thường**, dù bảng đã được đánh dấu là COMPRESS.

---

## Phần 2: Basic Compression với Direct Path Loading (dữ liệu ngẫu nhiên)

### Bước 7: Nạp lại bằng Direct Path INSERT (hint APPEND)

```sql
TRUNCATE TABLE CUST_BCOMPRESSED;

-- Direct path loading với hint /*+ APPEND */
INSERT /*+ APPEND */ INTO CUST_BCOMPRESSED SELECT * FROM CUST_SOURCE;
COMMIT;

exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_BCOMPRESSED')
```

### Bước 8: Xem thống kê — dữ liệu ngẫu nhiên → nén ít

```sql
@ display_table_stats.sql
```

> **Quan sát**: `CUST_BCOMPRESSED` nhỏ hơn `CUST_SOURCE` một chút.
>
> **Kết luận**: Basic Compression **có nén** khi dùng Direct Path, nhưng dữ liệu **ngẫu nhiên** (ít trùng lặp) → tỉ lệ nén **thấp**.

---

## Phần 3: Basic Compression với dữ liệu có nhiều trùng lặp

### Bước 9: Tạo lại dữ liệu có nhiều giá trị trùng lặp trong NOTE1, NOTE2

```sql
TRUNCATE TABLE CUST_SOURCE;
TRUNCATE TABLE CUST_BCOMPRESSED;

-- Dữ liệu này: NOTE1='XXXXXX', NOTE2='YYYYYY' lặp lại cho 100,000 rows
INSERT INTO CUST_SOURCE
  SELECT LEVEL AS CUSTOMER_NO,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(10,20))) FIRST_NAME,
         DBMS_RANDOM.STRING('A', TRUNC(DBMS_RANDOM.value(10,20))) LAST_NAME,
         'XXXXXX' NOTE1,
         'YYYYYY' NOTE2
  FROM DUAL
  CONNECT BY LEVEL <= 100000;
COMMIT;

INSERT /*+ APPEND */ INTO CUST_BCOMPRESSED SELECT * FROM CUST_SOURCE;
COMMIT;

exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_SOURCE')
exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_BCOMPRESSED')
```

### Bước 10: Xem thống kê — dữ liệu trùng lặp → nén hiệu quả

```sql
@ display_table_stats.sql
```

> **Quan sát**: `CUST_BCOMPRESSED` **nhỏ hơn rõ rệt** so với `CUST_SOURCE`.
>
> **Kết luận**: **Tỉ lệ nén của Basic Compression phụ thuộc vào mức độ trùng lặp dữ liệu.** Dữ liệu càng trùng lặp (ví dụ: cột mã vùng, mã phòng ban, giá trị cố định) → nén càng hiệu quả.

---

## Phần 4: Advanced Compression với INSERT thường

### Bước 11: Nạp CUST_ACOMPRESSED bằng INSERT thường

```sql
INSERT INTO CUST_ACOMPRESSED SELECT * FROM CUST_SOURCE;
COMMIT;

exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_ACOMPRESSED')
```

### Bước 12: Xem thống kê — Advanced nén được INSERT thường

```sql
@ display_table_stats.sql
```

> **Quan sát**: `CUST_ACOMPRESSED` **nhỏ hơn** `CUST_SOURCE` dù dùng INSERT thường.
>
> **Kết luận**: **Advanced Compression hoạt động với INSERT thông thường** (không cần APPEND hint).

---

## Phần 5: Advanced Compression với Direct Path Loading

### Bước 13: Nạp lại CUST_ACOMPRESSED bằng Direct Path

```sql
TRUNCATE TABLE CUST_ACOMPRESSED;

INSERT /*+ APPEND */ INTO CUST_ACOMPRESSED SELECT * FROM CUST_SOURCE;
COMMIT;

exec DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST_ACOMPRESSED')
```

### Bước 14: Xem thống kê cuối cùng — kết quả tổng hợp

```sql
@ display_table_stats.sql
```

> **Quan sát**: `CUST_ACOMPRESSED` (Advanced + Direct Path) có kích thước **gần bằng** `CUST_BCOMPRESSED` (Basic + Direct Path).
>
> **Kết luận**: Với Direct Path Loading, Advanced Compression cho kết quả **tương đương** Basic Compression.

### Bảng tóm tắt kết quả thực hành

| Bảng | Insert Method | Dữ liệu | Kích thước |
|------|-------------|---------|-----------|
| CUST_SOURCE | INSERT thường | Có trùng lặp | 100% (base) |
| CUST_BCOMPRESSED | INSERT thường | Có trùng lặp | ~100% (không nén!) |
| CUST_BCOMPRESSED | Direct Path (APPEND) | Ngẫu nhiên | ~95% (ít nén) |
| CUST_BCOMPRESSED | Direct Path (APPEND) | Có trùng lặp | ~40-60% (nén tốt) |
| CUST_ACOMPRESSED | INSERT thường | Có trùng lặp | ~50-70% (nén được) |
| CUST_ACOMPRESSED | Direct Path (APPEND) | Có trùng lặp | ~40-60% (tương đương Basic) |

---

## Dọn dẹp

### Bước 15: Xóa các bảng và script

```sql
DROP TABLE CUST_SOURCE;
DROP TABLE CUST_BCOMPRESSED;
DROP TABLE CUST_ACOMPRESSED;

host rm display_table_stats.sql
```

---

## Câu hỏi ôn tập

**Câu 1**: Trong thực hành này, vì sao khi INSERT thông thường vào `CUST_BCOMPRESSED` (bảng đã khai báo COMPRESS BASIC), kích thước lại bằng với bảng không nén?

> **Trả lời**: Vì **Basic Compression chỉ kích hoạt với bulk load** (Direct Path). INSERT thông thường bỏ qua cơ chế nén — dữ liệu được ghi vào block theo cách thông thường, không được nén.

**Câu 2**: Hint nào cần thêm vào câu lệnh INSERT để kích hoạt Direct Path Loading?

> **Trả lời**: Hint `/*+ APPEND */`:
> ```sql
> INSERT /*+ APPEND */ INTO target_table SELECT * FROM source_table;
> ```

**Câu 3**: Trong thực hành bước 9-10, dữ liệu có `NOTE1='XXXXXX'` và `NOTE2='YYYYYY'` cho 100,000 rows. Tại sao tỉ lệ nén lại cao hơn so với dữ liệu ngẫu nhiên?

> **Trả lời**: Basic Compression dùng **de-duplication** (loại bỏ giá trị trùng lặp trong block). Khi `NOTE1` và `NOTE2` cùng một giá trị cho hàng chục nghìn rows, mỗi block chỉ lưu giá trị đó **một lần** và các rows chỉ lưu **link**. Kết quả là block chứa được nhiều rows hơn nhiều → kích thước tổng thể giảm đáng kể.

**Câu 4**: Trong thực hành, khi nào thì Advanced Compression cho kết quả tương đương Basic Compression?

> **Trả lời**: Khi dùng **Direct Path Loading** (`INSERT /*+ APPEND */`). Trong trường hợp này, Advanced Compression hoạt động tương tự Basic và đạt tỉ lệ nén gần bằng nhau.

**Câu 5**: Bạn đang vận hành một hệ thống OLTP với bảng `ORDERS` bị INSERT liên tục bởi ứng dụng. Bạn nên dùng kiểu compression nào?

> **Trả lời**: **Advanced Compression (ROW STORE COMPRESS ADVANCED)**. Đây là lựa chọn duy nhất hỗ trợ OLTP vì nó nén dữ liệu được INSERT bởi câu lệnh thông thường (không cần Direct Path). Tuy nhiên cần lưu ý **cần license riêng** và nên **kiểm thử ảnh hưởng đến hiệu năng** trước khi triển khai.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/46-thuc-hanh-table-compression.md`
