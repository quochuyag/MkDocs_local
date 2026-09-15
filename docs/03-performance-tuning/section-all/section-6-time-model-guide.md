---
title: Section 6 — Time Model Views
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_6_time_model_guide.md
---

# Section 6 — Time Model Views

## Mục tiêu

Hiểu cách dùng **Time Model Views** để đo lường workload tổng thể của Oracle Database:

- Đo tổng thời gian DB xử lý (DB Time, DB CPU)
- Đo tỷ lệ wait time so với CPU time
- Xác định loại thao tác nào tiêu tốn nhiều thời gian nhất
- Tìm các session đang chờ lâu nhất

---

## Khái niệm nền tảng

### DB Time là gì?

**DB Time** = tổng thời gian CPU + tổng thời gian wait của tất cả foreground sessions.

```
DB Time = DB CPU + Total Wait Time
```

- **DB CPU**: thời gian CPU thực sự được dùng để xử lý
- **Wait Time**: thời gian session phải chờ (I/O, lock, latch, network...)
- Các giá trị này là **cumulative** (tích lũy từ lúc instance khởi động)

### Tại sao quan trọng?

| Chỉ số | Ý nghĩa |
|--------|---------|
| DB Time tăng nhanh | Database đang bận — có nhiều workload |
| Wait % cao | Phần lớn thời gian DB bị chặn bởi wait events — có bottleneck |
| DB CPU cao | Database đang xử lý nhiều — cần kiểm tra CPU bottleneck |
| Wait/User cao | Mỗi user đang phải chờ lâu — UX kém |

---

## Các Views chính

### V$SYS_TIME_MODEL — Thống kê cấp hệ thống

```sql
SELECT STAT_NAME, VALUE/1000000 SECONDS
FROM V$SYS_TIME_MODEL
ORDER BY VALUE DESC;
```

Các `STAT_NAME` quan trọng:

| STAT_NAME | Mô tả |
|-----------|-------|
| `DB time` | Tổng thời gian xử lý toàn database |
| `DB CPU` | Thời gian CPU thuần túy |
| `sql execute elapsed time` | Thời gian thực thi SQL |
| `parse time elapsed` | Thời gian parse câu lệnh |
| `hard parse elapsed time` | Thời gian hard parse (tốn kém) |
| `PL/SQL execution elapsed time` | Thời gian chạy PL/SQL |
| `connection management call elapsed time` | Thời gian quản lý kết nối |

> **Lưu ý quan hệ phân cấp:** `DB time` là tổng. `DB CPU` + các wait events = `DB time`. Tổng phần trăm của các con không phải 100% vì chúng có thể overlap.

### V$SESS_TIME_MODEL — Thống kê cấp session

```sql
SELECT s.SID, s.USERNAME, s.STATUS,
       t.STAT_NAME,
       t.VALUE/1000000 SECONDS
FROM V$SESSION s
JOIN V$SESS_TIME_MODEL t ON s.SID = t.SID
WHERE s.USERNAME IS NOT NULL
  AND t.STAT_NAME = 'DB time'
ORDER BY t.VALUE DESC;
```

---

## Scripts thực hành (Practice 2)

### Chuẩn bị môi trường

```bash
# Giải nén scripts vào staging folder
cd /media/sf_extdisk
unzip scripts.zip
rm scripts.zip

# Thêm biến SD vào profile
echo "export SD=/media/sf_extdisk/scripts" >> ~/.bash_profile
source ~/.bash_profile
```

### Script 1 — Top 7 Time Model Statistics

```sql
-- time_model.sql
-- Hiển thị top 7 loại thao tác tiêu tốn thời gian nhất
SELECT STAT_NAME, VALUE/1000000 SECONDS
FROM V$SYS_TIME_MODEL
ORDER BY VALUE DESC
FETCH FIRST 7 ROWS ONLY;
```

**Dùng khi:** Muốn biết database đang dành thời gian vào đâu (SQL execute? Parse? PL/SQL?).

### Script 2 — Time Model theo % của DB Time

