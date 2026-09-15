---
title: Hướng dẫn học Section 24 — Tuning the Redo Path
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_24/HUONG_DAN_HOC_SECTION_24.md
---

# Hướng dẫn học Section 24 — Tuning the Redo Path

> Lab: `labs/section_24/` · Nguồn: Practice 26 (Ahmed Baraka)
> ⚠️ **Chưa kiểm chứng trên VM** · **CHẠY TRONG VM** · **BẮT BUỘC snapshot trước**. Mọi "output kỳ vọng" là dự tính.

---

## 0. Kiến thức nền (5 phút)

Mỗi thay đổi dữ liệu sinh **redo** (bản ghi "làm lại"). LGWR ghi redo từ log buffer xuống **online redo log** — vòng tròn nhiều group. Group đầy → **log switch** sang group kế. Nếu group kế chưa "dọn xong" (checkpoint chưa flush hết block bẩn của nó, hoặc chưa archive) thì LGWR phải **đứng chờ** → cả DB khựng.

| Khái niệm | Là gì | Nhìn ở đâu |
|---|---|---|
| Log switch | Chuyển sang group redo kế tiếp | `V$LOG_HISTORY`, `V$LOG.STATUS` |
| CURRENT / ACTIVE / INACTIVE | Đang ghi / cần cho recovery-checkpoint chưa xong / rảnh (drop được) | `V$LOG.STATUS` |
| log file sync | **Khách** (session commit) chờ LGWR xác nhận đã ghi | `V$SYSTEM_EVENT` |
| log file parallel write | **Thợ** (LGWR) ghi redo xuống đĩa | `V$SYSTEM_EVENT` |
| log file switch (checkpoint incomplete) | LGWR chờ DBWR flush xong group kế | wait class Configuration |
| Redo Log Size Advisor | Size redo tối thiểu để switch không quá dày | `V$INSTANCE_RECOVERY.OPTIMAL_LOGFILE_SIZE` |

**Luật ngón tay cái:** redo khỏe khi switch **~1 lần / 20 phút** lúc tải bình thường. Switch mỗi phút = redo quá nhỏ.

---

