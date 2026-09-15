---
title: Section 32 — Database Connection Optimization
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_32_database_connection_optimization_guide.md
---

# Section 32 — Database Connection Optimization

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 34  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 32

Section 32 tối ưu hóa **Oracle Net (SQL*Net) connection** — lớp mạng giữa client và database server. Ba yếu tố chính: **SDU size** (kích thước packet), **socket buffer size**, và **ARRAYSIZE** (số rows fetch mỗi lần). Tối ưu ba yếu tố này giảm số round-trips mạng và tăng throughput.

---

## Kiến thức nền tảng

### Luồng dữ liệu khi fetch query

```
Client (SQL*Plus / JDBC / App)
       │
       │  ← Oracle Net (TCP/IP) →
       │
  Listener (port 1521)
       │
  Server Process (Dedicated)
       │
  Buffer Cache → Query Result
```

**Khi query trả về 100,000 rows:**

```
Với ARRAYSIZE=15 (mặc định):
Round-trip 1: gửi query
Round-trip 2: nhận rows 1-15
Round-trip 3: nhận rows 16-30
...
Round-trip 6668: nhận rows cuối
→ ~6,667 fetch operations!

Với ARRAYSIZE=100:
Round-trip 1: gửi query
Round-trip 2: nhận rows 1-100
...
Round-trip 1001: nhận rows cuối
→ ~1,000 fetch operations (6.7x ít hơn)
```

**Mỗi round-trip = một lần network I/O** → ARRAYSIZE lớn hơn = ít network I/O = query nhanh hơn.

---

## Ba tham số tối ưu hóa

### 1. SDU (Session Data Unit)

**SDU là gì:**  
Kích thước đơn vị dữ liệu mỗi Oracle Net packet. Tương tự MTU trong networking.

| Giá trị | Ý nghĩa |
|---------|---------|
| Default | 8 KB (8,192 bytes) |
| Tối đa | 2 MB (2,097,152 bytes) |
| Khuyến nghị | 512 KB cho bulk data retrieval |

**Tác động:**
- SDU nhỏ → nhiều packets để truyền cùng một lượng data → nhiều overhead
- SDU lớn → ít packets → ít overhead khi truyền lượng lớn data

**Cấu hình SDU:**

```ini
# tnsnames.ora (phía client) — trong connection descriptor
ORADB =
  (DESCRIPTION =
   (SDU=524288)                         ← 512 KB
   (SEND_BUF_SIZE=375000)
   (RECV_BUF_SIZE=375000)
    (ADDRESS = (PROTOCOL=TCP)(HOST=192.168.1.159)(PORT=1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORADB.localdomain)
    ))
```

```ini
# sqlnet.ora (phía server) — áp dụng cho tất cả kết nối
DEFAULT_SDU_SIZE=524288    ← 512 KB
SEND_BUF_SIZE=375000
RECV_BUF_SIZE=375000
```

**Verify SDU đang dùng:**

```bash
# Bật trace để xem SDU negotiation
# sqlnet.ora:
TRACE_LEVEL_SERVER=16

# Sau khi connect, xem trace file
cat <trace_file> | grep nsconneg
# Sẽ thấy dòng như: nsconneg: sdu=524288
```

---

### 2. Socket Buffer Size (SEND_BUF_SIZE / RECV_BUF_SIZE)

**Socket buffer là gì:**  
OS-level buffer cho TCP socket. Lớn hơn → network stack có thể gửi/nhận nhiều data hơn trước khi cần xác nhận (ACK) → giảm waiting.

**Công thức tính kích thước tối ưu:**

```
Recommended socket size = Bandwidth × Latency × 3

Ví dụ:
- Bandwidth  = 1000 Mb/s = 1,000,000,000 bits/s
- Latency    = 1 ms = 0.001 s
- Factor     = 3 (để buffer cho burst traffic)

Recommended = 1,000,000,000 × 0.001 × 3 = 3,000,000 bits
            = 3,000,000 / 8 bytes
            = 375,000 bytes
```

**Cách xác định bandwidth và latency:**

```bash
# Xem bandwidth của network adapter (server side)
ethtool eth0 | grep Speed
# Speed: 1000Mb/s

# Xem latency từ client tới server
ping -l 9000 <server_ip>        # Windows
ping -s 9000 <server_ip>        # Linux
tracert -4 <server_ip>          # Windows traceroute
```

---

### 3. ARRAYSIZE (Batch Fetch Size)

**ARRAYSIZE là gì:**  
Số rows được Oracle Net fetch về phía client trong một round-trip. Còn gọi là **row prefetch size** hay **fetch size**.

