---
title: Lab Section 2 — Kiểm chứng môi trường thực hành
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_2/README.md
---

# Lab Section 2 — Kiểm chứng môi trường thực hành

> Thay thế Practice 1 (dựng VM thủ công OL6 + 12.2 — EOL) bằng môi trường Vagrant OL7.9 + Oracle 19.3 EE đã dựng sẵn: [ke_hoach/03_phase2_setup_log.md](../../ke-hoach/003-phase2-setup-log.md) · SSH/VM: [ke_hoach/05_huong_dan_ssh_vm.md](../../ke-hoach/005-huong-dan-ssh-vm.md)
> Chạy từ thư mục này (`labs/section_2/`). Quy ước chung: [labs/README.md](../readme.md)

**Câu hỏi lab trả lời:** môi trường có đúng hình dạng mọi lab sau kỳ vọng không, và bộ sinh tải (hạ tầng của cả khóa) chạy được không?

## Chạy lab — user `system` (không tạo object nào)

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql      -- khám sức khỏe: instance/PDB, tham số, tablespace, SOE schema
@02_workload.sql   -- ~1 phút: smoke test chuỗi credential → external job → 2 phiên SOE
@99_cleanup.sql
```

## Giá trị kỳ vọng (đo 2026-07-14 — checklist đối chiếu)

| Mục | Kỳ vọng |
|---|---|
| Instance / version | `ORCLCDB` / 19.0 trên host `srv1` |
| PDB ORADB | `READ WRITE`, con_id 3 (ghi lại con_dbid ≠ cdb_dbid — Section 9 cần) |
| cpu_count / db_block_size | 2 / 8192 |
| statistics_level | `TYPICAL` (BASIC = time model + AWR chết!) |
| SOETBS | ~1.2GB |
| SOE segments | **49** gốc; nhiều hơn = object lab cũ còn sót (vd `CUST` ≈121MB của lab section_28 → dọn bằng `labs/section_28/99_cleanup.sql`) |
| CUSTOMERS / ORDERS / ORDER_ITEMS | ~48.6k / ~1.35M / ~3.7M rows |
| Invalid SOE objects | 0 |
| Smoke test (02) | 2 phiên SOE ACTIVE (event `log file sync`) · DB time +~60s · job `LAB_SOE_DRIVER` SUCCEEDED |

## Hạ tầng sinh tải (dùng cho mọi section — hiểu một lần ở đây)

`@../_toolkit/workload_soe.sql N S` = external job (credential `LAB_OS_CRED`) chạy `soe_load.sh` trong VM → spawn N phiên `sqlplus soe/soe` **thật** chạy `lab_soe_load(S)`. Vì sao không dùng job PLSQL_BLOCK thường: slave J00x là background process, **không tính vào DB time** (đo được: job 15s → +0.01s). Chuẩn bị một lần (mất khi restore snapshot): password OS oracle — `vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"`.

## Câu hỏi tự kiểm tra

1. `statistics_level=BASIC` thì những công cụ nào của khóa này ngừng hoạt động?
2. Vì sao phải ghi nhớ con_dbid của ORADB khác dbid của CDB? (gợi ý: DBA_HIST_*)
3. Smoke test dựa vào chuỗi 4 mắt xích nào? Mắt xích nào mất sau `vagrant snapshot restore`?
4. VM 2 vCPU nghĩa là gì với các lab tải nặng? (xem số liệu section_6)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_2/README.md`
