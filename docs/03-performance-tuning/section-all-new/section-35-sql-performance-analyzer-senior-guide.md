---
title: 'Section 35 — SQL Performance Analyzer: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_35_sql_performance_analyzer_senior_guide.md
---

# Section 35 — SQL Performance Analyzer: Senior DBA Guide

**Nguồn:** Practice 37 (PDF gốc) + section_all guide + Oracle internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

SQL Performance Analyzer (SPA) trả lời đúng một câu hỏi trước khi bạn đụng vào production: **"Thay đổi này có làm câu SQL nào chậm đi (plan regression) không?"** — ở mức **từng câu SQL**. SPA lấy một tập SQL (SQL Tuning Set), chạy TEST EXECUTE **hai lần** — trước và sau thay đổi — rồi so từng câu: cải thiện / thoái hóa / đổi plan / lỗi.

Đây là **change assurance**, không phải tuning. Và nó là **anh em vi mô** của Database Replay (Section 36):

```
SPA         → mức TỪNG SQL   → phát hiện plan regression   → nhẹ, nhanh, chạy sớm
DB Replay   → mức TOÀN workload → concurrency/contention/throughput → nặng, thực tế
```

SPA **không** thấy concurrency, lock, contention (nó chạy tuần tự từng câu). Nó bắt regression về **plan/chi phí SQL**. Quy trình upgrade an toàn chuẩn dùng CẢ HAI: SPA trước (bắt regression plan sớm) → DB Replay sau (kiểm tải đồng thời thật).

---

## 2. Internals & Mechanics

### SQL Tuning Set (STS) — nguyên liệu đầu vào

STS là tập SQL lưu trong dictionary: text + bind set + execution context + plan + stats. Nguồn nạp:
- **Cursor cache**: `DBMS_SQLTUNE.CAPTURE_CURSOR_CACHE_SQLSET` — sample V$SQL theo `TIME_LIMIT`/`REPEAT_INTERVAL`, lọc bằng `BASIC_FILTER` (ví dụ `PARSING_SCHEMA_NAME='SOE'`).
- **AWR**: `SELECT_WORKLOAD_REPOSITORY` — lấy SQL lịch sử từ snapshot.
- **STS khác** hoặc thủ công.

STS đại diện chất lượng thế nào → SPA đáng tin thế đó. Sample 1 phút giờ thấp điểm = mù với SQL peak.

### DBMS_SQLPA — 4 kiểu EXECUTION_TYPE

```
CREATE_ANALYSIS_TASK(sqlset) → task
EXECUTE_ANALYSIS_TASK(task, EXECUTION_TYPE => ...):
   'EXPLAIN PLAN'        — chỉ sinh plan, KHÔNG chạy SQL (nhanh, an toàn, chỉ so plan)
   'TEST EXECUTE'        — CHẠY THẬT từng SQL, thu stats+plan runtime (chính xác, tốn tài nguyên)
   'CONVERT SQLSET'      — dùng stats đã lưu sẵn trong STS (không chạy lại)
   'COMPARE PERFORMANCE' — so 2 execution (before vs after)
REPORT_ANALYSIS_TASK(task, TYPE=>'TEXT'|'HTML', SECTION=>...)
```

Khác biệt sống còn: **TEST EXECUTE thực sự chạy SQL** — kể cả DML sẽ thực thi và để lại side effect, và tốn tài nguyên như chạy thật. **EXPLAIN PLAN** chỉ compile plan (an toàn trên prod, nhưng chỉ so được thay đổi **plan**, không so runtime stats như buffer gets/elapsed thật).

### Luồng chuẩn (before/after)

```
1. Capture STS trên hệ nguồn (đại diện business cycle)
2. TEST EXECUTE 'before'          ← trạng thái hiện tại
3. ÁP DỤNG THAY ĐỔI               ← upgrade / param / index / stats / OFE
4. TEST EXECUTE 'after'
5. COMPARE PERFORMANCE            ← metric mặc định: elapsed_time (đổi được: buffer_gets, cpu_time)
6. REPORT_ANALYSIS_TASK          ← liệt kê improved / regressed / plan changed / errors
```

### Vận chuyển STS giữa hai hệ

