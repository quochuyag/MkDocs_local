---
title: Section 8 — Instance Activity & Wait Events — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_8_instance_activity_wait_events_senior_guide.md
---

# Section 8 — Instance Activity & Wait Events — Deep Dive for Senior DBA

---

# OUTPUT 1 — LECTURE NOTES

## 1. Mental Model

Oracle's wait interface là một profiler nhúng trực tiếp vào kernel — không phải logging add-on, mà là inline instrumentation trong mọi code path của Oracle server process. Mỗi khi một process không thể tiếp tục ngay lập tức — chờ latch, I/O completion, lock, network — Oracle ghi lại trong **session state object** (ksuseond) trong SGA. Toàn bộ hệ sinh thái chẩn đoán của Oracle (ASH, AWR, ADDM) đều là các lớp aggregation và persistence bên trên wait interface này. Hiểu Section 8 là hiểu nền tảng của mọi thứ phía trên.

---

## 2. Internals & Mechanics

### Wait Event Lifecycle trong Oracle Kernel

Khi một session bắt đầu wait:
1. Oracle gọi **`ksewtsw`** (kernel service event wait set wait) — ghi event name, class, P1/P2/P3 parameters vào session state object, set `STATE = 'WAITING'`, bắt đầu timer
2. `V$SESSION` phản ánh ngay lập tức: `WAIT_TIME = 0`, `SECONDS_IN_WAIT` đếm real-time
3. `V$SESSION_WAIT` cập nhật đồng thời với V$SESSION (trên Oracle 12c về sau, V$SESSION đã bao gồm hầu hết columns của V$SESSION_WAIT)

Khi wait kết thúc:
1. Oracle gọi **`ksewtef`** (event finish) — tính elapsed time, cộng vào `V$SESSION_EVENT.TIME_WAITED`
2. Event được đẩy vào **V$SESSION_WAIT_HISTORY** — ring buffer 10 entries/session, circular overwrite
3. `V$SYSTEM_EVENT` được increment tương ứng (aggregate toàn instance)

### Activity Statistics — Cơ chế khác biệt

V$SYSSTAT/V$SESSTAT là **operation counters**, hoàn toàn tách biệt khỏi wait infrastructure:
- Mỗi statistic có `STATISTIC#` cố định trong một phiên bản Oracle — nhưng **numbering thay đổi giữa các versions**. Script hardcode STATISTIC# sẽ sai khi upgrade
- `CLASS` column là **bitmap**: CLASS=40 có nghĩa là Cache (8) + RAC (32). Một statistic có thể thuộc nhiều class đồng thời

| CLASS value | Bit meaning |
|-------------|-------------|
| 1 | User |
| 2 | Redo |
| 4 | Enqueue |
| 8 | Cache |
| 16 | OS |
| 32 | RAC |
| 64 | SQL |
| 128 | Debug |

- Các counter này nằm trong SGA memory (không phải disk), đọc bằng fixed table scan — trên hệ thống nhiều CPU, có latch contention khi nhiều session update cùng bucket

### V$MYSTAT — Tại sao tồn tại

V$MYSTAT không cần SYS privilege hay SID lookup: nó map trực tiếp vào session state object của **calling process**. Hữu ích khi DBA hoặc developer muốn đo overhead của một đoạn PL/SQL cụ thể trong session họ đang dùng mà không cần quyền truy cập toàn bộ V$SESSTAT.

---

## 3. Production Realities

**TIME_WAITED đơn vị centiseconds** — không phải milliseconds. Divide by 100 để ra seconds. Lỗi này xuất hiện thường xuyên trong custom monitoring script của các team internal. Kết quả: số "seconds" bị inflate 10x, tạo alert giả.

**V$SESSION_EVENT mất khi session disconnect** — đây là limitation nghiêm trọng nhất của Section 8. Khi user báo cáo ứng dụng chậm lúc 14:00, đến 15:00 mới có DBA nhìn vào thì session đã disconnect. Post-mortem yêu cầu ASH (`V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_ACTIVE_SESS_HISTORY`) — fixed-size ring buffer capture mỗi giây, persistent qua AWR snapshot.

