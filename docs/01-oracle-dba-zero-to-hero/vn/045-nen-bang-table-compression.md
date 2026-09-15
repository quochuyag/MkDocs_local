---
title: 'Bài 45: Nén Bảng (Table Compression)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/45-nen-bang-table-compression.md
---

# Bài 45: Nén Bảng (Table Compression)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Mô tả và sử dụng Basic Compression
- Mô tả và sử dụng Advanced Compression
- Truy vấn thông tin nén trong database
- Mô tả Oracle Hybrid Columnar Compression (HCC)

---

## 1. Tại sao cần nén bảng?

Nén bảng giúp:
- **Tiết kiệm không gian đĩa** — giảm kích thước vật lý của dữ liệu
- **Cải thiện hiệu năng** — ít I/O hơn khi đọc dữ liệu (ít blocks hơn cần đọc)
- **Tăng hiệu quả cache** — nhiều dữ liệu hơn vừa trong Buffer Cache

Oracle cung cấp hai loại nén chính:
| Loại | Khi nào nén? | License riêng? |
|------|-------------|--------------|
| **Basic Compression** | Chỉ khi bulk load | Không (miễn phí) |
| **Advanced Compression** | Cả INSERT thường lẫn bulk load | Có (trả phí) |

---

## 2. Basic Compression

### 2.1 Cơ chế hoạt động

Basic Compression sử dụng kỹ thuật **de-duplication** (loại bỏ giá trị trùng lặp):

- Trong mỗi **data block**, các giá trị lặp đi lặp lại trong cùng một cột được lưu **một lần duy nhất** ở vùng Symbol Table của block
- Các row trong block chỉ lưu **liên kết (link)** đến giá trị đó thay vì lưu lại toàn bộ giá trị

```
Không nén:           Với Basic Compression:
Col3  Col4           Symbol Table:  ZZZ→link1, YYY→link2
ZZZ   EFGH           Col3    Col4
ZZZ   YYY     →      link1   EFGH
ZZZ   YYY            link1   link2
ABCD  YYY            link1   link2
                     ABCD    link2
```

**Hiệu quả phụ thuộc vào mức độ trùng lặp dữ liệu** — dữ liệu càng có nhiều giá trị lặp → tỉ lệ nén càng cao.

### 2.2 Đặc điểm quan trọng

> **Basic Compression CHỈ nén dữ liệu được nạp bằng bulk load!**

Các phương pháp bulk load tương thích:
- **Direct-path INSERT** với hint `/*+ APPEND */`
- **SQL*Loader** với Direct Path
- **ALTER TABLE ... MOVE COMPRESS**
- **Online table redefinition**

Lệnh INSERT thông thường (`INSERT INTO ... VALUES`) **KHÔNG** được nén!

### 2.3 Khi nào nên dùng Basic Compression?

- Bảng được **nạp hàng loạt** (batch load) và **ít khi UPDATE**
- Ví dụ: bảng lịch sử, data warehouse fact tables
- **Không nên dùng** cho bảng OLTP có nhiều DML thường xuyên

### 2.4 Cú pháp Basic Compression

```sql
-- Tạo bảng với Basic Compression
CREATE TABLE sales_history (...) ROW STORE COMPRESS BASIC;
CREATE TABLE sales_history (...) COMPRESS;  -- tương đương

-- Thêm compression vào bảng hiện có (chỉ ảnh hưởng dữ liệu mới nạp)
ALTER TABLE sales_history ROW STORE COMPRESS BASIC;
ALTER TABLE sales_history COMPRESS;

-- Nén toàn bộ dữ liệu hiện có (+ dữ liệu mới)
ALTER TABLE sales_history MOVE COMPRESS;

-- Tắt compression
ALTER TABLE sales_history NOCOMPRESS;

-- Đặt mặc định cho cả tablespace
CREATE TABLESPACE hist_tbs ... DEFAULT COMPRESS;
```

> **Lưu ý**: Khi bật Basic Compression, `PCTFREE` tự động được đặt thành `0` vì block cần được lấp đầy để đạt tỉ lệ nén tốt nhất.

---

## 3. Advanced Compression

### 3.1 Cơ chế hoạt động

Advanced Compression (còn gọi là **OLTP Compression**) hoạt động khác biệt:

- Dữ liệu ban đầu được INSERT vào block theo dạng **không nén**
- Khi block đạt đến ngưỡng `PCTFREE`, Oracle **tự động nén** dữ liệu trong block đó
- Sau khi nén, có không gian cho các INSERT tiếp theo

```
Block với PCTFREE=10%:
[...data inserted...PCTFREE=10%...]
              ↓ đạt ngưỡng PCTFREE
[==compressed data==|  free space  ]
              ↓ INSERT tiếp tục
[==compressed==|new rows|PCTFREE=10%]
```

### 3.2 Ưu điểm

- Hỗ trợ **INSERT thông thường** (OLTP workload)
- **Không cần thay đổi ứng dụng** — hoạt động minh bạch
- Cải thiện hiệu năng queries (ít I/O hơn)
- Hiệu quả hơn trong việc nạp bulk so với Basic

### 3.3 Nhược điểm

- **Cần license riêng** (Oracle Advanced Compression Option)
- Với cùng dữ liệu, Basic Compression có thể cho tỉ lệ nén **cao hơn** (vì được kiểm soát khi nào nén)
- Có overhead do **row migration** (dữ liệu bị di chuyển khi nén)
- Cần **kiểm thử trước** khi triển khai trong môi trường OLTP

### 3.4 Cú pháp Advanced Compression

