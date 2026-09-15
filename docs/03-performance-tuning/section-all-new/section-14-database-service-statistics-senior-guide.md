---
title: Section 14 — Database Service Statistics & Module/Action/Client ID — Deep Dive for
  Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_14_database_service_statistics_senior_guide.md
---

# Section 14 — Database Service Statistics & Module/Action/Client ID — Deep Dive for Senior DBA

---

## 1. Mental Model

Đây là layered instrumentation — Oracle cho phép phân tích performance ở bốn độ phân giải tăng dần: **Instance → Service → Module/Action → Client Identifier**. Instance-level views (V$SYS_TIME_MODEL, V$SYSTEM_EVENT) cho biết *WHAT* đang xảy ra globally. Service/Module/Client layers cho biết *WHO* gây ra nó và trong business context nào.

Senior DBA dùng đây như một triage funnel: AWR report thấy `db file sequential read` spike lúc 14:00 → pivot sang V$SERVICE_EVENT để isolate service nào → drilldown qua ASH MODULE/ACTION để tìm SQL family → confirm bằng DBMS_MONITOR aggregation nếu cần số liệu chính xác. Không có funnel này, bạn đang đoán mò xem gọi team nào.

---

## 2. Internals & Mechanics

**SERVICE_HASH là CRC32 của service name** — consistent ở mọi nơi: V$SERVICES.NAME_HASH, V$SERVICE_EVENT.SERVICE_NAME_HASH, V$ACTIVE_SESSION_HISTORY.SERVICE_HASH. Trong RAC, hash này giống nhau trên tất cả instances cho cùng một service name. Đây là tại sao cross-join giữa các views dùng hash thay vì varchar comparison — performance và consistency.

**V$SERVICE_STATS accumulate tự động từ instance startup** — không cần configuration. Bao gồm elapsed_time, cpu_time, user_calls, user_io_wait_time và các stats tương tự V$SYS_TIME_MODEL nhưng scoped theo service. Đơn vị là **microseconds** cho time-based stats — khác với V$SERVICE_EVENT dùng **centiseconds** (same as V$SYSTEM_EVENT). Sự không nhất quán này là nguồn gốc của những so sánh sai trong production.

**V$SERVICE_EVENT không được flush vào AWR** — đây là limitation quan trọng nhất của section này. Không có DBA_HIST_SERVICE_EVENT. DBA_HIST_SERVICE_WAIT_CLASS tồn tại nhưng chỉ granular đến wait class level, không đến từng event. Nếu bạn cần per-event history cho một service, ASH (DBA_HIST_ACTIVE_SESS_HISTORY với filter SERVICE_HASH) là *duy nhất* option.

**V$SERVICEMETRIC sampling mechanism**: MMON slave process sample metrics mỗi 5 giây và 60 giây. V$SERVICEMETRIC chỉ giữ hai sample gần nhất (5s và 1m). V$SERVICEMETRIC_HISTORY giữ 1 giờ của 1-minute samples. **Cả hai không được preserve vào AWR** — sau 1 giờ, dữ liệu mất. DBTIMEPERSEC trong view này là SLA metric realtime của bạn.

**DBMS_MONITOR aggregation là opt-in và persistent**: Khi gọi SERV_MOD_ACT_STAT_ENABLE, configuration được lưu vào SYSAUX — survives instance restart (DBA_ENABLED_AGGREGATIONS phản ánh dictionary state). Nhưng accumulated statistics trong V$SERV_MOD_ACT_STATS là in-memory only — instance bounce reset chúng về zero. Trong RAC, cần enable per-instance hoặc dùng INSTANCE_NAME => NULL để enable globally [⚠️ verify RAC behavior với MOS Doc 1233723.1].

**CLIENT_INFO vs CLIENT_ID — sự khác biệt có hậu quả lớn**:

