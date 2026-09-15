---
title: 'Bài 29: Khái niệm Bộ nhớ Oracle Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/29-khai-niem-bo-nho-database.md
---

# Bài 29: Khái niệm Bộ nhớ Oracle Database

## Mục tiêu bài học
Trong bài học này, bạn sẽ hiểu và mô tả được:
- **Database Buffer Cache** (bộ đệm dữ liệu)
- **Shared Pool** (vùng nhớ chia sẻ)
- **Large Pool** (vùng nhớ lớn)
- **Redo Log Buffer** (bộ đệm redo log)
- Tác động của loại ứng dụng (**OLTP vs DSS**) đến việc cấu hình bộ nhớ.

---

## 1. Tổng quan kiến trúc bộ nhớ Oracle

Oracle Database sử dụng hai vùng bộ nhớ chính:

| Vùng nhớ | Viết tắt | Mô tả | Chia sẻ? |
|----------|---------|-------|---------|
| **System Global Area** | SGA | Vùng nhớ dùng chung cho toàn instance | ✅ Mọi user |
| **Program Global Area** | PGA | Vùng nhớ riêng cho từng server process | ❌ Riêng biệt |

```
Oracle Instance
├── SGA (chia sẻ toàn instance)
│   ├── Database Buffer Cache
│   ├── Shared Pool
│   │   ├── Library Cache
│   │   ├── Data Dictionary Cache
│   │   └── Result Cache
│   ├── Redo Log Buffer
│   ├── Large Pool
│   ├── Java Pool
│   └── Fixed SGA
└── PGA (riêng từng server process)
    ├── SQL Work Area
    └── Session Memory
```

---

## 2. Database Buffer Cache (Bộ đệm Dữ liệu)

> 💡 **Ý tưởng cốt lõi:** Đọc dữ liệu từ **RAM nhanh hơn ổ cứng rất nhiều**. Buffer Cache là "bộ nhớ đệm" giữ các data block đã đọc từ datafiles, để lần sau truy cập không phải đọc lại từ đĩa.

### 2.1. Cách hoạt động

```
Người dùng SELECT dữ liệu
        │
        ▼
Oracle kiểm tra Buffer Cache
        │
        ├── TÌM THẤY (Cache Hit) → Trả về từ RAM (nhanh!)
        │
        └── KHÔNG TÌM THẤY (Cache Miss) → Đọc từ Datafile → Lưu vào Buffer Cache → Trả về
```

### 2.2. Ba trạng thái của Buffer

| Trạng thái | Mô tả |
|-----------|-------|
| **Unused** (Chưa dùng) | Buffer trống, chưa chứa dữ liệu gì. |
| **Clean** (Sạch) | Chứa dữ liệu đọc từ datafile, **trùng khớp** với dữ liệu trên đĩa. |
| **Dirty** (Bẩn) | Chứa dữ liệu đã **bị thay đổi** (DML), chưa được ghi xuống đĩa. |

### 2.3. Quản lý bộ đệm

- **DBWn (Database Writer):** Ghi các dirty blocks xuống datafiles khi cần giải phóng bộ đệm.
- **LRU List (Least Recently Used):** Oracle theo dõi block nào ít được dùng nhất để giải phóng trước.
  - Đầu danh sách = **Hot blocks** (truy cập nhiều, giữ trong cache).
  - Cuối danh sách = **Cold blocks** (ít truy cập, có thể ghi xuống đĩa và giải phóng).

### 2.4. Tại sao Buffer Cache quan trọng?

```
Buffer Cache nhỏ → Cache Miss nhiều → Đọc từ đĩa nhiều → I/O cao → DB chậm
Buffer Cache lớn → Cache Hit nhiều → Đọc từ RAM → I/O thấp → DB nhanh
```

---

## 3. Shared Pool (Vùng nhớ Chia sẻ)

Shared Pool lưu trữ các thông tin được chia sẻ giữa tất cả người dùng:

