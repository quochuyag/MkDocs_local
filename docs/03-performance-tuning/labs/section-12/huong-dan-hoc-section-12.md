---
title: 📚 Hướng dẫn học Section 12 — ADDM (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_12/HUONG_DAN_HOC_SECTION_12.md
---

# 📚 Hướng dẫn học Section 12 — ADDM (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~70 phút (lecture 15' + lab 40' + debrief 15').
> Nguồn: Practice 10 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**ADDM = chuyên gia tuning tự động** — sau mỗi cặp AWR snapshot, nó phân tích DB time và trả về chuỗi 3 tầng:

```
1 TASK  →  N FINDINGS (vấn đề, xếp theo % IMPACT lên DB time)
             →  N RECOMMENDATIONS (khuyến nghị, kèm BENEFIT ước tính)
                  →  N ACTIONS (việc cụ thể: SQL nào, tham số nào)
```

| Điều phải nhớ | Vì sao |
|---|---|
| ADDM **không tự đo gì** — chỉ đọc AWR | Chất lượng phân tích = chất lượng snapshot; cửa sổ 60p pha loãng sự cố 5p |
| Khuyến nghị là **triệu chứng**, không phải root cause | "Add more CPUs" nghĩa thật: "CPU không kịp phục vụ trong cửa sổ này" → đi điều tra, đừng mua máy |
| Thuộc **Diagnostics Pack** | Giống AWR/ASH — Standard Edition không được dùng (Section 11 là đường thay thế) |
| Multitenant | Auto-ADDM chạy ở **CDB root** sau mỗi snapshot của MMON; PDB muốn có phải **tự chạy** trên snapshot PDB-local (19c) |

**Chuỗi tư duy của lab:** chụp B → gây bão CPU có chủ đích (biết trước đáp án!) → tự chạy ADDM → đối chiếu findings với sự thật mình đã biết → học cách "dịch" khuyến nghị.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_12   # ⚠️ BẮT BUỘC: script gọi ../_toolkit/
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS.

---

## 2. Lab chính (user `system`, ~40 phút)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Điều kiện + snapshot B: `@01_setup.sql` (~30 giây)

🤔 **Dự đoán:** `DBA_ADDM_TASKS` trong PDB có bao nhiêu task? (nhớ: auto-ADDM là việc của ai?)

```sql
@01_setup.sql
```

**Kỳ vọng:** `statistics_level=TYPICAL`, `control_management_pack_access=DIAGNOSTIC+TUNING` → task trong PDB = **0** (auto-ADDM chỉ chạy ở root) → in `snap B`. **GHI LẠI snap B.**

### Bước 2 — Bão CPU + snapshot E: `@02_workload.sql` (~3.5 phút)

🤔 **Dự đoán:** tải 8 user trên 2 vCPU — finding lớn nhất của ADDM sẽ là gì? Impact bao nhiêu %?

```sql
@02_workload.sql
```

Trong lúc chờ 190s, mở cửa sổ SSH thứ hai chạy `@../_toolkit/top_waits.sql` để tự thấy hệ thống đang chịu trận gì — bạn đang "biết trước đáp án" mà lát nữa ADDM phải tìm ra.

### Bước 3 — Chạy ADDM + đọc 3 tầng: `@03_diagnose.sql` (~2 phút + 10 phút đọc)

🤔 **Dự đoán:** ADDM sẽ khuyến nghị gì cho CPU bão hòa — và bạn có nên làm theo không?

```sql
@03_diagnose.sql
```

**Kỳ vọng theo từng phần:**

| Phần | Kỳ vọng |
|---|---|
| [2] ANALYZE_INST | Task `LAB12_ADDM` chạy xong trong vài giây |
| [4] Report text | `/tmp/lab12_addm_report.txt` — đọc bằng `less` TRƯỚC khi xem query |
| [5] Findings | Finding CPU (vd "Host CPU was a bottleneck") impact cao nhất; có thể kèm "Top SQL Statements", "Commits and Rollbacks" |
| [6] Recommendations | Kiểu "Consider adding more CPUs to the host..." — course cảnh báo: **ĐỪNG làm theo đen** |
| [7] Actions | SQL_ID cụ thể cần tune (nếu có finding Top SQL) |

💡 **Cách "dịch" khuyến nghị của senior:** "add more CPUs" = "trong cửa sổ đo, host CPU không luôn sẵn sàng phục vụ DB" → hành động đúng là **giám sát + điều tra CPU** (ai ăn CPU? SQL nào? — Section 25), không phải mua máy. ADDM nhìn số liệu, không nhìn ngữ cảnh kinh doanh.

### Bước 4 — Comparison report: `@04_usecase_compare.sql` (~2.5 phút)

🤔 **Dự đoán:** so cửa sổ YÊN TĨNH với cửa sổ QUÁ TẢI — chỉ số `SQL Commonality` sẽ cao hay thấp? Report còn "hợp lệ" không?

```sql
@04_usecase_compare.sql
```

**Kỳ vọng:** script tự dựng cửa sổ yên tĩnh (snap Q1 → nghỉ 90s → snap Q2) rồi xuất `/tmp/lab12_addm_compare.html`. Copy về host mở browser:

```powershell
# PowerShell trên host
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant ssh -c "cat /tmp/lab12_addm_compare.html" > lab12_compare.html
```

**Đọc 3 thứ:** (1) `SQL Commonality` — sẽ **thấp** vì một bên idle; course dạy: **>80% mới là so sánh hợp lệ** — đây là bài học cố ý; (2) 2 biểu đồ load — event nào đóng góp nhiều nhất mỗi bên; (3) `Average Active Sessions` — bên nhỏ hơn là bên "khỏe" hơn.

---

## 3. Dọn dẹp (BẮT BUỘC — 30 giây)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. ADDM lấy dữ liệu từ đâu — nó có tự đo gì không?
2. Task name của auto-ADDM có format gì? Vì sao trong PDB `DBA_ADDM_TASKS` trống?
3. IMPACT của finding tính theo đơn vị gì? Vì sao tổng impact các finding có thể vượt 100%?
4. Compare report cần điều kiện gì để so sánh HỢP LỆ?
5. ADDM thuộc pack license nào? Hệ quả với Standard Edition?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. ADDM **chỉ đọc AWR** (cặp snapshot) — không đo gì thêm. Hệ quả: sự cố ngắn bị cửa sổ dài pha loãng (muốn sắc phải chụp snapshot quanh sự cố rồi chạy ADDM tay trên cặp đó — chính là điều lab làm); và ADDM "mù" với những gì AWR không ghi.
2. `ADDM:<DBID>_<instance#>_<snap_id>` — mỗi lần MMON chụp snapshot CDB, auto-ADDM chạy ở **CDB root** và đặt tên theo format đó. PDB không có auto-ADDM nên `DBA_ADDM_TASKS` trong PDB trống cho tới khi bạn tự `ANALYZE_INST`.
3. IMPACT tính theo **thời gian DB time** (microseconds) của cửa sổ mà finding "chịu trách nhiệm", thường hiển thị kèm %. Các finding có thể **giao nhau** (cùng một giây DB time vừa là "CPU" vừa là "Top SQL") nên tổng % vượt 100% là bình thường — giống bài stat cha-con của time model (Section 6).
4. **SQL Commonality ≥ ~80%** — hai cửa sổ phải chạy cùng loại workload thì so sánh mới có nghĩa (so OLTP với batch là so táo với cam). Lab cố ý so idle vs quá tải để bạn thấy chỉ số này tụt và hiểu vì sao phải nhìn nó ĐẦU TIÊN.
5. **Diagnostics Pack** (như AWR/ASH). Standard Edition không mua được pack này → không ADDM; EE chưa mua pack cũng vậy. Đường thay thế không license: Statspack (Section 11) + tự phân tích.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `ANALYZE_INST` báo lỗi trong PDB (ORA-13769/ORA-20200...) | Snapshot PDB-local thiếu hoặc ADDM-trong-PDB chưa bật → kiểm tra [3] của 01 có ≥2 snap PDB-local; fallback: làm ở CDB root (`sqlplus / as sysdba`) trên cặp snap CDB, nhớ lọc `dbid` CDB |
| Findings "No significant issues" | Tải chưa đủ nặng/cửa sổ lệch → chạy lại 01→02→03 liền mạch, đừng để hở thời gian dài giữa B và tải |
| Report HTML mở lên trống | Dòng SQL*Plus lẫn đầu/cuối file → xóa các dòng ngoài `<html>...</html>` (course cũng phải làm bước này) |
| `SP2-0310 ../_toolkit/...` | Không đứng ở `/labs/section_12` → `cd /labs/section_12` |
| Tải không chạy (job FAILED) | Password OS oracle mất sau restore → `chpasswd` (xem [labs/README.md](../readme.md)) |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 13 — ASH (khi cần độ phân giải GIÂY thay vì cửa sổ snapshot)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_12/HUONG_DAN_HOC_SECTION_12.md`