| | CLIENT_INFO | CLIENT_ID |
|---|---|---|
| Set bằng | DBMS_APPLICATION_INFO.SET_CLIENT_INFO | DBMS_SESSION.SET_IDENTIFIER |
| Max length | 64 bytes | 64 bytes |
| Visible trong V$SESSION | ✅ | ✅ |
| Captured trong ASH | ❌ | ✅ |
| Dùng cho DBMS_MONITOR aggregation | ❌ | ✅ |

Ứng dụng set CLIENT_INFO mà không set CLIENT_ID có blind spot hoàn toàn cho post-incident analysis via ASH.

**DBMS_SESSION.SET_IDENTIFIER phải được gọi trong PL/SQL block riêng** để CLIENT_ID aggregation hoạt động đúng. Lý do: aggregation engine cần context switch được committed trước sample đầu tiên. Nếu SET_IDENTIFIER cùng block với DML, Oracle có thể sample context cũ trước khi identifier được set.

**INSERT /*+ APPEND */ TM lock mechanics**: Direct path insert bypass buffer cache, ghi trực tiếp vào new extents above HWM. Để đảm bảo segment header consistency, Oracle acquire TM lock ở **exclusive mode (mode 6)**. Điều này serialize tất cả parallel APPEND inserts vào cùng một table. Remove APPEND hint → regular INSERT → row-level locking → 20 parallel sessions chạy độc lập hoàn toàn.

---

## 3. Production Realities

**MMON không backfill V$SERVICEMETRIC_HISTORY sau gap**: Nếu MMON bận (SGA pressure, contention với background tasks), sampling có thể bị delayed hoặc bỏ qua. Bạn sẽ thấy gaps trong V$SERVICEMETRIC_HISTORY. Treat view này như best-effort realtime, không phải forensic evidence.

**Middleware thường override MODULE**: Connection pools (JDBC, UCP, OCI, WebLogic) reset MODULE về identifier của chính chúng: 'JDBC Thin Client', 'WebLogic', 'OCI'. Trong production, nếu query V$SESSION.MODULE chỉ thấy generic names thay vì tên business function — app team không implement DBMS_APPLICATION_INFO. Đây phá vỡ toàn bộ module-level analysis.

**SERV_MOD_ACT_STAT_ENABLE với ACTION_NAME = NULL tạo aggregation type 'SERVICE_MODULE_ACTION'** — aggregate across *tất cả* actions trong module. Nếu cần per-action granularity, phải gọi ENABLE riêng cho từng (SERVICE, MODULE, ACTION) tuple. Common mistake: DBA enable ở module level nghĩ sẽ có action-level breakdown.

**DBMS_MONITOR aggregations left enabled vô thời hạn**: Check DBA_ENABLED_AGGREGATIONS trên tất cả production instances. Aggregations không dùng nữa nên được disable — chúng add marginal overhead và V$SERV_MOD_ACT_STATS accumulate data vô giới hạn cho đến khi bounce.

**Multi-tenant CDB gotcha**: Trong 12c+, V$SERVICES từ CDB root hiển thị services của tất cả PDB open. DBA_SERVICES trong một PDB chỉ thấy services của PDB đó. Query join DBA_SERVICES với V$SERVICE_STATS phải chạy từ correct container [⚠️ verify với MOS].

**V$SERVICEMETRIC_HISTORY retention là 1 giờ**: Nếu alert fire và bạn check 90 phút sau, spike đã gone. Cần custom snapshot job nếu muốn trend analysis dài hơn.

---

## 4. Decision Framework

