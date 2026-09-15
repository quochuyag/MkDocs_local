---
title: 'Section 36 — Database Replay: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_36_database_replay_senior_guide.md
---

# Section 36 — Database Replay: Senior DBA Guide

**Nguồn:** Practice 38 (PDF gốc) + section_all guide + Oracle internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Database Replay tái tạo **TOÀN BỘ workload production** — mọi session, đúng concurrency, timing, think time, thứ tự — chạy lại trên hệ test đã áp thay đổi. Nó trả lời câu hỏi mà SPA (Section 35) không trả lời được: **"Tải thật sự đồng thời của production sẽ hành xử/scale ra sao dưới thay đổi này?"**

```
SPA        → từng SQL, plan regression, tuần tự      → nhẹ, bắt regression sớm
DB Replay  → TOÀN workload, concurrency thật         → nặng, bắt lock/contention/throughput
```

SPA thấy plan; DB Replay thấy **hệ thống dưới tải**: lock contention, buffer busy, latch, thứ tự commit, throughput. Một thay đổi có thể "SPA all green" nhưng làm sập concurrency — chỉ DB Replay lộ ra. Đây là công cụ **change assurance cấp hệ thống** cho những thay đổi lớn: upgrade, migration OS/hardware, RAC, storage, consolidation.

Năm pha bắt buộc:

```
Capture (prod) → Preprocess (test) → [ÁP THAY ĐỔI] → Replay (test, qua wrc) → Report
```

---

## 2. Internals & Mechanics

### Pha 1 — Capture (trên production)

`DBMS_WORKLOAD_CAPTURE.START_CAPTURE` ghi **mọi external client request** (SQL + bind + timing + thông tin session) vào **capture files** trong một directory object. Đặc điểm:
- **Filters** INCLUDE/EXCLUDE theo USER/MODULE/ACTION/PROGRAM/SERVICE/PDB (`DEFAULT_ACTION` quyết định filter là bao gồm hay loại trừ). Không filter = bắt tất cả.
- Nên `STARTUP RESTRICT` trước khi bắt đầu → tránh transaction dở dang lúc capture khởi động (khi capture start, DB tự chuyển sang unrestricted).
- Ghi lại **start SCN** → hệ test **phải** được phục hồi về đúng SCN này để dữ liệu nhất quán khi replay.
- Directory phải **rỗng** (ORA-15505 nếu không).
- Capture cũng tạo **AWR snapshot** → sau này AWR-diff capture vs replay.

### Pha 2 — Preprocess (trên hệ test)

`DBMS_WORKLOAD_REPLAY.PROCESS_CAPTURE(dir)` chuyển capture files thô thành **metadata sẵn sàng replay**. Preprocess **phụ thuộc version** → phải preprocess trên đúng version đích. Chạy một lần cho mỗi version target.

### Pha 3 — Replay (trên hệ test)

- `INITIALIZE_REPLAY` nạp metadata từ file vào bảng.
- `PREPARE_REPLAY` đặt các tham số quyết định độ trung thực:
  - **SYNCHRONIZATION**: `SCN` (giữ đúng thứ tự commit — concurrency chính xác) hoặc `OBJECT_ID`/`OFF` (lỏng hơn, ít serialize hơn).
  - **CONNECT_TIME_SCALE / THINK_TIME_SCALE**: co/giãn thời gian kết nối và nghĩ (100 = giữ nguyên; <100 = nén tải dày hơn — stress test).
  - **THINK_TIME_AUTO_CORRECT**: tự bù nếu replay chậm hơn capture.
- **wrc (Workload Replay Client)**: tiến trình OS ngoài (không phải SQL) thực sự đẩy request. `wrc ... mode=calibrate` cho biết cần bao nhiêu client; `wrc user/pass@db replaydir=...` khởi động client (chờ "Wait for the replay to start").
- `START_REPLAY()` bắt đầu — các wrc client đồng loạt đẩy workload.

### Pha 4 — Divergence & Report

