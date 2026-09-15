---
title: 📚 Hướng dẫn học Section 25 — CPU Bottleneck Detection (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_25/HUONG_DAN_HOC_SECTION_25.md
---

# 📚 Hướng dẫn học Section 25 — CPU Bottleneck Detection (thực hành trong Linux VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 27 + Oracle internals. Cần đúng **xu hướng**, không cần khớp từng số.
> Thời lượng gợi ý: ~80 phút (lecture 20' + lab 45' + debrief 15').
> Nguồn: Practice 27 (Ahmed Baraka) + [senior guide](../../section_all_new/section_25_cpu_bottleneck_senior_guide.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Chẩn đoán CPU là **bài toán quy nguồn**: Oracle biết chính xác *chính nó* tiêu bao nhiêu CPU, nhưng **không thấy tiến trình ngoài Oracle**. Quy trình 2 bước:

```
CPU bão hòa (OS %busy ~100%, Load Average >> #CPU)?
        │
        ▼
%Busy CPU cao (> 60-70%)?   ← %Busy CPU = Oracle CPU / OS busy time
    │                │
   CÓ               KHÔNG
    │                │
Oracle là thủ phạm   Tiến trình NGOÀI Oracle
    │                │
ASH ON CPU ->        OS: top / ps / OSWatcher
SQL_ID culprit       (ASH KHÔNG thấy được)
```

**3 con số phải phân biệt:**

| Metric | Công thức | Nghĩa |
|---|---|---|
| Maximum CPU | `#CPU × elapsed_s` | Tổng công suất CPU trong khoảng đo |
| `%Total CPU` | `(DB CPU + bg cpu) / Maximum CPU` | Oracle chiếm bao nhiêu **công suất máy** |
| `%Busy CPU` | `(DB CPU + bg cpu) / OS busy` | **Discriminator** — Oracle chiếm bao nhiêu phần CPU đang bận |

⚠️ **Bẫy:** `% of Total CPU Time` trong Time Model = `DB CPU / (DB CPU + bg cpu)` — là **tỷ lệ nội bộ của Oracle**, KHÔNG phải % CPU máy. "DB CPU = 95% of Total CPU Time" nghe đáng sợ nhưng nếu DB CPU = 8s / (2 CPU × 600s) thì chỉ 0.7% máy.

**Lab dùng gì thay AWR-HTML:** `cpu_sample.sql` đo **delta** `V$OSSTAT` (CPU góc OS) so với `V$SYS_TIME_MODEL` (CPU của Oracle) trong 30s → tính thẳng `%Busy CPU`. Tái lập được trong VM, không cần Swingbench.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_25
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```
**Kỳ vọng:** 8 mục PASS. (Lab này chạy bằng `system`, sinh tải bằng shell trong VM.)

---

## 2. Ngữ cảnh + Scenario 2 (CPU từ database) — kịch bản chính (~25 phút)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

### Bước 1 — Ngữ cảnh CPU: `@01_setup.sql`

🤔 **Dự đoán:** VM có mấy vCPU? Nếu đo trong 30s thì Maximum CPU = bao nhiêu CPU-giây?

```sql
@01_setup.sql
```

**Kỳ vọng:** `NUM_CPUS = 2` → Maximum CPU (30s) = 60 CPU-giây. Ghi nhớ công thức trước khi xem bất kỳ số CPU nào.

### Bước 2 — Sinh tải DB CPU + đo: `@02_workload.sql`

**Cửa sổ 2 (shell trong VM):** khởi động 4 phiên PL/SQL đốt CPU:
```bash
cd /labs/section_25
./cpu_load.sh db 4 240
```

🤔 **Dự đoán:** 4 phiên đốt CPU thuần (math, không I/O) trên 2 vCPU. `%Busy CPU` (Oracle/OS busy) sẽ cao hay thấp? OS busy delta có ≈ DB CPU delta không?

**Cửa sổ 1 (system):**
```sql
@02_workload.sql
```

**Output kỳ vọng (đo 30s):**
```text
OS %busy của máy      ~100%
DB CPU delta          ~ xấp xỉ OS busy delta  (Oracle giải thích gần hết)
%Busy CPU             >= 60-70%   -> KẾT LUẬN: DATABASE là thủ phạm
```

### Bước 3 — Tìm đích danh: `@03_diagnose.sql` (chạy khi tải còn chạy)

🤔 **Dự đoán:** ASH lọc `SESSION_STATE='ON CPU'` sẽ chỉ ra SQL_ID nào? Thủ phạm là SELECT hay PL/SQL?

```sql
@03_diagnose.sql
```

| Bước | Kỳ vọng | Bài học |
|---|---|---|
| 2. ASH ON CPU top SQL | anonymous PL/SQL block đứng đầu | Chỉ đếm mẫu **ON CPU** (không tính WAITING) |
| 3. ASH top session | nhiều session `CPU_LOAD/BURN_CPU` | MODULE/ACTION giúp quy về ứng dụng |
| 4. V$SESSTAT CPU | các phiên CPU_LOAD dẫn đầu "CPU used" | CPU tích lũy từng phiên |
| 5. AAS vs #CPU | AAS ≈ 2 (= #CPU) | Dấu hiệu **bão hòa** CPU kinh điển |

💡 Thủ phạm là **PL/SQL**, không phải một SELECT → tuning = tối ưu thuật toán / dời off-peak / giảm DOP nếu parallel — **không** phải thêm index.

---

## 3. Scenario 1 (CPU từ ngoài Oracle) — bài học ranh giới (~15 phút)

**Cửa sổ 2 (shell trong VM):** dừng tải db cũ (chờ hết giờ hoặc mở cửa sổ mới), khởi động tải NGOÀI Oracle:
```bash
cd /labs/section_25
./cpu_load.sh external 2 240      # 2 core busy bash, KHÔNG phải session Oracle
```

🤔 **Dự đoán:** OS %busy vẫn ~100%, nhưng `%Busy CPU` (Oracle/OS busy) lần này cao hay thấp? ASH có thấy 2 tiến trình bash này không?

**Cửa sổ 1 (system):**
```sql
@04_usecase_external_cpu.sql
```

**Output kỳ vọng:**
```text
OS %busy của máy      ~100%   (máy vẫn bão hòa)
%Busy CPU             THẤP (<30%)   -> tiến trình NGOÀI Oracle
ASH ON CPU 5 phút     gần 0 session  -> ASH KHÔNG thấy tải bash
```

💡 **Bài học ranh giới:** AWR/ASH chỉ nói "Oracle tiêu ít CPU, phần còn lại ở ngoài" — **không gọi tên được tiến trình**. Phải xuống OS: `top`, `ps aux --sort=-%cpu`, OSWatcher (Section 34). Và nếu `%WIO` cao thay vì `%user` → tải thực ra là **I/O-wait**, không phải CPU thuần → fix khác hẳn.

**So sánh 2 scenario** (điểm chốt của cả buổi):

| | Scenario 2 (DB) | Scenario 1 (external) |
|---|---|---|
| OS %busy | cao | cao |
| %Busy CPU | **cao** | **thấp** |
| ASH thấy? | có | không |

---

## 4. Mở rộng (tùy chọn): Parse CPU giấu mặt (~10 phút)

**Cửa sổ 2 (VM):** tái dùng bão hard-parse của Section 20:
```bash
cd /labs/section_20
./hard_parse.sh 2 180 literal      # mỗi vòng một câu SQL literal MỚI
```
**Cửa sổ 1 (system):**
```sql
@05_parse_cpu.sql
```
**Kỳ vọng:** `parse time cpu` chiếm % lớn của DB CPU + hàng loạt SQL_ID cùng `FORCE_MATCHING_SIGNATURE`. 💡 `SQL ordered by CPU Time` sẽ thấy **nhiều** câu CPU nhỏ (không phải 1 thủ phạm to) → fix là **bind variable / CURSOR_SHARING**, không kill từng SQL.

---

## 5. Dọn dẹp (BẮT BUỘC — 2 phút)

```sql
@99_cleanup.sql          -- kill phiên CPU_LOAD/LAB20_PARSE còn sống
```
Tải **external** là tiến trình OS → kill trong VM:
```bash
pkill -f 'while :'       # hoặc chờ timeout tự tắt
```
```sql
exit
```
```bash
exit
exit
```
```powershell
vagrant halt
```

---

## 6. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. `Maximum CPU` tính thế nào? Vì sao đọc `DB CPU` mà không có nó là vô nghĩa?
2. `% of Total CPU Time` trong Time Model KHÔNG phải % CPU máy — vậy là gì? Công thức?
3. `%Busy CPU` cao/thấp phân biệt nguồn CPU nào? Vì sao nó là discriminator?
4. Vì sao ASH **không** phát hiện tải CPU ngoài Oracle? Đây là giới hạn cứng hay có cách vòng?
5. Load Average = 15 trên máy 2 CPU — đủ để kết luận "bottleneck CPU" chưa? Cần kiểm tra thêm gì?

<details>
<summary>📖 Đáp án</summary>

1. `Maximum CPU = #CPU × elapsed_seconds` = tổng công suất CPU khả dụng. Mọi % CPU tính tương đối với nó. `DB CPU = 8s` là ít hay nhiều tùy Maximum CPU (8s/1200s = 0.7% vs 8s/20s = 40%) → không có Maximum CPU thì con số DB CPU vô nghĩa.
2. Nó là tỷ lệ **nội bộ** của Oracle: `DB CPU / (DB CPU + background cpu time)` — Oracle chia CPU của *chính nó* giữa foreground và background, KHÔNG phải % CPU máy. Muốn biết % máy → so `DB CPU` với `Maximum CPU`.
3. `%Busy CPU = (DB CPU + bg cpu) / OS busy time`. **Cao** (>70%) → Oracle giải thích được phần lớn CPU đang bận → database là thủ phạm. **Thấp** với OS busy cao → CPU bị tiến trình ngoài Oracle ăn. Đây là discriminator vì nó ghép được cả 2 phía (OS busy từ V$OSSTAT + Oracle CPU từ Time Model).
4. Giới hạn **cứng**: ASH chỉ sample **session Oracle**. Tiến trình ngoài Oracle (backup agent, antivirus, app server, `stress`) không có session trong DB → không xuất hiện trong V$ACTIVE_SESSION_HISTORY. Không có cách vòng ở tầng DB — phải dùng OS-level (top/ps/OSWatcher).
5. **Chưa đủ.** Load Average = số tiến trình trong run queue **CỘNG** tiến trình ở uninterruptible I/O wait (D state). Load 15 có thể là 15 CPU-bound HOẶC 2 CPU-bound + 13 I/O-waiting. Phải xem `%WIO` (I/O-wait) so với `%User`/`%System` trong Host CPU: nếu `%WIO` cao → thực ra là bottleneck **I/O**, không phải CPU → fix hoàn toàn khác.

</details>

---

## 7. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `cpu_sample.sql` báo "CPU gần như rảnh" | Tải chưa chạy / đã hết giờ → khởi động lại `cpu_load.sh` ngay trước khi chạy sample |
| `%Busy CPU` scenario db không cao | N quá nhỏ so với #CPU → tăng `./cpu_load.sh db 4 240`; đảm bảo tải đang chạy lúc sample |
| ASH ON CPU rỗng ở scenario db | Sample_time lệch / tải vừa bắt đầu → chờ ~1 phút cho ASH tích mẫu rồi chạy lại 03 |
| `cpu_load.sh: bad interpreter ^M` | CRLF → `sed -i 's/\r$//' cpu_load.sh` trong VM |
| external load không tắt | tiến trình OS → `pkill -f 'while :'` trong VM |
| `timeout: command not found` | hiếm; dùng `./cpu_load.sh db ...` (db mode không cần timeout) hoặc cài coreutils |

---

## 8. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt` (kiểm tra không còn tiến trình busy trong VM)
- [ ] **Lab chưa kiểm chứng VM** — khi chạy thật, ghi số đo thật để cập nhật tài liệu
- [ ] Buổi kế tiếp: Section 26 (Disk I/O) — cùng nhóm "Storage & Object Tuning"


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_25/HUONG_DAN_HOC_SECTION_25.md`
