---
title: 'Bài 32: Cấu trúc Lưu trữ Oracle Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/32-cau-truc-luu-tru-database.md
---

# Bài 32: Cấu trúc Lưu trữ Oracle Database

## Mục tiêu bài học
Trong bài học này, bạn sẽ:
- Mô tả cấu trúc lưu trữ **logic** và **vật lý** của Oracle Database.
- Hiểu mối quan hệ giữa: Database → Tablespace → Segment → Extent → Data Block.
- Biết về **Database Standard Block Size** và ý nghĩa của nó.
- Biết các view tra cứu thông tin lưu trữ.

---

## 1. Hai tầng cấu trúc lưu trữ

Oracle Database có hai tầng cấu trúc lưu trữ song song:

```
┌──────────────────────────────────────────────┐
│              LOGICAL (Logical)                │
│  Database                                    │
│    └── Tablespace                            │
│          └── Segment (Table, Index, ...)     │
│                └── Extent                   │
│                      └── Data Block         │
├──────────────────────────────────────────────┤
│              PHYSICAL (Vật lý)               │
│  Database                                    │
│    └── Data File (.dbf)                      │
│          └── OS Block                        │
└──────────────────────────────────────────────┘
```

**Ánh xạ logic ↔ vật lý:**
- **Tablespace** ↔ một hoặc nhiều **Data Files**
- **Data Block** ↔ một hoặc nhiều **OS Blocks**

---

## 2. Các thành phần cấu trúc logic

### 2.1. Tablespace (Không gian bảng)
- Là nhóm logic của một hoặc nhiều **Data Files**.
- Tất cả dữ liệu trong database đều nằm trong tablespace.
- Ví dụ: Tablespace `USERS` có thể gồm 2 datafiles: `users01.dbf` và `users02.dbf`.

### 2.2. Segment (Phân đoạn)
- Là tập hợp các extents phân bổ cho một **đối tượng cụ thể** (table, index, ...).
- Mỗi table có một segment riêng.
- **Segment được tạo khi dữ liệu đầu tiên được INSERT** (không phải khi CREATE TABLE).

```sql
-- Xem thông tin segment
SELECT SEGMENT_NAME, SEGMENT_TYPE, TABLESPACE_NAME, EXTENTS, BYTES/1024 KB
FROM USER_SEGMENTS
WHERE SEGMENT_NAME = 'EMPLOYEES';
```

> 💡 **Quan trọng:** Nếu CREATE TABLE nhưng chưa INSERT gì → **chưa có segment** nào được tạo. Segment chỉ được cấp phát khi có dữ liệu thực sự.

### 2.3. Extent (Phần mở rộng)
- Là tập hợp các **data blocks liên tiếp** về mặt logic.
- Một extent **không thể trải dài qua nhiều datafiles** - nó chỉ nằm trong một datafile.
- Khi segment cần thêm không gian, Oracle cấp phát thêm một extent mới.

```
Segment (Table EMPLOYEES)
  ├── Extent 1: blocks 1-8 trong users01.dbf
  ├── Extent 2: blocks 9-16 trong users01.dbf
  └── Extent 3: blocks 1-8 trong users02.dbf   ← có thể ở datafile khác
```

### 2.4. Data Block (Khối dữ liệu)
- Đơn vị I/O nhỏ nhất của Oracle (Oracle đọc/ghi theo đơn vị block).
- Một block ánh xạ tới một hoặc nhiều **OS blocks** trên đĩa.
- Kích thước block được xác định bởi `DB_BLOCK_SIZE`.

---

## 3. Cấu trúc bên trong Data Block

```
┌─────────────────────────────┐
│         Block Header         │   ← Metadata: địa chỉ block, transaction info
├─────────────────────────────┤
│          Row Data            │   ← Dữ liệu thực tế (rows)
│          Row Data            │
│          Row Data            │
│          ...                 │
├─────────────────────────────┤
│          Free Space          │   ← Vùng trống để INSERT thêm
├─────────────────────────────┤
│    PCTFREE boundary line     │   ← Ranh giới: dưới đây dành cho UPDATE
└─────────────────────────────┘
```

**PCTFREE:** Phần trăm block được **giữ lại** cho các lệnh UPDATE (mở rộng row). Mặc định 10%.
- Ví dụ: Block 8KB, PCTFREE=10% → Khi đã INSERT đến 90% → block "đầy" với INSERT, nhưng 10% còn lại dành cho UPDATE.