Replay có thể **lệch (diverge)** so với capture: kết quả/lỗi khác nếu dữ liệu/trạng thái test khác production. Vì thế test DB **phải** ở đúng data state của capture-start SCN. `DBMS_WORKLOAD_REPLAY.REPORT` so **DB Time, user calls, errors, divergence** giữa capture và replay; kèm AWR cả hai. Divergence/error cao = replay không đại diện → kiểm data state + external references.

### External references phải resolve/remap

DB link, external table, directory object, URL trong workload → khi replay ở hệ test có thể trỏ sai đích. `DBA_WORKLOAD_CONNECTION_MAP` + `REMAP_CONNECTION` để ánh xạ connection sang đích test đúng. Bỏ qua → replay gọi nhầm hệ ngoài.

### Thời gian & đồng hồ hệ thống — bẫy time-sensitive

SQL phụ thuộc `SYSDATE`/`SYSTIMESTAMP` sẽ sai nếu đồng hồ test khác thời điểm capture. Phải set clock test = thời điểm capture-start. Trên VirtualBox, guest **tự đồng bộ giờ với host** (`GetHostTimeDisabled`) → phải tắt tính năng này (bằng `VBoxManage setextradata ... GetHostTimeDisabled 1`) trước replay, nếu không mọi `date -s` bị ghi đè.

---

## 3. Production Realities

### Bước khó nhất: phục hồi test DB về capture-start SCN

Để replay không lệch, test DB phải ở đúng data state lúc capture bắt đầu: `RESTORE DATABASE` từ backup + `RECOVER DATABASE UNTIL SCN <capture_scn>` + `OPEN RESETLOGS`. Điều này đòi backup + archivelog đầy đủ của production (Practice bật ARCHIVELOG + RMAN backup trước capture). Không làm đúng bước này → divergence khổng lồ → report vô nghĩa. Đây là phần tốn công/rủi ro nhất, không phải bản thân replay.

### Capture overhead nhỏ nhưng capture files lớn

Capture trên production overhead thấp (chỉ ghi request), nhưng **file có thể rất lớn** cho workload nặng/dài → cần dung lượng directory. Lên kế hoạch chỗ chứa + thời lượng capture (đủ dài để đại diện peak, không quá dài gây phình file).

### Replay không "bằng" production 1:1

Ngay cả cấu hình hoàn hảo, replay là **xấp xỉ**: thời gian mạng, think time được mô phỏng, một số thao tác không capture được (nhiều loại background, một số PL/SQL nội bộ). Đọc report để hiểu **mức divergence chấp nhận được**, không kỳ vọng khớp tuyệt đối. Mục tiêu là **so sánh tương đối** before/after change, không phải tái tạo hoàn hảo.

### SYNCHRONIZATION=SCN đánh đổi trung thực lấy tốc độ

`SCN` giữ đúng thứ tự commit → concurrency/data divergence thấp nhất, NHƯNG có thể **serialize** (replay chậm hơn, ít song song hơn thực) → không phản ánh đúng throughput. `OFF` cho throughput thực hơn nhưng data divergence cao hơn. Chọn theo mục tiêu: test **correctness/concurrency** → SCN; test **throughput/scalability** → cân nhắc OFF + chấp nhận divergence. `[⚠️ verify]` theo phiên bản.

### License — Real Application Testing

Database Replay thuộc **RAT option — tính phí riêng** (chung gói SPA). `DBA_FEATURE_USAGE_STATISTICS`. Xác nhận license trước khi capture trên production.

### wrc client & vận hành

Cần đủ wrc client (calibrate); nhiều stream/host → nhiều client, có thể trên nhiều máy. Bẫy: mật khẩu SYSTEM sắp hết hạn → `wrc` login fail (ORA-15552). Replay chạy dài → giám sát `DBA_WORKLOAD_REPLAYS` (STATUS, USER_CALLS, DBTIME, ERROR_CODE) và `V$WORKLOAD_REPLAY_THREAD`.

---

## 4. Decision Framework

**Dùng Database Replay khi:**
- Validate thay đổi **lớn** ảnh hưởng toàn hệ: upgrade major, migration OS/hardware/storage, chuyển RAC, consolidation, đổi tham số instance ảnh hưởng concurrency
- Cần biết hệ thống **dưới tải đồng thời thật** hành xử ra sao (lock/contention/throughput), không chỉ per-SQL
- Có khả năng phục hồi test DB về capture-start SCN (backup + archivelog)
- Có license RAT

