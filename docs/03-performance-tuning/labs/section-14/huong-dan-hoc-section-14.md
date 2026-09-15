---
title: 📚 Hướng dẫn học Section 14 — Service / Module / Action / Client ID (thực hành trong
  Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_14/HUONG_DAN_HOC_SECTION_14.md
---

# 📚 Hướng dẫn học Section 14 — Service / Module / Action / Client ID (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~90 phút (lecture 15' + lab 55' + debrief 20').
> Nguồn: Practice 13 + 14 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Một database gánh NHIỀU ứng dụng. Câu "database chậm" phải được thu hẹp dần theo **tầng đo lường**:

| Tầng | Trả lời câu hỏi | View chính | Bật thế nào |
|---|---|---|---|
| **Service** | App NÀO ăn tài nguyên? | `V$SERVICE_STATS`, `V$SERVICE_EVENT`, `V$SERVICEMETRIC` | Tự động sẵn |
| **Module/Action** | Chức năng nào của app? | `V$SERV_MOD_ACT_STATS` | `DBMS_MONITOR.SERV_MOD_ACT_STAT_ENABLE` |
| **Client ID** | Luồng nghiệp vụ nào (xuyên qua connection pool)? | `V$CLIENT_STATS` | `DBMS_MONITOR.CLIENT_ID_STAT_ENABLE` |

App tự "dán nhãn" bằng `DBMS_APPLICATION_INFO.SET_MODULE/SET_ACTION` và `DBMS_SESSION.SET_IDENTIFIER` — chính cột ACTION bạn đã dùng ở lab 13.

**2 cái bẫy đơn vị:** `V$SERVICE_STATS` (DB time/CPU) tính **micro-giây**; các view `V$*EVENT` tính **centi-giây**. View không ghi đơn vị — phải thuộc.

**So với ASH:** ASH ước lượng được cả 3 chiều mà không cần bật gì (GROUP BY module/action/client_id), nhưng là **sample**. DBMS_MONITOR aggregation đo **thật, đủ 100%, đủ bộ stat** — đổi lại phải BẬT TRƯỚC khi sự việc xảy ra.

**Chuỗi tư duy của lab:** khám phá service → đọc stats service-level → đo module cụ thể → **vụ án thật**: ETL chậm, client-id stats buộc tội, ASH chỉ đích danh, fix, đo lại.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_14   # ⚠️ BẮT BUỘC: script gọi ../_toolkit/ + etl_load.sh
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS.

---

## 2. Lab chính (~55 phút)

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Tạo ORDERS2: `@01_setup.sql` (user `soe`, ~30 giây)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

```sql
@01_setup.sql
exit
```

### Bước 2 — Khám phá service: `@02_workload.sql` (user `system`, ~1 phút)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

🤔 **Dự đoán:** database này có bao nhiêu service? Các phiên lab connect qua service nào?

```sql
@02_workload.sql
```

**Kỳ vọng:** danh sách service (`SYS$BACKGROUND`, `SYS$USERS`, service của PDB...) kèm `NAME_HASH` — khóa nối sang mọi view thống kê; các phiên SOE đếm theo service; **[5] in ra service của phiên này — các script sau tự lấy lại**. Muốn xem phía listener: gõ `lsnrctl services` trong shell VM.

### Bước 3 — Stats service-level: `@03_diagnose.sql` (~3 phút, tải còn chạy)

🤔 **Dự đoán:** tổng wait tính từ `V$SERVICE_EVENT` và tính bằng `DB time - DB CPU` từ `V$SERVICE_STATS` — hai số có bằng nhau không?

```sql
@03_diagnose.sql
```

**Kỳ vọng:** [1] DB time/CPU của service (micro-giây!); [2] top wait event (centi-giây!); [3] hai cách tính wait **lệch nhẹ** (course: cách event thường NHỈNH hơn — hai bộ đếm độc lập); [4]-[5] metric per-service cửa sổ 5s/60s (`DB time per sec` = Average Active Sessions của riêng service).

### Bước 4 — Đo module: `@04_usecase_modact.sql` (~1.5 phút)

🤔 **Dự đoán:** sau khi bật aggregation nhưng CHƯA chạy report — `V$SERV_MOD_ACT_STATS` có gì?

```sql
@04_usecase_modact.sql
```

**Kỳ vọng theo mốc:** [1] chưa có aggregation nào → [2] bật cho module `Top Customers Report`, `DBA_ENABLED_AGGREGATIONS` hiện `SERVICE_MODULE_ACTION` → [3] stats = 0 row → [4] chạy `cust_report.sql` (app gắn module rồi chạy query nặng) → [5] **stats của RIÊNG module** hiện ra: DB time, CPU, `sql execute elapsed time`... → [6] tắt lại.

### Bước 5 — VỤ ÁN ETL: `@05_usecase_clientid_etl.sql` (~5 phút)

Bối cảnh: developer than "script nạp ORDERS2 chạy CHẬM khi chạy nhiều phiên song song". Script gắn `CLIENT_ID = 'ETL Load Orders'`.

🤔 **Dự đoán trước khi chạy:** 8 phiên cùng `INSERT /*+ APPEND */` vào MỘT bảng — chúng chạy song song thật không? Wait class nào sẽ nổi lên?

```sql
@05_usecase_clientid_etl.sql
```

**Kỳ vọng theo 4 hồi của vụ án:**

1. **Buộc tội** [3]: `V$CLIENT_STATS` — `application wait time` chiếm **% lớn** của `DB time`. Wait class Application = ứng dụng TỰ chặn nhau.
2. **Chỉ đích danh** [4]: ASH lọc theo `CLIENT_ID` → event `enq: TM - contention` áp đảo; P2 của enq: TM = object_id → **ORDERS2**.
3. **Root cause**: APPEND = direct-path insert → giữ **table lock exclusive tới khi commit** → 8 phiên XẾP HÀNG. APPEND chỉ nhanh khi chạy MỘT phiên — hint đúng ngữ cảnh này là hint sai ngữ cảnh khác.
4. **Fix + đo lại** [5]-[6]: reset stats (disable→enable), chạy bản KHÔNG APPEND → `application wait time` ≈ 0, `sql execute elapsed time` chiếm phần lớn DB time — trạng thái khỏe mạnh.

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. Khi nào dùng service-level stats thay vì instance-level? Khi nào phải xuống module/action?
2. CLIENT_IDENTIFIER giải quyết bài toán gì mà USERNAME không giải quyết được?
3. V$SERVICE_EVENT có bản DBA_HIST không? Muốn lịch sử wait theo service thì nhìn đâu?
4. Vì sao `SET_IDENTIFIER` trong load script phải nằm ở PL/SQL block riêng?
5. Giải thích cơ chế enq: TM khi 8 phiên cùng INSERT /*+ APPEND */: lock gì, mode nào, giữ tới khi nào?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Service-level khi database gánh **nhiều ứng dụng** — câu đầu tiên là "app nào?" trước khi tốn công xuống SQL. Xuống module/action khi đã khoanh được app nhưng cần biết **chức năng nào** trong app (report? batch? màn hình nào?) — nhất là khi app không thể sửa để log phía client.
2. Với **connection pool**, mọi session đều login bằng MỘT username kỹ thuật (app user) — USERNAME vô dụng để phân biệt luồng nghiệp vụ/end-user. CLIENT_IDENTIFIER do app set theo từng request → xuyên thủng pool, gom stats theo đúng luồng nghiệp vụ (ở đây: 'ETL Load Orders').
3. **Không** — course nhấn mạnh V$SERVICE_EVENT không có bản _HIST. Lịch sử wait theo service chỉ có ở mức **wait class**: `DBA_HIST_SERVICE_WAIT_CLASS` (xem được trong AWR report, mục Service Wait Class Stats), hoặc tự suy từ ASH.
4. Ghi chú nguyên văn của course: để client-id aggregation "ăn" ngay từ các lệnh sau đó, SET_IDENTIFIER phải hoàn thành như một call riêng — nếu gộp chung block với INSERT thì cả block được thực thi như MỘT call và phần lớn công việc chưa được gắn nhãn.
5. APPEND → direct-path insert: phiên ghi thẳng block mới **trên HWM**, đòi **TM lock mode X (exclusive)** trên bảng (thay vì mode 3/RX của DML thường) và giữ **tới khi COMMIT**. Phiên thứ 2 trở đi xin TM lock bị chặn → `enq: TM - contention`. 8 phiên = 1 chạy + 7 xếp hàng, tổng elapsed ≈ tuần tự. Bỏ APPEND → RX lock tương thích nhau → song song thật.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| Stats module ở [5] của 04 toàn 0 | Query chạy quá nhanh giữa 2 lần đọc → chạy lại `@cust_report.sql` rồi query V$SERV_MOD_ACT_STATS lại (ghi chú của course) |
| Service name có domain (ORADB.localdomain) | Bình thường — script tự lấy bằng `SYS_CONTEXT('USERENV','SERVICE_NAME')`, không hardcode |
| Job ETL FAILED | Password OS oracle mất sau restore → `chpasswd`; ORDERS2 chưa có → chạy 01 trước |
| [4] của 05: enq: TM ít sample | ETL xong quá nhanh → tăng phiên (8→12) hoặc tăng lượng row trong etl_load_append.sql |
| Client stats không reset về 0 ở [5] | DISABLE rồi ENABLE lại mới reset — đúng thứ tự trong script |
| `SP2-0310 ../_toolkit/...` | Không đứng ở `/labs/section_14` → `cd /labs/section_14` |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 15 — SQL Tracing (DBMS_MONITOR còn một vũ khí nữa: bật TRACE theo đúng các chiều service/module/action vừa học)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_14/HUONG_DAN_HOC_SECTION_14.md`
