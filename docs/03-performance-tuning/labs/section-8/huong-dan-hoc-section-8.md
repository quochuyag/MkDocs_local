---
title: 📚 Hướng dẫn học Section 8 — Instance Activity Statistics & Wait Events (thực hành
  trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_8/HUONG_DAN_HOC_SECTION_8.md
---

# 📚 Hướng dẫn học Section 8 — Instance Activity Statistics & Wait Events (thực hành trong Linux VM)

> Số đo mẫu trong file này là **số thật đo trên VM 2026-07-14**.
> Thời lượng gợi ý: ~75 phút (lecture 15' + lab 45' + debrief 15').
> Nguồn: Practice 3 (Ahmed Baraka) + guide [section_all/section_8_instance_activity_wait_events_guide.md](../../section-all/section-8-instance-activity-wait-events-guide.md) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Section 6 cho biết DB time chia thành CPU và WAIT. Section này trả lời: **đang chờ CÁI GÌ, và AI chờ?** — bằng bản đồ 6 view, phân biệt theo 2 câu hỏi: *thống kê gì?* và *cấp nào?*

| | Cấp instance | Cấp session | Chính session mình |
|---|---|---|---|
| **Activity stats** (đếm việc ĐÃ làm: logical reads, commits, table scans...) | `V$SYSSTAT` | `V$SESSTAT` (join `V$STATNAME` mới có tên) | `V$MYSTAT` |
| **Wait events** (đếm thời gian CHỜ) | `V$SYSTEM_EVENT` | `V$SESSION_EVENT` | — |
| **Đang chờ gì NGAY LÚC NÀY** (ảnh chụp tức thời) | — | `V$SESSION` (event, state, seconds_in_wait) | — |

**3 quy tắc đọc phải thuộc trước khi vào lab:**

1. Mọi số đều **cộng dồn** → chạy query 2 lần, số phải TĂNG, ý nghĩa nằm ở phần chênh.
2. Trong `V$SESSION`: `WAIT_TIME = 0` + `STATE = WAITING` nghĩa là **ĐANG chờ** (nhìn `SECONDS_IN_WAIT`); `WAIT_TIME > 0` là wait **ĐÃ XONG**. Đọc nhầm cột → kết luận ngược.
3. Mọi view `V$SESSION*` **chết theo session** — logout là mất sạch.

**Chuỗi tư duy của lab:** sinh tải nền → đọc 6 view khi số liệu đang "sống" → điều tra một session bị treo thật (enq: TX).

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
cd /labs/section_8   # ⚠️ BẮT BUỘC: script gọi ../_toolkit/ và lock_demo.sh
```

### 1.3. Kiểm tra môi trường sẵn sàng

```bash
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS.

---

## 2. Lab chính (~45 phút)

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Tạo bảng LAB_EMP: `@01_setup.sql` (user `soe`, ~30 giây)

Chỉ bước này chạy bằng soe (bảng phải thuộc schema soe để 2 phiên SOE tranh lock):

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

```sql
@01_setup.sql
exit
```

**Output kỳ vọng:** `LAB_EMP` 200 rows — nhân vật chính là `EMP_NO = 104` (row mà blocker và victim sẽ tranh nhau ở bước 4).

### Bước 2 — Sinh tải nền: `@02_workload.sql` (user `system`, trả về ngay)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

🤔 **Dự đoán:** 4 phiên chạy CÙNG MỘT procedure trên máy 2 vCPU — wait class nào sẽ nổi lên: User I/O, Commit, hay Concurrency?

```sql
@02_workload.sql
```

**Khác các lab trước:** KHÔNG đo trước/sau — tải chạy nền 180 giây và script trả về NGAY, vì bài này học **cách đọc số liệu đang sống**. Chạy bước 3 lập tức khi tải còn chạy.

### Bước 3 — Đọc 6 view: `@03_diagnose.sql` (chạy NHIỀU LẦN, ~10 phút)

```sql
@03_diagnose.sql
-- đợi 20-30 giây...
@03_diagnose.sql   -- lần 2: so số nào tăng
```

**Kết quả thật (2026-07-14) và cách đọc từng phần:**

| Phần | Thấy gì | Bài học |
|---|---|---|
| [1] V$SYSSTAT theo class | Hàng trăm stat chia class User/Redo/Cache... | Không ai đọc hết — biết cách LỌC theo tên (vd `table scan%`) |
| [2] V$SESSTAT top logical reads | Các SID của SOE dẫn đầu | V$SESSTAT không có tên stat → phải join V$STATNAME |
| [3] V$MYSTAT | Số của CHÍNH session system này | Dùng làm "đồng hồ cá nhân" khi đo before/after |
| [4] V$SYSTEM_EVENT | Top wait: **Concurrency ~52%** (`cursor: pin S`, `latch: cache buffers chains`) | Đặc trưng của nhiều session chạy CÙNG MỘT SQL trên máy ít CPU |
| [6] V$SESSION_EVENT `log file sync` | Từng phiên SOE có total_waits tăng dần giữa 2 lần chạy | Tải commit liên tục → event Commit class |
| [7] V$SESSION | Có thể ra 0 row! | V$SESSION = **ảnh chụp khoảnh khắc**; V$SESSION_EVENT = cộng dồn cả đời session |

### Bước 4 — Use case: điều tra session treo: `@04_usecase_hung_session.sql` (~2.5 phút, tự động)

Kịch bản `lock_demo.sh` tự dựng bằng 2 phiên SOE thật: T+0 blocker UPDATE row 104 KHÔNG commit (giữ 75s) → T+3 victim UPDATE đúng row đó → TREO với `enq: TX - row lock contention` → T+75 blocker rollback.

🤔 **Dự đoán:** trong lúc victim ĐANG treo — (1) `WAIT_TIME` của nó bằng bao nhiêu? (2) `V$SESSION_WAIT_HISTORY` đã có event `enq: TX` chưa?

```sql
@04_usecase_hung_session.sql
```

**Các mốc output thật (victim SID 38 trong lần đo mẫu):**

1. **[A] Đang treo:** `STATE=WAITING`, `WAIT_TIME=0`, `SECONDS_IN_WAIT` 12 → 32 (đo 2 lần cách 20s, phải TĂNG). P1/P2/P3 cho biết chi tiết enqueue.
2. **[B] Đang treo:** `V$SESSION_WAIT_HISTORY` = **0 row** — view này CHỈ ghi wait đã hết hạn!
3. **[C] Sau khi blocker rollback:** event biến khỏi `V$SESSION`, nhưng `V$SESSION_EVENT` ghi lại 1 wait ≈ 72s, và wait history giờ MỚI có row (7202 centi-giây).
4. ~40 giây sau 2 phiên thoát → **mọi dấu vết biến mất** — muốn truy vết quá khứ phải có AWR (Section 9) / ASH (Section 13).

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 rồi `vagrant halt` trên host.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Muốn biết "hệ thống đang chờ gì nhiều nhất từ lúc startup" dùng view nào? "Session X đời nó đã chờ gì" dùng view nào? "Session X NGAY LÚC NÀY đang chờ gì"?
2. V$SESSTAT thiếu cột NAME — phải join với view nào?
3. Vì sao lúc victim đang treo, `V$SESSION_WAIT_HISTORY` chưa có `enq: TX`?
4. P1/P2/P3 của một wait event tra nghĩa ở đâu?
5. Idle wait (`SQL*Net message from client`) có đáng lo không? Khi nào có?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Instance từ startup: **V$SYSTEM_EVENT** (sắp theo `time_waited`). Cả đời session X: **V$SESSION_EVENT** (lọc theo SID). Ngay lúc này: **V$SESSION** (cột event/state/seconds_in_wait — 1 row mỗi session, luôn có "wait hiện tại hoặc gần nhất").
2. **V$STATNAME**, join qua `statistic#`. (V$MYSTAT cũng thiếu tên như vậy.)
3. Vì `V$SESSION_WAIT_HISTORY` chỉ ghi **10 wait ĐÃ KẾT THÚC** gần nhất của session. Wait đang diễn ra chưa có "thời lượng cuối cùng" nên chưa được ghi — nó chỉ hiện trong V$SESSION. Đây là bẫy kinh điển: soi wait history lúc session đang treo và kết luận nhầm "không chờ gì".
4. **V$EVENT_NAME** — cột `parameter1/2/3` cho biết P1/P2/P3 của event đó nghĩa là gì (vd `enq: TX`: P1=name|mode, P2=usn<<16|slot, P3=sequence). Trong V$SESSION cũng có sẵn `p1text/p2text/p3text`.
5. Bình thường KHÔNG — idle wait nghĩa là DB rảnh, đang chờ client gửi việc. Đáng lo khi **ứng dụng kêu chậm mà DB toàn idle wait** → nút thắt nằm NGOÀI database (app server, network, connection pool) — đó cũng là một chẩn đoán giá trị: "không phải lỗi DB".

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open file "../_toolkit/..."` | Không đứng ở `/labs/section_8` → `cd /labs/section_8` rồi vào lại sqlplus |
| Bước 4 không thấy session treo ([A1] 0 row) | Job lock_demo chưa kịp chạy (VM chậm) hoặc credential hỏng → đợi 10s query lại tay; nếu job FAILED: đặt lại password OS oracle (`chpasswd`, xem [labs/README.md](../readme.md)) |
| [6] không thấy `log file sync` | Tải 02 đã hết (180s) → chạy lại `@02_workload.sql` (vô hại) |
| `ORA-00942` khi soe chạy toolkit | soe thiếu grant sau restore snapshot → bằng SYS: `GRANT SELECT ON sys.v_$session_event TO soe;` |
| [7] ra 0 row | Bình thường! Khoảnh khắc chụp không session nào đang trong non-idle wait — chính là bài học V$SESSION = ảnh tức thời |
| sqlplus: command not found | Thiếu `-i` khi sudo → `sudo -u oracle -i` |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 9 — AWR (giải bài toán "dấu vết biến mất khi session thoát" vừa gặp ở bước 4)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_8/HUONG_DAN_HOC_SECTION_8.md`
