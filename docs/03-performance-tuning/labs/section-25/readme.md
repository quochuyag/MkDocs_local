---
title: Lab Section 25 — CPU Bottleneck Detection
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_25/README.md
---

# Lab Section 25 — CPU Bottleneck Detection

> Nguồn: Practice 27 (Ahmed Baraka) · Guide: [section_all/section_25_cpu_bottleneck_guide.md](../../section-all/section-25-cpu-bottleneck-guide.md) · Senior: [section_all_new/section_25_cpu_bottleneck_senior_guide.md](../../section_all_new/section_25_cpu_bottleneck_senior_guide.md)
> Chạy từ thư mục này (`labs/section_25/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**. Cần đúng **xu hướng**: %Busy CPU cao khi database là thủ phạm, thấp khi tải từ ngoài.

**🎓 Học theo buổi đầy đủ (từng bước, dự đoán + đáp án):**
👉 **[HUONG_DAN_HOC_SECTION_25.md](huong-dan-hoc-section-25.md)**

## Ý tưởng lab

Chẩn đoán CPU là bài toán **quy nguồn**: Oracle biết chính xác *Oracle* tiêu bao nhiêu CPU (Time Model/ASH), nhưng **không thấy tiến trình ngoài Oracle**. Lab dựng 2 kịch bản và dùng **`%Busy CPU` = Oracle CPU / OS busy** làm discriminator:

| | Scenario 1 — CPU từ ngoài | Scenario 2 — CPU từ database |
|---|---|---|
| Nguồn | tiến trình bash busy (ngoài Oracle) | phiên PL/SQL đốt CPU trong DB |
| OS %busy | cao (bão hòa) | cao |
| **%Busy CPU** | **thấp (<30%)** | **cao (>60-70%)** |
| ASH thấy được? | **KHÔNG** | Có (ON CPU → SQL_ID) |
| Fix | OS-level (top/OSWatcher) | tune SQL/PL-SQL |

Lab thay `stress`/`apply_soe_cpu.sh`/AWR-HTML của PDF bằng **`cpu_load.sh` + delta live view** (`V$OSSTAT` vs `V$SYS_TIME_MODEL`) — tái lập được trong VM không cần Swingbench.

## Chạy lab — user `system` (quan sát) + shell trong VM (sinh tải)

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```
```
@01_setup.sql                     -- ngữ cảnh CPU: #CPU, công thức Maximum CPU
```

**Scenario 2 (database CPU) — kịch bản chính.** Trong VM, cửa sổ khác:
```bash
cd /labs/section_25 && ./cpu_load.sh db 4 240
```
Rồi trong SQL*Plus:
```
@02_workload.sql                  -- đo 30s -> kỳ vọng %Busy CPU cao -> DATABASE
@03_diagnose.sql                  -- ASH ON CPU + V$SESSTAT -> đích danh CPU_LOAD/BURN_CPU
```

**Scenario 1 (external CPU) — bài học ranh giới.** Trong VM:
```bash
cd /labs/section_25 && ./cpu_load.sh external 2 240
```
Rồi:
```
@04_usecase_external_cpu.sql      -- kỳ vọng %Busy CPU thấp; ASH KHÔNG thấy tải ngoài
```

## Mở rộng (tùy chọn)

- **Parse CPU giấu mặt** — trong VM: `cd /labs/section_20 && ./hard_parse.sh 2 180 literal`, rồi `@05_parse_cpu.sql`. Kỳ vọng: parse cpu chiếm % lớn DB CPU + nhiều SQL_ID unique → fix bằng bind variable, không kill từng SQL.

## Dọn dẹp

```
@99_cleanup.sql                   -- kill phiên tải còn sống (external: pkill trong VM)
```

## Câu hỏi tự kiểm tra

1. `Maximum CPU` tính thế nào? Vì sao đọc `DB CPU` mà không có nó là vô nghĩa?
2. `% of Total CPU Time` trong Time Model **KHÔNG** phải % CPU của máy — nó là gì?
3. `%Busy CPU` phân biệt điều gì? Cao/thấp nói lên nguồn CPU nào?
4. Vì sao ASH **không** phát hiện được tải CPU từ ngoài Oracle?
5. Load Average cao — trước khi kết luận "bottleneck CPU", phải kiểm tra cột nào? (gợi ý: I/O-wait)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_25/README.md`
