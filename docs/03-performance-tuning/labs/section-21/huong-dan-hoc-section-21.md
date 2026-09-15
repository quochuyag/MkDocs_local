---
title: 📚 Hướng dẫn học Section 21 — Shared Pool, Session Cursors, Result Cache (thực hành
  trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_21/HUONG_DAN_HOC_SECTION_21.md
---

# 📚 Hướng dẫn học Section 21 — Shared Pool, Session Cursors, Result Cache (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~100 phút (lecture 20' + lab 60' + debrief 20') — lab dài, có thể tách 06 sang buổi sau.
> Nguồn: Practice 20 + 21 + 22 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**Shared pool = "trí nhớ chung"** của instance: library cache (cursor, package đã parse), dictionary cache, và Result Cache. Lab này leo trọn **thang chi phí parse**:

```
ĐẮT NHẤT   hard parse        (xây plan mới — lab 20 đã diệt bằng bind)
           soft parse        (tra shared pool + latch — vẫn tốn)
           session cursor cache hit  (con trỏ ngay trong session — bài 04)
RẺ NHẤT    app giữ cursor mở (không parse call nào)
NGOẠI HẠNG Result Cache      (không parse-đọc gì cả: trả thẳng KẾT QUẢ — bài 05)
```

| Công cụ | Trả lời |
|---|---|
| `hard parse elapsed time` (time model) | Shared pool đang "ốm" vì parse không? |
| `V$SHARED_POOL_ADVICE` | Size hiện tại thiếu hay thừa? (chỉ tin khi đo lúc BÌNH THƯỜNG) |
| `V$OPEN_CURSOR.CURSOR_TYPE` + V$MYSTAT | Cursor được cache ở session chưa? |
| `V$RESULT_CACHE_OBJECTS/STATISTICS` + `DBMS_RESULT_CACHE.MEMORY_REPORT` | RC sống hay chết yếu? |

**Vị trí trong lộ trình:** lab 20 nhìn bệnh literal từ phía latch/mutex; lab này nhìn CÙNG bệnh từ phía shared pool, rồi đi tiếp 2 tầng tối ưu mà lab 20 chưa chạm.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_21   # ⚠️ BẮT BUỘC (02 gọi ../_toolkit/ và ../section_20/hard_parse.sh)
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

---

## 2. Lab chính (user `system`, ~60 phút)

### Bước 1 — Toàn cảnh + snapshot B: `@01_setup.sql` (~1 phút)

🤔 **Dự đoán:** VM dùng AMM hay ASMM? `session_cached_cursors` mặc định bao nhiêu?

```sql
@01_setup.sql
```

**Kỳ vọng:** ASMM (`sga_target` > 0, `memory_target` = 0); `session_cached_cursors = 50`; V$SGAINFO cho thấy shared pool hiện tại; library cache memory theo namespace; snap B.

### Bước 2 — Bão literal, nhìn từ phía shared pool: `@02_workload.sql` (~4 phút)

🤔 **Dự đoán:** `hard parse elapsed time` sẽ chiếm bao nhiêu % DB time lúc bão?

```sql
@02_workload.sql
```

**Kỳ vọng:** [2] time model — `hard parse elapsed time` **tăng dần từng lần chạy lại query** (chạy 2-3 lần để thấy); [3] top wait hệ thống có nhóm Concurrency; [4] ASH đếm CPU của SOE theo TỪNG PHÚT (đừng tính phút chưa tròn — ghi chú nguyên bản của course); [5] snap E chốt cửa sổ "lúc bệnh".

### Bước 3 — Shared Pool Advisory: `@03_diagnose.sql` (~2 phút)

🤔 **Dự đoán:** advisory đo TRONG lúc bão sẽ khuyên tăng hay giảm shared pool — và có nên nghe không?

```sql
@03_diagnose.sql
```

**Kỳ vọng:** [1] bảng advisory quanh factor 1.00 — đọc cột `EST_TIME_SAVED`: tăng size mà time_saved tăng rõ = pool "thiếu"; [2] **cú lật**: hàng nghìn cursor literal đang bơm phồng con số đó — advisory thấy triệu chứng, không thấy bệnh. Nguyên tắc vàng: **chỉ tin advisory đo lúc hệ thống bình thường**; [4] AWR report cũng có mục Shared Pool Advisory (đối chiếu bằng kỹ thuật lab 9).

### Bước 4 — Session Cursor Cache: `@04_usecase_session_cursor_cache.sql` (~3 phút)

Demo ngay trong CHÍNH phiên này (không cần restart DB như course!).

🤔 **Dự đoán:** cache TẮT, chạy cùng 1 query 3 lần — `parse count (total)` tăng bao nhiêu? Có hits không?

```sql
@04_usecase_session_cursor_cache.sql
```

**Kỳ vọng theo kịch bản 2 hồi:**

| | Cache TẮT (=0), chạy 3 lần | Cache BẬT (=50), chạy 3 lần |
|---|---|---|
| parse count (hard) | +1 (lần đầu) | +0 |
| parse count (total) | **+3** (mỗi lần vẫn 1 soft parse) | +3 nhưng là "found in cache" |
| session cursor cache hits/count | 0 | **> 0** |
| CURSOR_TYPE (V$OPEN_CURSOR) | OPEN | **DICTIONARY LOOKUP CURSOR CACHED** (tên "đúng" phải là SESSION CURSOR CACHED — ghi chú của course) |

[5] Sizing: đếm phiên SOE có `CURR_CACHED` chạm MAX — nhiều phiên kịch trần = tăng tham số. **Đừng** dùng công thức hits/parse% — course chứng minh nó ra số vô nghĩa (hits có thể > total parses).

### Bước 5 — Result Cache: `@05_usecase_result_cache.sql` (~4 phút)

🤔 **Dự đoán:** lần chạy thứ 2 của query có RESULT_CACHE hint — `consistent gets` bằng bao nhiêu? Và nếu kết quả TO HƠN trần mỗi-kết-quả thì sao?

```sql
@05_usecase_result_cache.sql
```

**Kỳ vọng theo 3 hồi:** (1) lần 1 gets lớn → lần 2 **gets ~0, physical reads 0** — trả thẳng kết quả; (2) soi RC: block 1KB (nằm trong shared pool!), 2 loại object Result + **Dependency** (soe.ORDERS — DML là invalidate); (3) kết quả ~2MB > trần → object **INVALID**, RC lặng lẽ vô dụng → nới `RESULT_CACHE_MAX_RESULT=50` → chạy 2 lần → dùng được → trả về 5.

### Bước 6 (mở rộng) — library cache pin: `@06_usecase_library_cache_pin.sql` (SYS, ~4 phút)

```sql
exit
```

```bash
sqlplus sys/oracle_4U@//localhost:1521/ORADB as sysdba
```

🤔 **Dự đoán:** compile một package đang được 2 phiên gọi liên tục — lệnh compile sẽ ra sao?

```sql
@06_usecase_library_cache_pin.sql
```

**Kỳ vọng:** compiler treo với `library cache pin` ([3] chạy lại vài lần thấy tăng dần); [4] lấy P1RAW của phiên treo; [5] `X$KGLOB` giải mã P1RAW → **SOE / PCKORDERS** — từ địa chỉ bộ nhớ chỉ ra đích danh object. Bài học vận hành: đừng deploy code vào giờ app đang gọi nó; hệ 24x7 cân nhắc Edition-Based Redefinition.

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
exit
```

**Kỳ vọng:** jobs drop, package drop, `result_cache_max_result` về 5, RC flush, shared pool flush (chỉ làm ở lab!). Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. Soft parse khác hard parse chỗ nào? Session cursor cache hit khác soft parse thường chỗ nào?
2. Vì sao KHÔNG dùng được "hits/total parses %" để sizing session cursor cache? Quy tắc thay thế?
3. Shared Pool Advisory đọc cột nào? Đường cong "gãy khúc" nghĩa là gì?
4. RC object bị INVALID trong những tình huống nào (kể 2)? Kiểm tra bằng view nào?
5. Vì sao ALTER PACKAGE COMPILE có thể làm cả hệ thống khựng? Deploy an toàn trên 24x7 thế nào?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. **Hard parse**: câu chưa có trong library cache → syntax/semantic check + **xây execution plan** (tốn CPU + giữ mutex ghi). **Soft parse**: tìm thấy cursor trong shared pool → bỏ qua bước xây plan nhưng vẫn phải hash + tra cứu + latch/mutex đọc. **Session cursor cache hit**: parse call vẫn xảy ra nhưng session đã giữ **con trỏ** tới cursor → khỏi tra shared pool, gần như không đụng latch — rẻ hơn soft parse thường một bậc.
2. Vì thống kê `session cursor cache hits` đếm theo cách khác (có thể cộng cả hits của cursor đã bị đẩy khỏi cache, và không cùng "mẫu số" với parse count) → course đo được **hits > total parses** — tỷ lệ % vô nghĩa. Quy tắc thay thế: chạy `display_scc_counts` lúc tải bình thường, đếm **bao nhiêu phiên có CURR_CACHED chạm MAX** — nhiều phiên kịch trần → tăng dần (50 → 100), ít → giữ nguyên.
3. Cột `ESTD_LC_TIME_SAVED` (và `_FACTOR`): đi từ size hiện tại (factor 1.00) lên các size lớn hơn, chỗ nào time_saved **ngừng tăng đáng kể** ("gãy khúc") chính là size tối ưu — thêm nữa là RAM chết. Chiều ngược lại: giảm size mà time_saved tụt mạnh = đừng giảm.
4. (a) **DML lên bảng phụ thuộc** — mọi result phụ thuộc bảng đó invalidate (cột INVALIDATIONS đếm); (b) **kết quả lớn hơn trần** `RESULT_CACHE_MAX_RESULT`% × `RESULT_CACHE_MAX_SIZE` — object sinh ra đã INVALID và query âm thầm không dùng RC. Kiểm tra: `V$RESULT_CACHE_OBJECTS.STATUS` (+ INVALIDATIONS), tổng quan bằng `DBMS_RESULT_CACHE.MEMORY_REPORT`.
5. Compile cần **pin EXCLUSIVE** trên object; caller đang giữ pin SHARE → compiler xếp hàng (`library cache pin`). Nguy hiểm ở chỗ: caller MỚI đến sau compiler phải xếp SAU nó → toàn bộ luồng gọi package khựng lại vì một lệnh compile. An toàn trên 24x7: deploy vào cửa sổ ít tải, đặt timeout (mặc định compile chờ tới ORA-04021), dùng **Edition-Based Redefinition** để phiên bản mới sống song song, hoặc drain traffic khỏi service trước khi compile.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| 02 báo không tìm thấy hard_parse.sh | Lab section_20 chưa có trên máy → kiểm tra `/labs/section_20/hard_parse.sh` tồn tại |
| `hard parse elapsed time` không tăng | Bão chưa chạy (job FAILED → `chpasswd`) hoặc query time model chạy 1 lần duy nhất — chạy lại nhiều lần |
| [4]: CURSOR_TYPE vẫn OPEN sau 3 lần | Cache hoạt động sau lần ~3 (có khi 2) → chạy thêm 1-2 lần query rồi query lại V$OPEN_CURSOR |
| AUTOTRACE báo thiếu quyền | Thiếu PLUSTRACE → chạy bằng system (có DBA) như hướng dẫn; đừng dùng soe |
| ORA-65040 khi ALTER SYSTEM result_cache_max_result | Tham số bị hạn chế trong PDB (hiếm) → làm ở CDB root rồi quay lại |
| RC lần 2 vẫn gets lớn | Có DML nền lên ORDERS (workload toolkit!) invalidate kết quả → `@../_toolkit/workload_stop.sql` rồi thử lại |
| X$KGLOB không truy vấn được | Đang chạy 06 bằng system → phải SYS (`as sysdba`) |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 22 — Buffer Cache & Smart Flash Cache (vùng nhớ lớn nhất của SGA)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_21/HUONG_DAN_HOC_SECTION_21.md`