---

## 4. Database Standard Block Size

| Thuộc tính | Mô tả |
|-----------|-------|
| **Tham số** | `DB_BLOCK_SIZE` |
| **Không thể thay đổi** | Sau khi tạo database, không thể sửa |
| **Giá trị hợp lệ** | 2K, 4K, 8K, 16K, 32K |
| **Phổ biến nhất** | 8K (8192 bytes) |
| **Điều kiện** | Phải là bội số của physical block size của OS |
| **32K** | Chỉ hỗ trợ trên nền tảng 64-bit |

```sql
-- Xem block size hiện tại
SHOW PARAMETER DB_BLOCK_SIZE
-- Hoặc:
SELECT VALUE FROM V$PARAMETER WHERE NAME = 'db_block_size';
```

> ℹ️ **Kích thước datafile tối đa phụ thuộc vào block size:**

| Block Size | Kích thước Datafile tối đa |
|-----------|---------------------------|
| 2K | 8 GB |
| 4K | 16 GB |
| **8K** | **32 GB** (phổ biến nhất) |
| 16K | 64 GB |
| 32K | 128 GB |

**Tablespace với block size khác chuẩn:**
- Có thể tạo tablespace với block size khác standard.
- Phải cấu hình **non-standard buffer cache**: `DB_8K_CACHE_SIZE`, `DB_16K_CACHE_SIZE`, ...

---

## 5. Cách dữ liệu được lưu trữ

```
Table (Logical)         Tablespace (Logical)        Data File (Physical)
┌─────────────┐        ┌──────────────────────┐    ┌─────────────────┐
│  Row 1      │──────▶ │  Segment EMPLOYEES   │    │  users01.dbf    │
│  Row 2      │        │    Extent 1          │───▶│    Block 1      │
│  Row 3      │        │      Block 1         │    │    Block 2      │
│  ...        │        │      Block 2         │    │    Block 3      │
└─────────────┘        │    Extent 2          │    │    ...          │
                       │      Block 3         │    └─────────────────┘
                       └──────────────────────┘
```

---

## 6. Các View tra cứu thông tin lưu trữ

| View | Mô tả |
|------|-------|
| `DBA_TABLESPACES` / `V$TABLESPACE` | Thông tin về tablespaces |
| `DBA_DATA_FILES` / `V$DATAFILE` | Thông tin về datafiles |
| `DBA_SEGMENTS` | Thông tin về segments (tables, indexes, ...) |
| `DBA_EXTENTS` | Thông tin về extents |
| `V$BH` | Thông tin về data blocks trong Buffer Cache |

```sql
-- Ví dụ: xem tất cả segments của user HR
SELECT SEGMENT_NAME, SEGMENT_TYPE, TABLESPACE_NAME,
       EXTENTS, BYTES/1024/1024 SIZE_MB
FROM DBA_SEGMENTS
WHERE OWNER = 'HR'
ORDER BY BYTES DESC;

-- Ví dụ: xem extents của bảng EMPLOYEES
SELECT EXTENT_ID, FILE_ID, BLOCK_ID, BYTES/1024 KB, BLOCKS
FROM DBA_EXTENTS
WHERE OWNER = 'HR'
AND SEGMENT_NAME = 'EMPLOYEES'
ORDER BY EXTENT_ID;
```

---

## 7. Tóm tắt bài học

1. **Cấu trúc logic:** Database → Tablespace → Segment → Extent → Data Block.
2. **Cấu trúc vật lý:** Database → Data File → OS Block.
3. **Ánh xạ:** Tablespace ↔ Data Files; Data Block ↔ OS Blocks.
4. **Segment** được tạo khi **INSERT** dữ liệu đầu tiên, không phải khi CREATE TABLE.
5. **Extent** không thể trải dài qua nhiều datafiles.
6. `DB_BLOCK_SIZE` không thể thay đổi sau khi tạo database; 8K là phổ biến nhất.
7. Kích thước block ảnh hưởng đến kích thước datafile tối đa (8K → max 32GB/datafile).

---

## 8. Câu hỏi ôn tập