| Scenario | Tool | Trade-off |
|---|---|---|
| "Service nào đang consume DB time right now?" | V$SERVICEMETRIC (DBTIMEPERSEC) | Chỉ 2 samples; không historical |
| "Service nào gây vấn đề 2 giờ trước?" | DBA_HIST_ACTIVE_SESS_HISTORY với SERVICE_HASH filter | Không cần pre-config; 1-sample/sec resolution |
| "Top module/action trong 30 phút qua?" | V$ACTIVE_SESSION_HISTORY GROUP BY MODULE, ACTION | Không cần pre-config; ASH sampling có thể miss short bursts |
| "Measure chính xác CPU/IO của một module trong job 1 giờ" | DBMS_MONITOR.SERV_MOD_ACT_STAT_ENABLE → V$SERV_MOD_ACT_STATS | Phải enable *trước* khi job chạy; reset khi disable |
| "Track toàn bộ ETL job group performance" | DBMS_MONITOR.CLIENT_ID_STAT_ENABLE → V$CLIENT_STATS | App phải set CLIENT_ID; reset bằng disable/enable cycle |
| "Per-event wait analysis cho service post-incident" | ASH với SERVICE_HASH filter | V$SERVICE_EVENT vô dụng cho post-incident; AWR chỉ có wait class |

**Anti-patterns cần tránh:**
- Dùng DBMS_MONITOR aggregation cho exploratory investigation — đây là precision instrumentation cho known modules, không phải ad-hoc analysis
- So sánh V$SERVICE_EVENT total wait time với V$SERVICE_STATS wait time và expect exact match — slight discrepancy là bình thường do timing khác nhau
- Enable CLIENT_ID aggregation *sau* incident — V$CLIENT_STATS bắt đầu từ zero; incident data đã mất
- Dùng CLIENT_INFO thay CLIENT_ID cho tracking — CLIENT_INFO không có trong ASH

---

## 5. Key SQL / Commands

```sql
-- Service inventory: NAME_HASH là key cho tất cả queries sau
SELECT SERVICE_ID, NAME, NAME_HASH
FROM DBA_SERVICES
ORDER BY SERVICE_ID;

-- Real-time SLA dashboard: DBTIMEPERSEC > threshold → SLA breach
-- INTSIZE_CSEC/100 = 5 (5s sample) hoặc 60 (1m sample)
SELECT BEGIN_TIME,
       ROUND(INTSIZE_CSEC/100) INTERVAL_S,
       ROUND(DBTIMEPERSEC)     DBTIMEPERSEC,   -- microseconds of DB time per second
       ROUND(CALLSPERSEC)      CALLSPERSEC,
       ROUND(ELAPSEDPERCALL)   ELAPSEDPERCALL  -- microseconds per call
FROM V$SERVICEMETRIC
WHERE SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY BEGIN_TIME;

-- Wait % của DB time: > 30% thường đáng điều tra
-- V$SERVICE_STATS unit: microseconds
SELECT ROUND(
    (1 - (SELECT VALUE FROM V$SERVICE_STATS
          WHERE SERVICE_NAME_HASH = h.NAME_HASH AND STAT_NAME = 'DB CPU')
         /
         NULLIF((SELECT VALUE FROM V$SERVICE_STATS
                 WHERE SERVICE_NAME_HASH = h.NAME_HASH AND STAT_NAME = 'DB time'), 0)
    ) * 100, 2) AS WAIT_PCT
FROM (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain') h;

-- Top wait events cho service (V$SERVICE_EVENT dùng centiseconds)
SELECT EVENT, TIME_WAITED, AVERAGE_WAIT, MAX_WAIT
FROM V$SERVICE_EVENT E, V$EVENT_NAME N
WHERE E.EVENT_ID = N.EVENT_ID
  AND N.WAIT_CLASS <> 'Idle'
  AND TIME_WAITED <> 0
  AND SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY TIME_WAITED DESC FETCH FIRST 10 ROWS ONLY;

-- Top modules by DB time từ ASH (không cần pre-configuration)
WITH TOTAL AS (
    SELECT COUNT(1) CNT
    FROM V$ACTIVE_SESSION_HISTORY
    WHERE SESSION_TYPE = 'FOREGROUND'
)
SELECT MODULE,
       COUNT(1) MODULE_DBTIME,
       ROUND(COUNT(1) / (SELECT CNT FROM TOTAL) * 100, 2) PCT_DBTIME
FROM V$ACTIVE_SESSION_HISTORY
WHERE SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND SESSION_TYPE = 'FOREGROUND'
  AND SERVICE_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
GROUP BY MODULE
ORDER BY PCT_DBTIME DESC;

-- CLIENT_STATS: tính wait % để assess job health
-- Reset cycle: DISABLE → ENABLE trước mỗi job run
SELECT CLIENT_IDENTIFIER,
       STAT_NAME,
       VALUE,
       ROUND(VALUE /
             NULLIF(SUM(CASE WHEN STAT_NAME = 'DB time' THEN VALUE ELSE 0 END)
                    OVER (PARTITION BY CLIENT_IDENTIFIER), 0) * 100, 2) PCT_OF_DBTIME
FROM V$CLIENT_STATS
WHERE CLIENT_IDENTIFIER = 'ETL Load Orders'
ORDER BY VALUE DESC;

-- Verify enabled aggregations (persistent across restart)
SELECT AGGREGATION_TYPE, PRIMARY_ID, QUALIFIER_ID1, QUALIFIER_ID2
FROM DBA_ENABLED_AGGREGATIONS;

-- Historical service stats per snapshot (note: no timestamp in DBA_HIST_SERVICE_STAT)
SELECT S.SNAP_ID,
       TO_CHAR(N.BEGIN_INTERVAL_TIME, 'DD-MON HH24:MI') SNAP_TIME,
       S.STAT_NAME,
       S.VALUE
FROM DBA_HIST_SERVICE_STAT S,
     DBA_HIST_SNAPSHOT N,
     DBA_SERVICES V
WHERE S.SNAP_ID = N.SNAP_ID
  AND S.SERVICE_NAME_HASH = V.NAME_HASH
  AND V.NAME = 'ORADB.localdomain'
  AND N.BEGIN_INTERVAL_TIME >= SYSDATE - 1
  AND S.STAT_NAME IN ('DB time', 'DB CPU', 'user calls')
ORDER BY S.SNAP_ID, S.STAT_NAME;
```