```sql
-- time_model_pct.sql
-- Hiển thị tỷ lệ % từng loại thao tác so với tổng DB Time
SELECT STAT_NAME,
       VALUE/1000000 SECONDS,
       ROUND(VALUE / (SELECT VALUE FROM V$SYS_TIME_MODEL
                      WHERE STAT_NAME = 'DB time') * 100, 2) PCT_OF_DBTIME
FROM V$SYS_TIME_MODEL
WHERE STAT_NAME != 'DB time'
ORDER BY VALUE DESC;
```

### Script 3 — Time Model dạng cây phân cấp

```sql
-- time_model_tree.sql
-- Hiển thị quan hệ cha-con giữa các loại thao tác
```

Dùng để hiểu cấu trúc: `DB time` → `sql execute` → `hard parse` → ...

### Script 4 — Đo workload tăng dần (Snapshot approach)

Tạo bảng lưu lịch sử snapshot:

```sql
-- create_tm_history.sql
DROP TABLE TM_HISTORY;
DROP SEQUENCE S;
CREATE SEQUENCE S;

CREATE TABLE TM_HISTORY AS
SELECT S.NEXTVAL AS SNAP_ID,
       DBTIME.VALUE/1000000   DBTIME,
       DBCPU.VALUE/1000000    DBCPU,
       (DBTIME.VALUE - DBCPU.VALUE)/1000000  WAIT_TIME,
       (SELECT COUNT(*) FROM V$SESSION WHERE USERNAME IS NOT NULL) USERS_CNT
FROM V$SYS_TIME_MODEL DBTIME, V$SYS_TIME_MODEL DBCPU
WHERE DBTIME.STAT_NAME = 'DB time'
  AND DBCPU.STAT_NAME  = 'DB CPU';
```

Lưu snapshot tại một thời điểm:

```sql
-- take_tm_snapshot.sql
INSERT INTO TM_HISTORY
SELECT S.NEXTVAL AS SNAP_ID,
       DBTIME.VALUE/1000000,
       DBCPU.VALUE/1000000,
       (DBTIME.VALUE - DBCPU.VALUE)/1000000,
       (SELECT COUNT(*) FROM V$SESSION WHERE USERNAME IS NOT NULL)
FROM V$SYS_TIME_MODEL DBTIME, V$SYS_TIME_MODEL DBCPU
WHERE DBTIME.STAT_NAME = 'DB time'
  AND DBCPU.STAT_NAME  = 'DB CPU';
COMMIT;
```

Phân tích lịch sử theo thời gian:

```sql
-- display_tm_history.sql
SET LINESIZE 180
SELECT
    TO_CHAR(DBTIME,     '999,999,999')       DBTIME,
    TO_CHAR(DBCPU,      '999,999,999')       DBCPU,
    ROUND(DBCPU - LAG(DBCPU, 1, 0) OVER (ORDER BY DBCPU))           DBCPU_DIFF,
    TO_CHAR(WAIT_TIME,  '999,999,999,999')   WAIT_TIME,
    ROUND(WAIT_TIME - LAG(WAIT_TIME, 1, 0) OVER (ORDER BY WAIT_TIME)) WAIT_TIME_DIFF,
    TO_CHAR((DBTIME - DBCPU) / DBTIME * 100, '99.99') || '%'        WAIT_PCT,
    USERS_CNT,
    ROUND((DBTIME - DBCPU) / USERS_CNT)                              WAIT_USER_SHARE
FROM TM_HISTORY
ORDER BY SNAP_ID;
```

**Giải thích các cột:**

| Cột | Ý nghĩa |
|-----|---------|
| `DBTIME` | Tổng DB Time tích lũy (giây) |
| `DBCPU` | Tổng DB CPU tích lũy (giây) |
| `DBCPU_DIFF` | DB CPU tăng thêm so với snapshot trước |
| `WAIT_TIME` | Tổng wait time tích lũy (giây) |
| `WAIT_TIME_DIFF` | Wait time tăng thêm so với snapshot trước |
| `WAIT_PCT` | `(DB Time - DB CPU) / DB Time * 100` — % thời gian bị chờ |
| `USERS_CNT` | Số session user tại thời điểm snapshot |
| `WAIT_USER_SHARE` | Wait time trung bình mỗi user |

### Script 5 — Top Sessions theo Wait Time