### 3.1. Library Cache (Bộ đệm Thư viện)
- Lưu trữ: **SQL text** (câu SQL gốc), **parsed code** (mã đã phân tích cú pháp), và **execution plan** (kế hoạch thực thi).
- **Soft parse:** Câu SQL đã có trong Library Cache → tái sử dụng execution plan → nhanh.
- **Hard parse:** Câu SQL mới lần đầu → phải phân tích, tối ưu, tạo plan mới → tốn tài nguyên.

> 💡 **Mẹo tối ưu:** Dùng **bind variables** thay vì literal values để tái sử dụng execution plan.
> ```sql
> -- Không tốt (hard parse mỗi lần):
> SELECT * FROM employees WHERE id = 100;
> SELECT * FROM employees WHERE id = 101;
> 
> -- Tốt hơn (soft parse, dùng lại plan):
> SELECT * FROM employees WHERE id = :v_id;
> ```

### 3.2. Data Dictionary Cache (Bộ đệm Từ điển Dữ liệu)
- Lưu định nghĩa của bảng, cột, quyền hạn vào RAM.
- Mỗi khi Oracle cần kiểm tra cấu trúc bảng hay quyền user → tìm ở đây trước thay vì đọc từ SYSTEM tablespace.

### 3.3. Result Cache (Bộ đệm Kết quả)
- Lưu kết quả của các câu SQL và PL/SQL function thường xuyên chạy.
- Lần sau chạy câu SQL tương tự → trả kết quả ngay từ cache.

### 3.4. UGA (User Global Area)
- Lưu thông tin session khi Oracle dùng **Shared Server** (và khi Large Pool chưa được cấu hình).

---

## 4. Large Pool (Vùng nhớ Lớn)

Cung cấp bộ nhớ cho các thao tác cần **vùng nhớ lớn, tạm thời**:

| Mục đích | Mô tả |
|---------|-------|
| **RMAN I/O buffers** | RMAN dùng Large Pool để đọc/ghi backup nhanh hơn. |
| **UGA (Shared Server)** | Lưu session info khi dùng Shared Server (thay vì Shared Pool). |
| **Deferred inserts** | Bộ đệm cho các thao tác INSERT bị hoãn. |

> 💡 **Tại sao cần Large Pool riêng?** Nếu không có Large Pool, RMAN và Shared Server phải dùng Shared Pool → gây **phân mảnh (fragmentation)** và ảnh hưởng đến hiệu năng SQL. Cấu hình Large Pool giúp phân tách các loại bộ nhớ.

**Khuyến nghị:** Luôn cấu hình Large Pool cho môi trường production.

---

## 5. Redo Log Buffer (Bộ đệm Redo Log)

> 💡 **Redo Log là gì?** Là bản ghi lại mọi thay đổi xảy ra trong database, dùng để phục hồi database khi có sự cố.

### 5.1. Cơ chế

```
Người dùng thực hiện DML (INSERT/UPDATE/DELETE)
        │
        ▼
Oracle ghi thông tin thay đổi vào Redo Log Buffer (RAM)
        │
        ▼ (LGWR - Log Writer ghi xuống đĩa khi:)
Online Redo Log Files (Disk)
```

### 5.2. LGWR ghi xuống đĩa khi nào?

| Điều kiện | Mô tả |
|-----------|-------|
| **User COMMIT** | Người dùng commit transaction → LGWR ghi ngay. |
| **Mỗi 3 giây** | LGWR định kỳ ghi dù chưa có COMMIT. |
| **Buffer đầy 1/3** | Khi Redo Log Buffer đã 1/3 → LGWR ghi. |
| **Trước khi DBWn ghi** | Trước khi DBWn ghi dirty blocks xuống đĩa, LGWR phải ghi trước (Write-Ahead Logging). |

> 💡 **Write-Ahead Logging (WAL):** Redo log phải được ghi xuống đĩa **trước** data blocks. Đây là nguyên tắc đảm bảo tính toàn vẹn dữ liệu: nếu server crash sau COMMIT, Oracle có thể replay redo log để khôi phục transaction đã commit.

---

## 6. Ảnh hưởng của Loại Ứng dụng đến Cấu hình Bộ nhớ

### 6.1. OLTP (Online Transaction Processing)

**Đặc điểm:**
- Số lượng user **lớn** (hàng trăm, hàng nghìn).
- Mỗi transaction **nhỏ** (INSERT/UPDATE từng record).
- Query lấy **ít dữ liệu** (tra cứu theo ID, filter hẹp).

