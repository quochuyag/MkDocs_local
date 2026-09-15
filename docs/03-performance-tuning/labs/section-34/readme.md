---
title: Lab Section 34 — OS Performance (Linux Utilities & OSWatcher)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_34/README.md
---

# Lab Section 34 — OS Performance (Linux Utilities & OSWatcher)

> Nguồn: Practice 35 (Linux Utilities) + Practice 36 (OSWatcher Black Box) · Guide: [section_all/section_34_os_performance_guide.md](../../section-all/section-34-os-performance-guide.md) · Senior: [section_all_new/section_34_os_performance_senior_guide.md](../../section-all-new/section-34-os-performance-senior-guide.md)
> Chạy **TRONG VM** (lab ở tầng OS, không phải SQL). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — output là **kỳ vọng**.

**🎓 Học theo buổi đầy đủ (đi qua từng công cụ):** 👉 **[HUONG_DAN_HOC_SECTION_34.md](huong-dan-hoc-section-34.md)**

## Ý tưởng lab

Các view DB (Time Model/ASH/AWR) **chỉ thấy Oracle**. Khi nút thắt ngoài Oracle, hoặc cần biết **tài nguyên OS nào** cạn (CPU / swap / disk / network), phải dùng công cụ OS. Khung **USE** (Utilization/Saturation/Errors) + **cầu SPID** nối OS ↔ DB.

| Tài nguyên | Công cụ | Metric chính |
|---|---|---|
| Tổng quan | `vmstat -t 2` | r, b, si/so, %us, %wa |
| CPU | `mpstat`, `top`, `ps` | %usr, %sys, run queue |
| Memory | `free`, `vmstat` | si/so (swap) |
| Disk | `iostat -x`, `iotop` | %util, await, per-process |
| Network | `netstat -s`, `ip -s` | retransmit, RX-ERR/DRP |

## Chạy lab — TRONG VM

```bash
vagrant ssh → sudo -u oracle -i
cd /labs/section_34
./01_setup.sh                 # kiểm tra công cụ có sẵn + số vCPU + pmon
```

**Sinh tải để quan sát** (cửa sổ khác):
```bash
./os_stress.sh cpu 60 2       # 2 core busy 60s  → vmstat r/%us tăng
./os_stress.sh io  60         # I/O stress 60s   → vmstat b/%wa, iostat %util tăng
```

**Cầu SPID — map process OS nóng về DB** (Exercise 2): chạy PL/SQL đốt CPU bằng soe, rồi:
```bash
ps -e -o pcpu,pid,user,args | sort -nrk1 | head    # lấy PID nóng
sqlplus / as sysdba @02_map_os_to_db.sql            # nhập PID → ra session/SQL
```

**Kỳ vọng:** CPU stress → `r`>#CPU, `%us` cao, `%wa`~0. I/O stress → `b` cao, `%wa` cao, `iostat %util`~100%, `await` tăng. Mapping trả đúng session soe + SQL_TEXT.

## OSWatcher (Practice 36 — tùy chọn)

Collector shell nhẹ chạy 24/7 lưu vmstat/iostat/... vào `archive/` (AWR **không** lưu metric OS). Xem HUONG_DAN mục 4.

## Dọn dẹp

```bash
./99_cleanup.sh               # xóa /tmp/test1.img, kill busy loop, stop OSWatcher
```

## Câu hỏi tự kiểm tra

1. Vì sao load average không đủ để kết luận CPU bottleneck? Tách bằng cột nào của vmstat?
2. `%wa` cao nghĩa gì? Vì sao trên máy nhiều core `%wa` thấp vẫn có thể I/O bottleneck?
3. `si/so > 0` trên DB server — vì sao là báo động đỏ?
4. Cột nào trong `V$PROCESS` là cầu nối tới PID của OS? Map hai chiều thế nào?
5. `%st` (steal) là gì? Vì sao DB metric bình thường mà máy vẫn chậm?
6. Vì sao OSWatcher phải chạy **trước** sự cố, còn AWR thì không thay thế được nó cho metric OS?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_34/README.md`