```sql
-- time_model_topsessions.sql
SELECT s.SID, s.USERNAME, s.STATUS,
       t.VALUE/1000000 DBTIME_SEC
FROM V$SESSION s
JOIN V$SESS_TIME_MODEL t ON s.SID = t.SID
WHERE t.STAT_NAME = 'DB time'
  AND s.USERNAME IS NOT NULL
ORDER BY t.VALUE DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## Quy trình đo workload thực tế (Practice flow)

```
1. Khởi động database (srv1)
2. Tạo bảng TM_HISTORY       → @ $SD/create_tm_history.sql
3. Lưu snapshot baseline      → @ $SD/take_tm_snapshot.sql
4. Bật Swingbench 10 users, chạy 1 phút
5. Lưu snapshot               → @ $SD/take_tm_snapshot.sql
6. Tắt Swingbench
7. Bật lại 30 users, chạy 1 phút
8. Lưu snapshot               → @ $SD/take_tm_snapshot.sql
9. Bật lại 60 users, chạy 1 phút
10. Lưu snapshot              → @ $SD/take_tm_snapshot.sql
11. Phân tích kết quả         → @ $SD/display_tm_history.sql
```

**Phân tích kết quả:**
- Khi users tăng, `WAIT_PCT` tăng → bottleneck xuất hiện
- `WAIT_USER_SHARE` tăng → mỗi user phải chờ lâu hơn
- So sánh `DBCPU_DIFF` vs `WAIT_TIME_DIFF`: nếu wait tăng nhanh hơn CPU → có resource contention

---

## Cleanup

```sql
DROP TABLE TM_HISTORY;
DROP SEQUENCE S;
EXIT
```

```bash
rm $SD/create_tm_history.sql
rm $SD/display_tm_history.sql
rm $SD/take_tm_snapshot.sql
```

---

## Tóm tắt — Khi nào dùng Time Model Views?

| Tình huống | View/Script |
|-----------|------------|
| Database chậm, không rõ nguyên nhân | `V$SYS_TIME_MODEL` — xem phần nào chiếm nhiều time |
| Muốn biết % wait so với CPU | `WAIT_PCT` từ script display_tm_history |
| Muốn tìm session gây chậm | `V$SESS_TIME_MODEL` — top sessions theo DB time |
| Theo dõi workload theo thời gian | Snapshot approach với TM_HISTORY table |

---

## Câu hỏi Ôn tập

1. `DB Time` khác `DB CPU` ở điểm gì? Công thức tính `Wait Time` là gì?
2. Tại sao tổng phần trăm các `STAT_NAME` con không bằng 100%?
3. `V$SYS_TIME_MODEL` và `V$SESS_TIME_MODEL` khác nhau ở điểm gì?
4. Khi `WAIT_PCT` = 80% nghĩa là gì? Database đang gặp vấn đề gì?
5. Tại sao phải dùng `LAG()` khi phân tích TM_HISTORY thay vì chỉ đọc giá trị tích lũy?

<details>
<summary>Gợi ý trả lời</summary>

1. `DB Time = DB CPU + Wait Time`. DB CPU là thời gian CPU thực sự tính toán. Wait Time là thời gian session bị chặn (I/O, lock...). Công thức: `Wait Time = DB Time - DB CPU`.

2. Vì các thống kê con có thể overlap (ví dụ: `hard parse` là một phần của `parse time elapsed` vốn đã là phần của `sql execute`). Không phải là phép cộng đơn giản.

3. `V$SYS_TIME_MODEL` = toàn instance, tích lũy từ khi startup. `V$SESS_TIME_MODEL` = từng session riêng biệt, tích lũy từ khi session connect.

4. `WAIT_PCT = 80%` nghĩa là 80% thời gian database đang chờ (không làm việc thực sự). Đây là dấu hiệu rõ ràng của bottleneck — có thể là I/O, lock contention, latch, v.v. Cần đào sâu vào Wait Events để tìm nguyên nhân cụ thể.

5. Vì `V$SYS_TIME_MODEL` lưu giá trị tích lũy từ instance startup. Để đo khoảng thời gian giữa hai snapshot, cần lấy hiệu (`LAG()`). Ví dụ: snapshot lúc 10:00 có DBCPU=1000s, lúc 10:01 có 1060s → khoảng 10:00–10:01 DB dùng 60s CPU.

</details>


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_6_time_model_guide.md`