Để test trên hệ khác (giống production): `CREATE_STGTAB_SQLSET` → `PACK_STGTAB_SQLSET` → Data Pump export → import ở đích → `UNPACK_STGTAB_SQLSET`. Đây là cách đưa workload prod sang hệ test mà không đụng prod.

### OPTIMIZER_FEATURES_ENABLE — proxy của "upgrade"

Practice mô phỏng nâng cấp bằng cách đổi `OPTIMIZER_FEATURES_ENABLE` 11.2.0.2 → 12.2.0.1. OFE **chỉ bật/tắt tập tính năng optimizer** theo version — KHÔNG phải nâng cấp code/binary/stats thật. Nó là proxy tốt để **pre-check plan regression** do optimizer, nhưng không thay thế test nâng cấp đầy đủ (stats mới, tính năng mới, bug fix). Đây là kỹ thuật hữu ích: đổi OFE (không cần cài bản mới) để xem plan đổi ra sao.

---

## 3. Production Realities

### TEST EXECUTE trên production = nguy hiểm

`TEST EXECUTE` chạy thật từng SQL: SELECT tốn buffer gets/CPU như thật; **DML thực thi và để lại side effect**. Trên production → tốn tài nguyên + thay đổi dữ liệu ngoài ý muốn. Quy tắc: TEST EXECUTE **chỉ trên bản test** (STS chuyển sang qua Data Pump). Trên production chỉ dùng **EXPLAIN PLAN** mode (an toàn, so plan-diff, không chạy).

### STS phải đại diện — nếu không, mù

SPA chỉ đánh giá SQL **có trong STS**. SQL peak-hour không capture → không biết nó regress. Capture STS qua **trọn business cycle** (ngày/tuần), gộp từ nhiều nguồn (cursor cache nhiều thời điểm + AWR top SQL). STS nghèo → kết luận SPA "an toàn" là giả.

### Bind sensitivity — SPA test một bộ bind

STS lưu **một bind set/câu**. SQL bind-sensitive (có histogram, bind peeking) có thể ra plan khác với bind khác → SPA chỉ test bộ bind đã capture → có thể bỏ sót regression chỉ xuất hiện với bind khác. Với SQL bind-sensitive quan trọng, cân nhắc capture nhiều bind set.

### Xử lý regression: SPA + SQL Plan Baselines

SPA phát hiện regressed SQL — bước tiếp là **giữ plan tốt qua thay đổi**. Chuẩn: dùng **SQL Plan Management (SPM/Baselines)** cố định plan "before" cho các câu regressed, để sau upgrade optimizer không được đổi sang plan xấu. Luồng thực chiến: SPA tìm regression → SPM baseline plan cũ cho đúng các câu đó → upgrade an toàn. `[⚠️ verify]` SPA có thể tự tạo baseline cho regressed SQL qua tùy chọn report/action.

### License — Real Application Testing

SPA thuộc **Real Application Testing (RAT) option — tính phí riêng** (chung gói với Database Replay). `DBA_FEATURE_USAGE_STATISTICS` ghi nhận khi dùng. Xác nhận license trước khi triển khai.

### SPA bỏ sót cái gì

SPA chạy **tuần tự từng SQL** → không có concurrency: không thấy lock contention, latch/mutex, buffer busy, throughput đồng thời, thứ tự commit. Một thay đổi có thể tốt cho từng SQL (SPA xanh) nhưng làm hỏng concurrency (chỉ DB Replay thấy). Đừng coi "SPA all green" là "an toàn go-live" cho thay đổi lớn.

---

## 4. Decision Framework

**Dùng SPA khi:**
- Đánh giá tác động của thay đổi lên **plan/hiệu năng từng SQL** trước khi áp production: upgrade, đổi optimizer param, thêm/bớt index, gather stats mới, đổi OFE
- Có (hoặc dựng được) STS đại diện
- Muốn phát hiện plan regression **sớm và rẻ**

**Chọn EXECUTION_TYPE:**
- Trên production / chỉ cần so plan → `EXPLAIN PLAN` (an toàn)
- Trên bản test / cần stats runtime thật → `TEST EXECUTE`
- Đã có stats trong STS, muốn nhanh → `CONVERT SQLSET`

**Dùng SPA + DB Replay cùng nhau khi:**
- Thay đổi lớn (upgrade major, migration): SPA trước bắt plan regression → DB Replay validate concurrency