**V$SESSION_WAIT_HISTORY giới hạn 10 events** — trong một OLTP transaction processing hàng trăm waits/giây, ring buffer overwrite liên tục. View này chỉ hữu ích trong môi trường controlled test hoặc khi investigating session có throughput thấp. Đừng dựa vào nó cho high-concurrency forensics.

**V$SYSTEM_EVENT không có context** — cumulative từ instance startup. Hệ thống chạy 6 tháng với value cao trong `log file sync` không nói lên điều gì nếu không có baseline. AWR delta (chênh lệch giữa 2 snapshot) mới là số có ý nghĩa. Đây là lý do AWR (Section 9) là công cụ thực tế, còn Section 8 là foundation để hiểu AWR nói về cái gì.

**Idle wait class là noise** — `SQL*Net message from client`, `pipe get`, `Space Manager: slave idle wait`... Nếu không filter `WAIT_CLASS <> 'Idle'`, các events này thường chiếm 90%+ total wait time và che khuất vấn đề thật. Luôn exclude.

**`db file parallel write` là DBWR wait** — xuất hiện trong `V$SYSTEM_EVENT` với value cao nhưng là background process wait, không phải user session. Đừng trigger alert vì event này đơn độc; chỉ đáng lo khi kết hợp với user-facing I/O waits cao đồng thời.

**V$SESSION.P1/P2/P3 — không universal** — mỗi wait event có parameter semantics riêng. `enq: TX - row lock contention`: P1=lock type (TX), P2=mode, P3=0. `db file sequential read`: P1=file#, P2=block#, P3=blocks. Không có cách generic đọc P1/P2/P3; phải tra Oracle Reference Appendix C theo từng event.

---

## 4. Decision Framework

### Chọn View theo tình huống

| Tình huống | View nên dùng | Lý do |
|-----------|---------------|-------|
| Database chậm, không biết category nào | `V$SYSTEM_WAIT_CLASS` | Macro view, loại bỏ noise nhanh |
| Xác định event cụ thể chiếm nhiều nhất | `V$SYSTEM_EVENT` | Granular, sort by TIME_WAITED |
| Session cụ thể bị chậm — historical | `V$SESSION_EVENT` | Accumulated since logon |
| Session đang bị treo ngay bây giờ | `V$SESSION` (STATE='WAITING') | Real-time, có P1/P2/P3 |
| Muốn xem 10 waits vừa rồi của session | `V$SESSION_WAIT_HISTORY` | Chỉ useful khi session còn connected |
| Post-mortem sau khi session đã disconnect | `V$ACTIVE_SESSION_HISTORY` | 1-second sampling, ring buffer |
| Phân tích xu hướng theo thời gian | `DBA_HIST_SYSTEM_EVENT` (AWR) | Delta giữa snapshots |

### Anti-patterns

- **❌ SELECT * FROM V$SYSSTAT trên production** — hàng trăm rows, shared pool latch contention, làm chậm system đang điều tra
- **❌ Dùng V$SESSION_WAIT_HISTORY cho OLTP forensics** — ring buffer 10 events bị overwrite trong mili-giây
- **❌ Report V$SYSTEM_EVENT values mà không so baseline** — số tuyệt đối vô nghĩa nếu không có context time window
- **❌ Trust duy nhất một view** — V$SESSION (real-time) và V$SESSION_EVENT (accumulated) bổ sung nhau, không thay thế nhau

---

## 5. Key SQL / Commands

### Blocking Chain — Tìm ai đang block ai