**Tác động đến bộ nhớ:**
- **Buffer Cache:** Cần đủ lớn để giữ các hot blocks thường xuyên truy cập.
- **Shared Pool:** Cần lớn vì nhiều user chia sẻ execution plans.
- **Redo Log Buffer:** Cần vừa đủ (nhiều COMMIT nhỏ).
- **PGA:** Mỗi user cần ít bộ nhớ.

### 6.2. DSS (Decision Support System) / Data Warehouse

**Đặc điểm:**
- Số lượng user **ít** (hàng chục).
- Query lấy **lượng lớn dữ liệu** (báo cáo, analytics, full table scan).
- Ít DML, chủ yếu là SELECT.

**Tác động đến bộ nhớ:**
- **Buffer Cache:** Ít quan trọng hơn (full scan không tái sử dụng buffer nhiều).
- **PGA (SQL Work Area):** **Rất quan trọng** - sort và hash join cần nhiều bộ nhớ.
- **Large Pool:** Quan trọng cho parallel query.

### 6.3. So sánh

| | OLTP | DSS |
|--|------|-----|
| Số user | Nhiều | Ít |
| Kích thước transaction | Nhỏ | Lớn |
| Buffer Cache | ★★★★ Quan trọng | ★★ Ít quan trọng |
| Shared Pool | ★★★★ Quan trọng | ★★ Ít quan trọng |
| PGA (Work Area) | ★★ Vừa | ★★★★★ Rất quan trọng |

---

## 7. Tóm tắt bài học

1. **SGA** là vùng nhớ chia sẻ toàn instance; **PGA** là vùng nhớ riêng từng process.
2. **Database Buffer Cache**: Cache data blocks từ datafiles → giảm I/O đĩa.
   - Ba trạng thái: **Unused**, **Clean**, **Dirty**. DBWn ghi dirty blocks.
3. **Shared Pool**: Gồm Library Cache (SQL plans), Data Dictionary Cache, Result Cache.
   - Soft parse (tái sử dụng plan) nhanh hơn Hard parse nhiều.
4. **Large Pool**: Cung cấp bộ nhớ lớn cho RMAN, Shared Server. **Nên cấu hình**.
5. **Redo Log Buffer**: Buffer tạm trước khi LGWR ghi xuống Online Redo Log files.
   - LGWR ghi khi: COMMIT, mỗi 3 giây, buffer 1/3 đầy, trước DBWn.
6. **OLTP** cần Buffer Cache và Shared Pool lớn; **DSS** cần PGA lớn.

---

## 8. Câu hỏi ôn tập

**1. Một data block đang ở trạng thái "Dirty" có nghĩa là gì? Process nào chịu trách nhiệm ghi nó xuống đĩa?**
> **Trả lời:**
> - Data block ở trạng thái **"Dirty"** (block bẩn) là block dữ liệu trong Database Buffer Cache trên RAM đã bị các câu lệnh DML (INSERT, UPDATE, DELETE) làm thay đổi nội dung nhưng **chưa được ghi đồng bộ xuống Datafile trên đĩa cứng**.
> - Tiến trình nền **DBWn (Database Writer)** là tiến trình duy nhất chịu trách nhiệm tìm các dirty blocks trong Buffer Cache và ghi chúng xuống Datafiles khi có Checkpoint xảy ra hoặc khi vùng nhớ đệm cần dọn chỗ trống.

