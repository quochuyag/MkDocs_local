---
title: 'Section 32 — Database Connection Optimization: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_32_database_connection_optimization_senior_guide.md
---

# Section 32 — Database Connection Optimization: Senior DBA Guide

**Nguồn:** Practice 34 (PDF gốc) + section_all guide + Oracle Net internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Với query trả về nhiều row, thời gian có thể bị chi phối bởi **số round-trip mạng × latency**, chứ không phải công việc trong DB. Client fetch một lô row (theo fetch size), xử lý, rồi xin lô tiếp — **mỗi vòng là một round-trip**, mỗi round-trip ăn một lần latency. 110,000 row với fetch size 15 = ~7,333 round-trip; cùng dữ liệu với fetch size 1000 = ~110 round-trip. Nếu latency 1ms, chênh lệch là ~7 giây thuần chờ mạng — không liên quan gì tới tốc độ đọc data của DB.

Connection optimization có **ba đòn bẩy độc lập**, mỗi cái sửa một nút thắt khác nhau:

```
1. FETCH SIZE (arraysize)  → giảm SỐ round-trip        (app-side, ROI cao nhất)
2. SDU                     → giảm số PACKET mỗi lần gửi (row lớn / transfer lớn)
3. SOCKET BUFFER (BDP)     → giữ pipe đầy trên mạng     (băng thông × latency cao)
```

Câu hỏi chẩn đoán: *chậm vì nhiều round-trip nhỏ (latency) hay vì đẩy nhiều data qua pipe hẹp (bandwidth)?* Round-trip → sửa fetch size. Bandwidth/BDP → sửa SDU + socket. Nhầm hai cái này là tune sai chỗ.

---

## 2. Internals & Mechanics

### Round-trip và fetch size

Một fetch cycle: client xin N row (N = arraysize/fetchSize) → server gửi N row trong **một message logic** (có thể trải nhiều packet SDU) → client xử lý → xin N tiếp. Số fetch call ≈ `CEIL(rows / arraysize)`. Trong tkprof, `count` của thao tác **Fetch** chính là con số này (Practice 34: 110k row / 15 ≈ 7,333; đổi arraysize 100 → ≈ 1,100).

- SQL*Plus `ARRAYSIZE` mặc định **15**.
- JDBC `setFetchSize` mặc định **10**.
- cx_Oracle/python-oracledb `arraysize` mặc định **100**.

Fetch size mặc định thấp là **nguyên nhân số 1** khiến kéo bulk data chậm — và sửa hoàn toàn ở phía ứng dụng, không cần đụng DB.

### SQL*Net wait events — đọc đúng

| Event | Nghĩa | Dùng để |
|---|---|---|
| `SQL*Net message to client` | Server gửi message cho client; **count = số round-trip** | Đếm round-trip; giảm khi tăng arraysize |
| `SQL*Net message from client` | Server **chờ** client gửi request tiếp | Phần lớn là **idle/think time** — đừng đuổi theo |
| `SQL*Net more data to client` | Một message logic **không vừa** một SDU → phải gửi thêm segment | SDU quá nhỏ so với khối gửi |
| `SQL*Net more data from client` | Tương tự chiều ngược (client gửi khối lớn: bind array, LOB) | SDU nhỏ cho insert lớn |

Bẫy kinh điển: thấy `SQL*Net message from client` chiếm phần lớn "DB time" rồi kết luận "mạng chậm" — sai. Đó chủ yếu là server **rảnh** chờ client (think time), không phải vấn đề mạng. Round-trip thể hiện ở **count** của `message to client`, không phải ở event `from client`.

### SDU — Session Data Unit

SDU là **buffer tầng ứng dụng** Oracle Net dùng để đóng gói data trước khi giao cho TCP. Mặc định 8192 byte (8KB); nâng được tới **2MB** (2097152) ở 12c+. SDU được **thương lượng** giữa client và server khi kết nối — giá trị dùng là **min của hai đầu**. Trong 10046 trace, dòng `nsconneg` cho biết SDU đã thương lượng.

