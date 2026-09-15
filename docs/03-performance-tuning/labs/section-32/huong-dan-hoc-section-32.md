---
title: 📚 Hướng dẫn học Section 32 — Database Connection Optimization (thực hành trong VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_32/HUONG_DAN_HOC_SECTION_32.md
---

# 📚 Hướng dẫn học Section 32 — Database Connection Optimization (thực hành trong VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 34 + Oracle Net internals.
> Thời lượng gợi ý: ~75 phút (lecture 20' + lab 40' + debrief 15').
> Nguồn: Practice 34 (Ahmed Baraka) + [senior guide](../../section-all-new/section-32-database-connection-optimization-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

Query trả nhiều row: thời gian có thể bị chi phối bởi **số round-trip × latency**, không phải công việc DB. Client fetch một lô (fetch size) → xử lý → xin lô tiếp; **mỗi vòng = 1 round-trip = 1 latency**.

```
1. FETCH SIZE (arraysize) → giảm SỐ round-trip        ← app-side, ROI cao nhất
2. SDU                    → giảm số PACKET/lần gửi     ← row lớn / transfer lớn
3. SOCKET BUFFER (BDP)    → giữ pipe đầy trên WAN      ← bandwidth × latency lớn
```

- SQL*Plus `ARRAYSIZE` mặc định **15**; JDBC `fetchSize` **10** — thủ phạm số 1 kéo bulk chậm.
- `SQL*Net message from client` (thường cao) = **idle** (server chờ client) — KHÔNG phải mạng chậm.
- Round-trip thể hiện ở **count** `SQL*Net message to client` và fetch count trong tkprof.
- BDP = bandwidth × RTT; socket buffer chỉ đáng trên mạng BDP lớn (WAN), vô ích trên LAN.

**Chuỗi tư duy:** đo round-trip theo arraysize (đòn bẩy chính) → hiểu SQL*Net waits → SDU/socket là config phụ, đo BDP trước.

---

## 1. Khởi động (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
```
**Grant một lần** (SYS) cho AUTOTRACE:
```powershell
vagrant ssh
```
```bash
sudo -u oracle -i
sqlplus / as sysdba
```
```sql
GRANT PLUSTRACE TO soe;
-- Nếu role chưa tồn tại: @?/sqlplus/admin/plustrce.sql  rồi GRANT PLUSTRACE TO soe;
EXIT
```

---

## 2. Lab chính — ARRAYSIZE & round-trip (user `soe`, ~30 phút)

Có thể chạy từ host: `sqlplus soe/soe@//localhost:15210/ORADB` (hoặc trong VM port 1521).

### Bước 1 — Tạo bảng: `@01_setup.sql`

```sql
@01_setup.sql
```
Kỳ vọng: ORDERS_CONN 110,000 rows; dòng "PLUSTRACE co san" (nếu không có → grant lại).

### Bước 2 — Đo round-trip theo arraysize: `@02_workload.sql`

🤔 **Dự đoán:** 110,000 row với arraysize 15 → bao nhiêu round-trip? Với 1000 thì sao? `bytes sent` có đổi không?

```sql
@02_workload.sql
```

**Kỳ vọng — GHI 'SQL*Net roundtrips to/from client' mỗi lần:**

| ARRAYSIZE | round-trips ≈ CEIL(110000/arraysize) |
|---|---|
| 15 | ~7,334 |
| 100 | ~1,100 |
| 1000 | ~110 |

💡 `bytes sent via SQL*Net to client` **gần như không đổi** giữa 3 lần (cùng data) — chỉ số **round-trip** đổi. Arraysize giảm SỐ LẦN đi lại, không giảm lượng data.

### Bước 3 — SQL*Net waits + công thức: `@03_diagnose.sql`

🤔 **Dự đoán:** Trong SQL*Net waits, event nào là round-trip thật, event nào là idle (server chờ client)?

```sql
@03_diagnose.sql
```
| Bước | Kỳ vọng | Bài học |
|---|---|---|
| 1. V$MYSTAT | roundtrips + bytes | Số round-trip tích lũy của session |
| 2. display_sqlnet | `message from client` cao (idle!), `message to client` = round-trip | Đừng tune `from client` |
| 3. Công thức | CEIL(rows/arraysize) khớp số đo | Round-trip là hàm của fetch size |

---

## 3. Mở rộng — SDU & Socket buffer (trong VM, ~10 phút)

⚠️ Phần này sửa file cấu hình + restart listener. Trên LAN latency thấp, hiệu quả thời gian **rất ít** (đúng lý thuyết — BDP nhỏ).

```bash
# trong VM, user oracle
cd /labs/section_32
sqlplus soe/soe@//localhost:1521/ORADB
```
```sql
@04_usecase_sdu_socket.sql
```
Script bật 10046, cho tracefile. Ở OS:
```bash
grep nsconneg <tracefile>                    # SDU hiện tại (mặc định 8192)
tkprof <tracefile> out.log sys=no waits=yes  # Fetch count
ethtool eth0 | grep Speed                    # bandwidth
ping <db_host>                               # latency → tính BDP
```

**Config (theo Practice 34):**
- Server `$TNS_ADMIN/sqlnet.ora`: thêm `DEFAULT_SDU_SIZE=524288`, `SEND_BUF_SIZE=375000`, `RECV_BUF_SIZE=375000`.
- Client `tnsnames.ora`: thêm `(SDU=524288)(SEND_BUF_SIZE=375000)(RECV_BUF_SIZE=375000)` vào DESCRIPTION.
- Áp dụng: `lsnrctl stop && lsnrctl start`; rồi `sqlplus / as sysdba` → `ALTER SYSTEM REGISTER;`
- Kết nối lại, chạy lại query, `grep nsconneg` → kỳ vọng SDU = **524288**.

💡 SDU = **min của hai đầu** (client + server). Đặt 512KB một bên mà bên kia 8192 → dùng 8192.

---

## 4. Dọn dẹp (BẮT BUỘC)

```sql
@99_cleanup.sql
```
Nếu đã chạy 04: gỡ config khỏi `sqlnet.ora` + `tnsnames.ora`, `lsnrctl stop && lsnrctl start`, `ALTER SYSTEM REGISTER`. Hoặc `vagrant snapshot restore baseline`.

```powershell
vagrant halt
```

---

## 5. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Round-trip ≈ công thức nào? Vì sao `bytes sent` không đổi mà thời gian giảm khi tăng arraysize?
2. `SQL*Net message from client` chiếm 88% DB time — "mạng chậm"? Đây là event gì?
3. Ba đòn bẩy sửa nút thắt nào? Thứ tự ưu tiên?
4. BDP tính thế nào? Vì sao trên LAN chỉnh socket buffer gần như vô ích?
5. SDU 512KB client, server 8192 → SDU thực dùng?
6. Arraysize 1000 tốt hơn 100 — sao không đặt 100,000?

<details>
<summary>📖 Đáp án</summary>

1. Round-trip ≈ `CEIL(rows/arraysize)`. `bytes sent` không đổi vì cùng data. Thời gian giảm vì mỗi round-trip ăn 1 latency; ít round-trip → ít lần chờ latency (rõ nhất trên mạng latency cao).
2. **Không.** `SQL*Net message from client` là **idle wait** — server chờ client xin lô tiếp/nghĩ (think time). Oracle xếp vào Idle class. Nó cao vì có nhiều round-trip, nhưng bản thân nó không phải "mạng chậm". Nút thắt round-trip = count `message to client` + fetch count tkprof.
3. **arraysize** → giảm số round-trip (app-side, ROI cao nhất, không restart); **SDU** → giảm số packet/message khi row/transfer lớn (`more data` cao); **socket buffer** → giữ pipe đầy trên BDP lớn. Thứ tự: fetch size trước → SDU/socket sau (và chỉ khi BDP/row size biện minh).
4. BDP = bandwidth × RTT. Socket buffer cần ≥ BDP để TCP giữ pipe đầy. LAN latency <1ms → BDP nhỏ xíu → socket mặc định đã đủ → chỉnh vô ích (còn tốn RAM/session). Chỉ đáng trên WAN (RTT cao × bandwidth cao).
5. **8192** — SDU là min của hai đầu thương lượng (`nsconneg`). Đặt 512KB một bên vô nghĩa nếu bên kia còn 8192.
6. Mỗi fetch cấp RAM client = arraysize × row size. 100,000 cho query trả ít row = phí RAM. Lợi ích round-trip bão hòa dần (đường cong): 15→100 giảm mạnh, 1000→10000 giảm không đáng kể trong khi RAM tăng tuyến tính. Điểm ngọt thường 100–1000.

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `SP2-0618/0611: cannot find PLUSTRACE role` | SYS: `@?/sqlplus/admin/plustrce.sql` rồi `GRANT PLUSTRACE TO soe;` |
| AUTOTRACE không hiện roundtrips | Thiếu quyền v$; grant PLUSTRACE (gồm SELECT các v$ cần) cho soe |
| `nsconneg` không thấy trong trace | Trace level thấp → 10046 LEVEL 12; hoặc set `TRACE_LEVEL_SERVER=16` sqlnet.ora |
| SDU không đổi sau config | Chưa restart listener / chưa `ALTER SYSTEM REGISTER`; hoặc bên còn lại vẫn 8192 |
| Thời gian không giảm khi tăng arraysize | VM latency ~0 → đo **round-trip count** (autotrace) thay vì wall-clock |
| `SP2-0310` không mở `display_sqlnet.sql` | Đứng đúng `labs/section_32/` (hoặc `/labs/section_32`) |

---

## 7. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt` (gỡ config sqlnet/tnsnames nếu đã chạy 04)
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi số đo thật
- [ ] Buổi kế tiếp: Section 34 (OS Performance — Linux, OSWatcher)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_32/HUONG_DAN_HOC_SECTION_32.md`