---

## 6. Senior Checklist

- **Verify instrumentation trước khi phân tích**: query V$SESSION.MODULE cho target service trong production — nếu thấy > 30% rows có MODULE = NULL hoặc 'JDBC Thin Client', module-level analysis không có ý nghĩa; escalate tới app team trước
- **V$SERVICE_EVENT là cumulative từ startup, không time-bounded**: dùng để xem wait profile tổng quan, không dùng để so sánh trước/sau incident; pivot sang ASH với SERVICE_HASH filter cho time-bounded analysis
- **CLIENT_ID aggregation reset là thủ công**: DISABLE rồi ENABLE mới reset V$CLIENT_STATS về zero — build vào ETL runbook để có clean per-run stats; không có auto-reset mechanism
- **DBMS_MONITOR aggregations orphan trong production**: audit DBA_ENABLED_AGGREGATIONS định kỳ; aggregation cho jobs đã discontinued tốn overhead và tích lũy stale data vô thời hạn
- **V$SERVICEMETRIC_HISTORY retention 1 giờ**: nếu cần SLA trend > 1h, tạo DBMS_SCHEDULER job snapshot DBTIMEPERSEC vào custom table với interval 10–15 phút
- **RAC: dùng GV$ views**: V$SERVICE_STATS, V$CLIENT_STATS là per-instance; trong RAC environment cần query GV$SERVICE_STATS và aggregate theo INST_ID để có cluster-wide view — lưu ý GV$CLIENT_STATS chỉ có data trên instance mà client đang connect
- **APPEND hint trong parallel ETL là TM-contention trap**: bất kỳ parallel INSERT với APPEND vào shared table → enq: TM - contention guaranteed; pattern này tái diễn thường xuyên trong data warehouse ETL và khó detect cho đến khi bùng phát ở scale

---

---

# Lab: Section 14 — Database Service Statistics & Module/Action/Client ID — Hands-on for Senior DBA