**Dùng SPA thay vì DB Replay khi:**
- Chỉ cần kiểm plan/hiệu năng **từng SQL** (rẻ hơn nhiều, không cần restore-to-SCN, không cần clock/wrc)

**Dùng cả hai:**
- Major upgrade: SPA trước (bắt plan regression sớm, rẻ) → DB Replay sau (validate concurrency/throughput trước go-live)

**Cấu hình replay:**
- Test correctness/concurrency → `SYNCHRONIZATION=SCN`
- Test throughput/scalability → cân nhắc lỏng hơn + chấp nhận divergence
- Stress test → `THINK_TIME_SCALE`/`CONNECT_TIME_SCALE` < 100 (nén tải)

**Anti-patterns:**
- Replay mà không restore test DB về capture SCN → divergence rác
- Quên clock/GetHostTime trên VM → SYSDATE lệch, workload time-sensitive sai
- Capture cửa sổ ngắn không đại diện peak
- Bỏ qua divergence/errors trong report rồi tuyên bố "an toàn"
- Quên remap external connections (db link/dir/URL) → gọi nhầm hệ ngoài
- Chạy capture trên production không có license RAT

---

## 5. Key SQL / Commands

```sql
-- 5.1 CHUAN BI CAPTURE (production): directory + filter + restricted + SCN
CREATE DIRECTORY workload_dir AS '/home/oracle/workload';   -- phai RONG
BEGIN
  DBMS_WORKLOAD_CAPTURE.ADD_FILTER(
    FNAME=>'INCLUDE_SOE', FATTRIBUTE=>'USER', FVALUE=>'SOE');
END;
/
SELECT fname, attribute, value FROM dba_workload_filters;   -- (10g: DBA_WORKLOAD_FILTERS)
-- STARTUP RESTRICT (tranh txn do dang), roi:
SELECT current_scn FROM v$database;                          -- GHI LAI cho restore

-- 5.2 CAPTURE
BEGIN
  DBMS_WORKLOAD_CAPTURE.START_CAPTURE(
    NAME=>'SOE_CAPTURE', DIR=>'WORKLOAD_DIR',
    DEFAULT_ACTION=>'EXCLUDE',   -- filter la INCLUSION (chi SOE)
    DURATION=>300);              -- giay; NULL = cho FINISH_CAPTURE tay
END;
/
-- ... sinh tai (Swingbench / phien SOE that) ...
EXEC DBMS_WORKLOAD_CAPTURE.FINISH_CAPTURE()    -- neu muon dung som

SELECT id, name, status, connects, user_calls, awr_begin_snap, awr_end_snap
FROM   dba_workload_captures WHERE id=(SELECT MAX(id) FROM dba_workload_captures);
SELECT DBMS_WORKLOAD_CAPTURE.REPORT(&cap_id,'HTML') FROM dual;   -- bao cao capture

-- 5.3 PREPROCESS (test system, dung version dich)
EXEC DBMS_WORKLOAD_REPLAY.PROCESS_CAPTURE('WORKLOAD_DIR')

-- 5.4 REPLAY init + prepare + remap
EXEC DBMS_WORKLOAD_REPLAY.INITIALIZE_REPLAY(REPLAY_NAME=>'SOE_CAPTURE', REPLAY_DIR=>'WORKLOAD_DIR')
SELECT replay_id, conn_id, capture_conn, replay_conn FROM dba_workload_connection_map ORDER BY 1,2;
-- EXEC DBMS_WORKLOAD_REPLAY.REMAP_CONNECTION(CONNECTION_ID=>1, REPLAY_CONNECTION=>'srv1:1521/ORADB')
EXEC DBMS_WORKLOAD_REPLAY.PREPARE_REPLAY(SYNCHRONIZATION=>'SCN', -
     CONNECT_TIME_SCALE=>100, THINK_TIME_SCALE=>100, THINK_TIME_AUTO_CORRECT=>TRUE)

-- 5.5 wrc (OS, khong phai SQL) + START_REPLAY
--   wrc replaydir=/home/oracle/workload mode=calibrate     (bao can bao nhieu client)
--   wrc system/oracle@ORADB replaydir=/home/oracle/workload  (khoi dong client, cho)
EXEC DBMS_WORKLOAD_REPLAY.START_REPLAY()

-- 5.6 GIAM SAT replay
SELECT id, capture_id, status, num_clients, num_clients_done,
       user_calls, dbtime, network_time, think_time, error_code
FROM   dba_workload_replays ORDER BY id;
SELECT logon_user, wrc_id, COUNT(*) FROM v$workload_replay_thread
GROUP  BY logon_user, wrc_id ORDER BY 1,2;

-- 5.7 BAO CAO replay (so capture vs replay)
DECLARE
  v_cap NUMBER; v_rep NUMBER; v_rpt CLOB;
BEGIN
  v_cap := DBMS_WORKLOAD_REPLAY.GET_REPLAY_INFO(REPLAY_DIR=>'WORKLOAD_DIR');
  SELECT MAX(id) INTO v_rep FROM dba_workload_replays WHERE capture_id=v_cap;
  v_rpt := DBMS_WORKLOAD_REPLAY.REPORT(REPLAY_ID=>v_rep, FORMAT=>DBMS_WORKLOAD_REPLAY.TYPE_HTML);
END;
/
```