## 1. Khởi động — snapshot + vào VM

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant snapshot save section24_redo        # ⚠️ KHÔNG bỏ qua bước này
```

```bash
vagrant ssh
sudo -u oracle -i
cd /labs/section_24
sqlplus / as sysdba
```

🤔 **Trước khi làm gì:** vì sao lab này phải chạy `sqlplus / as sysdba` trong VM chứ không connect từ host như các lab trước?

<details><summary>Gợi ý</summary>Redo log là cấu trúc cấp **CDB/instance**, không thuộc PDB. `ALTER DATABASE ADD/DROP LOGFILE` cần SYSDBA ở CDB$ROOT. Connect từ host bằng `system@ORADB` chỉ vào PDB → không làm được.</details>

---

## 2. Lab chính từng bước

### Bước 1 — Chụp cấu hình redo gốc

🤔 **Dự đoán:** VM có mấy redo group, mỗi group mấy member, size bao nhiêu?

```text
@01_setup.sql
```

**Kỳ vọng:** liệt kê group + member + MB; lưu vào `soe.lab_redo_config`; cho biết có OMF không. Lịch sử switch hôm nay còn thưa. **Ghi lại size gốc** (04 sẽ dùng lại).

### Bước 2 — Thu redo về 10MB + tải (BASELINE)

🤔 **Dự đoán:** redo 10MB + 4 phiên UPDATE/COMMIT liên tục → mấy switch/phút? Event nào leo top?

```text
@02_workload.sql
```

Script sẽ: thêm 3 group 10MB → switch/checkpoint → drop group to → chụp AWR B → **PAUSE** yêu cầu bạn mở **SSH window thứ 2**:

```bash
sudo -u oracle -i
cd /labs/section_24
nohup ./redo_update.sh 4 120 >/tmp/redo_load.log 2>&1 &
```

Quay lại window 1 nhấn Enter. **Kỳ vọng:** mục [5] switch/giờ nhảy vọt; `redo log space requests` tăng đều mỗi lần chạy lại; sau 120s chụp AWR E.

> Nếu [2] báo "chưa drop được group to nào": các group to còn CURRENT/ACTIVE. Chạy lại phần [2] (switch + checkpoint thêm) — xem mục 6.

### Bước 3 — Chẩn đoán + Advisor

🤔 **Dự đoán:** top wait class Configuration/Commit sẽ là event nào? OPTIMAL_LOGFILE_SIZE advisor trả về lớn hơn 10MB bao nhiêu lần?

```text
@03_diagnose.sql
```

**Kỳ vọng:** `log file switch (checkpoint incomplete)` / `log file switch completion` / `log file sync` chiếm top; switch < 1 phút/lần; advisor trả `OPTIMAL_LOGFILE_SIZE` cỡ trăm MB. Nếu Effective MTTR = 0 → tải chưa chạy, thả `redo_update.sh` lại rồi đọc lại.

### Bước 4 — Phục hồi redo + đo lại (FIX)

🤔 **Dự đoán:** đưa redo về size gốc, chạy lại đúng tải — `redo log space requests` delta sẽ về đâu so với đợt 10MB?

```text
@04_fix.sql
```

Thêm lại group to (size đọc từ `lab_redo_config`) → switch/checkpoint → drop group 10MB → chụp B2 → **PAUSE** chạy lại `redo_update.sh` → chụp E2.

**Kỳ vọng (bảng so sánh bắt buộc):**

| Đợt | Δ redo log space requests | switch/phút | 'log file switch %' |
|---|---|---|---|
| redo 10MB (02) | lớn | dày | tăng mạnh |
| redo gốc (04) | ≈ 0 | thưa | ngừng tăng |

---

## 3. Phần mở rộng (không bắt buộc)

- Chạy Advisor ở **nhiều mức FAST_START_MTTR_TARGET** (300, 1800, 3600) và xem `OPTIMAL_LOGFILE_SIZE` đổi thế nào — cảm nhận đánh đổi recovery vs hiệu năng.
- Trong lúc tải 10MB, mở window 3 chạy `@/labs/_toolkit/top_waits.sql` để thấy 'log file switch %' theo thời gian thực.

---

## 4. Dọn dẹp bắt buộc

```text
@99_cleanup.sql
```

**Hoặc (chắc chắn nhất, giống course):**

```powershell
vagrant snapshot restore section24_redo
vagrant snapshot delete section24_redo
```

Kiểm tra: chỉ còn redo group size gốc, 0 group 10MB, 0 session module='CRM'.

---

## 5. Debrief — trả lời KHÔNG nhìn tài liệu

1. `log file sync` vs `log file parallel write`: cái nào là khách chờ, cái nào là thợ làm? Redo nhỏ đánh vào cái nào?
2. Vì sao `log file switch (checkpoint incomplete)` đáng sợ hơn `log file sync`?
3. Group redo phải ở trạng thái nào mới DROP được? Vì sao cần switch nhiều lần + checkpoint trước?
4. `OPTIMAL_LOGFILE_SIZE` phụ thuộc tham số nào? Vì sao đo lúc batch đêm cho số sai với OLTP ban ngày?
5. Redo cấp CDB hay PDB? Tuning redo cho riêng 1 PDB trong CDB nhiều PDB có được không?

<details>
<summary>Đáp án</summary>

1. `log file sync` = **khách** (session gọi COMMIT ngồi chờ LGWR báo "đã ghi bền"); `log file parallel write` = **thợ** (LGWR thực sự ghi redo xuống đĩa). Redo nhỏ đánh vào tầng *switch* trước (khách chờ vì phải đợi log switch xong mới ghi tiếp) — thể hiện thành `log file switch %` và gián tiếp kéo dài `log file sync`. `parallel write` chỉ xấu khi đĩa redo chậm (vấn đề khác).
2. `log file sync` là chờ commit bình thường (mọi hệ đều có ít nhiều). `log file switch (checkpoint incomplete)` nghĩa là **toàn bộ hoạt động sinh redo bị đóng băng** vì không có group nào ghi được — DBWR chưa flush kịp block bẩn của group sắp tái dùng. Đây là nghẽn hệ thống, không phải chờ một giao dịch.
3. Phải là **INACTIVE** (không CURRENT — đang ghi; không ACTIVE — còn cần cho instance recovery). Switch đẩy CURRENT sang group khác; CHECKPOINT ép DBWR flush để group vừa rời thành INACTIVE. Không checkpoint thì nó kẹt ở ACTIVE, drop báo lỗi.
4. Phụ thuộc `FAST_START_MTTR_TARGET` (không đặt → advisor không tính) và **workload đang chạy** (redo sinh nhanh thì cần log to hơn để giữ nhịp switch). Batch đêm sinh redo ồ ạt → advisor khuyên size rất lớn; áp cho OLTP ban ngày (redo nhẹ hơn) là thừa/lệch. Đo lúc tải **đại diện**.
5. Redo là cấp **CDB/instance** — dùng chung cho mọi PDB. Không thể có redo log riêng cho từng PDB; tuning redo là tuning cho toàn CDB. (Đây cũng là lý do lab phải làm ở CDB$ROOT, và một PDB "ồn ào" sinh redo nhiều ảnh hưởng redo path của mọi PDB khác.)

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Nguyên nhân/Xử lý |
|---|---|
| 02 "chưa drop được group to nào" | Group to còn CURRENT/ACTIVE. Chạy lại khối [2] (switch 5× + checkpoint). Nếu 1 group cứ ACTIVE: `ALTER SYSTEM CHECKPOINT;` vài lần rồi thử drop tay `ALTER DATABASE DROP LOGFILE GROUP n;` |
| `ORA-00350/ORA-00361` khi drop | Đang drop group CURRENT hoặc member cuối. Switch thêm rồi checkpoint; đừng drop group đang CURRENT |
| `ORA-01623: log ... is current` | Group đó đang ghi — `ALTER SYSTEM SWITCH LOGFILE` để đổi CURRENT trước |
| ADD LOGFILE báo cần path | Không phải OMF (01 mục [2] rỗng). Thêm path tay: `ALTER DATABASE ADD LOGFILE GROUP n '<member_dir>/redo_small_n.log' SIZE 10M;` — lấy `<member_dir>` từ `soe.lab_redo_config` |
| Advisor `OPTIMAL_LOGFILE_SIZE` null/0 | Chưa đặt `FAST_START_MTTR_TARGET` (03 đã set 3600) hoặc chưa có tải → Effective MTTR=0. Chạy `redo_update.sh` rồi đọc lại |
| Lỡ tay, redo config rối | `vagrant snapshot restore section24_redo` — đây là lý do bắt buộc snapshot ở đầu |
| Muốn phục hồi member y hệt gốc | SQL khó tái tạo path/member chính xác → **restore snapshot** là cách đúng nhất (course cũng vậy) |

---

## 7. Sau buổi học

- [ ] Điền cột "Số thật" trong `README.md`, bỏ banner "chưa kiểm chứng" nếu chạy trọn vẹn
- [ ] Debrief 5 câu không nhìn tài liệu
- [ ] Redo đã về size gốc (`@99_cleanup.sql` kiểm tra) **hoặc** đã `vagrant snapshot restore section24_redo`
- [ ] Xóa snapshot: `vagrant snapshot delete section24_redo` (nếu đã restore/không cần nữa)
- [ ] Cập nhật `progress.md`
- [ ] `vagrant halt`


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_24/HUONG_DAN_HOC_SECTION_24.md`
