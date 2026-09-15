---
title: 📚 Hướng dẫn học Section 6 — Time Model Views (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_6/HUONG_DAN_HOC_SECTION_6.md
---

# 📚 Hướng dẫn học Section 6 — Time Model Views (thực hành trong Linux VM)

> Số đo mẫu trong file này là **số thật đo trên VM 2026-07-14**.
> Thời lượng gợi ý: ~75 phút (lecture 15' + lab 45' + debrief 15').
> Nguồn: Practice 2 (Ahmed Baraka) + guide [section_all/section_6_time_model_guide.md](../../section-all/section-6-time-model-guide.md) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**DB time** = tổng thời gian các session foreground tiêu trong database (CPU + wait non-idle). Đây là "đơn vị tiền tệ" của toàn bộ khóa học — tuning tức là làm giảm DB time cho cùng một khối lượng việc.

| | DB CPU | WAIT (non-idle) |
|---|---|---|
| Là gì | Thời gian thực sự chạy trên CPU | Thời gian ngồi chờ (I/O, lock, latch, CPU queue...) |
| Trần | = số vCPU × thời gian đo (VM này: 2 vCPU) | Không có trần — càng nghẽn càng phình |
| Quan hệ | **DB time = DB CPU + WAIT** — idle wait KHÔNG tính | |

**2 quy tắc đọc số phải thuộc:**

1. `V$SYS_TIME_MODEL` là số **CỘNG DỒN từ lúc instance start** → muốn biết "tải hiện tại" phải chụp 2 thời điểm rồi **trừ nhau (delta)**. Đọc số cộng dồn trực tiếp = bị quá khứ pha loãng.
2. Các stat trong time model **đếm trùng nhau** (cha-con: `sql execute elapsed time` chứa cả thời gian con) → cộng các mục con lại vượt 100% DB time là bình thường.

**Chuỗi tư duy của lab:** chụp baseline không tải → tăng tải 2 → 4 → 8 user → xem DB CPU chạm trần ở đâu và WAIT phình thế nào.

---

## 1. Khởi động môi trường (5 phút)

### 1.1. Bật VM (PowerShell trên host)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up          # chờ ~1-2 phút, DB tự start
```

### 1.2. SSH vào VM và thành user oracle

```powershell
vagrant ssh
```

```bash
sudo -u oracle -i   # KHÔNG có password
cd /labs/section_6  # ⚠️ BẮT BUỘC: script gọi ../_toolkit/ và tm_snap.sql
```

### 1.3. Kiểm tra môi trường sẵn sàng

```bash
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS. (Sau restore snapshot nhớ đặt lại password OS oracle — xem [labs/README.md](../readme.md).)

---

## 2. Lab chính (user `system`, ~45 phút)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Tạo bảng lịch sử: `@01_setup.sql` (~30 giây)

🤔 **Dự đoán trước khi chạy:** khi tăng user ảo 2 → 4 → 8 trên VM chỉ có 2 vCPU, DB CPU và WAIT sẽ tăng theo kiểu nào — cùng tuyến tính, hay một cái chạm trần?

```sql
@01_setup.sql
```

**Output kỳ vọng:** bảng `LAB_TM_HISTORY` được tạo kèm **snapshot #1** (trạng thái chưa tải): DBTIME/DBCPU/WAIT cộng dồn hiện tại + `USERS_CNT`. Ghi nhớ: snapshot chụp bằng file `tm_snap.sql` (giống course), không dùng procedure — vì definer-rights procedure của SYSTEM không compile được static SQL trên V$ view (role DBA bị tắt trong PL/SQL).

### Bước 2 — Sinh tải 3 mức: `@02_workload.sql` (~4 phút, tự động)

🤔 **Dự đoán:** mức 2 user thì WAIT chiếm bao nhiêu %? Mức 8 user thì bao nhiêu?

```sql
@02_workload.sql
```

Script tự chạy: tải 2 user × 60s → chụp snapshot ở giây ~50 → tải 4 user → chụp → tải 8 user → chụp. **Vì sao chụp ở giây 50:** phải chụp GIỮA LÚC tải đang chạy thì `USERS_CNT` mới đếm đúng số session — chụp sau khi job kết thúc là sai.

**Output kỳ vọng:** 4 snapshot trong LAB_TM_HISTORY (1 trước tải + 3 mức tải).

### Bước 3 — Phân tích delta: `@03_diagnose.sql` (~2 phút)

🤔 **Dự đoán trước khi chạy:** từ mức 4 lên 8 user, `DBCPU_DIFF` hay `WAIT_DIFF` tăng mạnh hơn? Vì sao?

```sql
@03_diagnose.sql
```

**Output thật (đo trong VM 2026-07-14) — GHI BẢNG NÀY RA GIẤY:**

| Snapshot | User ảo | DBCPU_DIFF | WAIT_DIFF | WAIT_PCT trong khoảng |
|---|---|---|---|---|
| #2 | 2 | 95.9s | 3.3s | **3.3%** |
| #3 | 4 | 115.2s | 103.5s | **47.3%** |
| #4 | 8 | 114.8s | 322.1s | **73.7%** |

**Quy luật phải thấy:** từ 4 user trở đi **DB CPU chạm trần** (~115s ≈ 2 vCPU × khoảng đo ~60s... thực tế cửa sổ giữa 2 snapshot ~80s) — thêm user không thêm được CPU, toàn bộ phần tăng đổ vào **WAIT** (CPU queue + contention). Đây chính là lý do "thêm session không làm hệ thống nhanh hơn" khi CPU đã bão hòa.

Script còn in 2 phần nữa — đọc kèm chú giải:

| Phần | Đọc thế nào |
|---|---|
| [2] % DB time theo loại thao tác | `sql execute elapsed time` chiếm ~100% DB time — workload này thuần SQL. Các mục **không cộng lại bằng 100%** vì stat cha-con đếm trùng |
| [3] Time model dạng cây | Thấy quan hệ cha-con: `DB time` → `sql execute` / `parse` (→ `hard parse`) / `PL/SQL`... — đây là bản đồ để biết "DB time tiêu vào đâu" |

### Bước 4 — Use case: top session theo DB time: `@04_usecase_top_sessions.sql` (~1.5 phút)

🤔 **Dự đoán:** 4 phiên chạy CÙNG một workload thì wait% của chúng có giống nhau không?

```sql
@04_usecase_top_sessions.sql
```

**Output thật:** phiên chạy sẵn 60s có DB time ≈ 59s; các phiên vào sau wait ≈ 52% — cùng workload nhưng **wait% mỗi session phụ thuộc mức bão hòa tại thời điểm nó chạy**. Use case thật: "database chậm" → câu hỏi đầu tiên KHÔNG phải "SQL nào chậm" mà là "DB time đang dồn vào SESSION nào, nó CHỜ hay CHẠY" (`V$SESS_TIME_MODEL`).

> Tải còn chạy ~30s sau đó tự tắt; muốn cắt sớm: `@../_toolkit/workload_stop.sql`

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 (thoát oracle + SSH) rồi `vagrant halt` trên host.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Vì sao `sql execute elapsed time` (1,105s) gần bằng `DB time` (1,108s) nhưng cộng các stat con lại vượt 100%?
2. DB time = ? (công thức theo CPU và wait). Idle wait có nằm trong DB time không?
3. Từ 4 lên 8 user, DBCPU_DIFF gần như không đổi — kết luận gì về nút thắt?
4. `V$SESS_TIME_MODEL` mất dữ liệu khi nào? Muốn giữ lịch sử thì dùng công cụ gì (section nào)?
5. Số trong `V$SYS_TIME_MODEL` là cộng dồn từ đâu, và vì thế mọi phân tích phải làm gì trước tiên?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Các stat time model có quan hệ **cha-con và đếm trùng**: `sql execute elapsed time` đã bao gồm CPU + wait bên trong việc chạy SQL; `parse time elapsed`, `PL/SQL execution` cũng giao nhau với nó. Time model được thiết kế để trả lời "loại việc nào chiếm bao nhiêu" chứ không phải để cộng dồn — chỉ có `DB time = DB CPU + wait non-idle` là đẳng thức thật.
2. **DB time = DB CPU + thời gian wait non-idle (foreground) + thời gian xếp hàng chờ CPU**. Idle wait (vd `SQL*Net message from client`) KHÔNG nằm trong DB time — session rảnh không làm database "bận".
3. CPU đã **bão hòa** (2 vCPU kịch trần ~115s cho cửa sổ đo) → nút thắt là CPU. Thêm user chỉ làm hàng đợi dài hơn: WAIT_DIFF nhảy từ 103s lên 322s. Hành động đúng ở production: giảm CPU/query (tuning SQL) hoặc thêm CPU — KHÔNG phải tăng số connection.
4. Mất khi **session logout** (và khi instance restart). Muốn giữ lịch sử phải có công cụ chụp định kỳ: **AWR (Section 9)** cho instance-level, **ASH (Section 13)** cho session/sample-level.
5. Cộng dồn **từ lúc instance startup** → việc đầu tiên của mọi phân tích là **chụp 2 thời điểm và tính DELTA**. Đọc số cộng dồn trực tiếp sẽ bị toàn bộ quá khứ (kể cả các lab trước đó) pha loãng — lab đã minh họa bằng cột `WAIT_PCT_CUM` vs `WAIT_PCT_ITV`.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open file "../_toolkit/..."` hoặc `tm_snap.sql` | Không đứng ở `/labs/section_6` → `cd /labs/section_6` rồi vào lại sqlplus |
| Job sinh tải FAILED (credential) | Password OS oracle mất sau restore snapshot → `vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"` |
| `USERS_CNT` = 1 hoặc 2 ở snapshot có tải | Snapshot chụp khi tải đã/chưa chạy (VM chậm) → chạy lại `02_workload.sql`, số cũ vẫn nằm trong LAB_TM_HISTORY để so |
| DBCPU_DIFF thấp hơn mẫu nhiều | VM đang bận việc khác (backup, cập nhật) → quan trọng là ĐÚNG XU HƯỚNG: CPU chạm trần từ 4 user, wait tăng vọt |
| Số khác mẫu vài chục % | Bình thường (cache, nền). Chỉ cần đúng quy luật |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 8 — Instance Activity & Wait Events (mổ xẻ phần WAIT vừa thấy: chờ CÁI GÌ?)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_6/HUONG_DAN_HOC_SECTION_6.md`