---

## 6. Senior Checklist

1. **Restore test DB về capture-start SCN:** ghi SCN lúc capture; backup+archivelog đầy đủ; `RECOVER UNTIL SCN` + `OPEN RESETLOGS` — bỏ bước này thì divergence rác, report vô nghĩa
2. **Xử lý đồng hồ time-sensitive:** set clock test = thời điểm capture; trên VM tắt `GetHostTimeDisabled` trước, nếu không SYSDATE lệch
3. **Capture đại diện peak:** đủ dài + đúng cửa sổ tải cao + filter đúng phạm vi; cửa sổ ngắn/thấp điểm → replay không đại diện
4. **Remap external references:** db link/external table/dir/URL qua `DBA_WORKLOAD_CONNECTION_MAP` + `REMAP_CONNECTION` — tránh gọi nhầm hệ ngoài
5. **Chọn SYNCHRONIZATION đúng mục tiêu:** SCN cho correctness/concurrency (có thể serialize); lỏng hơn cho throughput (divergence cao hơn)
6. **Đọc divergence + errors trong report:** cao = replay không tin được → kiểm data state/external refs; đừng tuyên bố "an toàn" khi divergence lớn
7. **License RAT + vận hành wrc:** xác nhận license; đủ wrc client (calibrate); coi chừng mật khẩu SYSTEM hết hạn (ORA-15552); giám sát `DBA_WORKLOAD_REPLAYS`

---

# LAB EXERCISES

## Exercise 1 — Vòng đời đầy đủ 5 pha (Capture → Preprocess → Change → Replay → Report)

**Scenario:** Bạn cần validate rằng "upgrade" (mô phỏng bằng OFE) không làm giảm throughput của workload SOE đồng thời. Thực hiện trọn 5 pha Database Replay trên một VM test (đóng vai cả prod lẫn test), có snapshot.

**Tasks:**
1. Chuẩn bị: OFE=11.2.0.2 (before), tạo `WORKLOAD_DIR` (rỗng), thêm filter USER=SOE, `STARTUP RESTRICT`, ghi lại `CURRENT_SCN`.
2. `START_CAPTURE` (duration ngắn) → sinh tải SOE đồng thời (nhiều phiên) → `FINISH_CAPTURE`; xem `DBA_WORKLOAD_CAPTURES` + report.
3. `PROCESS_CAPTURE`; áp "upgrade" OFE=12.2.0.1 + restart.
4. `INITIALIZE_REPLAY` → `PREPARE_REPLAY(SYNCHRONIZATION=SCN)` → wrc calibrate → khởi động wrc client → `START_REPLAY`.
5. Giám sát `DBA_WORKLOAD_REPLAYS`; sau khi xong, sinh replay report; đọc divergence/errors + so DB Time capture vs replay.

