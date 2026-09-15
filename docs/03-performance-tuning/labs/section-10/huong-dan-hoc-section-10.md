---
title: 📚 Hướng dẫn học Section 10 — Server-generated Alerts (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_10/HUONG_DAN_HOC_SECTION_10.md
---

# 📚 Hướng dẫn học Section 10 — Server-generated Alerts (thực hành trong Linux VM)

> Số đo mẫu trong file này là **số thật đo trên VM 2026-07-14**.
> Thời lượng gợi ý: ~60 phút (lecture 15' + lab 35' + debrief 10').
> Nguồn: Practice 8 (Ahmed Baraka) + guide [section_all/section_10_server_generated_alerts_guide.md](../../section-all/section-10-server-generated-alerts-guide.md) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Câu hỏi của section: làm sao để database **TỰ báo động** khi một metric vượt mức bình thường — không cần ai ngồi canh?

| Khái niệm | Nhớ nhanh |
|---|---|
| **Metric** | Số liệu tính SẴN theo cửa sổ 60s (V$SYSMETRIC) — khác V$SYSSTAT cộng dồn phải tự trừ delta. Lab dùng `Database Wait Time Ratio` (metric_id **2107**) |
| **Threshold** | Ngưỡng warning/critical đặt bằng `DBMS_SERVER_ALERT.SET_THRESHOLD`; MMON đánh giá ~mỗi phút |
| **Alert stateful** | Có VÒNG ĐỜI: metric vượt ngưỡng → row trong `DBA_OUTSTANDING_ALERTS`; metric tụt xuống → MMON **tự clear** sang `DBA_ALERT_HISTORY` (resolution=cleared). Không ai phải "ack" |
| **Nguyên tắc VÀNG** | Threshold chỉ có nghĩa khi biết giá trị **BÌNH THƯỜNG** → bước 1 luôn là đo baseline của metric, không đoán ngưỡng |

**⚠️ Điểm CDB quan trọng nhất của lab:** `SET_THRESHOLD` chạy trong PDB dính **ORA-65040** (đã test) — server alert metric SYSTEM là việc của instance, phải làm ở **CDB root** (giống bài học `DB_32K_CACHE_SIZE` của Section 28). Metric có 2 bản: **2107** (CDB-wide — lab dùng) và 18047 (bản PDB).

**Chuỗi tư duy của lab:** đo bình thường → đặt ngưỡng CAO HƠN bình thường → gây bão wait → bắt alert xuất hiện → dừng bão → xem alert tự clear.

---

## 1. Khởi động môi trường (5 phút)

### 1.1. Bật VM (PowerShell trên host)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
```

### 1.2. SSH vào VM và thành user oracle

```powershell
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_10   # ⚠️ BẮT BUỘC: script gọi lock_storm.sh theo đường dẫn /labs
```

### 1.3. Vào SQL*Plus — ⚠️ TOÀN BỘ lab chạy bằng SYS qua CDB ROOT

```bash
sqlplus / as sysdba    # trong VM: vào thẳng CDB root, không cần password
```

> Từ host Windows: `sqlplus "sys/oracle_4U@//localhost:15210/ORCLCDB as sysdba"` (chú ý ORCLCDB, không phải ORADB).
> Sau restore snapshot nhớ đặt lại password OS oracle (`chpasswd`, xem [labs/README.md](../readme.md)) — bão lock chạy qua external job.

---

## 2. Lab chính (SYS @ CDB root, ~35 phút)

### Bước 1 — Đo giá trị BÌNH THƯỜNG: `@01_setup.sql` (~1 phút)

🤔 **Dự đoán trước khi chạy:** hệ thống đang idle, `Database Wait Time Ratio` trung bình 1 giờ qua sẽ cỡ bao nhiêu %? Max có thể lên tới bao nhiêu (các lab trước có ảnh hưởng không)?

```sql
@01_setup.sql
```

**Output thật (2026-07-14):** V$SYSMETRIC_HISTORY 1h: **avg 18%, max 76%** — max cao là "di chứng" các lab tải trước đó. Đây chính là minh họa nguyên tắc vàng: **chọn ngưỡng phải nhìn lịch sử, không đoán** (warning 60 đặt trên avg nhưng lab này chấp nhận vì bão lock sẽ đẩy metric >99%).

Script còn đối chiếu cách đo thứ 3 từ `V$SYS_TIME_MODEL` — số CỘNG DỒN từ startup nên khác metric cửa sổ 60s là bình thường.

### Bước 2 — Đặt threshold + thả bão lock: `@02_workload.sql` (~1 phút)

🤔 **Dự đoán:** bão lock (1 blocker giữ lock 300s + 3 victim treo `enq: TX` — wait thuần, gần như không tốn CPU) sẽ đẩy metric lên bao nhiêu %?

```sql
@02_workload.sql
```

**Các mốc output:**

1. Threshold đặt xong: **warning ≥ 60%, critical ≥ 85%**, observation_period 1 phút, consecutive_occurrences 1. Chú ý value là **%** (0–100), không phải ratio 0–1.
2. Đọc lại threshold 2 cách: `GET_THRESHOLD` (cách course) và view `DBA_THRESHOLDS` — phải khớp.
3. Credential `LAB_OS_CRED` tạo tại ROOT (credential của PDB không dùng chung được!) → job `LAB_LOCK_STORM` chạy `lock_storm.sh`.

### Bước 3 — Bắt alert: `@03_diagnose.sql` (CHẠY LẶP LẠI mỗi 30–60s, ~3 phút)

🤔 **Dự đoán:** từ lúc metric vượt 85% đến lúc alert xuất hiện trong `DBA_OUTSTANDING_ALERTS` mất bao lâu? (gợi ý: cửa sổ metric 60s + chu kỳ MMON ~60s)

```sql
@03_diagnose.sql
-- chưa thấy alert ở [3]? đợi 30-60 giây:
@03_diagnose.sql
```

**Output thật:**

```text
[1] metric nhảy: 0% → 99.51% → 99.96% qua các điểm đo 60s
[2] 3 session SOE treo 'enq: TX - row lock contention', seconds_in_wait ~114s
[3] sau ~1 phút: REASON: Metrics "Database Wait Time Ratio" is at 99.96
    MESSAGE_TYPE: Warning · MESSAGE_LEVEL: 5
    SUGGESTED_ACTION: "Run ADDM..."  ← Oracle tự gợi ý bước chẩn đoán kế tiếp
```

### Bước 4 — Dừng bão, xem alert TỰ clear: `@04_usecase_clear.sql` (~3 phút)

🤔 **Dự đoán:** sau khi dừng bão, ai xóa alert khỏi OUTSTANDING — bạn hay Oracle? Mất bao lâu?

```sql
@04_usecase_clear.sql
-- [3] chưa về 0 / [4] chưa 'cleared'? đợi 1-2 phút chạy lại
@04_usecase_clear.sql
```

**Các mốc output thật:**

1. Script đổi container vào ORADB set cờ dừng (chú ý: **đổi container xong DBMS_OUTPUT bị reset** → script tự `SET SERVEROUTPUT ON` lại — bài cũ Section 28) → blocker rollback ~1s, 3 victim thoát treo.
2. Metric tụt về ~0% trong điểm đo kế tiếp.
3. Sau ~2 phút MMON tự clear: row biến khỏi `DBA_OUTSTANDING_ALERTS`, xuất hiện trong `DBA_ALERT_HISTORY` với `RESOLUTION: cleared` — **không ai phải ack**. Đó là chữ "stateful".

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

Vẫn SYS @ CDB root:

```sql
@99_cleanup.sql
exit
```

**Kỳ vọng:** threshold được gỡ (⚠️ cách đúng là truyền **NULL** cho cả operator lẫn value — dùng `OPERATOR_DO_NOT_CHECK` sẽ dính ORA-13900), dọn cả 2 container. Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (10 phút)

1. Alert "stateful" khác gì cảnh báo kiểu log/email? Ai là người "xóa" alert?
2. Vì sao phải đo giá trị bình thường TRƯỚC khi đặt ngưỡng? Ngưỡng tĩnh có nhược điểm gì (gợi ý: hệ thống có chu kỳ ngày/đêm)?
3. `OBSERVATION_PERIOD` và `CONSECUTIVE_OCCURRENCES` dùng để chống cái gì?
4. Metric 2107 và 18047 khác nhau thế nào? Đặt threshold trong PDB được không?
5. Alert nằm ở view nào khi đang hiệu lực, và chuyển đi đâu sau khi hết?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Stateful = alert có **vòng đời gắn với trạng thái metric**: sinh ra khi vượt ngưỡng, nằm trong OUTSTANDING suốt thời gian còn vi phạm, và được **MMON tự động clear** khi metric về dưới ngưỡng — phản ánh đúng "hiện trạng". Log/email là stateless: bắn 1 lần rồi thôi, không ai biết sự cố còn hay đã hết, người nhận phải tự lần lại.
2. Ngưỡng thấp hơn max bình thường → **báo giả liên tục** → người vận hành nhờn cảnh báo (alert fatigue) và bỏ sót sự cố thật. Ngưỡng tĩnh không thích ứng chu kỳ tải (đêm batch wait ratio cao là bình thường, 10h sáng mà cao là sự cố) → Oracle có **adaptive thresholds** dựa trên baseline `SYSTEM_MOVING_WINDOW` (Section 9) — ngưỡng tự tính theo phân phối lịch sử từng khung giờ.
3. Chống **báo giả do spike thoáng qua**: `OBSERVATION_PERIOD` = độ dài mỗi lần quan sát (phút), `CONSECUTIVE_OCCURRENCES` = số lần vi phạm LIÊN TIẾP mới sinh alert. Ví dụ period 5 + occurrences 3 = chỉ báo khi vi phạm kéo dài ~15 phút.
4. 2107 = `Database Wait Time Ratio` bản **CDB-wide/instance** (đặt ở root); 18047 = bản **per-PDB**. `SET_THRESHOLD` cho metric SYSTEM trong PDB dính **ORA-65040** — threshold instance-level là việc của CDB root. (Một số metric/object khác đặt trong PDB được, nhưng bài này thì không.)
5. Đang hiệu lực: `DBA_OUTSTANDING_ALERTS`. Hết (metric về dưới ngưỡng hoặc gỡ threshold): MMON chuyển sang `DBA_ALERT_HISTORY` với `RESOLUTION = cleared`.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `ORA-65040` khi SET_THRESHOLD | Đang connect vào PDB → phải `sqlplus / as sysdba` (CDB root) |
| `ORA-13900` khi gỡ threshold | Dùng `OPERATOR_DO_NOT_CHECK` → truyền **NULL** cho cả operator lẫn value (xem 99_cleanup.sql) |
| Bão lock không nổ (job FAILED) | Credential/password OS mất sau restore snapshot → `vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"`; nhớ credential phải tạo tại ROOT |
| Chờ mãi không thấy alert ở [3] | MMON đánh giá ~mỗi phút + metric cần trọn 1 cửa sổ 60s vượt ngưỡng → kiên nhẫn 1–3 phút, chạy lại 03; kiểm tra [2] có 3 victim đang treo không |
| DBMS_OUTPUT im lặng sau ALTER SESSION SET CONTAINER | Đổi container reset serveroutput → `SET SERVEROUTPUT ON` lại |
| Threshold đặt 0.85 không bao giờ báo | Value là **%** (0–100), không phải ratio → dùng '85' |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: theo lộ trình — Senior Guide Section 28, rồi lab Section 29 (Table Fragmentation)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_10/HUONG_DAN_HOC_SECTION_10.md`
