---
title: 'Section 19 — Handling Enqueue Waits: Deep Dive for Senior DBA'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_19_enqueue_waits_senior_guide.md
---

# Section 19 — Handling Enqueue Waits: Deep Dive for Senior DBA

---

## OUTPUT 1 — LECTURE NOTES

---

## 1. Mental Model

Enqueue là Oracle's user-visible locking protocol — phân biệt rõ với latches (internal spin locks). Frame nó như: enqueue là locking theo **queuing protocol** (FIFO cho TX, priority-based cho một số types khác) — session request lock → nếu unavailable → enter queue → wait signal khi holder releases. Đây là user-level serialization, **intended và expected** trong concurrent OLTP. Vấn đề không phải là sự tồn tại của enqueue waits mà là **duration** và **frequency** — khi enqueue waits consume significant portion của DB time, investigation cần thiết.

Senior DBA không chỉ biết "session A block session B" — biết rõ: **tại sao** session A giữ lock lâu, **lock type** nào (TX vs TM vs HW), và **remediation nào không chỉ kill session mà giải quyết root cause tái diễn**.

---

## 2. Internals & Mechanics

**TX enqueue internals**: Mỗi transaction được cấp một slot trong undo segment — slot này là TX lock. Row-level lock không phải separate lock objects — chỉ là một bit trong row's ITL (Interested Transaction List) entry trong data block header. Khi session B tries to update row, Oracle finds ITL entry pointing to session A's TX lock → queries TX lock status → if active → waits. Không có lock table lookup overhead cho row locks — toàn bộ mechanism là in-block.

**ITL waits vs row lock waits**: Nếu block's ITL slots đầy hết (INITRANS tối đa = 255, mặc định 1 cho tables, 2 cho indexes), session phải wait cho ITL slot free → event vẫn là `enq: TX - row lock contention` nhưng **P3 = 4** (mode 4 = Share lock, waiting for ITL, không phải row lock). Distinguish by examining P3 value.

**TM lock modes**:
| Mode | Decimal | Tên | Khi nào |
|------|---------|-----|---------|
| 0 | None | — | No lock |
| 2 | RS | Row-S | SELECT FOR UPDATE, subquery |
| 3 | RX | Row-X | INSERT/UPDATE/DELETE |
| 4 | S | Share | Lock Table in Share Mode |
| 5 | SRX | Share Row-X | Lock Table in Share Row Exclusive |
| 6 | X | Exclusive | DDL, **Direct Path INSERT (APPEND hint)** |

Critical production gotcha: `INSERT /*+ APPEND */` requires **TM mode 6 (exclusive)** trên table → serializes all concurrent DML. Một batch job dùng APPEND hint để performance → unintentionally serializes all other transactions on same table.

**HW (High Water Mark) enqueue**: Khi bảng phát triển beyond HWM, cần extend segment. Chỉ một session extend tại một thời điểm → nhiều sessions insert small amounts → `enq: HW - contention`. Với ASSM (Automatic Segment Space Management), Oracle manages space differently và HW contention greatly reduced. Pre-ASSM (MANUAL storage): `FREELISTS` parameter controls concurrency.

**Deadlock detection**: PMON scan for deadlocks mỗi 3 giây. Deadlock detected → one session's statement rolled back (NOT transaction) với ORA-00060. Alert log records deadlock trace. DBA check: `grep ORA-00060 alert_*.log` — frequent ORA-00060 = application design issue, không phải DBA config issue.

**V$LOCK decoding**: ID1/ID2 interpretation varies by TYPE. TX lock: `ID1 = (undo_segment_number << 16) | slot_number`, `ID2 = wrap_number`. Extract: `ID1/65536 = undo seg#`, `MOD(ID1, 65536) = slot#`. Dùng `V$TRANSACTION` để link: `SELECT * FROM V$TRANSACTION WHERE XIDUSN = ID1/65536 AND XIDSLOT = MOD(ID1, 65536) AND XIDSQN = ID2`.

---

## 3. Production Realities

**Missing index → worse lock contention**: Trong SQL Server, "lock escalation" từ row → page → table là real. Oracle **không** có lock escalation. Nhưng UPDATE/DELETE không có index trên WHERE clause → full scan → mỗi row đọc qua là một potential lock candidate. Nếu WHERE clause không selective, nhiều rows bị lock hơn cần thiết. Fix: add index, không phải adjust lock parameters.

**Long-running uncommitted transactions**: Batch jobs chạy 4 giờ, mỗi row update không commit until batch complete → single transaction giữ row locks trên millions of rows. OLTP sessions trying to update overlapping rows → cascading waits. Solution: batch commit strategy (commit mỗi N rows) và proper error handling.

