---
title: Hướng dẫn học Section 22 — Buffer Cache Tuning + KEEP Pool
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_22/HUONG_DAN_HOC_SECTION_22.md
---

# Hướng dẫn học Section 22 — Buffer Cache Tuning + KEEP Pool

> Lab: `labs/section_22/` · Nguồn: Practice 23 + 24 (Ahmed Baraka)
> ⚠️ **Chưa kiểm chứng trên VM** — mọi "output kỳ vọng" bên dưới là dự tính, KHÔNG phải số đã đo. Buổi chạy đầu: đối chiếu, sửa lệch, điền số thật vào README.

---

## 0. Kiến thức nền (5 phút — đọc trước khi mở máy)

Buffer cache là "bàn làm việc" của DB: block phải nằm trên RAM mới đọc/sửa được. Khi bàn chật, sách ít dùng bị xếp xuống kho (LRU) — và nếu sách đang cần cũng bị xếp xuống thì mỗi lần dùng lại phải chạy xuống kho lấy = `physical read`.

| Khái niệm | Là gì | Nhìn ở đâu |
|---|---|---|
| Logical read | Đọc block (dù từ RAM hay phải nạp từ disk trước) — đo **khối lượng việc của SQL** | `session logical reads` |
| Physical read | Block không có trong cache, phải đọc disk — đo **tình trạng cache** | `physical reads`, `db file scattered/sequential read` |
| LRU + cờ CACHE | FTS bảng lớn bình thường đi direct path/đuôi lạnh LRU; gắn `CACHE` thì block được ưu ái như bảng nhỏ → chiếm cache | `DBA_TABLES.CACHE` |
| Buffer Pool Advisory | Mô phỏng "nếu cache to/nhỏ hơn X lần thì physical reads còn bao nhiêu" | `V$DB_CACHE_ADVICE` |
| KEEP pool | Ngăn riêng trong buffer cache, LRU riêng — lũ bên ngoài không đẩy được block trong này | `V$BUFFER_POOL_STATISTICS`, `DB_KEEP_CACHE_SIZE` |
| Smart Flash Cache | Tầng 2 của cache: block ấm rơi xuống flash thay vì mất hẳn | `V$FLASHFILESTAT`, V$BH status `flashcur` |

**Khác course:** course bóp `DB_CACHE_SIZE` xuống 10MB rồi restart DB 4 lần. Ta tạo cùng triệu chứng bằng "lũ FTS" (2 bảng lớn gắn CACHE quét liên tục) — không restart, không đổi tham số memory.

---

