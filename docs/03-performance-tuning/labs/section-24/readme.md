---
title: Lab Section 24 — Tuning the Redo Path
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_24/README.md
---

# Lab Section 24 — Tuning the Redo Path

> Nguồn: Practice 26 (Ahmed Baraka) · Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** · **CHẠY TRONG VM** (redo DDL cấp CDB, cần `sqlplus / as sysdba`) · **BẮT BUỘC snapshot trước**.

**Câu hỏi lab trả lời:** redo log quá nhỏ gây nghẽn ở đâu (switch liên tục → LGWR chờ checkpoint); nhận ra bằng wait event nào; và dùng Redo Log File Size Advisor chọn size tối ưu ra sao?

## ⚠️ Trước khi bắt đầu — snapshot

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant snapshot save section24_redo
```

Lab này DROP/ADD redo log group của cả CDB. Cleanup chính thức = `vagrant snapshot restore section24_redo` (giống course).

## Chạy lab — TRONG VM

```bash
vagrant ssh
sudo -u oracle -i
cd /labs/section_24
sqlplus / as sysdba          # vào thẳng CDB$ROOT — đúng nơi làm redo DDL
```

```text
@01_setup.sql      -- chụp cấu hình redo gốc vào soe.lab_redo_config + OMF check
@02_workload.sql   -- thu redo về 10MB → mở window 2 chạy redo_update.sh → đo BASELINE
@03_diagnose.sql   -- wait 'log file switch %', switch/phút, Redo Log Size Advisor
@04_fix.sql        -- phục hồi redo size gốc → chạy lại tải → so sánh
@99_cleanup.sql    -- dọn mềm; hoặc restore snapshot (chắc chắn nhất)
```

**Window 2** (SSH thứ 2, khi 02/04 nhắc): `cd /labs/section_24 && nohup ./redo_update.sh 4 120 >/tmp/redo_load.log 2>&1 &`

File phụ trợ: `redo_update.sh` (4 phiên soe UPDATE ORDERS + COMMIT WRITE IMMEDIATE WAIT).

## Khác bản gốc và vì sao

| Course (Practice 26) | Lab này | Vì sao |
|---|---|---|
| Swingbench + Putty client window | `redo_update.sh` chạy trực tiếp trong VM (không external job) | Cả lab đã ở trong VM → không cần credential; đúng kiểu "client window" của course |
| Redo 200MB × 3 group × 2 member (giả định) | Đọc size/số group thật từ `soe.lab_redo_config` rồi tái tạo | VM vagrant có thể khác cấu hình course |
| Cleanup = restore snapshot | 04 phục hồi chủ động + đo before/after; 99/snapshot lo phần chắc chắn | Lab dạng *fix* bắt buộc so số trước/sau |
| `COMMIT` thường | `COMMIT WRITE IMMEDIATE WAIT` | Ép LGWR ghi đồng bộ để 'log file sync' hiện rõ (PL/SQL loop hay bị batch-commit) |

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| BASELINE (10MB): switch/giờ khi tải | rất cao (chục+/phút) | |
| BASELINE: Δ 'redo log space requests' trong đợt | tăng mạnh | |
| BASELINE: top wait Configuration/Commit | 'log file switch %' + 'log file sync' | |
| Advisor: OPTIMAL_LOGFILE_SIZE(MB) | >> 10MB | |
| FIX (size gốc): Δ 'redo log space requests' | ≈ 0 | |
| FIX: 'log file switch %' | ngừng tăng | |

## 3 bài học phải thuộc

1. **Redo nhỏ = DB khựng theo chu kỳ**: group đầy → switch → nếu group kế còn ACTIVE (checkpoint/archive chưa xong) thì LGWR **đứng** → `log file switch (checkpoint incomplete)`. Nhỏ ⇒ switch dày ⇒ xác suất kẹt cao. Luật ngón tay cái: **~1 switch / 20 phút** lúc tải bình thường.
2. **Đọc theo tầng nghiêm trọng**: `log file switch (checkpoint incomplete)` (chờ DBWR) > `log file switch completion` (chờ switch) > `log file sync` (commit chờ LGWR) > `log file parallel write` (LGWR I/O thuần). Ba cái đầu là chuyện *cấu hình redo/checkpoint*; cái cuối là chuyện *tốc độ đĩa redo*.
3. **Advisor = min, không phải đáp số cuối**: `V$INSTANCE_RECOVERY.OPTIMAL_LOGFILE_SIZE` cần `FAST_START_MTTR_TARGET` được đặt và **chịu ảnh hưởng workload hiện tại** — chỉ tin khi đo lúc tải đại diện. `FAST_START_MTTR_TARGET` là đánh đổi: nhỏ = phục hồi instance nhanh nhưng checkpoint dày (ghi nhiều); lớn = hiệu năng cao nhưng recovery lâu.

## Câu hỏi tự kiểm tra

1. Phân biệt `log file sync` và `log file parallel write` — cái nào là "khách chờ", cái nào là "thợ làm"? Redo nhỏ ảnh hưởng cái nào trước?
2. Vì sao `log file switch (checkpoint incomplete)` mới là event đáng sợ nhất, không phải `log file sync`?
3. Tại sao phải `SWITCH LOGFILE` nhiều lần + `CHECKPOINT` mới drop được group cũ? Trạng thái group phải là gì mới drop được?
4. `OPTIMAL_LOGFILE_SIZE` phụ thuộc tham số nào và workload lúc đo? Vì sao đo lúc batch đêm lại cho số sai cho hệ OLTP ban ngày?
5. Redo là cấp CDB hay PDB? Điều đó nghĩa là gì khi bạn có 3 PDB dùng chung — tuning redo cho 1 PDB có được không?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_24/README.md`