## Lab Overview
- **Mục tiêu:** Phân biệt khi nào dùng Service stats vs DBMS_MONITOR aggregation vs ASH để isolate performance issues theo business context; identify instrumentation gaps
- **Môi trường:** Oracle 12c+ / non-CDB hoặc PDB trong CDB, có Swingbench hoặc workload generator
- **Thời gian ước tính:** 60–75 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Service SLA Breach Investigation

### Scenario
Bạn là DBA on-call. Ứng dụng banking chạy trên service `BANKING_SVC`. SLA team định nghĩa: DBTIMEPERSEC < 5,000 microseconds/sec và wait_pct < 30% trong giờ cao điểm 09:00–12:00. Lúc 10:45, users báo "login chậm bất thường". Khi bạn check (10:55), peak đã qua nhưng complaints vẫn đang incoming.

### Tasks
1. Query V$SERVICEMETRIC_HISTORY cho BANKING_SVC — xác định timeframe DBTIMEPERSEC vượt ngưỡng 5,000 và magnitude của spike so với baseline
2. Tính wait_pct từ V$SERVICE_STATS (DB time − DB CPU) / DB time × 100 — đơn vị microseconds; so sánh với threshold 30%
3. Extract top 5 non-idle wait events từ V$SERVICE_EVENT cho service — xác định wait class đang dominant
4. Pivot sang V$ACTIVE_SESSION_HISTORY với SERVICE_HASH filter và time window 09:00–10:45 — confirm wait event pattern và identify SQL_IDs đang bị ảnh hưởng

### Expected Findings
Nếu spike xảy ra > 60 phút trước khi check, V$SERVICEMETRIC_HISTORY đã clear. V$SERVICE_EVENT cho thấy wait profile từ startup, không isolate incident window. ASH (V$ACTIVE_SESSION_HISTORY với time filter) là nguồn tin cậy duy nhất để correlate với incident window.

### Debrief Questions
- Tại sao total wait time từ V$SERVICE_EVENT và wait time tính từ V$SERVICE_STATS (DB time − CPU) không match chính xác, dù cùng measure "wait time" cho cùng service?
- Nếu incident kéo dài 3 ngày trước (ngoài AWR retention window), bạn còn option nào để reconstruct service-level behavior?

---

## Exercise 2 — Module/Action Instrumentation Gap Audit

### Scenario
Một Java microservice mới được deploy production tuần trước. Dev team claim đã implement DBMS_APPLICATION_INFO. Trước khi đưa vào SLA monitoring, bạn cần verify coverage và quantify instrumentation gaps — bao nhiêu % DB time có meaningful business context, bao nhiêu bị masked bởi generic JDBC metadata.

### Tasks
1. Query V$SESSION để xem distribution của MODULE values cho target service — categorize: meaningful application names vs 'JDBC Thin Client' vs NULL vs khác; tính % của mỗi category theo COUNT(SID)
2. Query V$ACTIVE_SESSION_HISTORY (last 30 min) để tính % DB time có MODULE IS NULL hoặc MODULE IN ('JDBC Thin Client', 'JDBC') — đây là instrumentation gap
3. Enable SERV_MOD_ACT_STAT_ENABLE cho module name có tên có nghĩa nhất từ output bước 1; sau 10 phút chạy workload, query V$SERV_MOD_ACT_STATS và verify data đang accumulate
4. Query DBA_ENABLED_AGGREGATIONS — verify AGGREGATION_TYPE, PRIMARY_ID, QUALIFIER_ID1, QUALIFIER_ID2 match intention; disable aggregation sau khi verify

### Expected Findings
Nếu > 20% DB time có MODULE NULL hoặc generic JDBC, ứng dụng không đủ instrumented cho service-level SLA monitoring. V$SERV_MOD_ACT_STATS chỉ có data từ sau khi enable — không retroactive. AGGREGATION_TYPE = 'SERVICE_MODULE_ACTION' kể cả khi ACTION_NAME = NULL là expected behavior.