- Đặt SDU client: `(SDU=524288)` trong descriptor `tnsnames.ora`, hoặc `DEFAULT_SDU_SIZE` trong `sqlnet.ora` client.
- Đặt SDU server: `DEFAULT_SDU_SIZE` trong `sqlnet.ora` server (hoặc `(SDU=...)` trong SID_LIST của listener).
- SDU lớn giúp khi mỗi message logic lớn (row rộng, transfer lớn) → ít packet hơn, ít `more data` hơn. Với OLTP row nhỏ, SDU gần như vô ích.

### Socket buffer — Bandwidth-Delay Product

TCP chỉ giữ được "pipe đầy" nếu socket buffer ≥ **BDP = bandwidth × RTT**. Nếu buffer nhỏ hơn BDP, TCP rơi vào stop-and-wait (gửi một cửa sổ rồi chờ ACK) → không tận dụng hết băng thông trên mạng latency cao.

```
BDP = bandwidth (bit/s) × latency (s)
SEND_BUF_SIZE = RECV_BUF_SIZE = BDP × 3   (3× headroom, công thức course)
Ví dụ: 1000 Mb/s × 0.001 s × 3 = 3,000,000 bit = 375,000 byte
```

Đặt trong `tnsnames.ora` (client) và `sqlnet.ora` (server): `SEND_BUF_SIZE` / `RECV_BUF_SIZE`. **Chỉ có ý nghĩa trên mạng BDP lớn** (WAN, băng thông cao + latency cao). Trên LAN latency <1ms, BDP nhỏ xíu → socket buffer mặc định đã đủ → chỉnh gần như vô tác dụng. Đây là lý do trên VM local, đòn bẩy này khó thấy hiệu quả (khác hẳn arraysize).

### Vì sao thay đổi cần restart listener

`DEFAULT_SDU_SIZE`, `SEND/RECV_BUF_SIZE` trong `sqlnet.ora` phía server được listener đọc khi thiết lập kết nối → sửa xong phải `lsnrctl reload`/restart + `ALTER SYSTEM REGISTER` để service đăng ký lại với cấu hình mới. Client-side (`tnsnames.ora`) có hiệu lực ở lần kết nối kế tiếp, không cần restart.

---

## 3. Production Realities

### Fetch size là ROI cao nhất và thường bị bỏ quên

90% ca "kéo report chậm qua mạng" sửa được bằng một dòng ở tầng app: tăng `fetchSize` (JDBC), `arraysize` (SQL*Plus/python), hoặc row prefetch. Không cần DBA, không restart, không đụng listener. Trước khi động vào SDU/socket, luôn hỏi: *ứng dụng đang fetch bao nhiêu row/lần?* Một batch job JDBC dùng fetchSize mặc định 10 kéo 1 triệu row = 100,000 round-trip.

### Đừng đuổi theo `SQL*Net message from client`

Trong AWR/ASH, `SQL*Net message from client` thường đứng đầu wait — nhưng nó là **idle wait** (server chờ client nghĩ/gửi tiếp). Tối ưu nó = tối ưu tốc độ ứng dụng/người dùng, không phải DB. Oracle xếp nó vào Idle wait class chính vì lý do này. Nút thắt round-trip thật sự nằm ở **count** của `message to client` và số fetch call trong tkprof.

### Arraysize quá lớn cũng có hại

Mỗi fetch cấp bộ nhớ client = `arraysize × kích thước row`. Đặt arraysize 10,000 cho query trả 5 row = lãng phí RAM client, không lợi. Với result set lớn, arraysize 100–1000 thường là điểm ngọt; trên đó lợi ích round-trip giảm dần (đường cong bão hòa) trong khi RAM client tăng tuyến tính.

### SDU/socket: đo BDP trước, đừng cargo-cult