```sql
-- Tạo bảng với Advanced Compression
CREATE TABLE orders (...) ROW STORE COMPRESS ADVANCED;

-- Thêm vào bảng hiện có
ALTER TABLE orders ROW STORE COMPRESS ADVANCED;

-- Đặt mặc định cho tablespace
CREATE TABLESPACE oltp_tbs ... DEFAULT ROW STORE COMPRESS ADVANCED;
```

> **Lưu ý**: Với Advanced Compression, `PCTFREE` mặc định là `10` (khác Basic là `0`).

---

## 4. So sánh Basic và Advanced Compression

| Tiêu chí | Basic | Advanced |
|---------|-------|---------|
| Hoạt động với INSERT thường | ❌ Không | ✅ Có |
| Hoạt động với bulk load (APPEND) | ✅ Có | ✅ Có |
| Tỉ lệ nén (cùng dữ liệu có trùng lặp) | Cao hơn | Thấp hơn một chút |
| License | Miễn phí | Trả phí |
| PCTFREE mặc định | 0 | 10 |
| Phù hợp cho | Data Warehouse / Batch | OLTP / Mixed |

---

## 5. Truy vấn thông tin compression

```sql
-- Kiểm tra compression của các bảng
SELECT TABLE_NAME, COMPRESSION, COMPRESS_FOR
FROM USER_TABLES;
```

| `COMPRESSION` | `COMPRESS_FOR` | Ý nghĩa |
|-------------|--------------|--------|
| DISABLED | (null) | Không nén |
| ENABLED | BASIC | Basic Compression |
| ENABLED | ADVANCED | Advanced Compression |

### Kiểm tra kiểu nén của từng row

```sql
SELECT DECODE(
  DBMS_COMPRESSION.GET_COMPRESSION_TYPE(
    OWNNAME    => 'SOE',
    TABNAME    => 'SALES_HISTORY',
    SUBOBJNAME => '',
    ROW_ID     => 'AAAKEIEEGBBADBTDEDD'),
  1,    'Không nén',
  2,    'Advanced Row Compression',
  4,    'HCC Query High',
  8,    'HCC Query Low',
  16,   'HCC Archive High',
  32,   'HCC Archive Low',
  4096, 'Basic Table Compression',
  'Không xác định') COMPRESSION_TYPE
FROM DUAL;
```

---

## 6. Oracle Hybrid Columnar Compression (HCC)

HCC là công nghệ nén cao cấp nhất của Oracle, kết hợp cả **nén theo hàng (row)** và **nén theo cột (column)**:

- **Tỉ lệ nén**: 5× đến 15× (hoặc cao hơn với dữ liệu có tính lặp cao)
- **Chỉ khả dụng trên Oracle Storage**:
  - Oracle Exadata Storage Cell
  - Axiom Pillar
  - Solaris ZFS

| Chế độ HCC | Đặc điểm |
|-----------|---------|
| HCC Query High | Tỉ lệ nén cao, tối ưu cho query |
| HCC Query Low | Cân bằng giữa nén và hiệu năng |
| HCC Archive High | Tỉ lệ nén tối đa (cho data cũ ít truy cập) |
| HCC Archive Low | Nén cao nhưng truy cập nhanh hơn Archive High |

---

## Tổng kết

| Công nghệ | Phù hợp | Yêu cầu |
|-----------|---------|---------|
| Basic Compression | Data Warehouse, bulk load | Chỉ nén khi bulk load |
| Advanced Compression | OLTP, mixed workload | License riêng |
| HCC | Archival, Exadata | Oracle Storage hardware |

---

## Câu hỏi ôn tập

**Câu 1**: Basic Compression có nén dữ liệu được INSERT bằng câu lệnh `INSERT INTO ... VALUES` thông thường không?

> **Trả lời**: **Không**. Basic Compression chỉ nén dữ liệu được nạp bằng **bulk load** (Direct Path INSERT với hint `APPEND`, SQL*Loader Direct Path, ALTER TABLE MOVE, Online Redefinition). INSERT thông thường không được nén.

**Câu 2**: Khi bật Basic Compression, giá trị `PCTFREE` được đặt là bao nhiêu?

> **Trả lời**: `PCTFREE = 0`. Oracle đặt tự động vì block cần được lấp đầy hoàn toàn để đạt hiệu quả nén tốt nhất.

**Câu 3**: Câu lệnh nào dùng để bật Advanced Compression cho bảng `ORDERS`?

> **Trả lời**:
> ```sql
> ALTER TABLE ORDERS ROW STORE COMPRESS ADVANCED;
> ```

**Câu 4**: Làm thế nào để nén toàn bộ dữ liệu **hiện có** trong một bảng đang dùng Basic Compression?

> **Trả lời**: Dùng `ALTER TABLE ... MOVE COMPRESS`. Lệnh này di chuyển và đồng thời nén tất cả dữ liệu hiện có:
> ```sql
> ALTER TABLE sales_history MOVE COMPRESS;
> ```

**Câu 5**: Để kiểm tra bảng nào đang được nén và kiểu nén là gì, dùng view nào?

> **Trả lời**: Dùng view `USER_TABLES` (hoặc `DBA_TABLES`) với các cột:
> ```sql
> SELECT TABLE_NAME, COMPRESSION, COMPRESS_FOR FROM USER_TABLES;
> ```

**Câu 6**: Oracle Hybrid Columnar Compression (HCC) yêu cầu gì đặc biệt?

> **Trả lời**: HCC **chỉ khả dụng trên Oracle Storage** như Exadata Storage Cell, Axiom Pillar, và Solaris ZFS. Không thể dùng trên storage thông thường.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/45-nen-bang-table-compression.md`