### Debrief Questions
- Sau instance restart, DBA_ENABLED_AGGREGATIONS còn hiển thị aggregation đã enable không? V$SERV_MOD_ACT_STATS còn data không? Implication gì cho monitoring continuity?
- Nếu cùng module name xuất hiện từ 3 service khác nhau (OLTP, BATCH, REPORT), SERV_MOD_ACT_STAT_ENABLE với SERVICE_NAME cụ thể có isolate được không?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
03:00 sáng thứ Ba. Monitoring alert: `application wait time` tăng từ 2% lên 67% DB time trong 8 phút cho CLIENT_ID = 'nightly_settlement'. Batch ETL job này chạy hàng đêm từ 02:45, thường xong trong 12 phút. Hôm nay sau 45 phút vẫn chưa xong và bắt đầu overlap với job 'morning_recon' start lúc 03:15.

### Evidence Provided

```
-- V$CLIENT_STATS snapshot tại 03:20 (CLIENT_IDENTIFIER = 'nightly_settlement')
STAT_NAME                           VALUE (microseconds)
----------------------------------  --------------------
DB time                             28,450,000,000
DB CPU                               1,820,000,000
application wait time               19,070,000,000   → 67.0% of DB time
user I/O wait time                     890,000,000
sql execute elapsed time             7,200,000,000

-- Top ASH events (CLIENT_ID = 'nightly_settlement', 02:45–03:20)
EVENT                            COUNT   PCT
-------------------------------  ------  -----
enq: TM - contention              8,420   67.3%
db file sequential read             892    7.1%
CPU                                 780    6.2%
log file sync                       430    3.4%

-- Top SQL in ASH (same window)
SQL_ID        EVENT                    CNT    SQL_TEXT (excerpt)
----------    ----------------------   -----  ----------------------------------------
f3z9q2p1k    enq: TM - contention     6,100  INSERT /*+ APPEND NOLOGGING */ INTO SETTLE_FACT ...
f3z9q2p1k    db file sequential read    310  (same SQL_ID)
9xm4v8r2n    enq: TM - contention     2,100  INSERT /*+ APPEND NOLOGGING */ INTO SETTLE_FACT ...
9xm4v8r2n    CPU                        420  (same SQL_ID)

-- DBA_OBJECTS
OBJECT_ID = 74312  → SETTLE_FACT (TABLE, owner: DWH)

-- Context: job ran successfully every night for past 6 months with no issues
-- Last night data volume: 2.3M rows (typical: 400K–600K rows)
```

### Your Mission
1. Xác định root cause của application wait time spike — không chỉ "TM contention" mà cụ thể: *tại sao* job này gây TM contention, và *tại sao* hôm nay đặc biệt tệ hơn 6 tháng qua
2. Giải thích sự xuất hiện của 2 distinct SQL_IDs (f3z9q2p1k và 9xm4v8r2n) cho cùng INSERT pattern — đây là vấn đề hay behavior bình thường? Implication gì?
3. Đề xuất ít nhất 2 remediation options với trade-offs rõ ràng về: throughput, recoverability (NOLOGGING → unrecoverable segments), operational complexity, và impact lên morning_recon job nếu overlap tiếp tục xảy ra
4. Thiết kế monitoring trigger để phát hiện pattern này sớm hơn trong tương lai — dùng các metrics có sẵn trong Oracle, không propose external tools; address cả detection lag problem (alert fire sau 8 phút là quá muộn)

### Evaluation Criteria
- Root cause phải address CẢ HAI: technical mechanism (TM exclusive lock + APPEND/NOLOGGING) VÀ operational trigger (data volume 4–5x normal → job duration 4x → overlap với morning_recon → morning_recon có thể cũng acquire conflicting lock?)
- Remediation phải compare rõ: remove APPEND hint (throughput giảm, row-level locking) vs partition exchange (ETL complexity cao, full recoverability) vs serialize via DBMS_SCHEDULER dependency (đơn giản, không fix root cause)
- Monitoring design phải specify: metric, threshold, check frequency, và action khi threshold breach — không chỉ "alert khi TM contention cao"


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_14_database_service_statistics_senior_guide.md`