```sql
-- Identify blocker/waiter relationships với wait event details
SELECT
    w.SID                           waiter_sid,
    w.USERNAME                      waiter,
    w.EVENT                         wait_event,
    w.SECONDS_IN_WAIT               secs_waiting,
    b.SID                           blocker_sid,
    b.USERNAME                      blocker,
    b.STATUS                        blocker_status,
    b.SQL_ID                        blocker_sql_id
FROM V$SESSION w
JOIN V$SESSION b ON w.BLOCKING_SESSION = b.SID
WHERE w.BLOCKING_SESSION IS NOT NULL
ORDER BY w.SECONDS_IN_WAIT DESC;
```

> `BLOCKING_SESSION` column available từ Oracle 10gR2. Trước đó phải decode P1/P2 của enqueue events để tìm blocker thủ công.

### Top Wait Events với % breakdown — System level

```sql
-- Non-idle waits, percentage distribution
SELECT
    EVENT,
    WAIT_CLASS,
    TO_CHAR(ROUND(TIME_WAITED/100), '999,999,999')          time_sec,
    ROUND(RATIO_TO_REPORT(TIME_WAITED) OVER () * 100, 1)    pct_total,
    TOTAL_WAITS,
    ROUND(AVERAGE_WAIT/100, 3)                              avg_wait_sec
FROM V$SYSTEM_EVENT
WHERE WAIT_CLASS <> 'Idle'
  AND TIME_WAITED > 0
ORDER BY TIME_WAITED DESC
FETCH FIRST 15 ROWS ONLY;
```

### Session-level drill-down — waits + current SQL

```sql
-- Sessions với top accumulated wait time, kèm SQL đang chạy
SELECT
    s.SID,
    s.SERIAL#,
    s.USERNAME,
    s.STATUS,
    s.EVENT                                                  current_event,
    s.SECONDS_IN_WAIT,
    s.WAIT_CLASS,
    e.TIME_WAITED_MICRO / 1e6                               total_wait_sec,
    e.TOTAL_WAITS,
    SUBSTR(q.SQL_TEXT, 1, 60)                               sql_text
FROM V$SESSION s
JOIN V$SESSION_EVENT e ON s.SID = e.SID AND s.EVENT = e.EVENT
LEFT JOIN V$SQL q ON s.SQL_ID = q.SQL_ID
WHERE s.USERNAME IS NOT NULL
  AND e.WAIT_CLASS <> 'Idle'
  AND e.TIME_WAITED > 0
ORDER BY e.TIME_WAITED DESC
FETCH FIRST 20 ROWS ONLY;
```

> `TIME_WAITED_MICRO` (microseconds) xuất hiện từ Oracle 10g — precision tốt hơn `TIME_WAITED` (centiseconds). Dùng khi cần độ chính xác cao hơn.

### Delta statistics — so sánh 2 thời điểm (technique nền tảng cho AWR)

```sql
-- Snapshot thủ công V$SYSSTAT trước/sau workload
-- T1:
CREATE TABLE sysstat_snap AS
SELECT NAME, VALUE snap1_value, SYSDATE snap1_time
FROM V$SYSSTAT WHERE NAME IN (
    'table scans (long tables)',
    'table scans (short tables)',
    'physical reads',
    'physical writes',
    'parse count (hard)',
    'execute count',
    'user commits',
    'user rollbacks'
);

-- T2 (sau workload):
SELECT t.NAME,
       s.VALUE - t.SNAP1_VALUE                        delta,
       ROUND((s.VALUE - t.SNAP1_VALUE) /
             GREATEST((SYSDATE - t.SNAP1_TIME)*86400, 1), 2) per_sec
FROM V$SYSSTAT s
JOIN sysstat_snap t ON s.NAME = t.NAME
ORDER BY delta DESC;
```

---

## 6. Senior Checklist

