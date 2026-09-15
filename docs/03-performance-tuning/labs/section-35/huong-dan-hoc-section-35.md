---
title: 📚 Hướng dẫn học Section 35 — SQL Performance Analyzer (thực hành trong VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_35/HUONG_DAN_HOC_SECTION_35.md
---

# 📚 Hướng dẫn học Section 35 — SQL Performance Analyzer (thực hành trong VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 37 + Oracle internals.
> ⚠️⚠️ **SNAPSHOT nên có** (OFE + restart 2 lần) · **LICENSE** RAT.
> Thời lượng gợi ý: ~75 phút (lecture 20' + lab 40' + debrief 15').
> Nguồn: Practice 37 (Ahmed Baraka) + [senior guide](../../section-all-new/section-35-sql-performance-analyzer-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

SPA trả lời **"thay đổi này có làm câu SQL nào chậm/đổi plan không?"** ở mức **từng SQL**.

```
SPA         → từng SQL     → plan regression   → nhẹ, nhanh, chạy sớm
DB Replay   → toàn workload → concurrency/contention → nặng, thực tế (Section 36)
```

Luồng: **STS** (SQL Tuning Set) → `TEST EXECUTE` **before** → áp thay đổi → `TEST EXECUTE` **after** → `COMPARE PERFORMANCE` → report (improved/regressed/plan changed).

- `TEST EXECUTE` **chạy thật** từng SQL (DML có side effect!) → chỉ trên bản test; production dùng `EXPLAIN PLAN`.
- Mô phỏng "upgrade" = đổi `OPTIMIZER_FEATURES_ENABLE` (proxy plan optimizer, không phải upgrade thật).
- SPA chạy **tuần tự** → **không** thấy concurrency/lock/contention.

---

## 1. Khởi động + Snapshot (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant snapshot save pre_spa
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_35
```

---

## 2. Lab: SPA before/after quanh "upgrade" (~40 phút)

### Bước 1 — "Trước upgrade" + tạo STS (SYS): `@01_setup.sql`

🤔 **Dự đoán:** Vì sao mô phỏng "11g" bằng OFE thay vì cài bản 11g thật? OFE thay đổi cái gì?

```bash
sqlplus / as sysdba
```
```sql
@01_setup.sql
```
Ghi lại giá trị OFE gốc (dòng SHOW PARAMETER). Bỏ comment khối OFE=11.2.0.2 + restart. STS `SOE_WKLD_STS` được tạo.

### Bước 2 — Chạy workload (soe): `@client_wrkld.sql`

🤔 **Dự đoán:** Vì sao phải chạy workload TRƯỚC khi capture? Capture lấy SQL từ đâu?

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```
```sql
@client_wrkld.sql
```
**Kỳ vọng:** 8 câu SQL (có bind) chạy → cursor vào cache. ⚠️ Nếu báo lỗi bảng không tồn tại → schema SOE của bạn khác; sửa tên bảng/cột trong `client_wrkld.sql`.

### Bước 3 — Capture + 'before' (SYS): `@02_capture.sql`

🤔 **Dự đoán:** Capture filter `PARSING_SCHEMA_NAME='SOE'` — sẽ bắt được câu nào? `TEST EXECUTE` làm gì với từng câu?

```sql
@02_capture.sql
```
**Kỳ vọng:** `DBA_SQLSET_STATEMENTS` liệt kê các câu SOE; SPA task `SPA_SOE_TASK` tạo xong; execution 'before' chạy (TEST EXECUTE với OFE 11.2).

### Bước 4 — Áp "upgrade" + 'after' + compare (SYS): `@03_change_compare.sql`

🤔 **Dự đoán:** Sau khi đổi OFE 12.2, câu nào có khả năng đổi plan nhất — câu lookup đơn giản hay câu analytic (RANK/CUBE)?

```sql
@03_change_compare.sql
```
Bỏ comment khối OFE=12.2.0.1 + restart.

**Kỳ vọng — report SUMMARY:**
```text
SQL statements analyzed : 8
Improved                : n
Regressed               : m     ← mục tiêu bắt được (nếu có)
Unchanged               : k
Plan changed            : p     ← câu analytic dễ đổi plan giữa 2 OFE
```
💡 Task + STS **sống qua restart** (lưu trong dictionary) — đó là lý do dùng tên task cố định `SPA_SOE_TASK`.

---

## 3. Dọn dẹp (BẮT BUỘC)

```sql
@99_cleanup.sql
```
```powershell
vagrant snapshot restore pre_spa    # trả OFE + restart về trước lab
vagrant halt
```

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. SPA vs DB Replay khác ở mức nào? Khi nào dùng cái nào / cả hai?
2. `TEST EXECUTE` vs `EXPLAIN PLAN` — khác gì? Production dùng cái nào?
3. STS nạp từ đâu? Vì sao STS nghèo → "an toàn giả"?
4. OFE là proxy của gì? Không thay thế được gì?
5. Một câu regress — bước tiếp theo (giữ plan tốt) là gì?
6. Vì sao SPA không bắt được `enq: TX`/`buffer busy`?

<details>
<summary>📖 Đáp án</summary>

1. SPA = mức **từng SQL** (plan/chi phí regression), chạy tuần tự, nhẹ. DB Replay = mức **toàn workload** (concurrency/contention/throughput), nặng, thực tế. Thay đổi lớn (upgrade major): dùng **cả hai** — SPA trước (bắt plan regression sớm), DB Replay sau (validate concurrency).
2. `TEST EXECUTE` **chạy thật** từng SQL → thu stats runtime thật (elapsed/buffer gets) nhưng DML có side effect + tốn tài nguyên. `EXPLAIN PLAN` chỉ compile plan, không chạy → an toàn nhưng chỉ so plan-diff. Production dùng **EXPLAIN PLAN**; TEST EXECUTE chỉ trên bản test.
3. STS nạp từ cursor cache (`CAPTURE_CURSOR_CACHE_SQLSET`), AWR, hoặc STS khác. STS chỉ chứa SQL đã capture → SPA chỉ đánh giá những câu đó. STS nghèo (1 phút, 1 schema, giờ thấp điểm) → SQL peak/schema khác không được đánh giá → "0 regressed" chỉ đúng cho tập nhỏ, không phải toàn hệ.
4. OFE là proxy **tập tính năng optimizer** theo version → pre-check plan regression do optimizer. Không thay thế test upgrade đầy đủ (binary mới, stats mới, bug fix, tính năng mới).
5. Dùng **SQL Plan Management (SPM/Baseline)** cố định plan tốt "before" cho câu regressed → sau upgrade optimizer không được đổi sang plan xấu. SPA tìm regression, SPM giữ plan.
6. SPA chạy **tuần tự từng SQL** → không mô phỏng nhiều session đồng thời → không có lock/latch/hot block/throughput contention. `enq: TX`/`buffer busy` chỉ sinh khi concurrency thật → chỉ **DB Replay** thấy.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `client_wrkld.sql` lỗi ORA-00942 (table not found) | Schema SOE khác → sửa tên bảng/cột trong client_wrkld.sql |
| STS rỗng sau capture | Cursor đã rời cache → chạy lại `@client_wrkld.sql` NGAY trước `@02_capture.sql` |
| `ORA-01031` khi CREATE_SQLSET cho SOE | Chạy phần tạo STS bằng SYS (đã vậy trong 01), hoặc grant ADMINISTER SQL TUNING SET |
| Task mất sau restart | Task lưu dictionary — dùng đúng tên `SPA_SOE_TASK`; đừng tạo lại |
| Report rỗng/không phân loại | Chưa chạy đủ before + after + COMPARE PERFORMANCE theo thứ tự |
| Muốn hoàn tác OFE | `vagrant snapshot restore pre_spa` |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant snapshot restore pre_spa` rồi `vagrant halt`
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi số đo thật
- [ ] Buổi kế tiếp: Section 36 (Database Replay) — mức toàn workload/concurrency


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_35/HUONG_DAN_HOC_SECTION_35.md`