**Undo segment exhaustion và enqueue**: Khi UNDO tablespace full, Oracle không thể cấp new TX slots → `enq: US - contention` hoặc ORA-30036 (unable to extend undo segment). Distinguished từ TX enqueue bởi TYPE = 'US'. Monitor `V$UNDOSTAT.UNDOBLKS` và `V$UNDOSTAT.SSOLDERRCNT`.

**"Blocked by yourself"**: `V$LOCK` hiển thị cùng SID vừa là holder vừa là waiter → session đang wait cho chính nó. Thường xảy ra với constraint enable (ALTER TABLE ... ENABLE CONSTRAINT với deferred constraints) hoặc distributed transaction trong same session.

**ASH temporal correlation**: ASH sample mỗi giây. Enqueue wait event với duration < 1s có thể bị miss bởi ASH sampling. V$LOCK là real-time — nếu lock đã release trước ASH sample, không có evidence trong ASH. Dùng `V$ACTIVE_SESSION_HISTORY.BLOCKING_SESSION` để trace waiter-holder chains qua time.

---

## 4. Decision Framework

| Tình huống | Tool/Action |
|-----------|-------------|
| Lock đang xảy ra ngay bây giờ | `V$LOCK` + `V$SESSION` — identify holder và waiter real-time |
| Lock đã release, < 1 giờ qua | `V$ACTIVE_SESSION_HISTORY` với WAIT_CLASS = 'Application' |
| Lock > 1 giờ trước | `DBA_HIST_ACTIVE_SESS_HISTORY` + AWR Report Enqueue section |
| Proactive: tìm tables bị lock thường xuyên | `V$SEGMENT_STATISTICS` WHERE STATISTIC_NAME IN ('row lock waits', 'ITL waits') |
| Identify SQL gây lock nhất | `V$SQLSTATS.APPLICATION_WAIT_TIME` DESC |
| APPEND hint gây TM mode 6 | Check `V$LOCK` WHERE TYPE = 'TM' AND LMODE = 6 |

**Anti-patterns**:
- Kill holder session mà không identify root cause → lock recurs trên session tiếp theo
- Tăng INITRANS mà không check nếu thực sự là ITL wait (check P3 value trước)
- Dùng `SELECT FOR UPDATE NOWAIT` trong application mà không handle ORA-54 gracefully → application crash vì lock

---

## 5. Key SQL / Commands

