---
title: ke_hoach/ — Kế hoạch & Nhật ký xây dựng môi trường học
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/ke_hoach/00_INDEX.md
---

# ke_hoach/ — Kế hoạch & Nhật ký xây dựng môi trường học

Thư mục chứa các tài liệu kế hoạch/nhật ký sinh ra trong quá trình làm việc với Claude.
**Số thứ tự đầu tên file = trình tự tạo** (nhỏ tạo trước, lớn tạo sau).

| # | File | Loại | Ngày tạo | Nội dung |
| --- | --- | --- | --- | --- |
| 01 | [01_learning_plan.md](001-learning-plan.md) | Kế hoạch tổng | 2026-07-13 | Phân tích hiện trạng dự án + kế hoạch 4 giai đoạn (labs/, môi trường, senior guides, benchmark) + lộ trình học 10 tuần |
| 02 | [02_phase2_environment_vagrant_plan.md](002-phase2-environment-vagrant-plan.md) | Kế hoạch chi tiết | 2026-07-13 | Giai đoạn 2: dựng VM Oracle 19c bằng Vagrant — 8 bước A→H, checklist, bảng rủi ro |
| 03 | [03_phase2_setup_log.md](003-phase2-setup-log.md) | Nhật ký thực hiện | 2026-07-13 | Step-by-step các lệnh ĐÃ chạy thật (kể cả lỗi + cách xử lý) — dùng để tái lập môi trường |
| 04 | [04_huong_dan_swingbench.md](004-huong-dan-swingbench.md) | Hướng dẫn thao tác | 2026-07-13 | 5 bước GUI cài/cấu hình Swingbench 2.5 người dùng tự làm |
| 05 | [05_huong_dan_ssh_vm.md](005-huong-dan-ssh-vm.md) | Hướng dẫn thao tác | 2026-07-14 | SSH vào VM (account/pass/host/key, 3 cách), user oracle, mount `/labs`, chạy lab trong VM, bẫy vboxsf, troubleshooting |
| 06 | [06_lo_trinh_2_tuan.html](06-lo-trinh-2-tuan.html) + [.ics](06-lo-trinh-2-tuan.ics) | Lộ trình học + lịch | 2026-08-18 | Runbook 15 đêm (24/08→07/09/2026, 21:30–23:00) học lại toàn khóa trên VM: mỗi đêm có câu hỏi ôn bài đêm trước, việc chuẩn bị, ý chính bài giảng, các bước lab, số đo bắt buộc ghi lại; HTML có checkbox theo dõi tiến độ, ICS để import Google Calendar. Sinh lại bằng `python tools/make_lo_trinh.py --start ... --hour ...` |

## Quan hệ giữa các file

```text
01_learning_plan (kế hoạch tổng, 4 giai đoạn)
 └── 02_phase2_environment_vagrant_plan (chi tiết Giai đoạn 2)
      └── 03_phase2_setup_log (nhật ký thực thi kế hoạch 02)
           ├── 04_huong_dan_swingbench (phần người dùng tự thao tác trong 03)
           └── 05_huong_dan_ssh_vm (làm việc bên trong VM + mount /labs)
                └── 06_lo_trinh_2_tuan (lịch 15 đêm dùng môi trường đã dựng ở 03/05)
```

## Quy ước

- File mới trong quá trình làm việc → đặt tại đây, đánh số tiếp theo (05_, 06_, ...)
- Cập nhật bảng trên mỗi khi thêm file
- `progress.md` (tiến độ học theo buổi) vẫn ở thư mục gốc theo quy ước CLAUDE.md — không chuyển vào đây

## Tra cứu nhanh thông số môi trường

Xem bảng "Tóm tắt thông số môi trường" cuối [03_phase2_setup_log.md](003-phase2-setup-log.md) — VM `srv1`, Oracle 19c EE, PDB `ORADB`, connect từ host `//localhost:15210/ORADB`, password `oracle_4U`.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/ke_hoach/00_INDEX.md`