Copy `SDU=524288, SEND_BUF_SIZE=375000` vào mọi tnsnames vì "thấy người ta làm" là anti-pattern. Trên LAN latency thấp, chúng không giúp gì mà còn tốn RAM cho mỗi kết nối (socket buffer × số session). Tính BDP thật của đường mạng (bandwidth × RTT đo bằng ping) rồi mới quyết định. SDU chỉ đáng nâng khi row rộng / transfer lớn và thấy `SQL*Net more data to client` cao.

### Shared server, connection pooling, DRCP

Practice 34 dùng dedicated server. Trên hệ tải cao, đòn bẩy connection lớn hơn nhiều là **connection pooling** (app-side) và **DRCP** (Database Resident Connection Pooling) — giảm chi phí tạo/hủy connection (mỗi connect mới tốn fork process dedicated, PGA, round-trip auth). `[⚠️ verify]` DRCP hợp với nhiều client short-lived (PHP/Python web) hơn là app server đã pool sẵn. Đây là mảng senior cần cân nhắc ngoài phạm vi Practice 34.

### Tracing connection: 10046 + nsconneg + tkprof

10046 level 12 bắt cả wait + bind. `nsconneg` trong trace = SDU thương lượng. tkprof `waits=yes` gộp SQL*Net waits theo thao tác. Đây là bộ công cụ chuẩn để **chứng minh** round-trip giảm sau khi tăng arraysize (fetch count trong tkprof đi từ ~7,333 xuống ~1,100).

---

## 4. Decision Framework

**Tăng fetch size (arraysize/fetchSize) khi:**
- Query trả nhiều row + nhiều round-trip (fetch count cao trong tkprof)
- Nút thắt là latency × số round-trip
- → Sửa app-side trước, ROI cao nhất, không cần restart

**Tăng SDU khi:**
- Row rộng / transfer lớn + `SQL*Net more data to/from client` cao
- Mỗi message logic tràn nhiều SDU packet
- → Sửa cả hai đầu (min của hai), restart listener

**Tăng socket buffer (SEND/RECV_BUF_SIZE) khi:**
- Mạng BDP lớn (bandwidth cao × latency cao, ví dụ WAN/DR replication)
- TCP không tận dụng hết băng thông
- → Đặt = BDP × 3; vô nghĩa trên LAN latency thấp

**KHÔNG làm khi:**
- Nút thắt là `SQL*Net message from client` (idle/think time) → không phải vấn đề mạng
- Result set nhỏ (OLTP lookup) → round-trip đã ít, SDU/socket không liên quan
- LAN latency thấp mà đi chỉnh socket buffer → tốn RAM, không lợi

**Anti-patterns:**
- Tune `SQL*Net message from client` tưởng là mạng chậm
- Cargo-cult SDU/socket vào mọi tnsnames không tính BDP
- Đặt arraysize khổng lồ cho query trả ít row → phí RAM client
- Bỏ qua fetch size (app-side) mà đi restart listener chỉnh SDU — sai thứ tự ưu tiên

---

## 5. Key SQL / Commands

