---
title: Hướng dẫn học Section 23 — PGA Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_23/HUONG_DAN_HOC_SECTION_23.md
---

# Hướng dẫn học Section 23 — PGA Tuning

> Lab: `labs/section_23/` · Nguồn: Practice 25 (Ahmed Baraka)
> ⚠️ **Chưa kiểm chứng trên VM** — mọi "output kỳ vọng" là dự tính. Buổi chạy đầu: đối chiếu, sửa lệch, điền số thật vào README.

---

## 0. Kiến thức nền (5 phút)

SGA là bếp chung của cả nhà hàng; **PGA là thớt riêng của từng đầu bếp** — nơi SORT, HASH JOIN, GROUP BY thái đồ. Thớt đủ to thì thái một lượt xong (**optimal**); chật thì phải bê bớt ra bàn phụ ở kho (temp tablespace) một lần (**one-pass**) hay nhiều lần (**multipass** — thảm họa).

| Khái niệm | Là gì | Nhìn ở đâu |
|---|---|---|
| Work area | Vùng PGA cho 1 phép sort/hash/groupby đang chạy | `V$SQL_WORKAREA_ACTIVE` (sống), `V$SQL_WORKAREA` (lịch sử theo cursor) |
| optimal / one-pass / multipass | Vừa RAM / tràn temp 1 lượt / tràn nhiều lượt | `V$SYSSTAT: workarea executions - %` |
| PGA_AGGREGATE_TARGET | Mục tiêu **mềm** tổng PGA — thiếu thì Oracle vượt | `V$PGASTAT: over allocation count` |
| PGA_AGGREGATE_LIMIT | Trần **cứng** — chạm là ORA-4036 | `show parameter` |
| PGA Advisory | Mô phỏng hit% + số lần over-alloc theo từng target | `V$PGA_TARGET_ADVICE` |

**3 luật khám của course:** multipass = 0 · `sorts (disk)` thấp (OLTP) · `cache hit percentage` ≈ 100.

---