**KHÔNG dùng / cẩn thận:**
- TEST EXECUTE trên production (side effect + tài nguyên)
- Kết luận an toàn từ STS nghèo nàn
- Dựa SPA cho vấn đề concurrency (đó là việc của DB Replay)

**Anti-patterns:**
- OFE toggle coi như test nâng cấp đầy đủ (chỉ là proxy plan)
- Bỏ qua bind sensitivity → mù regression theo bind
- Thấy regressed SQL nhưng không có kế hoạch SPM baseline
- STS 1 phút giờ thấp điểm rồi tuyên bố "upgrade an toàn"

---

## 5. Key SQL / Commands

```sql
-- 5.1 Tao STS + capture tu cursor cache (loc theo schema)
EXEC DBMS_SQLTUNE.CREATE_SQLSET(SQLSET_NAME=>'SOE_WKLD_STS', SQLSET_OWNER=>'SOE', -
     DESCRIPTION=>'SQL to assess for upgrade')

BEGIN
  DBMS_SQLTUNE.CAPTURE_CURSOR_CACHE_SQLSET(
    SQLSET_NAME=>'SOE_WKLD_STS', SQLSET_OWNER=>'SOE',
    TIME_LIMIT=>60, REPEAT_INTERVAL=>3,
    BASIC_FILTER=>'UPPER(PARSING_SCHEMA_NAME)=''SOE''',
    CAPTURE_MODE=>DBMS_SQLTUNE.MODE_REPLACE_OLD_STATS);
END;
/

-- 5.2 Xem SQL da capture
SELECT sql_text FROM dba_sqlset_statements WHERE sqlset_name='SOE_WKLD_STS';

-- 5.3 Van chuyen STS sang he test (Data Pump)
EXEC DBMS_SQLTUNE.CREATE_STGTAB_SQLSET('SOE_WKLD_STS_TB','SOE')
EXEC DBMS_SQLTUNE.PACK_STGTAB_SQLSET('SOE_WKLD_STS','SOE','SOE_WKLD_STS_TB','SOE')
-- host: expdp ... tables=SOE_WKLD_STS_TB ; impdp o dich ;
EXEC DBMS_SQLTUNE.UNPACK_STGTAB_SQLSET('SOE_WKLD_STS','SOE',TRUE,'SOE_WKLD_STS_TB','SOE')

-- 5.4 SPA: task + before/after + compare
VARIABLE v_task VARCHAR2(64)
EXEC :v_task := DBMS_SQLPA.CREATE_ANALYSIS_TASK(SQLSET_NAME=>'SOE_WKLD_STS', -
     SQLSET_OWNER=>'SOE', TASK_NAME=>'SPA_SOE_TASK')

EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(TASK_NAME=>'SPA_SOE_TASK', -
     EXECUTION_TYPE=>'TEST EXECUTE', EXECUTION_NAME=>'before')
-- ... AP DUNG THAY DOI (upgrade/OFE/index) ...
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(TASK_NAME=>'SPA_SOE_TASK', -
     EXECUTION_TYPE=>'TEST EXECUTE', EXECUTION_NAME=>'after')
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(TASK_NAME=>'SPA_SOE_TASK', -
     EXECUTION_TYPE=>'COMPARE PERFORMANCE')

-- 5.5 Bao cao (SUMMARY nhanh, HTML/ALL day du)
SELECT DBMS_SQLPA.REPORT_ANALYSIS_TASK('SPA_SOE_TASK', 'TEXT', 'ALL', 'SUMMARY') FROM dual;

-- 5.6 Doc ket qua tu dictionary (cau nao regress)
SELECT * FROM dba_advisor_findings WHERE task_name='SPA_SOE_TASK';

-- 5.7 EXPLAIN PLAN mode (an toan tren production — khong chay SQL)
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(TASK_NAME=>'SPA_SOE_TASK', -
     EXECUTION_TYPE=>'EXPLAIN PLAN', EXECUTION_NAME=>'plan_before')
```

---

## 6. Senior Checklist