```sql
-- 5.1 SQL*Net wait events cua phien (module TEST) — display_sqlnet
SELECT e.event, e.time_waited time_cs, e.total_waits, e.wait_class
FROM   v$session_event e JOIN v$session s ON e.sid = s.sid
WHERE  s.module = 'TEST' AND e.event LIKE 'SQL*Net%'
ORDER  BY e.time_waited;

-- 5.2 Round-trip + bytes cua session HIEN TAI (V$MYSTAT)
SELECT n.name, s.value
FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
WHERE  n.name IN ('SQL*Net roundtrips to/from client',
                  'bytes sent via SQL*Net to client',
                  'bytes received via SQL*Net from client');

-- 5.3 Do round-trip theo arraysize (AUTOTRACE — can PLUSTRACE role)
SET AUTOTRACE TRACEONLY STATISTICS
SET ARRAYSIZE 15
SELECT order_id, order_total, order_date FROM orders_conn WHERE order_id <= 110000;
SET ARRAYSIZE 1000
SELECT order_id, order_total, order_date FROM orders_conn WHERE order_id <= 110000;
SET AUTOTRACE OFF
-- Doc dong 'SQL*Net roundtrips to/from client' trong output moi lan

-- 5.4 Bat 10046 de lay SDU (nsconneg) + fetch count (tkprof)
ALTER SESSION SET EVENTS '10046 TRACE NAME CONTEXT FOREVER, LEVEL 12';
-- ... chay query ...
ALTER SESSION SET EVENTS '10046 TRACE NAME CONTEXT OFF';
SELECT p.tracefile FROM v$session s JOIN v$process p ON s.paddr = p.addr
WHERE  s.sid = SYS_CONTEXT('USERENV','SID');
-- OS:  grep nsconneg <tracefile>        (SDU da thuong luong)
--      tkprof <tracefile> out.log sys=no waits=yes   (Fetch count)

-- 5.5 SDU dang dung cho cac ket noi hien tai (12c+)
SELECT sid, network_service_banner FROM v$session_connect_info
WHERE  sid = SYS_CONTEXT('USERENV','SID');
```

Cấu hình (OS, phía server `$TNS_ADMIN/sqlnet.ora`):
```
DEFAULT_SDU_SIZE=524288
SEND_BUF_SIZE=375000
RECV_BUF_SIZE=375000
```
Client `tnsnames.ora` descriptor:
```
ORADB = (DESCRIPTION=(SDU=524288)(SEND_BUF_SIZE=375000)(RECV_BUF_SIZE=375000)
         (ADDRESS=(PROTOCOL=TCP)(HOST=...)(PORT=1521))
         (CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=ORADB...)))
```
Áp dụng: `lsnrctl stop && lsnrctl start` rồi `ALTER SYSTEM REGISTER;`

---

## 6. Senior Checklist

1. **Hỏi fetch size của ứng dụng trước tiên:** JDBC fetchSize (default 10), SQL*Plus ARRAYSIZE (15), python arraysize (100) — đây là ROI cao nhất, sửa app-side, không restart
2. **Phân biệt round-trip vs bandwidth:** nhiều fetch nhỏ trên latency → fetch size; đẩy khối lớn qua pipe → SDU/socket; đo tkprof fetch count + `SQL*Net more data` để biết
3. **Đừng tune `SQL*Net message from client`:** đó là idle/think time (server chờ client), không phải mạng chậm; nút thắt round-trip nằm ở count của `message to client`
4. **Tính BDP trước khi chỉnh socket buffer:** `bandwidth × RTT`; LAN latency thấp → BDP nhỏ → socket buffer vô nghĩa; chỉ đáng trên WAN/DR
5. **SDU chỉnh cả hai đầu (dùng min):** client `tnsnames`/`sqlnet.ora` + server `sqlnet.ora`; xác nhận bằng `nsconneg` trong 10046 trace; restart listener + `ALTER SYSTEM REGISTER`
6. **Đo bằng round-trip count, không bằng wall-clock:** cache/tải nhiễu thời gian; `SQL*Net roundtrips to/from client` (V$MYSTAT/autotrace) và fetch count (tkprof) là bằng chứng khách quan
7. **Cân nhắc pooling/DRCP cho tải cao:** ngoài Practice 34, chi phí tạo/hủy connection thường lớn hơn — connection pool app-side hoặc DRCP giảm fork process/PGA/round-trip auth

---

# LAB EXERCISES

## Exercise 1 — ARRAYSIZE và Số Round-trip: Đòn bẩy app-side

**Scenario:** Một batch job kéo 110,000 row qua SQL*Plus chạy chậm bất thường dù DB nhàn. Bạn nghi nút thắt là số round-trip mạng do fetch size mặc định, và muốn chứng minh trước khi đề xuất đổi cấu hình JDBC ở app.