## 1. Khởi động môi trường

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
cd D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course
sqlplus -S -L "system/oracle_4U@//localhost:15210/ORADB" "@labs\_toolkit\00_env_check.sql"
```

8/8 PASS thì tiếp. Lab này cần bộ sinh tải external job hoạt động (đã đặt password OS oracle — xem [labs/README.md](../readme.md)).

---

## 2. Lab chính từng bước

### Bước 1 — Setup (SYS): bảng nóng + vũ khí lũ

🤔 **Dự đoán trước:** DEFAULT buffer cache của VM đang bao nhiêu MB? Bộ 3 bảng lab (~4-5MB) so với nó chiếm bao nhiêu %? Bình thường (không lũ) đọc lại lần 2 có physical read không?

```powershell
cd labs\section_22
sqlplus "sys/oracle_4U@//localhost:15210/ORADB as sysdba" "@01_setup.sql"
```

**Kỳ vọng:** DEFAULT cache cỡ vài trăm MB–1GB+; 3 bảng tạo xong (`LAB_EMP` ~3-4MB là chính); `ORDERS`/`ORDER_ITEMS` chuyển `CACHE='Y'`; advisory in bảng size_factor 0.1→2.0.

Ghi lại: **DEFAULT cache MB = ?** và **tổng blocks của LAB_% = ?** (dùng cho bước 3).

### Bước 2 — Workload BASELINE (system)

🤔 **Dự đoán trước:** 2 evictor quét ORDERS+ORDER_ITEMS (tổng vài trăm MB, gắn CACHE) trong 150s — có đủ đẩy 4MB bảng lab ra khỏi cache to hàng trăm MB không? Reader sẽ có physical_reads = 0 hay >> 0?

```text
@02_workload.sql        -- ~4 phút, script tự sleep
```

**Kỳ vọng:**

- Mục [2]: thấy 2 session `LAB22_EVICT` + 3 session `CUSTOMER ACCESS/ID 1`.
- Mục [3] (query display_stats của course): `physical reads` của nhóm reader tăng theo thời gian thực.
- Mục [5]: bảng `lab_bc_results` tag BASELINE — 3 reader, `avg_phys_reads` hàng nghìn+, `avg_elapsed_s` vài chục giây.

> Nếu `avg_phys_reads` ≈ 0: cache VM quá to so với lũ → xem mục 6 (Sự cố).

**Ghi số BASELINE**: avg_phys_reads = ? · avg_logical_reads = ? · avg_elapsed = ?

### Bước 3 — Chẩn đoán (system)

🤔 **Dự đoán trước:** trong V$BH, object nào chiếm nhiều block nhất? LAB_EMP còn lại bao nhiêu block trong cache so với tổng của nó? Advisory sẽ khuyên tăng hay nói "đủ rồi"?

```text
@03_diagnose.sql
```

**Kỳ vọng:** ORDERS/ORDER_ITEMS đứng đầu V$BH; LAB_% còn rất ít block; hit% tụt so với bình thường; top User I/O có `db file scattered read`. Advisory: đường `estd_physical_read_factor` giảm khi tăng size — **nhưng nhớ 2 cảnh báo**: chỉ nhìn xa 200%, và số đo lúc lũ nhân tạo là số bị nhiễm.

### Bước 4 — Fix bằng KEEP pool (system)

🤔 **Dự đoán trước:** KEEP 64MB lấy RAM từ đâu? Sau khi mồi + chạy lại đúng workload: physical_reads của reader còn bao nhiêu? logical_reads có đổi không? elapsed?

```text
@04_fix.sql             -- ~4 phút
```

**Kỳ vọng (mục [5] — bảng so sánh bắt buộc):**

| run_tag | avg_phys_reads | avg_logical_reads | avg_elapsed_s |
|---|---|---|---|
| BASELINE | hàng nghìn+ | X | dài |
| KEEP | ≈ 0 | ≈ X (bằng nhau!) | ngắn hơn rõ |

Logical bằng nhau chứng minh cùng khối lượng việc — chỉ physical đổi. Đó là cách chứng minh "fix ăn tiền" đúng chuẩn.

---

## 3. Phần mở rộng (tùy chọn — Smart Flash Cache, cần 2 lần RESTART)

Làm **trong VM** cuối buổi, khi các phần trên xong hết:

```bash
vagrant ssh
sudo -u oracle -i
dd if=/dev/zero of=/home/oracle/vdisk1 bs=1M count=512
dd if=/dev/zero of=/home/oracle/vdisk2 bs=1M count=512
cd /labs/section_22
sqlplus / as sysdba
@05_usecase_flash_cache.sql     # script dừng chờ bạn tự gõ SHUTDOWN/STARTUP
```

🤔 **Dự đoán:** block ORDERS sẽ xuất hiện ở status nào trong V$BH sau khi FLASH_CACHE KEEP + FTS vài lượt? Trên VM (file "flash" nằm cùng HDD) tốc độ có cải thiện không?

**Kỳ vọng:** có block `flashcur`; latency flash ≈ latency disk (VM không có SSD thật — practice chỉ demo cơ chế, course cũng ghi chú vậy). Script tự RESET tham số ở cuối; nhớ restart lần 2 + `rm vdisk*`.

---

## 4. Dọn dẹp bắt buộc

```text
@99_cleanup.sql
```

Kiểm tra: KEEP = 0, `ORDERS`/`ORDER_ITEMS` cache='N', không còn bảng LAB_% (trừ LAB_STOP_FLAG của toolkit).

---

## 5. Debrief — trả lời KHÔNG nhìn tài liệu

1. Logical read và physical read: cái nào đo khối lượng việc của SQL, cái nào đo sức khỏe cache? Vì sao fix của lab làm physical đổi mà logical không đổi?
2. Vì sao phải gắn cờ `CACHE` cho ORDERS thì lũ mới hoạt động?
3. Buffer Pool Advisory có 2 giới hạn nào khiến không thể "đọc 1 lần, set 1 lần là xong"?
4. KEEP pool giúp được trường hợp nào và vô ích/có hại trường hợp nào?
5. Sau khi `ALTER TABLE ... STORAGE (BUFFER_POOL KEEP)`, block của bảng có lập tức nằm trong KEEP pool không?

<details>
<summary>Đáp án (mở sau khi tự trả lời)</summary>

1. Logical = khối lượng việc (SQL đụng bao nhiêu block — muốn giảm phải sửa SQL/plan); physical = sức khỏe cache (bao nhiêu lần phải xuống disk). KEEP pool chỉ thay đổi *nơi block được giữ*, không thay đổi *số block SQL cần đụng* → logical y nguyên, physical về ~0.
2. FTS bảng lớn mặc định đi **direct path read** (thẳng vào PGA, bỏ qua buffer cache) hoặc xếp block ở đuôi lạnh LRU — cả 2 đều không chiếm cache. Cờ CACHE làm block FTS được đối xử như bảng nhỏ: vào giữa/đầu LRU → tích tụ dần → chiếm chỗ và đẩy bảng khác ra.
3. (a) Chỉ mô phỏng tối đa **200% size hiện tại** — cache đang quá nhỏ thì lợi ích thật nằm ngoài tầm nhìn, phải tăng dần và đọc lại sau mỗi lần; (b) số liệu phản ánh **workload lúc đo** — đo lúc bất thường (lũ, batch, đêm backup) thì khuyến nghị nhiễm. Cùng bài học với Shared Pool Advisory (lab 21).
4. Giúp: bảng/index **nhỏ + truy cập thường xuyên + đang bị object lớn chèn ép** — cách ly vào LRU riêng, không tốn thêm RAM tổng. Vô ích/có hại: object lớn (chiếm KEEP mà vẫn không vừa → tự chèn ép chính nó), hoặc khi cache tổng đang thừa chỗ (không ai chèn ai — thêm ngăn chỉ làm giảm linh hoạt của ASMM).
5. Không. Thuộc tính chỉ áp dụng cho lần **đọc từ disk tiếp theo**; block cũ vẫn ở DEFAULT đến khi bị đẩy ra. Vì thế 04_fix có bước "mồi" — FTS 1 lượt để nạp block vào KEEP.

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Nguyên nhân/Xử lý |
|---|---|
| BASELINE `avg_phys_reads` ≈ 0 | Cache VM quá to so với lũ. Tăng liều: sửa job trong `02_workload.sql` → evictor 3-4, evict_secs 240, reader passes 15; hoặc gắn CACHE thêm `soe.inventories`. Đo lại từ 02 |
| `ORA-02097/ORA-00384` khi set `DB_KEEP_CACHE_SIZE` | Không đủ granule trống để carve động. Thử 32M; vẫn lỗi → `SCOPE=SPFILE` + restart (đúng cách course làm) |
| Reader chạy quá lâu (> 3 phút chưa có kết quả) | 2 vCPU quá tải với 5 session. Giảm reader về 2, passes về 8 — nhớ giảm Ở CẢ 02 và 04 để so sánh công bằng |
| Mục [3] của 02 không có dòng nào | Poll trúng lúc reader chưa spawn (sleep 20s trong bc_demo) hoặc đã xong. Vô hại — số chốt sổ nằm ở [5] |
| `flashcur` = 0 ở bước mở rộng | Buffer cache còn thừa chỗ nên block chưa cần rơi xuống flash — FTS thêm bảng khác gắn CACHE để ép, hoặc chấp nhận (cơ chế chỉ kích hoạt khi RAM đầy) |
| Job không chạy (`LAB22_BC` FAILED) | Kiểm tra credential: `SELECT credential_name FROM dba_credentials;` phải có `LAB_OS_CRED` của SYSTEM; password OS oracle đã đặt chưa (labs/README) |

---

## 7. Sau buổi học

- [ ] Điền cột "Số thật" trong `README.md` (BASELINE vs KEEP), bỏ banner "chưa kiểm chứng" nếu chạy trọn vẹn
- [ ] Trả lời 5 câu debrief không nhìn tài liệu — chỗ nào bí, đọc lại phần tương ứng
- [ ] Đã chạy `@99_cleanup.sql` (KEEP=0, NOCACHE 2 bảng lớn)
- [ ] Nếu làm phần flash cache: đã RESET tham số + restart + xóa vdisk
- [ ] Cập nhật `progress.md`
- [ ] `vagrant halt`


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_22/HUONG_DAN_HOC_SECTION_22.md`
