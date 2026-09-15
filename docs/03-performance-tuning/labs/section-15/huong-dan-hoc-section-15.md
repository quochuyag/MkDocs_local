---
title: 📚 Hướng dẫn học Section 15 — SQL Tracing với DBMS_MONITOR (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_15/HUONG_DAN_HOC_SECTION_15.md
---

# 📚 Hướng dẫn học Section 15 — SQL Tracing với DBMS_MONITOR (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> ⚠️ **BẮT BUỘC chạy TRONG VM** — lab dùng lệnh OS (`grep`, `trcsess`, `tkprof`) trên máy chứa trace file.
> Thời lượng gợi ý: ~80 phút (lecture 15' + lab 45' + debrief 20').
> Nguồn: Practice 15 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Trace = **máy ghi âm từng lời** (mọi parse/execute/fetch, mọi wait, mọi bind) — khác ASH là máy quay chụp mỗi giây. Đổi lại: overhead cao, file lớn, PHẢI bật đúng phạm vi và NHỚ TẮT.

| Cách bật | Dùng khi | Lệnh |
|---|---|---|
| Theo SID/SERIAL# | Đã nhìn thấy 1 phiên cụ thể | `DBMS_MONITOR.SESSION_TRACE_ENABLE(sid, serial#, waits, binds)` |
| Theo service/module/action | Production: không biết SID, connection pool, cả **phiên tương lai** | `DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE(...)` — dựa trên nhãn của lab 14 |

**Chuỗi công cụ sau khi có trace:**

```
N trace file --(trcsess: lọc+gộp theo module/service/client_id)--> 1 file
             --(tkprof SYS=no waits=yes aggregate=yes sort=(exeela,prsela,fchela))--> báo cáo
```

**Đọc tkprof:** mỗi câu có bảng `count / cpu / elapsed / disk / query / current / rows` × 3 pha **Parse/Execute/Fetch**. `query`=logical read consistent, `current`=logical read current-mode, `disk`=physical read. `elapsed >> cpu` → phần chênh là WAIT (đọc mục "Elapsed times include waiting on..." ngay dưới).

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_15   # ⚠️ BẮT BUỘC
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

---

## 2. Lab chính (user `system` trong VM, ~45 phút)

### Bước 1 — Thư mục trace: `@01_setup.sql` (~30 giây)

🤔 **Dự đoán:** PDB ORADB có thư mục trace RIÊNG không?

```sql
@01_setup.sql
```

**Kỳ vọng:** `Diag Trace` trỏ về thư mục của **instance ORCLCDB** (PDB không có thư mục riêng — vì thế cần `TRACEFILE_IDENTIFIER` để đánh dấu file của mình giữa rừng trace).

### Bước 2 — Trace MỘT phiên: `@02_workload.sql` (~1.5 phút)

🤔 **Dự đoán:** bật trace khi phiên đang chạy giữa chừng — trace file có các lệnh chạy TRƯỚC đó không?

```sql
@02_workload.sql
```

**Kỳ vọng theo mốc:** [1] spawn phiên client (nhãn `LAB15_CLIENT`) → [2] tìm được SID/SERIAL# **không cần hỏi ai** (nhờ client_identifier) → [3] enable trace (waits=TRUE) → [4] đường dẫn trace file lấy từ `V$PROCESS.TRACEFILE` → [6] `grep LAB15_SINGLE` ra **số > 0**.

💡 Trả lời dự đoán: lệnh chạy trước khi enable **không** có trong file — trace chỉ ghi từ lúc bật. Muốn trọn vẹn phải bật trước khi nghiệp vụ chạy (→ cách theo module ở bước 3).

### Bước 3 — Trace theo MODULE: `@03_diagnose.sql` (~2.5 phút)

🤔 **Dự đoán:** 3 phiên nối tiếp cùng module → bao nhiêu trace file?

```sql
@03_diagnose.sql
```

**Kỳ vọng:** [2] `DBA_ENABLED_TRACES` hiện trace theo `SERVICE_MODULE` → [3] 3 phiên chạy → [4] **TẮT trace** (quên bước này = trace vô hạn!) → [5] `ls` ra **3 file** `*PORDERS*.trc` — mỗi phiên một file, tkprof không nhận nhiều file → cần trcsess.

### Bước 4 — trcsess + tkprof: `@04_usecase_tkprof.sql` (~1 phút + 15 phút đọc)

```sql
@04_usecase_tkprof.sql
```

**Kỳ vọng:** trcsess gộp 3 file thành `/tmp/lab15_PROCESS_ORDERS.trc` → tkprof sinh `/tmp/lab15_PROCESS_ORDERS.txt` + bản `insert=` sinh script lưu stats vào bảng (dùng khi muốn so trước/sau tuning bằng SQL).

Mở báo cáo và tự trả lời 3 câu (ghi ra giấy):

```bash
less /tmp/lab15_PROCESS_ORDERS.txt
```

1. Câu nào đứng đầu (tốn elapsed nhất)? — nhớ `sort=(exeela,prsela,fchela)`.
2. Câu `/* my query */` chạy 4 lần với 4 bind khác nhau — `aggregate=yes` gộp thành mấy mục, `count` cột Execute/Fetch bằng bao nhiêu?
3. Ở câu nặng nhất: `elapsed` hơn `cpu` bao nhiêu — phần chênh nằm ở wait nào (đọc "Elapsed times include waiting on...")?

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
exit
```

**Kỳ vọng:** `enabled_traces = 0` (cực kỳ quan trọng!) + file trace lab bị xóa. Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. Trace phiên đang chạy giữa chừng — trace file có chứa các lệnh đã chạy TRƯỚC đó không?
2. Khi nào phải dùng trcsess? Khi nào bỏ qua được?
3. `SYS=no` trong tkprof loại bỏ gì? Vì sao thường muốn loại?
4. Ba cột `query`, `current`, `disk` trong tkprof nghĩa là gì?
5. Trace vs ASH: mỗi cái thắng ở tình huống nào? Chi phí của trace là gì?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. **Không** — trace ghi từ thời điểm enable trở đi. Hệ quả thực chiến: sự cố tái diễn theo chu kỳ thì bật trace theo module/service TRƯỚC rồi chờ nó xảy ra; sự cố đã qua thì dùng ASH/AWR, trace vô dụng.
2. trcsess cần khi phạm vi trace sinh **nhiều trace file** (nhiều phiên — mỗi server process một file) mà tkprof chỉ nhận một: nó lọc và gộp theo module/service/action/client_id. Trace một phiên duy nhất = 1 file → đưa thẳng cho tkprof, khỏi trcsess.
3. Loại các **recursive SQL do SYS thực hiện** (parse dictionary, quản lý space...) — thường là nhiễu không thuộc code ứng dụng. Giữ lại khi nghi vấn chính recursive SQL là vấn đề (vd parse quá nhiều, dynamic sampling).
4. `query` = logical reads ở **consistent mode** (đọc phục vụ SELECT, có thể cần undo); `current` = logical reads ở **current mode** (đọc block phiên bản hiện tại — đặc trưng DML); `disk` = physical reads từ đĩa. Cả ba đơn vị **block**. So `disk` với `query+current` ra được tỷ lệ cache-hit của riêng câu đó.
5. **ASH thắng**: nhìn toàn hệ thống, luôn bật sẵn, chi phí ~0, điều tra hậu kỳ. **Trace thắng**: cần chính xác 100% từng call cho MỘT phạm vi hẹp đã khoanh — đủ cả bind, từng wait với thời lượng thật (không phải sample). Chi phí trace: overhead CPU/IO trên phiên bị trace (có thể làm chậm chính nghiệp vụ đang điều tra), file lớn nhanh, và rủi ro quên tắt. Quy trình chuẩn: ASH khoanh vùng → trace bắn tỉa.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| [2] của 02 không tìm thấy phiên client | Job spawn chậm/FAILED → đợi 5s query lại tay; password OS mất sau restore → `chpasswd` |
| grep ra 0 ở [6] của 02 | Trace bật SAU khi query chạy (VM chậm làm lệch nhịp sleep) → chạy lại 02 |
| `ls *PORDERS*` ra ít hơn 3 file | Phiên của traced_workload chạy quá nhanh, 2 phiên rơi cùng process? Hiếm — chạy lại 03; kiểm tra job SUCCEEDED |
| trcsess: command not found | Không phải shell user oracle (thiếu ORACLE_HOME/bin trong PATH) → `sudo -u oracle -i` |
| tkprof output trống | File gộp rỗng — trace không chứa module (quên bật [1] hoặc tắt trước khi chạy [3]) → chạy lại 03 |
| Chạy từ host Windows lỗi HOST | Đúng như cảnh báo — lab này phải chạy TRONG VM |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 16 — Real-time SQL Monitoring (giám sát câu ĐANG chạy mà không cần trace)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_15/HUONG_DAN_HOC_SECTION_15.md`