**Tasks:**
1. Tạo `ORDERS_CONN` ~110,000 row (order_id, order_total, order_date).
2. `SET AUTOTRACE TRACEONLY STATISTICS`; chạy query trả toàn bộ row với `ARRAYSIZE 15`; ghi `SQL*Net roundtrips to/from client` và `bytes sent via SQL*Net to client`.
3. Lặp lại với `ARRAYSIZE 100` rồi `ARRAYSIZE 1000`.
4. Đối chiếu round-trip với công thức `CEIL(rows/arraysize)`.

**Expected Findings:**
- Round-trip ≈ CEIL(110000/arraysize): ~7,334 (15) → ~1,100 (100) → ~110 (1000).
- `bytes sent` gần như không đổi giữa các arraysize (cùng data), chỉ số round-trip đổi.
- Thời gian giảm rõ khi round-trip giảm (nếu có latency); trên VM local latency ~0 nên thời gian đổi ít nhưng round-trip đổi rõ.

**Debrief Questions:**
- Vì sao `bytes sent` không đổi nhưng thời gian có thể giảm mạnh khi tăng arraysize?
- Trên VM latency ~0, đo gì để thấy tác dụng của arraysize thay vì wall-clock?
- Arraysize 1000 tốt hơn 100 — vậy sao không đặt 100,000 luôn?

---

## Exercise 2 — SDU và Socket Buffer: Đo BDP, chứng minh bằng trace

**Scenario:** Sau khi tối ưu arraysize, team muốn "tối ưu nốt SDU và socket buffer như tài liệu". Bạn cần đo BDP thực của đường mạng để quyết định các thay đổi này có đáng không, và chứng minh SDU đã đổi bằng trace.

**Tasks:**
1. Đo bandwidth (`ethtool eth0 | grep Speed`) và latency (`ping`); tính BDP và socket size = BDP × 3.
2. Bật 10046 level 12 cho query; lấy tracefile; `grep nsconneg` để đọc SDU hiện tại (mặc định 8192).
3. Thêm `DEFAULT_SDU_SIZE=524288`, `SEND/RECV_BUF_SIZE` vào `sqlnet.ora` server + `tnsnames.ora` client; restart listener; `ALTER SYSTEM REGISTER`.
4. Kết nối lại, chạy query, lấy trace mới, `grep nsconneg` xác nhận SDU = 524288.
5. So round-trip/thời gian trước-sau; giải thích tại sao trên LAN thay đổi nhỏ.

**Expected Findings:**
- BDP trên LAN 1Gb/s × 1ms = 375,000 byte (nhưng latency thật thường <<1ms → BDP thực nhỏ hơn nhiều).
- `nsconneg` trước: 8192; sau: 524288.
- Round-trip/thời gian đổi **rất ít** trên LAN latency thấp — SDU/socket đúng lý thuyết nhưng không phải nút thắt ở đây.

**Debrief Questions:**
- Vì sao SDU tăng 64× mà thời gian gần như không đổi trên mạng này?
- Trên đường DR replication WAN (RTT 40ms, 10Gb/s) thì socket buffer BDP×3 quan trọng thế nào?
- SDU đặt 512KB ở client nhưng server vẫn 8192 → SDU thực tế dùng là bao nhiêu?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Một report Java (JDBC) kéo ~2 triệu row từ DB sang app server đặt ở data center khác (RTT ~35ms) mất **48 phút**. Cùng report chạy từ SQL Developer trên máy trong cùng data center với DB mất 3 phút. Team hạ tầng khẳng định "băng thông liên DC là 10 Gb/s, không nghẽn". DBA định tăng SDU và socket buffer trên listener. Bạn được gọi review trước khi đổi.

**Evidence Provided:**