**Expected Findings:**
- Capture files xuất hiện trong WORKLOAD_DIR; `DBA_WORKLOAD_CAPTURES` STATUS=COMPLETED.
- wrc calibrate gợi ý số client; replay chạy qua các wrc client; `DBA_WORKLOAD_REPLAYS` tiến triển.
- Report so capture vs replay: DB Time, user calls, **data/error divergence** (trên VM cùng máy không restore-to-SCN chuẩn → divergence sẽ khác 0, đây là điểm học).

**Debrief Questions:**
- Vì sao nên `STARTUP RESTRICT` + ghi SCN trước capture?
- `PREPARE_REPLAY` SYNCHRONIZATION=SCN đánh đổi gì so với OFF?
- Trên VM cùng máy không restore-to-SCN, vì sao divergence cao? Thực tế production làm gì để tránh?

---

## Exercise 2 — Filter, Scale, và Divergence: điều khiển độ trung thực

**Scenario:** Bạn muốn (a) chỉ capture workload của schema SOE, loại phần còn lại; (b) chạy replay như một **stress test** (nén think time để tải dày hơn); (c) hiểu con số divergence nghĩa là gì.

**Tasks:**
1. Thêm filter INCLUDE USER=SOE với `DEFAULT_ACTION=EXCLUDE`; xác nhận `DBA_WORKLOAD_FILTERS`.
2. Capture; kiểm chỉ session SOE được ghi (`DBA_WORKLOAD_CAPTURES.CONNECTS`/`USER_CALLS`).
3. `PREPARE_REPLAY` với `THINK_TIME_SCALE=10` (nén 10× → tải dày hơn) và so với 100.
4. Chạy replay; đọc report: `DBTIME`, `NETWORK_TIME`, `THINK_TIME`, và các cột divergence.
5. Giải thích khác biệt giữa replay THINK_TIME_SCALE=10 vs 100.

**Expected Findings:**
- Filter loại đúng phần ngoài SOE.
- THINK_TIME_SCALE=10 → replay chạy nhanh/dày hơn (ít thời gian nghĩ) → tải đồng thời cao hơn.
- Report tách DBTIME (làm việc thật) vs THINK_TIME (nghĩ) vs NETWORK_TIME.

**Debrief Questions:**
- `DEFAULT_ACTION=EXCLUDE` + filter INCLUDE SOE nghĩa là gì? Nếu `DEFAULT_ACTION=INCLUDE` thì filter thành gì?
- Nén THINK_TIME dùng để test cái gì? Rủi ro của nó?
- Divergence cao có luôn nghĩa "thay đổi làm hỏng"? Còn nguyên nhân nào khác?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Team dùng Database Replay để validate một upgrade lớn (11.2 → 19c) trước go-live. Sau khi chạy, replay report cho **divergence 62%** và **hàng nghìn error ORA-01403 (no data found) + ORA-00001 (unique violation)**. Kết luận vội của một DBA: "19c làm hỏng ứng dụng, hoãn upgrade". Bạn được gọi review trước khi báo cáo lên cấp trên.

**Evidence Provided:**

Quy trình đã làm (từ runbook):
```
1. Capture trên prod (11.2), duration 30 phut, filter USER=SOE, ghi SCN=15,829,004
2. Preprocess tren test (19c)
3. OFE khong dat — test da la 19c that (upgrade that)
4. Test DB: KHOI PHUC tu "backup moi nhat cua test" (khong phai backup prod tai SCN capture)
5. PREPARE_REPLAY SYNCHRONIZATION=SCN, THINK_TIME_SCALE=100
6. wrc + START_REPLAY
```

Replay report (trích):
```
Data divergence          : 62%
Error divergence         : cao (ORA-01403 x 4,201 ; ORA-00001 x 1,880)
DB Time (capture)        : 1,240 s
DB Time (replay)         : 1,190 s   (≈ tương đương)
DBA_WORKLOAD_CONNECTION_MAP: 3 external db-link connections CHUA remap
```