**1. Bạn vừa chạy lệnh `CREATE TABLE test_table (id NUMBER)`. Ngay lúc đó có segment nào được tạo không? Khi nào segment mới được tạo?**
> **Trả lời:**
> - **Ngay lúc đó KHÔNG có segment nào được tạo** (nếu tính năng mặc định `DEFERRED_SEGMENT_CREATION = TRUE` đang được bật từ bản 11gR2 trở đi). Bảng chỉ được khai báo metadata trong Data Dictionary mà chưa chiếm dụng bất kỳ byte đĩa nào trong tablespace.
> - Segment chỉ thực sự được cấp phát (cấp extent đầu tiên) khi có **dòng dữ liệu đầu tiên được chèn vào** (`INSERT INTO test_table VALUES (1);`), hoặc khi người dùng chạy lệnh tạo bảng có mệnh đề ép buộc `SEGMENT CREATION IMMEDIATE`.

**2. Một extent có thể trải dài qua hai datafiles không?**
> **Trả lời:**
> **Hoàn toàn KHÔNG THỂ.**
> Theo định nghĩa cấu trúc vật lý của Oracle, một Extent là một tập hợp các **data blocks liên tiếp nhau về mặt vật lý nằm trên cùng một Datafile duy nhất**. Một Segment có thể gồm nhiều Extents nằm trên nhiều Datafiles khác nhau thuộc cùng Tablespace, nhưng từng Extent đơn lẻ thì không bao giờ được phép vắt ngang qua 2 Datafiles.

**3. `DB_BLOCK_SIZE = 4K`, vậy kích thước tối đa của một datafile là bao nhiêu?**
> **Trả lời:**
> Trong Smallfile Tablespace chuẩn (mặc định), một Datafile có thể chứa tối đa là **$2^{22} - 1 = 4,194,303$ blocks**.
> Khi `DB_BLOCK_SIZE = 4K` (4096 bytes):
> $$\text{Dung lượng tối đa} = 4,194,303 \times 4\text{ KB} \approx 16\text{ GB}$$
> (Nếu là 8KB block size thì tối đa là ~32GB; 16KB block size là ~64GB; 32KB block size là ~128GB).

**4. Khi nào bạn cần cấu hình `DB_16K_CACHE_SIZE`?**
> **Trả lời:**
> Bạn cần cấu hình tham số `DB_16K_CACHE_SIZE` khi database của bạn sử dụng **Non-Standard Block Size** (Kích thước block không chuẩn):
> - Giả sử kích thước block chuẩn toàn cục của database là `DB_BLOCK_SIZE = 8K`.
> - Nhưng bạn tạo một Tablespace đặc thù với kích thước block 16KB (`CREATE TABLESPACE ... BLOCKSIZE 16K;`) để phục vụ lưu trữ các bảng chứa cột LOB khổng lồ hoặc khối Data Warehouse lớn.
> - Khi đó, Oracle bắt buộc bạn phải cấp phát một vùng đệm riêng trong SGA có kích thước block tương ứng (`DB_16K_CACHE_SIZE > 0`) để nạp các block 16K này vào RAM, vì Buffer Cache mặc định chỉ chứa vừa các block 8K.

**5. `DBA_DATA_FILES` và `V$DATAFILE` khác nhau như thế nào?**
> **Trả lời:**
> - **`DBA_DATA_FILES` (Static Dictionary View):** Lấy dữ liệu từ Data Dictionary trong `SYSTEM` tablespace. Cho biết thông tin logic: tên tablespace (`TABLESPACE_NAME`), trạng thái Autoextend, kích thước logic tối đa. **Chỉ truy vấn được khi Database ở trạng thái OPEN**.
> - **`V$DATAFILE` (Dynamic Performance View):** Lấy thông tin trực tiếp từ **Control File** và RAM. Cho biết thông tin trạng thái vật lý cấp thấp: SCN checkpoint của file, trạng thái online/offline, lỗi media recovery. **Truy vấn được ngay từ khi Database ở trạng thái MOUNT** (hữu ích cho DBA chẩn đoán khi database bị lỗi không mở được).
> - Ngoài ra, `DBA_DATA_FILES` chỉ chứa các file dữ liệu vĩnh viễn (Permanent Datafiles), không chứa file tạm thời của TEMP Tablespace (TEMP files nằm ở `DBA_TEMP_FILES` hoặc `V$TEMPFILE`).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/32-cau-truc-luu-tru-database.md`