**2. Sự khác biệt giữa "Soft Parse" và "Hard Parse" là gì? Tại sao nên tránh Hard Parse?**
> **Trả lời:**
> - **Soft Parse (Phân tích nhẹ):** Câu lệnh SQL vừa gửi vào giống hệt một câu lệnh đã từng chạy trước đó và Execution Plan (kế hoạch thực thi) của nó vẫn còn lưu trong Library Cache của Shared Pool. Oracle chỉ việc tái sử dụng lại kế hoạch có sẵn, tốn rất ít CPU.
> - **Hard Parse (Phân tích nặng):** Câu lệnh SQL gửi vào chưa từng xuất hiện (hoặc đã bị xóa khỏi cache). Oracle bắt buộc phải: kiểm tra cú pháp, kiểm tra quyền truy cập bảng/cột từ Data Dictionary, và bộ tối ưu hóa (Cost-Based Optimizer - CBO) phải tính toán hàng ngàn phương án để sinh ra Execution Plan mới.
> - **Tại sao nên tránh Hard Parse?** Hard Parse ngốn cực kỳ nhiều CPU và gây nghẽn nghiêm trọng các cơ chế khóa chốt vùng nhớ (Latch contention / Mutex contention trong Shared Pool), làm chậm toàn bộ hệ thống khi có hàng nghìn giao dịch đồng thời. Do đó, luôn luôn phải dùng **Bind Variables** (`WHERE id = :b1` thay vì `WHERE id = 101`).

**3. Tại sao Oracle cần ghi Redo Log **trước** khi DBWn ghi data blocks xuống đĩa?**
> **Trả lời:**
> Đây là nguyên tắc vàng **Write-Ahead Logging (WAL)**:
> - Ghi Redo Log là thao tác ghi tuần tự nối đuôi (Sequential Write) cực nhanh vào một file nhỏ.
> - Ghi Data Block của DBWn là thao tác ghi ngẫu nhiên (Random Write) rải rác trên nhiều file dữ liệu lớn, tốn nhiều thời gian.
> - Nếu cho phép DBWn ghi data block xuống đĩa trước mà chưa có Redo Log, lỡ server mất điện đột ngột ngay giữa chừng, data block trên đĩa sẽ bị hỏng nửa chừng (Fractured Block) và Oracle hoàn toàn không có thông tin nhật ký để khôi phục lại trạng thái nhất quán trước đó. Ghi Redo Log trước đảm bảo dù máy chủ có sập bất kỳ tích tắc nào, Oracle vẫn dùng Redo Log để phục hồi nguyên vẹn mọi dữ liệu đã commit.

**4. Nếu bạn quản lý một DB dùng cho hệ thống BI (Business Intelligence) với các báo cáo phức tạp, bạn nên ưu tiên tăng thành phần bộ nhớ nào?**
> **Trả lời:**
> Bạn nên ưu tiên tăng dung lượng vùng nhớ **PGA (Program Global Area)**, cụ thể là **`PGA_AGGREGATE_TARGET`** (hoặc `PGA_AGGREGATE_LIMIT`).
> Lý do: Các câu truy vấn báo cáo BI/Data Warehouse thường quét lượng dữ liệu khổng lồ và thực hiện các phép toán phức tạp: sắp xếp (`ORDER BY`, `SORT`), gom nhóm (`GROUP BY`), phép nối băm (`HASH JOIN`), tạo bảng tạm. Toàn bộ các thao tác này đều diễn ra trong PGA Work Area (Sort Area, Hash Area). Nếu PGA quá nhỏ, Oracle sẽ phải tràn dữ liệu xuống Temp Tablespace trên đĩa cứng (Disk Spill), làm câu truy vấn chạy chậm gấp hàng chục đến hàng trăm lần.

**5. Large Pool giúp gì cho hiệu năng của Shared Pool?**
> **Trả lời:**
> - **Large Pool** là vùng nhớ riêng chuyên cấp phát các khối bộ nhớ lớn (Large Chunks) cho các tác vụ đặc thù như: Bộ đệm sao lưu/phục hồi của **RMAN**, các tiến trình song song (**Parallel Execution Message Buffers**), và kiến trúc **Shared Server** (UGA).
> - Nếu không có Large Pool, các tác vụ nặng này sẽ buộc phải xin cấp phát bộ nhớ trực tiếp từ **Shared Pool**. Do kích thước cấp phát lớn, nó sẽ đẩy văng (aging out) các câu lệnh SQL và PL/SQL package đang được cache ra ngoài, gây phân mảnh Shared Pool và buộc hệ thống phải Hard Parse liên tục. Có Large Pool sẽ "cách ly" hoàn toàn các tác vụ này, giữ cho Shared Pool luôn ổn định và sạch sẽ.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/29-khai-niem-bo-nho-database.md`