Clock hệ test:
```
Capture start time : 02:14:00 ngay 12/07
Replay clock       : 09:40:00 ngay 15/07  (khong set ve thoi diem capture)
VirtualBox GetHostTimeDisabled : chua tat
```

**Your Mission:**
1. DBA kết luận "19c làm hỏng app". Đúng hay sai? Liệt kê mọi nguyên nhân **quy trình** gây divergence/error, tách khỏi khả năng "19c thực sự có vấn đề".
2. Bước 4 (khôi phục test từ backup của test, không phải prod-tại-SCN-capture) gây hậu quả gì? Vì sao sinh ORA-01403 và ORA-00001?
3. Clock replay 09:40 ngày 15/07 (không set về 02:14 ngày 12/07) + GetHostTime chưa tắt → ảnh hưởng gì? Cho ví dụ loại SQL sẽ sai.
4. 3 db-link chưa remap → rủi ro gì khi replay?
5. `DB Time capture ≈ replay (1,240 vs 1,190s)` — con số này có nói lên điều gì tích cực không, giữa đống divergence? Đề xuất quy trình replay đúng để có kết luận đáng tin về upgrade.

**Evaluation Criteria:**
- Sai — không thể kết luận "19c hỏng app" từ replay này vì **quy trình sai** làm divergence không phản ánh thay đổi 19c. Nguyên nhân quy trình: (i) test DB không restore về capture SCN; (ii) clock không set về thời điểm capture + GetHostTime chưa tắt; (iii) db-link chưa remap. Ba lỗi này tự sinh divergence độc lập với chất lượng 19c.
- Bước 4: test DB ở **data state khác** với lúc capture (SCN 15,829,004). Workload replay giả định dữ liệu như production tại SCN đó → SELECT kỳ vọng row tồn tại nhưng test không có → **ORA-01403**; INSERT với key mà production chưa có nhưng test đã có (do state khác) → **ORA-00001**. Đây là divergence **do data state sai**, không phải do 19c. Phải `RESTORE` từ backup **prod** + `RECOVER UNTIL SCN 15,829,004` + `OPEN RESETLOGS`.
- Clock: SQL phụ thuộc `SYSDATE`/`SYSTIMESTAMP` (ví dụ `WHERE order_date >= TRUNC(SYSDATE)`, insert `SYSDATE`, tính tuổi/hạn) sẽ trả kết quả khác vì replay ở 15/07 thay vì 12/07 → thêm divergence. GetHostTime chưa tắt → mọi `date -s` bị VirtualBox ghi đè về giờ host → không set được clock → time-sensitive sai. Phải tắt GetHostTimeDisabled rồi set clock về 02:14 12/07.
- db-link chưa remap: replay có thể **gọi sang hệ ngoài thật** (production remote?) qua db-link chưa ánh xạ → tác dụng phụ nguy hiểm (ghi vào hệ thật) hoặc lỗi kết nối → thêm error/divergence. Phải `REMAP_CONNECTION` sang đích test.
- `DB Time ≈` (1,240 vs 1,190s): tín hiệu tích cực — tổng khối lượng công việc replay ≈ capture, gợi ý 19c **không** làm workload nặng lên rõ rệt ở mức tổng. Nhưng KHÔNG kết luận được gì chắc chắn khi divergence 62% (nhiều câu lỗi giữa chừng nên DB Time không so được công bằng). Quy trình đúng: (1) restore test = prod tại capture SCN; (2) tắt GetHostTime + set clock về capture time; (3) remap mọi external connection; (4) chạy lại replay → khi đó divergence thấp thì mới đọc DB Time/AWR-diff/plan để kết luận 19c an toàn hay không; (5) kết hợp **SPA** (Section 35) để bắt plan regression per-SQL.
- **Bonus:** chỉ ra nên chạy SPA song song (rẻ, bắt plan regression) + lưu ý divergence do quy trình che mất tín hiệu thật → "hoãn upgrade" dựa trên replay hỏng là quyết định tồi; và cảnh báo db-link gọi hệ thật là rủi ro an toàn dữ liệu nghiêm trọng khi replay.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_36_database_replay_senior_guide.md`