```sql
-- 1. Identify holder và waiter (current)
SELECT DECODE(REQUEST, 0, 'Holder SID: ', 'Waiter SID: ') || SID SESSIONS,
       ID1, ID2, LMODE, REQUEST, TYPE
FROM V$LOCK
WHERE (ID1, ID2, TYPE) IN (
    SELECT ID1, ID2, TYPE FROM V$LOCK WHERE REQUEST > 0
)
ORDER BY ID1, REQUEST;

-- 2. Chi tiết waiter session (event, P1/P2/P3, blocking SQL)
SELECT 'SID: '               || S.SID              || CHR(10) ||
       'USERNAME: '           || S.USERNAME          || CHR(10) ||
       'EVENT: '              || S.EVENT             || CHR(10) ||
       'SECONDS_IN_WAIT: '    || S.SECONDS_IN_WAIT   || CHR(10) ||
       'P1TEXT: '             || S.P1TEXT            || CHR(10) ||
       'P1: '                 || S.P1                || CHR(10) ||
       'P2TEXT: '             || S.P2TEXT            || CHR(10) ||
       'P2: '                 || S.P2                || CHR(10) ||
       'P3: '                 || S.P3                || CHR(10) ||  -- mode 4 = ITL wait
       'CURRENT SQL: '        || Q.SQL_TEXT          AS INFO
FROM V$SESSION S
JOIN V$LOCK L ON S.SID = L.SID
JOIN V$LOCK_TYPE T ON T.TYPE = L.TYPE
LEFT JOIN V$SQL Q ON S.SQL_ID = Q.SQL_ID
WHERE L.REQUEST > 0;

-- 3. Decode TX lock → find transaction
SELECT S.SID, S.USERNAME, T.START_TIME, T.STATUS,
       T.USED_UREC, T.USED_UBLK  -- undo records/blocks used
FROM V$SESSION S
JOIN V$LOCK L ON S.SID = L.SID
JOIN V$TRANSACTION T ON T.XIDUSN  = FLOOR(L.ID1 / 65536)
                     AND T.XIDSLOT = MOD(L.ID1, 65536)
                     AND T.XIDSQN  = L.ID2
WHERE L.TYPE = 'TX' AND L.REQUEST = 0;  -- holder sessions

-- 4. Xem row đang bị lock (từ waiter session info)
SELECT 'SELECT * FROM "' || O.OWNER || '"."' || O.OBJECT_NAME || '"' || CHR(10) ||
       'WHERE ROWID = DBMS_ROWID.ROWID_CREATE(1, ' ||
       S.ROW_WAIT_OBJ# || ', ' || S.ROW_WAIT_FILE# || ', ' ||
       S.ROW_WAIT_BLOCK# || ', ' || S.ROW_WAIT_ROW# || ');'
FROM DBA_OBJECTS O, V$SESSION S
WHERE S.ROW_WAIT_OBJ# = O.OBJECT_ID
  AND S.SID = &WAITER_SID;

-- 5. Proactive: enqueue wait events từ instance startup
SELECT EVENT,
       AVERAGE_WAIT,
       TO_CHAR(ROUND(TIME_WAITED/100),'999,999,999') TIME_SECONDS,
       WAIT_CLASS
FROM V$SYSTEM_EVENT
WHERE EVENT LIKE 'enq%'
ORDER BY TIME_WAITED DESC;

-- 6. Objects với highest row lock waits
SELECT OBJECT_NAME, STATISTIC_NAME, VALUE
FROM V$SEGMENT_STATISTICS
WHERE STATISTIC_NAME IN ('row lock waits', 'ITL waits')
  AND VALUE > 0
  AND OBJECT_NAME NOT LIKE 'BIN$%'
ORDER BY VALUE DESC
FETCH FIRST 20 ROWS ONLY;

-- 7. SQL statements với highest application wait time (TX enqueue proxy)
SELECT ROUND(APPLICATION_WAIT_TIME/1e6) WAIT_S,
       SQL_ID,
       SUBSTR(SQL_TEXT, 1, 80) SQL_TEXT
FROM V$SQLSTATS
WHERE APPLICATION_WAIT_TIME > 0
ORDER BY APPLICATION_WAIT_TIME DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## 6. Senior Checklist

1. Distinguish `enq: TX` P3 = 6 (row lock) vs P3 = 4 (ITL wait) — solutions khác nhau: kill session vs increase INITRANS
2. Khi thấy `enq: TM` LMODE = 6 → suspect APPEND hint hoặc DDL — không phải row-level contention
3. Frequent ORA-00060 trong alert log → application design problem (missing indexes, wrong commit frequency) không phải DBA config
4. Cho batch jobs: verify không dùng `INSERT /*+ APPEND */` trên tables mà OLTP sessions cũng write concurrently
5. Long-running transactions: `SELECT * FROM V$TRANSACTION ORDER BY START_TIME` để identify sessions giữ TX lock nhiều giờ
6. Sau enqueue incident: query `DBA_HIST_ACTIVE_SESS_HISTORY` với BLOCKING_SESSION để trace full waiter chain — nhiều hơn một "victim" thường có một single "root holder"
7. ITL contention chỉ xảy ra khi nhiều concurrent writers trên cùng block — nếu table mới với default INITRANS = 1 và heavy concurrent INSERT, raise INITRANS (ALTER TABLE ... INITRANS 4) và REBUILD nếu cần

---

## OUTPUT 2 — LAB EXERCISES

---

# Lab: Section 19 — Handling Enqueue Waits

## Lab Overview

- **Mục tiêu:** Diagnose enqueue wait events ở ba timeline: current, recent (ASH), và historical (AWR)
- **Môi trường:** Oracle 12c–19c / non-CDB với SOE schema
- **Thời gian ước tính:** 45 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Real-time Lock Chain Analysis

### Scenario
09:15 sáng. Helpdesk nhận 3 complaints đồng thời: "application hangs khi update customer profile." DBA confirm từ `V$SESSION`: 3 sessions trong state = 'WAITING' với event = 'enq: TX - row lock contention'. Cần identify root holder và SQL trong vòng 2 phút.

### Tasks
1. Query `V$LOCK` để identify holder SID(s) và waiter SID(s) — dùng self-join pattern
2. Với holder SID: query `V$TRANSACTION` để tìm START_TIME và USED_UREC (transaction size)
3. Với waiter SID: decode P3 — là row lock contention (P3=6) hay ITL wait (P3=4)?
4. Identify SQL đang chạy trong holder session và SQL bị block trong waiter session

### Expected Findings
- Single holder giữ TX lock hơn 10 phút trong OLTP → uncommitted transaction problem
- P3 = 6 → classic row lock → holder phải commit/rollback để release
- Holder's SQL_ID trong V$SESSION → V$SQL để xem SQL text và execution counts

### Debrief Questions
- Nếu holder session đã disconnected nhưng transaction chưa committed (orphaned transaction): PMON clean up tự động hay DBA phải intervene?
- Nếu V$LOCK cho thấy 5 waiters nhưng chỉ 1 holder: khi holder release lock, tất cả 5 waiters được grant đồng thời hay theo FIFO queue?

---

## Exercise 2 — TM Lock Contention From APPEND Hint

### Scenario
DBA nhận report: "nightly data load job bị slowdown bất thường sau khi application team thêm `/*+ APPEND */` hint vào bulk INSERT để improve ETL performance." Load job performance improved nhưng concurrent OLTP transactions trên cùng bảng bị freeze trong suốt load window.

### Tasks
1. Simulate: Session A chạy `INSERT /*+ APPEND */ INTO ORDERS SELECT ... FROM ORDERS_STAGING WHERE ROWNUM < 10000` (không commit)
2. Session B attempt `UPDATE ORDERS SET STATUS = 'PROCESSED' WHERE ORDER_ID = &N` — observe hang
3. Query `V$LOCK` — identify TYPE = 'TM' và LMODE của holder session
4. Compare với scenario không có APPEND hint: LMODE của TM lock khác như thế nào?

### Expected Findings
- APPEND hint: TM LMODE = 6 (exclusive) → serializes ALL DML trên table
- Không có APPEND hint: TM LMODE = 3 (RX = Row Exclusive) → concurrent DML có thể proceed
- Cùng session có cả TM lock (table level) và TX lock (transaction level)

### Debrief Questions
- APPEND hint required exclusive TM lock vì Direct Path Write bypass buffer cache — giải thích tại sao Direct Path Write cần exclusive TM access ở internal level?
- Nếu ETL performance với APPEND hint giảm 40% khi APPEND bị remove, alternatives nào để maintain performance mà không sacrifice concurrent DML?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Hệ thống e-commerce. 20:00 tối thứ Sáu. DBA nhận alert: `enq: TX - row lock contention` TIME_WAITED tăng 300% so với baseline. Business team báo: "checkout button bị freeze cho ~15% transactions."

### Evidence Provided

```
V$SYSTEM_EVENT (20:15):
  EVENT                           TIME_WAITED_S  AVERAGE_WAIT_MS
  enq: TX - row lock contention       8,420            180

