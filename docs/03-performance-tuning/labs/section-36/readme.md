---
title: Lab Section 36 — Database Replay
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_36/README.md
---

# Lab Section 36 — Database Replay

> Nguồn: Practice 38 (Ahmed Baraka) · Guide: [section_all/section_36_database_replay_guide.md](../../section-all/section-36-database-replay-guide.md) · Senior: [section_all_new/section_36_database_replay_senior_guide.md](../../section-all-new/section-36-database-replay-senior-guide.md)
> Chạy **TRONG VM** (OFE + restart + capture files + wrc). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**.
> ⚠️⚠️ **SNAPSHOT BẮT BUỘC:** `vagrant snapshot save pre_dbreplay`. **LICENSE:** Real Application Testing (RAT) — tính phí riêng.

**🎓 Học theo buổi đầy đủ:** 👉 **[HUONG_DAN_HOC_SECTION_36.md](huong-dan-hoc-section-36.md)**

## Ý tưởng lab

Database Replay tái tạo **TOÀN BỘ workload production** (mọi session, concurrency, timing) chạy lại trên test đã áp thay đổi → bắt **lock/contention/throughput** mà SPA (per-SQL, Section 35) không thấy. **5 pha:**

```
Capture (prod) → Preprocess (test) → [áp thay đổi] → Replay (test, qua wrc) → Report
```

⚠️ **Giới hạn single-VM:** production dùng RMAN restore + `RECOVER UNTIL SCN` để đưa test DB về đúng data state lúc capture. Lab chạy capture+replay trên **cùng VM** (bỏ restore-to-SCN) → **divergence sẽ khác 0** — đây là **điểm học** (xem senior guide Exercise 3), không phải lỗi. Mục tiêu: nắm **vòng đời 5 pha + API**.

## Chạy lab — TRONG VM

```bash
vagrant snapshot save pre_dbreplay
vagrant ssh → sudo -u oracle -i
mkdir -p /home/oracle/workload && rm -f /home/oracle/workload/*
cd /labs/section_36
sqlplus / as sysdba
```

```
@01_setup.sql                 -- OFE 11.2 + restart + directory + filter SOE
@02_capture.sql               -- STARTUP RESTRICT + SCN + START_CAPTURE(120s)
     -- cửa sổ khác: sqlplus system @../_toolkit/workload_soe.sql 4 90  (sinh tải SOE)
@03_preprocess_change.sql     -- PROCESS_CAPTURE + OFE 12.2 + restart
@04_replay.sql                -- INITIALIZE → PREPARE(SCN) → [./wrc_replay.sh] → START_REPLAY → report
```

wrc (cửa sổ shell): `./wrc_replay.sh calibrate` rồi `./wrc_replay.sh start 1` (client chờ), quay lại SQL chạy `START_REPLAY`.

**Kỳ vọng:** `DBA_WORKLOAD_CAPTURES` COMPLETED; capture files trong `/home/oracle/workload`; replay chạy qua wrc; `DBA_WORKLOAD_REPLAYS` tiến triển; report so **DB Time / errors / divergence** capture vs replay (divergence ≠ 0 do single-VM).

## Dọn dẹp

```
@99_cleanup.sql               -- cancel replay + xóa metadata + nhắc reset OFE
```
```bash
rm -f /home/oracle/workload/*
```
```powershell
vagrant snapshot restore pre_dbreplay
```

## Câu hỏi tự kiểm tra

1. 5 pha của Database Replay? Pha nào ở prod, pha nào ở test?
2. Vì sao test DB phải restore về **capture-start SCN**? Không làm thì báo lỗi gì (2 ví dụ)?
3. `SYNCHRONIZATION=SCN` vs `OFF` — đánh đổi gì?
4. `wrc` là gì? Vì sao là lệnh OS chứ không phải SQL? `START_REPLAY` khác khởi động wrc thế nào?
5. Bẫy đồng hồ (VirtualBox GetHostTime) ảnh hưởng workload nào? Vì sao phải tắt?
6. SPA (35) vs DB Replay (36) — khi nào dùng cái nào, khi nào cả hai?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_36/README.md`
