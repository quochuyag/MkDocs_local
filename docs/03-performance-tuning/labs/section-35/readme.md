---
title: Lab Section 35 — SQL Performance Analyzer (SPA)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_35/README.md
---

# Lab Section 35 — SQL Performance Analyzer (SPA)

> Nguồn: Practice 37 (Ahmed Baraka) · Guide: [section_all/section_35_sql_performance_analyzer_guide.md](../../section-all/section-35-sql-performance-analyzer-guide.md) · Senior: [section_all_new/section_35_sql_performance_analyzer_senior_guide.md](../../section-all-new/section-35-sql-performance-analyzer-senior-guide.md)
> Chạy **TRONG VM** (OFE + restart). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**.
> ⚠️⚠️ **SNAPSHOT nên có:** `vagrant snapshot save pre_spa` (đổi OFE + restart 2 lần). **LICENSE:** SPA thuộc Real Application Testing (RAT) — tính phí riêng.

**🎓 Học theo buổi đầy đủ:** 👉 **[HUONG_DAN_HOC_SECTION_35.md](huong-dan-hoc-section-35.md)**

## Ý tưởng lab

SPA trả lời: **"Thay đổi này có làm câu SQL nào chậm/đổi plan không?"** ở mức **từng SQL**. Lấy SQL Tuning Set (STS) → `TEST EXECUTE` **before** → áp thay đổi → `TEST EXECUTE` **after** → `COMPARE PERFORMANCE` → report. Là anh em **vi mô** của Database Replay (Section 36, mức toàn workload/concurrency). Mô phỏng "upgrade" bằng `OPTIMIZER_FEATURES_ENABLE` 11.2→12.2.

## Chạy lab — TRONG VM (đan xen SYS ↔ soe)

```bash
vagrant snapshot save pre_spa    # trên host, nên có
vagrant ssh → sudo -u oracle -i && cd /labs/section_35
```

```
sqlplus / as sysdba
@01_setup.sql              -- OFE 11.2.0.2 + restart (bỏ comment) + tạo STS

-- cửa sổ soe:
sqlplus soe/soe@//localhost:1521/ORADB
@client_wrkld.sql          -- chạy workload → nạp cursor cache

-- quay lại SYS:
@02_capture.sql            -- capture cache → STS + SPA task + TEST EXECUTE 'before'
@03_change_compare.sql     -- OFE 12.2.0.1 + restart + 'after' + COMPARE + report
```

**Kỳ vọng:** report SUMMARY phân loại từng SQL: **improved / regressed / unchanged / plan changed** (metric mặc định elapsed_time). Một số câu có thể đổi plan giữa 2 OFE.

## Dọn dẹp

```
@99_cleanup.sql            -- drop task/STS/staging + nhắc reset OFE
vagrant snapshot restore pre_spa   # sạch nhất (trả OFE + restart)
```

## Câu hỏi tự kiểm tra

1. SPA vs Database Replay khác nhau ở mức nào? Khi nào dùng cái nào (hoặc cả hai)?
2. `TEST EXECUTE` vs `EXPLAIN PLAN` mode — khác gì? Trên production dùng cái nào, vì sao?
3. STS được nạp từ đâu? Vì sao STS nghèo làm SPA "an toàn giả"?
4. `OPTIMIZER_FEATURES_ENABLE` là proxy của gì? Nó **không** thay thế được gì?
5. Một câu regress — bước tiếp theo để upgrade an toàn (giữ plan tốt) là gì?
6. Vì sao SPA **không** bắt được `enq: TX` / `buffer busy` khi upgrade?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_35/README.md`