AWR / ASH cho session report (48 phút):
```
Event                              Time(s)   %DB Time
SQL*Net message from client         2,510      88%
SQL*Net message to client              4       0.1%
DB CPU                                 95       3.3%
```

tkprof của session report:
```
call     count      cpu    elapsed   disk    query    rows
Fetch  200,001     22.1    2,730.5      0   410,882  2,000,000
```

Cấu hình JDBC (từ app team): `statement.setFetchSize()` — **không được set** (mặc định).
SDU hiện tại (nsconneg): 8192. Socket buffer: mặc định OS (~64KB).
Mạng: 10 Gb/s, RTT liên DC ~35ms đo bằng ping.

**Your Mission:**
1. DBA muốn tăng SDU + socket buffer. Đó có phải sửa đúng nút thắt không? Đọc bằng chứng để trả lời.
2. `SQL*Net message from client = 88% DB time` — điều này có nghĩa "mạng là thủ phạm" không? Giải thích đúng bản chất event này.
3. Từ tkprof: Fetch count = 200,001 cho 2M row. Suy ra fetch size hiện tại. Với RTT 35ms, ước lượng thời gian thuần round-trip.
4. Tính BDP liên DC và cho biết socket buffer mặc định có phải nút thắt không.
5. Đề xuất thứ tự fix + ước lượng cải thiện. Sau khi fix chính, SDU/socket còn đáng làm không?

**Evaluation Criteria:**
- Fetch size là gốc: Fetch count 200,001 ⇒ fetch size ≈ 2,000,000/200,000 = **10** (JDBC default). Với RTT 35ms, ~200,000 round-trip × 35ms = **7,000 giây ≈ 117 phút** thuần chờ mạng (thực tế 48 phút do overlap/pipelining nhưng đúng bậc độ lớn) → round-trip là nút thắt áp đảo.
- `SQL*Net message from client 88%`: đây là **idle wait** — server chờ client (app) xin lô tiếp giữa các fetch. Nó cao chính vì có **quá nhiều round-trip** (200k lần server chờ client). KHÔNG phải "mạng chậm" theo nghĩa bandwidth; là hệ quả của fetch size nhỏ. Tăng SDU/socket **không** giảm số round-trip.
- Fix đúng: đặt `statement.setFetchSize(1000)` (hoặc 2000) ở JDBC → fetch count từ 200,001 xuống ~2,000 → round-trip giảm 100× → thời gian chờ mạng từ ~117 phút xuống ~1-2 phút. Đây là fix app-side, không cần restart listener.
- BDP: 10 Gb/s × 0.035 s = 350,000,000 bit = ~43.75 MB. Socket buffer mặc định ~64KB **<< BDP** ⇒ trên đường WAN này socket buffer **thực sự là nút thắt bandwidth** cho transfer lớn — NHƯNG chỉ trở thành nút thắt sau khi đã sửa fetch size (khi đó mới đẩy khối lớn liên tục). Vậy socket buffer đáng làm, nhưng **sau** fetch size, không phải trước.
- Thứ tự: (1) `setFetchSize` ở app — thắng lớn nhất, làm ngay; (2) sau đó, vì BDP 43MB >> socket mặc định, **tăng SEND/RECV_BUF_SIZE lên ~130MB (BDP×3)** để tận dụng 10Gb/s cho các lô lớn; (3) SDU 512KB giúp ít hơn nhưng hợp lý cho row rộng. SDU/socket **có** đáng ở đây (khác Exercise 2 LAN) vì BDP liên DC lớn — nhưng vô ích nếu chưa sửa fetch size.
- **Bonus:** chỉ ra sai lầm của DBA là đảo thứ tự (chỉnh SDU/socket trước, restart listener gây gián đoạn, mà không đụng nút thắt chính là fetch size); và cảnh báo tăng socket buffer lên hàng chục MB × số session tốn RAM đáng kể — cân nhắc chỉ áp cho service report, không toàn instance.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_32_database_connection_optimization_senior_guide.md`