V$SEGMENT_STATISTICS (top by row lock waits):
  OBJECT_NAME    STATISTIC_NAME    VALUE
  INVENTORY      row lock waits    24,817   ← spiked from baseline ~200
  ORDERS         row lock waits       412

V$LOCK at 20:17 (snapshot):
  TYPE  SID   LMODE  REQUEST  ID1      ID2
  TM    1842    6      0      48291     0     ← INVENTORY table object_id
  TM    2103    3      6      48291     0     ← waiter
  TM    2847    3      6      48291     0     ← waiter
  TX    1842    6      0      131085    423

V$SESSION for SID 1842:
  USERNAME: ETL_USER
  MODULE:   INVENTORY_RECONCILE_JOB
  SQL_ID:   f7x2kqm9n3p1

V$SQL for f7x2kqm9n3p1:
  SQL_TEXT: INSERT /*+ APPEND PARALLEL(4) */ INTO INVENTORY
            SELECT * FROM INVENTORY_DELTA WHERE PROCESSED = 'N'
  EXECUTIONS: 1
  ELAPSED_TIME: 1,847,000,000 microseconds (30+ minutes)
```

### Your Mission
1. Identify exact root cause: tại sao 15% checkout bị freeze (không phải tất cả)?
2. Explain tại sao job đang chạy 30+ phút cho một INSERT operation
3. What evidence is missing để determine nếu có data volume issue hay query performance issue?
4. Immediate mitigation (kill vs không kill), và long-term architectural fix

### Evaluation Criteria
- **Root cause**: APPEND + PARALLEL → TM exclusive lock (mode 6) trên INVENTORY table → tất cả DML phải wait. "15% transactions" = only those trying to UPDATE/INSERT INVENTORY, not all checkouts — confirms TM lock, not TX row lock
- **30-minute runtime**: Không thể determine từ evidence hiện tại. Missing: `V$SQL.ROWS_PROCESSED` (bao nhiêu rows đã xong), `V$PX_SESSION` (parallel slaves active không?), `V$SESSION_LONGOPS` (progress estimate), physical I/O stats
- **Ambiguity**: Có thể (a) INVENTORY_DELTA là very large table → expected long runtime; (b) parallel slaves không hoạt động đúng → degenerating to serial; (c) INVENTORY table tablespace full → HW contention thêm vào TM contention. Cần differentiate
- **Kill decision**: Kill ETL job → releases TM lock → OLTP unblocked immediately; nhưng INSERT với APPEND là non-restartable (Direct Path Write không partial commit). Phải re-run entire job. Business tradeoff: 15% checkout loss now vs delay until ETL completes
- **Long-term fix**: Move INVENTORY_RECONCILE_JOB sang maintenance window; hoặc refactor sang row-by-row INSERT (loses performance); hoặc use IOT/staging table pattern (insert to separate staging table, then online MERGE)

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_19_enqueue_waits_senior_guide.md`