| Tool | Tham số |
|------|---------|
| SQL*Plus | `SET ARRAYSIZE <n>` (default: 15) |
| JDBC | `oracle.jdbc.defaultRowPrefetch` (default: 10) |
| ODP.NET | `FetchSize` |
| Python (cx_Oracle) | `cursor.arraysize` (default: 100) |

**Trong SQL*Plus:**

```sql
-- Xem giá trị hiện tại
SHOW ARRAYSIZE
-- arraysize 15  (default)

-- Thay đổi trước khi chạy query
SET ARRAYSIZE 100

-- Sau đó chạy query
SELECT ORDER_ID, ORDER_TOTAL, ORDER_DATE
FROM ORDERS
WHERE ORDER_ID <= 110000;
```

**Tác động trong tkprof:**

```
-- Với ARRAYSIZE=15:
FETCH count=6667  → gần (110,000 / 15) = 7,333 lần fetch

-- Với ARRAYSIZE=100:
FETCH count=1000  → gần (110,000 / 100) = 1,100 lần fetch
→ SQL*Net message to client giảm đáng kể
```

---

## Monitoring SQL*Net Wait Events

### V$SESSION_EVENT — SQL*Net events của session

```sql
-- Script display_sqlnet.sql — xem SQL*Net waits của sessions module='TEST'
COL EVENT     FORMAT A30
COL WAIT_CLASS FORMAT A10

SELECT E.EVENT,
       TIME_WAITED  TIME_CS,
       E.WAIT_CLASS
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID
  AND S.MODULE = 'TEST'
  AND E.EVENT LIKE 'SQL*Net%'
ORDER BY TIME_WAITED;
```

**Các SQL*Net wait events chính:**

| Event | Ý nghĩa | Dấu hiệu vấn đề |
|-------|---------|----------------|
| `SQL*Net message to client` | Server gửi data cho client | Cao → network bottleneck hoặc ARRAYSIZE nhỏ |
| `SQL*Net message from client` | Server chờ request từ client | Cao → client processing chậm (bình thường trong OLTP) |
| `SQL*Net more data to client` | Gửi tiếp data (packet chưa đủ) | Cao → SDU quá nhỏ |
| `SQL*Net more data from client` | Nhận tiếp data từ client | Cao → query/data gửi lên lớn |

**So sánh trước và sau tối ưu:**

```
Trước (ARRAYSIZE=15, SDU=8KB):
  SQL*Net message to client: TIME_CS = 450 (cao)

Sau (ARRAYSIZE=100, SDU=512KB):
  SQL*Net message to client: TIME_CS = 80  (giảm ~80%)
```

---

## Phân tích với tkprof

### Bật SQL Trace

```sql
-- Bật event tracing level 12 (bao gồm wait events)
EXEC DBMS_APPLICATION_INFO.SET_MODULE('TEST', 'TEST');
ALTER SESSION SET EVENTS '10046 TRACE NAME CONTEXT FOREVER, LEVEL 12';

-- Chạy query
SELECT ORDER_ID, ORDER_TOTAL, ORDER_DATE
FROM ORDERS
WHERE ORDER_ID <= 110000;

-- Tắt trace
ALTER SESSION SET EVENTS '10046 TRACE NAME CONTEXT OFF';

-- Lấy trace file path
SELECT P.TRACEFILE
FROM V$SESSION S
JOIN V$PROCESS P ON S.PADDR = P.ADDR
WHERE S.USERNAME = 'SOE';
```

### Phân tích bằng tkprof

```bash
# Convert trace file thành readable format
tkprof <trace_file> output.log SYS=no waits=yes

# Mở và xem
vi output.log
```

**Đọc kết quả tkprof:**

```
SELECT ORDER_ID, ORDER_TOTAL, ORDER_DATE FROM ORDERS WHERE ORDER_ID <=110000

call     count       cpu    elapsed       disk      query    current        rows
------- ------  -------- ---------- ---------- ---------- ----------  ----------
Parse        1      0.00       0.00          0          0          0           0
Execute      1      0.00       0.00          0          0          0           0
Fetch     6667      1.23       3.45          0      12500          0      100000
------- ------  -------- ---------- ---------- ---------- ----------  ----------

Elapsed times include waiting on following events:
  Event waited on                             Times   Max. Wait  Total Waited
  ----------------------------------------   Waited  ----------  ------------
  SQL*Net message to client                    6667        0.00          0.45
  SQL*Net message from client                  6667        0.00          0.01
```

**Phân tích:**
- `Fetch count = 6667` → gần 100,000 / 15 = 6,667 (ARRAYSIZE=15)
- Sau tối ưu: `Fetch count = 1000` → gần 100,000 / 100 = 1,000 (ARRAYSIZE=100)

---