## 1. Khởi động môi trường

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
cd D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course
sqlplus -S -L "system/oracle_4U@//localhost:15210/ORADB" "@labs\_toolkit\00_env_check.sql"
```

---

## 2. Lab chính từng bước

### Bước 1 — Khám sức khỏe lúc bình thường

🤔 **Dự đoán trước:** VM mới bật, chưa có tải — `workarea executions - multipass` sẽ là bao nhiêu? `cache hit percentage` bao nhiêu?

```powershell
cd labs\section_23
sqlplus system/oracle_4U@//localhost:15210/ORADB "@01_setup.sql"
```

**Kỳ vọng:** multipass = 0, hit ≈ 100, histogram chỉ có executions ở giỏ size nhỏ. **Ghi lại `pga_aggregate_target` gốc** — cuối lab phải về đúng số này.

### Bước 2 — Soi work area đang sống dưới tải

🤔 **Dự đoán trước:** 3 phiên sort ~cả bảng ORDERS chạy song song — cột PASS trong `V$SQL_WORKAREA_ACTIVE` sẽ là 0 hay ≥1 với target hiện tại?

```text
@02_workload.sql        -- ~3 phút, tự sleep và poll 2 lần
```

**Kỳ vọng:** thấy dòng `WINDOW (SORT)` / `HASH-JOIN` với MEM_KB hàng nghìn; PASS = 0 (PGA còn khỏe); mục [5] `V$SQL_WORKAREA` giữ lịch sử sau khi câu chạy xong — khác `_ACTIVE` biến mất.

### Bước 3 — Tự tay ép tràn temp (thí nghiệm đắt giá nhất lab)

🤔 **Dự đoán trước:** cùng câu sort 50k row — lần 2 (auto) và lần 3 (bóp 160KB) khác nhau ở chỉ số nào trong autotrace? `sorts (disk)` sẽ nhảy mấy?

```text
@03_diagnose.sql
```

**Kỳ vọng:**

- SQLID 1 (100 row): `sorts (memory)` tăng, disk = 0.
- SQLID 2 (50k row, AUTO): vẫn disk = 0 — PGA tự cấp vài MB.
- SQLID 3 (50k row, MANUAL 160KB): **`sorts (disk)` = 1**, xuất hiện `physical writes direct temporary tablespace`.
- Mục [4]: SQLID 3 có `EST_OPTIMAL_KB` lớn nhưng `LAST_MEM_KB` nhỏ và `MAX_TEMP_KB` có giá trị — Oracle *biết* cần bao nhiêu nhưng bị ta trói tay.

### Bước 4 — Bóp target toàn cục + đọc Advisory

🤔 **Dự đoán trước:** target 50MB nhưng 3 phiên cần nhiều hơn — `total PGA allocated` sẽ dừng ở 50MB hay vượt? Oracle chọn hy sinh gì?

```text
@04_usecase_pga_advice.sql   -- ~3 phút; TỰ trả target về gốc ở cuối
```

**Kỳ vọng:** allocated **vượt** 50MB, `over allocation count` > 0; advisory in bảng target/hit%/overalloc. Thực hành đọc: gạch dòng overalloc > 0 trước, rồi tìm điểm gãy hit%. Cuối script `show parameter` phải hiện lại giá trị gốc.

---

## 3. Phần mở rộng (không bắt buộc)

- Chạy lại bước 3 với `SORT_AREA_SIZE` = 1MB, 8MB — tìm ngưỡng hết tràn temp cho câu 50k row → cảm nhận "work area cần cỡ nào cho X MB dữ liệu sort".
- Trong lúc 02 chạy: mở phiên thứ 2 chạy `@labs/_toolkit/top_waits.sql` — thấy `direct path read/write temp` không? Nếu không: PGA vẫn đủ, thử hạ target trước khi thả tải.

---

## 4. Dọn dẹp bắt buộc

```text
@99_cleanup.sql
```

Kiểm tra: `pga_aggregate_target` = giá trị gốc, `workarea_size_policy` = AUTO, 0 session LAB23_SORT.

---

## 5. Debrief — trả lời KHÔNG nhìn tài liệu

1. Kể 3 kiểu kết thúc của work area và mức độ chấp nhận từng kiểu ở OLTP vs batch.
2. Vì sao bước 3 phải `ALTER SESSION SET WORKAREA_SIZE_POLICY=MANUAL` trước khi `SORT_AREA_SIZE` có tác dụng?
3. `V$SQL_WORKAREA_ACTIVE` vs `V$SQL_WORKAREA`: khi user báo "báo cáo hôm qua chạy 1 tiếng", bạn mở view nào, lọc cột nào?
4. `total PGA allocated` = 180MB khi target = 50MB — giải thích. Khi nào Oracle mới thực sự chặn cấp phát?
5. Thứ tự 2 bước đọc `V$PGA_TARGET_ADVICE`? Vì sao chọn theo hit% trước là sai?

<details>
<summary>Đáp án</summary>

1. **optimal** (vừa RAM — mong muốn mọi nơi), **one-pass** (tràn temp 1 lượt — batch/DSS chấp nhận được vì câu to sort hàng GB không thể đòi RAM tương đương; OLTP mà one-pass nhiều là target thiếu), **multipass** (tràn nhiều lượt, I/O nhân lên nhiều lần — báo động ở *mọi* môi trường).
2. Ở chế độ AUTO, Oracle tự quyết size từng work area từ quỹ `PGA_AGGREGATE_TARGET` và **bỏ qua** các tham số `*_AREA_SIZE` thủ công. MANUAL trả quyền về tay tham số phiên — course dùng nó như công cụ thí nghiệm để ép tràn tái lập được (không phải khuyến nghị production).
3. `V$SQL_WORKAREA` (lịch sử theo cursor, còn sau khi chạy xong) — lọc/ORDER theo `LAST_MEMORY_USED DESC` và nhìn `MAX_TEMPSEG_SIZE` để biết có tràn temp không. `_ACTIVE` chỉ dùng khi câu **đang** chạy. Xa hơn nữa (cursor đã rời shared pool): AWR (`DBA_HIST_SQLSTAT` cột direct writes).
4. Target là mục tiêu **mềm**: mỗi process có phần PGA cố định không nén được, và khi work area thiếu đến mức sắp multipass, Oracle thà vượt target còn hơn — mỗi lần vượt cộng 1 vào `over allocation count`. Chặn cứng chỉ xảy ra ở `PGA_AGGREGATE_LIMIT`: chạm là ORA-4036 / kill call.
5. (1) Loại mọi dòng `ESTD_OVERALLOC_COUNT > 0` — các target đó Oracle tự dự báo sẽ phải vượt, tức không đủ sống; (2) trong phần còn lại lấy điểm hit% hết tăng mạnh. Chọn hit% trước sai vì một target có hit% đẹp vẫn có thể nằm trong vùng over-alloc — nghĩa là con số hit% đó đạt được *bằng cách vượt target*, không phải bằng target đó.

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Nguyên nhân/Xử lý |
|---|---|
| 02 mục [2] không có dòng nào | Poll trượt nhịp (câu vừa xong = biến khỏi `_ACTIVE`). Chạy lại query bằng tay vài lần khi job còn sống; window sort trên ORDERS chạy khá lâu nên thường bắt được |
| 03 SQLID 3 vẫn disk = 0 | 50k row của bản SOE này sort < 160KB? Tăng khoảng lên `MIN+200000` hoặc giảm `SORT_AREA_SIZE` còn 65536. Đo lại |
| 03 autotrace báo thiếu quyền | Thiếu PLUSTRACE — chạy bằng system (DBA) như header; đừng chạy bằng soe |
| 04 advisory toàn dòng overalloc = 0 | Tải chưa đủ ép trong cửa sổ đo (advisory tích lũy từ startup). Kéo dài tải 240s, poll advisory khi tải sống |
| ORA-4036 xuất hiện | Chạm `PGA_AGGREGATE_LIMIT` (mặc định = max(2G, 2×target) — target 50M kéo limit xuống theo). Vô hại trong lab; nếu phiền: `ALTER SYSTEM SET PGA_AGGREGATE_LIMIT=2G` rồi thí nghiệm tiếp |
| Quên trả target gốc | 04 in giá trị gốc ở mục [1] ngay đầu output — cuộn lại lấy số, `ALTER SYSTEM SET PGA_AGGREGATE_TARGET=<số>;` |

---

## 7. Sau buổi học

- [ ] Điền cột "Số thật" trong `README.md`, bỏ banner "chưa kiểm chứng" nếu chạy trọn vẹn
- [ ] Debrief 5 câu không nhìn tài liệu
- [ ] `@99_cleanup.sql` — target về gốc, policy AUTO
- [ ] Cập nhật `progress.md`
- [ ] `vagrant halt`


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_23/HUONG_DAN_HOC_SECTION_23.md`