1. **STS đại diện trọn business cycle:** gộp cursor cache nhiều thời điểm + AWR top SQL; STS nghèo → SPA "xanh" là giả
2. **TEST EXECUTE chỉ trên bản test:** nó chạy thật (DML có side effect + tốn tài nguyên); trên production chỉ EXPLAIN PLAN
3. **OFE toggle là proxy plan, không phải test upgrade đầy đủ:** đủ để pre-check regression optimizer, không thay thế test bản mới thật
4. **Lường bind sensitivity:** SPA test một bind set/câu; SQL có histogram/bind peeking cần nhiều bind set
5. **Có kế hoạch cho regressed SQL:** SPM/SQL Plan Baselines cố định plan tốt qua thay đổi — SPA tìm, SPM giữ
6. **SPA không thấy concurrency:** lock/contention/throughput là việc của DB Replay; thay đổi lớn dùng cả hai
7. **License RAT:** xác nhận trước; `DBA_FEATURE_USAGE_STATISTICS` ghi nhận khi dùng

---

# LAB EXERCISES

## Exercise 1 — Bắt Plan Regression trước Upgrade bằng SPA

**Scenario:** Sắp nâng cấp DB. Bạn cần biết trước câu SQL nào đổi plan/chậm đi do optimizer mới, trên một hệ test — không đụng production. Mô phỏng "upgrade" bằng `OPTIMIZER_FEATURES_ENABLE`.

**Tasks:**
1. Đặt OFE=11.2.0.2 (before), restart; tạo STS `SOE_WKLD_STS`.
2. Chạy workload SOE (nhiều câu có bind) để nạp cursor cache; capture vào STS; xác nhận `DBA_SQLSET_STATEMENTS`.
3. Tạo SPA task; `TEST EXECUTE` execution 'before'.
4. Đổi OFE=12.2.0.1 (mô phỏng upgrade), restart; `TEST EXECUTE` execution 'after'.
5. `COMPARE PERFORMANCE`; đọc report: câu nào improved / regressed / plan changed.

**Expected Findings:**
- Report phân loại từng SQL: improved / regressed / unchanged / plan changed.
- Một số câu có thể đổi plan giữa hai OFE (đây là mục tiêu bắt được).
- Metric so mặc định = elapsed_time; đổi được sang buffer_gets.

**Debrief Questions:**
- `TEST EXECUTE` khác `EXPLAIN PLAN` thế nào? Trên production dùng cái nào, vì sao?
- Nếu một câu regress, bước tiếp theo để upgrade an toàn là gì?
- STS chỉ có 10 câu — kết luận "upgrade an toàn" đáng tin đến đâu?

---

## Exercise 2 — Vận chuyển STS sang hệ test (Data Pump) + EXPLAIN-only trên "prod"

**Scenario:** Production không được TEST EXECUTE (side effect + tài nguyên). Quy trình đúng: capture STS trên prod (chỉ EXPLAIN mode), chuyển sang hệ test để TEST EXECUTE đầy đủ.

**Tasks:**
1. Trên "prod": capture STS; chạy SPA `EXPLAIN PLAN` mode 'plan_before' (an toàn, không chạy SQL).
2. `PACK_STGTAB_SQLSET` → Data Pump export bảng staging.
3. (Mô phỏng hệ test) import + `UNPACK_STGTAB_SQLSET` vào STS.
4. Trên hệ test: `TEST EXECUTE` before/after quanh thay đổi; compare.
5. So sánh: EXPLAIN mode (prod) chỉ cho plan-diff; TEST EXECUTE (test) cho stats runtime thật.

**Expected Findings:**
- EXPLAIN mode chạy nhanh, không đụng dữ liệu, chỉ so plan.
- Staging table pack/unpack chuyển đúng SQL + context sang hệ khác.
- TEST EXECUTE cho elapsed/buffer_gets thật để so định lượng.

**Debrief Questions:**
- Vì sao không TEST EXECUTE thẳng trên production?
- Data Pump chuyển STS — cái gì được mang theo (text, bind, plan, stats)?
- EXPLAIN mode bỏ sót loại regression nào mà TEST EXECUTE bắt được?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Cuối tuần trước team upgrade DB (11.2 → 19c). Trước upgrade, một script SPA chạy với STS "SOE_WKLD" cho kết quả **"0 regressed, tất cả improved/unchanged"** → team tự tin go-live. Thứ Hai, hai sự cố: (a) một report tài chính chạy 40 phút (trước 4 phút); (b) OLTP giờ cao điểm bị `enq: TX` và `buffer busy waits` tăng vọt, throughput giảm 30% — dù mỗi câu SQL đơn lẻ vẫn nhanh.