## Quy trình tối ưu hóa kết nối

```
1. Baseline
   - Ghi elapsed time query trước khi tối ưu
   - Chạy display_sqlnet.sql để ghi SQL*Net wait events
   - Phân tích tkprof: xem fetch count
       ↓
2. Đo network
   - Bandwidth: ethtool eth0 | grep Speed
   - Latency: ping <server_ip>
       ↓
3. Tính socket buffer size
   - socket_size = bandwidth(b/s) × latency(s) × 3 ÷ 8
       ↓
4. Cập nhật tnsnames.ora (client)
   - Thêm SDU=524288, SEND_BUF_SIZE=..., RECV_BUF_SIZE=...
       ↓
5. Cập nhật sqlnet.ora (server)
   - DEFAULT_SDU_SIZE=524288
   - SEND_BUF_SIZE=..., RECV_BUF_SIZE=...
       ↓
6. Restart listener + register service
   - lsnrctl stop && lsnrctl start
   - ALTER SYSTEM REGISTER;
       ↓
7. Tăng ARRAYSIZE trong application
   - SET ARRAYSIZE 100 (SQL*Plus)
   - Tương đương trong JDBC/ODP.NET/cx_Oracle
       ↓
8. Verify và so sánh
   - Elapsed time mới vs baseline
   - SQL*Net wait events: thấp hơn
   - tkprof: fetch count giảm
```

---

## Connection Architecture — Dedicated vs Shared Server

### Dedicated Server (mặc định)

```
Client App → Listener → Tạo 1 Server Process riêng cho client
                                     ↕
                                Database (SGA, PGA)
```

- Mỗi client có **1 server process riêng**
- PGA riêng → phù hợp cho complex queries, sort, hash join
- Nhiều concurrent connections → nhiều processes → tốn RAM

### Shared Server (MTS — Multi-Threaded Server)

```
Client App → Listener → Dispatcher → Request Queue → Shared Server Pool
                                                              ↕
                                                          Database (SGA)
```

- Nhiều clients **chia sẻ** một pool server processes
- Phù hợp khi có rất nhiều concurrent connections ít hoạt động
- Session context lưu trong SGA (không phải PGA riêng)

### Database Resident Connection Pooling (DRCP)

```
App → Connection Pool Broker → Pre-spawned Server Process Pool
                                          ↕
                                       Database
```

- Pool server processes được duy trì sẵn trong database
- Phù hợp cho web applications với connection/release nhanh (PHP, CGI)
- Cấu hình: `DBMS_CONNECTION_POOL.START_POOL()`

---

## Tóm tắt Parameters & Views

| Parameter/View | Dùng để |
|---------------|---------|
| `ARRAYSIZE` (SQL*Plus) | Số rows mỗi fetch — default 15, tăng lên 100+ |
| `SDU` trong tnsnames.ora | Kích thước Oracle Net packet (client side) |
| `DEFAULT_SDU_SIZE` trong sqlnet.ora | SDU mặc định (server side) |
| `SEND_BUF_SIZE`, `RECV_BUF_SIZE` | OS socket buffer size |
| `TRACE_LEVEL_SERVER=16` trong sqlnet.ora | Bật Oracle Net tracing |
| `V$SESSION_EVENT` — `SQL*Net%` events | Monitor SQL*Net wait time |
| `tkprof` | Phân tích trace file: fetch count, elapsed, waits |
| `grep nsconneg <trace_file>` | Xem SDU size thực tế đang dùng |
| `ethtool eth0 | grep Speed` | Xem bandwidth network adapter |
| `ALTER SYSTEM REGISTER` | Đăng ký service với listener sau khi restart |

---

## Câu hỏi ôn tập

1. `ARRAYSIZE` trong SQL*Plus là gì? Tại sao tăng ARRAYSIZE lại giảm số lần fetch và `SQL*Net message to client`?
2. SDU (Session Data Unit) là gì? Phải cấu hình SDU ở những file nào để có hiệu lực?
3. Công thức tính recommended socket buffer size là gì? Cần đo những thông số nào?
4. Sự khác biệt giữa `SQL*Net message to client` và `SQL*Net message from client` — cái nào thường là vấn đề cần tối ưu?
5. Sau khi thay đổi `sqlnet.ora` và `tnsnames.ora`, cần làm gì để listener nhận cấu hình mới?
6. `TRACE_LEVEL_SERVER=16` trong `sqlnet.ora` dùng để làm gì? Lệnh nào để xem SDU đang thực sự được sử dụng?
7. Trong tkprof output, `Fetch count = 6667` với query 100,000 rows — giá trị ARRAYSIZE đang là bao nhiêu? Tính như thế nào?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_32_database_connection_optimization_guide.md`