- [ ] **TIME_WAITED unit**: centiseconds — khi viết script custom, luôn chia 100. Dùng `TIME_WAITED_MICRO / 1e6` nếu cần microsecond precision
- [ ] **Filter Idle**: mọi query wait event phải có `WAIT_CLASS <> 'Idle'` — không có ngoại lệ
- [ ] **V$SYSTEM_EVENT không có context**: chỉ meaningful khi so với AWR baseline hoặc delta snapshot; tuyệt đối không report raw cumulative value
- [ ] **Post-mortem planning**: nếu cần forensics sau khi session disconnect, phải có ASH (V$ACTIVE_SESSION_HISTORY hoặc DBA_HIST_ACTIVE_SESS_HISTORY) — V$SESSION_EVENT không đủ
- [ ] **P1/P2/P3 semantics**: tra Oracle Reference Appendix C cho từng event trước khi interpret; không assume convention chung
- [ ] **STATISTIC# không portable**: script query V$SESSTAT/V$SYSSTAT phải JOIN qua NAME, không hardcode số
- [ ] **BLOCKING_SESSION**: verify column available ≥ 10gR2; trên RAC, blocker có thể ở node khác → `BLOCKING_INSTANCE` cần check thêm

---
---

# OUTPUT 2 — LAB EXERCISES

# Lab: Instance Activity & Wait Events — Hands-on for Senior DBA

## Lab Overview
- **Mục tiêu:** Xây dựng workflow chẩn đoán wait events từ system-level đến session-level; verify hiểu về wait event lifecycle
- **Môi trường:** Oracle 12c–19c / non-CDB hoặc PDB
- **Thời gian ước tính:** 45–60 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — System-Level Wait Signature Profiling

### Scenario
Production DBA nhận complaint: "Database chậm vào cuối ngày, khoảng 17:00–18:00." Không có AWR snapshot manual nào được chụp trong window đó. Hệ thống hiện đang idle (22:00). Bạn có V$SYSTEM_EVENT với data tích lũy từ khi instance start (3 tuần trước).

### Tasks
1. Query V$SYSTEM_EVENT để lấy top 10 non-idle wait events, bao gồm % tổng wait time và average wait time. Xác định events nào thuộc User I/O, Commit, Application, Concurrency
2. Query V$SYSTEM_WAIT_CLASS để so sánh distribution across wait classes. Wait class nào chiếm tỷ lệ cao nhất?
3. Từ top event có average_wait cao nhất: tra Oracle docs Appendix C để xác định P1/P2/P3 semantics của event đó
4. Giải thích tại sao kết quả hiện tại không đủ để confirm hoặc deny complaint về 17:00–18:00

### Expected Findings
- `log file sync` (Commit class) hoặc `db file sequential read` (User I/O) thường dẫn đầu trên OLTP workload
- Wait class distribution phản ánh workload type: I/O-heavy, lock-heavy, hay commit-heavy
- Bước 4 là câu trả lời quan trọng nhất: V$SYSTEM_EVENT là cumulative, không có time dimension

### Debrief Questions
- Nếu `log file sync` average_wait = 15ms, đây là vấn đề hay bình thường? Cần thêm thông tin gì?
- Làm thế nào để capture delta cho time window cụ thể nếu AWR retention không đủ dài?

---

## Exercise 2 — Session Forensics với Wait Event Parameters

### Scenario
Trong giờ cao điểm, application team báo cáo 3 user session bị timeout. DBA vào kiểm tra: 2 session đã disconnect, 1 session vẫn còn connected ở trạng thái hung với `WAIT_CLASS = 'Application'`.

### Tasks
1. Viết query tìm tất cả session đang WAITING với non-Idle wait class. Extract đầy đủ P1TEXT/P1, P2TEXT/P2, P3TEXT/P3 của session hung
2. Dùng BLOCKING_SESSION (và BLOCKING_INSTANCE nếu là RAC) để map blocking chain. Tìm root blocker
3. Query V$SESSION_EVENT cho session hung: xem total TIME_WAITED của event đó kể từ logon. Tính số phút session đã chờ
4. Sau khi xử lý blocking: verify lifecycle — event xuất hiện/biến mất ở V$SESSION, V$SESSION_EVENT, V$SESSION_WAIT_HISTORY như thế nào?
5. Cho 2 session đã disconnect: giải thích tại sao không thể lấy được wait event history từ V$* views. Nên tìm ở đâu thay thế?