**Evidence Provided:**

SPA report trước upgrade (STS SOE_WKLD):
```
Statements analyzed : 47
Improved            : 12
Unchanged           : 35
Regressed           : 0
Plan changed        : 3 (nhung elapsed better)
```

STS SOE_WKLD được capture:
```
Nguon    : CAPTURE_CURSOR_CACHE_SQLSET
Thoi diem: 02:00-02:05 (batch window, 5 phut)
Filter   : PARSING_SCHEMA_NAME='SOE'
```

Report tài chính (câu chạy 40 phút) tra trong STS: **KHÔNG có** trong SOE_WKLD (nó chạy bởi schema `FIN`, lúc 08:30, không phải 02:00).

AWR sau upgrade, giờ cao điểm OLTP:
```
Top events: enq: TX - row lock contention, buffer busy waits, gc buffer busy (nếu RAC)
Per-SQL elapsed: các câu OLTP đơn lẻ ~ bằng hoặc nhanh hơn trước
```

**Your Mission:**
1. SPA báo "0 regressed" nhưng report tài chính chậm 10×. SPA sai, hay dùng sai? Chỉ ra lỗ hổng.
2. Vì sao OLTP bị `enq: TX`/`buffer busy` tăng dù mỗi SQL đơn lẻ vẫn nhanh? SPA có khả năng bắt được vấn đề này không? Vì sao?
3. STS được capture 02:00-02:05 giờ batch, filter schema SOE. Liệt kê mọi thứ SPA đã **mù**.
4. Quy trình change-assurance đúng lẽ ra phải gồm những gì để bắt cả (a) và (b)?
5. Bây giờ đã go-live rồi: đề xuất hành động khắc phục cho report tài chính (a) mà không rollback.

**Evaluation Criteria:**
- SPA không sai — **dùng sai**: STS không đại diện. Report tài chính (schema FIN, 08:30) không nằm trong STS (chỉ SOE, 02:00-02:05) → SPA chưa bao giờ đánh giá nó → "0 regressed" chỉ đúng cho 47 câu SOE, không phải toàn hệ.
- OLTP `enq: TX`/`buffer busy`: đây là vấn đề **concurrency/contention**, xuất hiện khi nhiều session chạy đồng thời — SPA chạy **tuần tự từng SQL**, không mô phỏng concurrency → **không thể** bắt. Mỗi SQL nhanh nhưng tương tác đồng thời (lock, hot block) mới sinh contention → chỉ **DB Replay** (Section 36) thấy.
- SPA mù: (1) SQL của schema khác SOE (filter loại FIN); (2) SQL ngoài cửa sổ 02:00-02:05 (report 08:30, giờ cao điểm OLTP); (3) mọi hiệu ứng concurrency (lock/latch/buffer busy/throughput); (4) SQL bind-sensitive với bind khác bind đã capture; (5) SQL peak không có trong 5 phút batch.
- Quy trình đúng: (i) STS đại diện — capture trọn business cycle (nhiều giờ/ngày), **mọi schema** liên quan (bỏ filter SOE hoặc thêm FIN), gộp AWR top SQL; (ii) chạy SPA (bắt plan regression per-SQL) VÀ (iii) **Database Replay** (bắt concurrency/contention/throughput) — hai tầng bổ sung nhau; (iv) SPM baseline cho câu regressed.
- Khắc phục (a) không rollback: tìm plan cũ tốt của report FIN (AWR/cursor history trước upgrade) → cố định bằng **SQL Plan Baseline (SPM)** hoặc SQL Profile; hoặc gather stats/hint; kiểm plan mới bằng `DBMS_XPLAN` để xác định thao tác đắt (FTS thay index? sai join order?) rồi ép plan cũ.
- **Bonus:** chỉ ra bài học license/quy trình: SPA + DB Replay đều thuộc RAT; và cảnh báo "SPA all green" không bao giờ nên là cổng go-live duy nhất cho major upgrade — STS coverage + concurrency test là bắt buộc.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_35_sql_performance_analyzer_senior_guide.md`
