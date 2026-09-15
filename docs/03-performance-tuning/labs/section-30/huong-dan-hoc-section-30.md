---
title: 📚 Hướng dẫn học Section 30 — Table Compression (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_30/HUONG_DAN_HOC_SECTION_30.md
---

# 📚 Hướng dẫn học Section 30 — Table Compression (thực hành trong Linux VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 32 + Oracle internals.
> ⚠️⚠️ **LICENSE:** `COMPRESS ADVANCED` = Advanced Compression Option (tính phí). Basic = miễn phí. Lab chỉ để học.
> Thời lượng gợi ý: ~75 phút (lecture 20' + lab 40' + debrief 15').
> Nguồn: Practice 32 (Ahmed Baraka) + [senior guide](../../section-all-new/section-30-table-compression-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

Compression của Oracle = **de-duplication cấp block**, không phải zip toàn bảng.

```
Data block nén:
[Symbol table: [0]="XXXXXX" [1]="CATEGORY_5"]  ← giá trị lặp lưu 1 lần
[Row1: id=1 note→[0] cat→[1]]                  ← row chỉ giữ con trỏ
[Row2: id=2 note→[0] cat→[1]] ...
```

- Ratio phụ thuộc **độ lặp TRONG block** → data unique ~1x, data lặp nhiều → nén tốt.
- Nén xảy ra **khi block đầy tới ngưỡng**, không từng row → **cách nạp** quyết định.

| loại \ nạp | conventional INSERT | direct-path (APPEND) |
|---|---|---|
| **BASIC** (free) | ❌ không nén | ✅ nén |
| **ADVANCED** (license) | ✅ nén | ✅ nén |

**Chuỗi tư duy:** chứng minh điều kiện nén có hiệu lực → ratio phụ thuộc độ lặp → lợi ích load & query.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_30
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```
**Grant một lần** (SYS) cho `before_after.sql` (dùng ở bước 04):
```bash
sqlplus / as sysdba
```
```sql
GRANT SELECT ON sys.v_$session_event TO soe;
EXIT
```

---

## 2. Lab chính (user `soe`, ~40 phút)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

### Bước 1 — Tạo 3 bảng: `@01_setup.sql`

🤔 **Dự đoán:** 3 bảng cùng cấu trúc (nocompress / basic / advanced), source nạp data **RANDOM**. Data random thì compression có ích không?

```sql
@01_setup.sql
```

### Bước 2 — Điều kiện nén có hiệu lực: `@02_workload.sql`

🤔 **Dự đoán:** Nạp CUST_BCOMPRESSED (basic) bằng conventional INSERT — kích thước có nhỏ hơn source không? Còn `INSERT /*+ APPEND */` thì sao?

```sql
@02_workload.sql
```

**Kỳ vọng — GHI bảng tổng kết:**
```text
THI NGHIEM 1: Basic + conventional  → SIZE = source   (KHÔNG nén!)
THI NGHIEM 2: Basic + direct-path   → nhỏ hơn chút     (random: ít lặp)
THI NGHIEM 3: Advanced + conventional → nhỏ hơn source (Advanced nén conventional!)
              Advanced + direct-path   → ~ bằng basic direct-path
```

💡 **Điểm đắt giá:** "khai báo COMPRESS" **không** nghĩa là dữ liệu đã nén. Basic chỉ nén ở direct-path.

### Bước 3 — Ratio phụ thuộc độ lặp: `@03_diagnose.sql`

🤔 **Dự đoán:** Lần này nạp data **LẶP NHIỀU** (NOTE1='XXXXXX'). Ratio nén so với data random ở bước 2 thay đổi thế nào?

```sql
@03_diagnose.sql
```

**Kỳ vọng:** Basic direct-path với data lặp → nén **rất tốt** (khác hẳn data random). `GET_COMPRESSION_RATIO` ước lượng ratio trước khi nén thật.

### Bước 4 — Lợi ích load & query: `@04_usecase_query_perf.sql`

🤔 **Dự đoán:** T1 (nocompress), T2 (basic+conventional), T3 (basic+append). Cái nào **nạp nhanh nhất**? Query cái nào ít logical reads nhất?

```sql
@04_usecase_query_perf.sql
```

**Kỳ vọng:**

| | Thời gian nạp | Kích thước | logical reads (COUNT) |
|---|---|---|---|
| T1 nocompress | chậm | lớn | nhiều |
| T2 basic+conventional | chậm (~T1) | ~T1 (không nén) | ~T1 |
| T3 basic+append | **nhanh nhất** | **nhỏ nhất** | **ít nhất** |

💡 **Nghịch lý:** T3 nạp nhanh hơn dù phải nén — vì block nén chứa nhiều row hơn → **ít block phải ghi ra đĩa hơn** → I/O ghi ít, thắng chi phí CPU nén.

---

## 3. Dọn dẹp (BẮT BUỘC)

```sql
@99_cleanup.sql
exit
```
```bash
exit
exit
```
```powershell
vagrant halt
```

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Vì sao Basic không nén conventional INSERT? (cơ chế "nén khi block đầy")
2. `COMPRESSION='ENABLED'` chứng minh dữ liệu đã nén chưa?
3. Ratio phụ thuộc gì? Vì sao `ORDER BY` cột lặp làm tăng ratio?
4. Vì sao direct-path load trên bảng nén nhanh hơn nạp bảng không nén?
5. Basic vs Advanced khác cốt lõi ở đâu? Cái nào cần license?
6. Khi nào không nên nén dù đĩa đầy?

<details>
<summary>📖 Đáp án</summary>

1. Basic chỉ nén khi block được xây đầy một lần (bulk load). Conventional INSERT chèn từng row → block không bao giờ qua bước nén → dữ liệu nằm uncompressed dù bảng khai báo COMPRESS BASIC.
2. **Chưa.** `COMPRESSION='ENABLED'` chỉ là **thuộc tính** áp cho dữ liệu tương lai (direct-path với basic). Dữ liệu cũ không nén cho tới khi `MOVE`/reload. Kiểm bằng BLOCKS trước/sau hoặc `GET_COMPRESSION_RATIO`.
3. Phụ thuộc **độ lặp dữ liệu trong cùng block** (symbol table cấp block). `ORDER BY` gom giá trị giống nhau vào cùng block → symbol table hiệu quả hơn → ratio cao hơn.
4. Block nén chứa nhiều row hơn → ít block phải ghi ra đĩa hơn; direct-path ghi thẳng block đầy trên HWM, không qua buffer cache, ít undo. I/O ghi tiết kiệm > chi phí CPU nén → nhanh hơn. (Chỉ đúng với direct-path.)
5. Cốt lõi: **khi nào block được nén**. Basic chỉ nén ở direct-path (bulk); Advanced (OLTP) nén cả conventional DML bằng cơ chế batched/amortized (nén khi block đầy). **Advanced cần license** (Advanced Compression Option); Basic miễn phí.
6. Khi dữ liệu unique/ngẫu nhiên (ratio ~1x, tốn CPU vô ích); khi bảng OLTP update nặng mà chỉ có Basic (conventional INSERT không nén, còn phình do update); khi hệ thống đã CPU-bound (chi phí giải nén làm chậm thêm).

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `SP2-0310` không mở được `../_toolkit/...` | `cd /labs/section_30` rồi vào lại sqlplus |
| `ORA-00942` khi before_after (bước 04) | SYS: `GRANT SELECT ON sys.v_$session_event TO soe;` |
| `ORA-00439: feature not enabled: Advanced Compression` | Phiên bản/edition không cho ADVANCED → bỏ qua bảng ACOMPRESSED, chỉ học Basic |
| Basic direct-path không nén (random) | Đúng kỳ vọng — data random ít lặp; xem bước 03 với data lặp nhiều |
| `@04` build T_SRC lâu | 1M rows cross — chấp nhận ~30-60s; hoặc giảm `LEVEL <= 500000` |
| `INSERT /*+ APPEND */` xong rồi query báo `ORA-12838` | Phải `COMMIT` sau APPEND trước khi đọc lại bảng (đã có trong script) |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi số đo thật
- [ ] Buổi kế tiếp: Section 31 (In-Memory Column Store)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_30/HUONG_DAN_HOC_SECTION_30.md`