### Expected Findings
- Blocking chain thường có nhiều hơn 2 nodes — root blocker thường không phải session đầu tiên được báo cáo
- V$SESSION_WAIT_HISTORY chỉ populated sau khi wait kết thúc, không trong khi đang chờ
- Cho disconnected sessions: chỉ `DBA_HIST_ACTIVE_SESS_HISTORY` (nếu trong AWR retention window) hoặc V$ACTIVE_SESSION_HISTORY (1 giờ gần nhất trong SGA)

### Debrief Questions
- P1 của `enq: TX - row lock contention` encode lock type và mode trong cùng một số — decode như thế nào?
- Tại sao `SECONDS_IN_WAIT` tăng nhưng `WAIT_TIME = 0` khi session đang WAITING?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Hệ thống OLTP 24/7, Oracle 19c, 32-CPU, 256GB RAM, storage all-flash SAN. Vào 09:15 thứ Hai, monitoring team trigger alert: application response time tăng từ 200ms lên 4.2s trung bình. Incident kéo dài 22 phút, tự recover lúc 09:37. Không có deployment hay maintenance nào trong window này.

### Evidence Provided

**V$SYSTEM_WAIT_CLASS snapshot lúc 09:25 (captured by on-call DBA):**
```
WAIT_CLASS          TIME_SECONDS    PCT
------------------- -----------     ---
User I/O            12,847,221      61%
Concurrency         7,234,109       34%
Application         891,234          4%
Other               234,112          1%
```

**V$SYSTEM_EVENT top 5 lúc 09:25 (non-idle, sorted by TIME_WAITED desc):**
```
EVENT                                AVG_WAIT(ms)  TOTAL_WAITS   WAIT_CLASS
------------------------------------ ------------- ------------- -----------
db file sequential read               0.8           16,234,441    User I/O
cursor: pin S wait on X               183.2         39,441        Concurrency
latch: shared pool                    12.4          584,221       Concurrency
library cache lock                    97.6          40,112        Concurrency
db file scattered read                1.1           2,341,221     User I/O
```

**V$SYSSTAT delta 09:15–09:25 (10 phút):**
```
NAME                              DELTA      PER_SEC
--------------------------------- ---------- -------
parse count (hard)                1,847,221  3,079/s
parse count (total)               1,891,034  3,152/s
execute count                     2,103,441  3,506/s
session cursor cache hits         12,441      21/s
```

**Alert log excerpt 09:14–09:16:**
```
09:14:52 Mon Jan 13 2025
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_ora_12847.trc:
ORA-04031: unable to allocate 4096 bytes of shared memory
("shared pool","SELECT COUNT(*) FROM...","Typecheck heap","kglob")
09:15:03 Mon Jan 13 2025
...repeated 847 times in next 22 minutes...
```

### Your Mission
1. Xác định root cause của incident — không phải symptoms
2. Explain tại sao `cursor: pin S wait on X` và `library cache lock` xuất hiện đồng thời với pattern parse count này
3. Đề xuất immediate mitigation (trong khi incident đang xảy ra) và long-term fix
4. Giải thích tại sao I/O metrics (db file sequential read) tăng đồng thời — có liên quan đến root cause không hay là independent factor?

### Evaluation Criteria
- Root cause chỉ đến một component cụ thể (không phải "shared pool issues" chung chung)
- Correlation giữa ORA-04031, hard parse spike, và concurrency waits phải được explain bằng internal mechanics (library cache, latch, mutex)
- Mitigation phải differentiate giữa "stop the bleeding now" vs "prevent recurrence" — hai action set khác nhau
- I/O question: senior sẽ nhận ra đây là consequence (cache miss do shared pool pressure flush buffer) hay coincidence — phân tích cả hai hypothesis

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_8_instance_activity_wait_events_senior_guide.md`
