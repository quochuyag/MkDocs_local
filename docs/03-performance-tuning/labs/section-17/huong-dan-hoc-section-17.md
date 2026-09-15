---
title: 📚 Hướng dẫn học Section 17 — Automated Maintenance Tasks (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_17/HUONG_DAN_HOC_SECTION_17.md
---

# 📚 Hướng dẫn học Section 17 — Automated Maintenance Tasks (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~50 phút (lecture 10' + lab 25' + debrief 15') — lab ngắn nhất từ đầu khóa.
> Nguồn: Practice 17 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Oracle tự chạy **3 việc bảo trì** trong các "maintenance window":

| Task | Làm gì | Ghi chú vận hành |
|---|---|---|
| `auto optimizer stats collection` | Gather stats cho object stale | Gần như **không bao giờ tắt** — tắt là optimizer mù dần |
| `auto space advisor` | Segment Advisor tự động (tìm segment nên shrink) | Vô hại, ít ai đụng |
| `sql tuning advisor` | Tự tune SQL nặng, có thể tạo SQL Profile | **Thuộc Tuning Pack** — không mua pack là PHẢI tắt (license, không phải hiệu năng) |

**Lịch mặc định**: 7 window `<THỨ>_WINDOW` — ngày thường mở **22:00 + 4 tiếng**, cuối tuần **06:00 + 20 tiếng**. Đổi giờ window = đổi giờ chạy của MỌI task (chúng chung window group).

**Vì sao DBA phải quan tâm:** các task này ăn CPU/IO thật. Hệ thống có batch đêm mà window mở 22:00 là hai bên giẫm nhau; ngược lại hệ 24x7 thì "đêm" của Oracle chưa chắc là giờ thấp điểm của bạn.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_17
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

---

## 2. Lab chính (user `system`, ~25 phút)

### Bước 1 — Khám phá: `@01_setup.sql` (~1 phút)

🤔 **Dự đoán:** sửa `DURATION` của một window đang ENABLED — được không?

```sql
@01_setup.sql
```

**Kỳ vọng:** [1] 3 task đều ENABLED kèm `MEAN_JOB_DURATION` (căn cứ quy hoạch window); [2] 7 window đúng lịch mặc định; [3] **GHI RA GIẤY** config gốc của SUNDAY/FRIDAY — cleanup cần đối chiếu.

### Bước 2 — Đổi lịch 2 window: `@02_workload.sql` (~30 giây)

Kịch bản của course: doanh nghiệp nghỉ **thứ Sáu** thay vì Chủ nhật → hoán đổi vai trò 2 window.

```sql
@02_workload.sql
```

**Kỳ vọng:** cả 2 block chạy OK — chú ý pattern bắt buộc `DISABLE → SET_ATTRIBUTE (DURATION, REPEAT_INTERVAL) → ENABLE`. Trả lời dự đoán: sửa window đang enabled **bị chặn**, phải disable trước.

### Bước 3 — Xác minh + đọc log: `@03_diagnose.sql` (~2 phút)

🤔 **Dự đoán:** log job `ORA$AT%` trên VM lab sẽ dày hay thưa? Vì sao?

```sql
@03_diagnose.sql
```

**Kỳ vọng:** [1] SUNDAY giờ là `byhour=22` + 4h, FRIDAY là `byhour=6` + 20h; [2]-[3] log job `ORA$AT%SA%/%OS%/%SQ%` — trên VM lab **thưa thớt** vì VM thường tắt vào giờ window mở (chính điều đó là bài học: task chỉ chạy khi window MỞ và instance SỐNG); [4] `DBA_AUTOTASK_CLIENT_HISTORY` — task nào chạy trong window nào.

### Bước 4 — Tắt/bật task: `@04_usecase_task_onoff.sql` (~1 phút)

🤔 **Dự đoán:** tắt `sql tuning advisor` bằng lệnh gì — DBMS_SCHEDULER hay package khác?

```sql
@04_usecase_task_onoff.sql
```

**Kỳ vọng:** `DBMS_AUTO_TASK_ADMIN.DISABLE(client_name => 'sql tuning advisor', window_name => NULL)` → STATUS = DISABLED → ENABLE lại. Biến thể đáng nhớ: truyền `window_name` cụ thể để tắt task chỉ trong MỘT window (đêm có batch nặng).

---

## 3. Dọn dẹp (BẮT BUỘC — 30 giây)

```sql
@99_cleanup.sql
exit
```

**Kỳ vọng:** SUNDAY về 06:00+20h, FRIDAY về 22:00+4h, 3 task ENABLED — đối chiếu với tờ giấy ghi ở bước 1. Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Ba automated tasks là gì — task nào nguy hiểm nhất nếu TẮT, task nào nguy hiểm nhất nếu ĐỂ BẬT?
2. Muốn auto stats không chạy đêm thứ Hai (batch nặng) nhưng vẫn chạy các đêm khác — làm thế nào?
3. Window đóng khi job stats đang chạy dở — chuyện gì xảy ra?
4. `MEAN_JOB_DURATION` dùng để làm gì khi quy hoạch window?
5. Hệ 24x7 tải đều: lịch mặc định có hợp lý không? Cân nhắc gì khi dời?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. (Xem bảng mục 0.) Nguy hiểm nhất nếu TẮT: **auto optimizer stats** — stats thoái hóa dần, vài tuần sau plan đổ vỡ hàng loạt và rất khó truy về nguyên nhân. Nguy hiểm nhất nếu ĐỂ BẬT: **sql tuning advisor** với shop không mua Tuning Pack — chạy nó là dùng tính năng chưa trả tiền (rủi ro audit), chưa kể nó có thể tự tạo SQL Profile làm plan đổi "bí ẩn" (nếu ACCEPT_SQL_PROFILES bật).
2. `DBMS_AUTO_TASK_ADMIN.DISABLE(client_name => 'auto optimizer stats collection', operation => NULL, window_name => 'MONDAY_WINDOW')` — tắt đúng một window, các đêm khác không ảnh hưởng. Đây là lý do tham số window_name tồn tại.
3. Job auto stats bị **dừng** khi window đóng (stats gather được thiết kế chạy theo batch object nhỏ, phần đã xong vẫn giữ); danh sách object stale còn lại chờ window sau. Hệ quả: window quá ngắn so với lượng object stale → stats "đuổi không kịp" — nhìn `MAX_DURATION_LAST_7_DAYS` sát duration của window là dấu hiệu phải nới.
4. So `MEAN_JOB_DURATION`/`MAX_DURATION` với độ dài window: nếu job thường xuyên chạy gần hết window → window thiếu giờ (nới duration hoặc giảm việc); nếu job xong trong vài phút → có thể thu hẹp window để trả tài nguyên cho nghiệp vụ đêm.
5. Không đương nhiên hợp lý — "22:00" chỉ là giả định giờ thấp điểm kiểu văn phòng. Hệ 24x7 phải: nhìn profile tải thật (AWR theo giờ) tìm vùng trũng; tránh trùng batch/backup; đủ dài cho auto stats; và nhớ resource manager plan mặc định trong window (`DEFAULT_MAINTENANCE_PLAN`) sẽ giới hạn tài nguyên nghiệp vụ trong giờ đó.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| ORA-27476/quyền khi sửa window | Thiếu prefix SYS. hoặc thiếu quyền → script đã dùng `SYS.SUNDAY_WINDOW`, chạy bằng system (có DBA) |
| Sửa window báo lỗi "enabled" | Quên DISABLE trước → đúng bài học; chạy trọn block trong script |
| Log ORA$AT% trống trơn | VM chưa từng sống qua giờ window mở — bình thường với VM lab |
| DBA_AUTOTASK_CLIENT không thấy 3 task | Đang ở CDB root hoặc PDB khác → connect đúng ORADB |
| Quên chạy 99_cleanup | Lịch window sai lệch vĩnh viễn → chạy lại 99 bất cứ lúc nào (giá trị mặc định ghi trong script) |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 19 — Enqueue Waits (bắt đầu Giai đoạn 3: Contention)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_17/HUONG_DAN_HOC_SECTION_17.md`
