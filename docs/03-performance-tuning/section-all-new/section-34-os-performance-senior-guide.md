---
title: 'Section 34 — OS Performance (Linux Utilities & OSWatcher): Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_34_os_performance_senior_guide.md
---

# Section 34 — OS Performance (Linux Utilities & OSWatcher): Senior DBA Guide

**Nguồn:** Practice 35 (Linux Utilities) + Practice 36 (OSWatcher Black Box) + Oracle/Linux internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Các view của DB (Time Model, ASH, AWR) có **một ranh giới cứng: chúng chỉ thấy Oracle**. Khi nút thắt nằm **ngoài** Oracle (tiến trình khác, tài nguyên OS bão hòa), hoặc khi bạn cần biết **tài nguyên OS nào** đang cạn (CPU / memory-swap / disk / network), phải tụt xuống tầng OS. OS và DB là hai lăng kính nhìn cùng một cỗ máy — kỹ năng senior là **tương quan hai lăng kính** qua cầu nối **SPID**.

Khung tư duy chuẩn để đọc mọi công cụ OS là **USE method** (Utilization / Saturation / Errors) cho từng tài nguyên:

```
Tài nguyên  │ Utilization        │ Saturation              │ Công cụ
────────────┼────────────────────┼─────────────────────────┼──────────────
CPU         │ %us + %sy          │ run queue r > #CPU      │ mpstat, vmstat, top
Memory      │ used/free          │ swap si/so > 0          │ vmstat, free, top
Disk        │ %util (per device) │ await, avgqu-sz         │ iostat -x, iotop
Network     │ throughput (RX/TX) │ RX-ERR/DRP, retransmits │ netstat, ip -s, sar
```

Câu hỏi đầu tiên khi mở bất kỳ công cụ nào: *tài nguyên nào? utilization hay saturation? Oracle hay external?* Nếu là Oracle → map SPID về session.

---

## 2. Internals & Mechanics

### Load Average không phải "CPU load"

Load average (1/5/15 phút) là trung bình động số tiến trình ở **run queue** CỘNG tiến trình ở **uninterruptible sleep (D state — chờ I/O)**. Vì vậy load = 8 trên máy 4-CPU có thể là 8 tiến trình đói CPU, HOẶC 2 đói CPU + 6 chờ I/O. **Load cao ≠ CPU bottleneck.** Phải tách:
- `vmstat` cột **`r`** (run queue) > #CPU kéo dài = **CPU saturation** thật.
- `vmstat` cột **`b`** (blocked, chờ I/O) cao = nút thắt **I/O**, không phải CPU.
- `top`/`mpstat` **`%wa`** (iowait) cao = CPU **rảnh** đang chờ I/O → storage là nút thắt.

Đây chính là ranh giới Section 25 nêu (Load Average với %WIO). `%wa` là **chỉ báo I/O duy nhất trong top**.

### Swap = báo động đỏ cho Oracle

`vmstat` `si`/`so` (swap in/out) **liên tục > 0** = memory bottleneck. Trên server Oracle, swap nghĩa là **SGA/PGA bị đẩy ra đĩa** → mọi truy cập bộ nhớ Oracle biến thành I/O đĩa → thảm họa hiệu năng. HugePages ghim SGA để **không bao giờ** bị paged. Thấy swapping trên DB server → xử lý ngay, không chờ.

### iostat -x: đọc %util và await đúng

- **`%util`**: % thời gian device có ít nhất một request đang xử lý. Gần 100% = device bão hòa (với đĩa cơ đơn; với SSD/array nhiều queue, %util 100% chưa chắc bão hòa vì xử lý song song — `[⚠️ đọc theo loại storage]`).
- **`await`**: latency trung bình mỗi I/O (ms), gồm cả thời gian xếp hàng. > 10ms (cơ) / > 2ms (SSD) = đáng ngờ.
- **`avgqu-sz`**: độ dài hàng đợi trung bình — saturation.
- **`r/s`, `w/s`, `rkB/s`, `wkB/s`**: IOPS và throughput.
- `iostat` không option = số **tích lũy từ boot** (vô dụng); phải `iostat -xd 2` (delta mỗi 2s), `-y` bỏ report đầu.

### Steal time %st — vô hình bên trong DB

Trên VM/cloud, `%st` (steal) = CPU mà hypervisor lấy đi cho VM khác (noisy neighbor). Bên trong guest, Oracle **không thấy** %st — Time Model chỉ đo CPU Oracle dùng được. Chỉ công cụ OS (`top`, `mpstat`, `vmstat`) mới lộ %st. Trên môi trường ảo hóa, `%st` cao giải thích "DB chậm mà mọi metric Oracle bình thường".

### Cầu nối SPID — OS process ↔ DB session

Đây là kỹ thuật Oracle-connecting cốt lõi của cả section:

```
top/ps → PID nóng (oracleORADB_xxx / ora_xxxx)
                  │
                  ▼  SPID = PID
   V$PROCESS.SPID ──JOIN── V$SESSION (S.PADDR = P.ADDR)
                  │
                  ▼
   USERNAME / MODULE / SQL_ID / SQL_TEXT / MACHINE
```

- OS → DB: từ PID nóng trong `top`, `SELECT ... V$PROCESS P JOIN V$SESSION S ON S.PADDR=P.ADDR WHERE P.SPID='<pid>'` → biết session/SQL nào.
- DB → OS: từ session nóng (ASH), lấy `V$PROCESS.SPID` để `strace`/`pstack`/`gdb` tiến trình đó ở OS.
- Foreground: `oracle<SID>` (hoặc `oracle_<pid>_<sid>`); background: `ora_pmon_<SID>`, `ora_dbw0_<SID>`, `ora_lgwr_<SID>`... — biết tên process để nhận diện nhanh trong `ps -ef | grep <SID>`.

### OSWatcher Black Box — vì sao cần

AWR **không lưu** metric OS (CPU external, iostat, swap, netstat). Không có collector lịch sử, bạn **không thể** điều tra một sự cố OS đã qua (external CPU spike, I/O storm lúc 03:00). OSWatcher là **collector shell nhẹ** chạy liên tục, sample `vmstat/mpstat/iostat/netstat/top/ps` (và private-net/cell trên Exadata) mỗi N giây, giữ M giờ trong file phẳng dưới `archive/`. Overhead cực nhỏ → chạy 24/7 trên production. `OSWbba` (analyzer, cần Java 8) vẽ graph + dashboard HTML từ archive. Chuẩn của Oracle Support (MOS 301137.1); Exadata có sẵn ExaWatcher. **Điểm mấu chốt: nó phải đang chạy TRƯỚC sự cố** — post-mortem cần lịch sử.

---

## 3. Production Realities

### Không tin load average một mình

Một alert "load average 40!" gửi lúc 3 giờ sáng có thể vô hại (40 tiến trình chờ I/O trên NFS treo) hoặc thảm họa (40 đói CPU trên 8-core). Luôn correlate: `vmstat` r vs b, `%wa`, `si/so`. Kết luận từ load đơn thuần là sai lầm kinh điển.

### %wa gây hiểu nhầm trên máy nhiều core

`%wa` là chỉ số **toàn hệ thống**: tỷ lệ thời gian CPU rảnh mà có I/O đang chờ. Trên máy 32-core, một tiến trình I/O-bound làm `%wa` chỉ ~3% (31 core khác bận/rảnh việc khác) nhưng `iostat %util` của device đó = 100%. Đừng dựa `%wa` để loại trừ I/O bottleneck trên máy nhiều core — dùng `iostat -x` per-device + `iotop` per-process.

### Swap zero-tolerance + HugePages

Trên DB server chuẩn production: `vm.swappiness` thấp, HugePages đủ cho SGA, `USE_LARGE_PAGES=ONLY`. Mục tiêu là SGA **không bao giờ** vào swap. `si/so > 0` kéo dài trên DB server là sự cố P1, không phải "để ý sau".

### iotop/iostat cần đúng device của Oracle

`apply_io_stress.sh` của Practice ghi vào `/tmp` — nhưng datafile Oracle thường ở `/u01`, `/u02`, ASM disk. Khi điều tra I/O của DB, phải xác định **đúng device/mount** chứa datafile (`V$DATAFILE` → path → `df` → device) rồi mới đọc `iostat -x <device>`. Nhìn nhầm device = kết luận sai.

### Batch mode để thu thập, không chỉ xem

`top -b`, `iotop -b -o`, `vmstat -t 2` (có timestamp) cho phép **ghi ra file** để phân tích sau hoặc feed vào script. Trong sự cố, chạy `vmstat -t 2 >> /tmp/vmstat.log &` + `top -bc -d 5 >> ...` để có bằng chứng lịch sử ngay cả khi chưa có OSWatcher.

### OSWatcher phải chạy sẵn + Java 8 cho analyzer

Cài đặt OSWatcher lúc sự cố đang xảy ra là quá muộn cho khoảng thời gian trước đó. Chạy nó như service từ đầu. Analyzer `oswbba.jar` cần **Java 8** — Java shipped của OS (thường 7 hoặc mới hơn) có thể sai version → prepend `$ORACLE_HOME/jdk/jre/bin` vào PATH (bẫy đã ghi trong Practice 36).

### Công cụ nào KHÔNG trả lời được gì

`iostat`/`mpstat` cho biết CPU bận nhưng **không** biết tiến trình nào → cần `top`/`ps`. `ifconfig`/`netstat` kiểm tra sức khỏe kết nối nhưng **khó** đo tải mạng theo thời gian → cần OSWatcher graph hoặc `sar -n DEV`. Biết giới hạn từng công cụ để không dừng điều tra sai chỗ.

---

## 4. Decision Framework

**Triệu chứng → công cụ → metric:**

```
"Hệ thống chậm" → vmstat 2  (tổng quan nhanh: r, b, si/so, %us, %wa)
        │
        ├── r > #CPU, %us cao        → CPU bound  → top/ps tìm process → SPID map nếu Oracle
        ├── b cao, %wa cao           → I/O bound  → iostat -x tìm device → iotop tìm process
        ├── si/so > 0 liên tục       → Memory bound (swap) → free, top; kiểm HugePages/SGA
        ├── %st cao (VM)             → hypervisor steal → vấn đề tầng ảo hóa, ngoài DB
        └── mọi thứ thấp mà vẫn chậm → network? → netstat -s (retransmit), sar -n DEV; hoặc lock/app
```

**Khi nào dùng OSWatcher (vs công cụ real-time):**
- Điều tra sự cố **đã qua** → OSWatcher archive (real-time tools vô dụng cho quá khứ)
- Cần **graph xu hướng** nhiều giờ/ngày → OSWbba analyzer/dashboard
- Baseline OS trước/sau thay đổi hạ tầng → OSWatcher liên tục
- Real-time "đang cháy ngay bây giờ" → vmstat/top/iostat/iotop trực tiếp

**Khi nào map SPID:**
- top/ps chỉ ra `oracle<SID>`/`ora_*` là process nóng → map về session/SQL để hành động (kill, tune)
- Ngược lại: session Oracle nóng cần trace OS-level (`strace`/`pstack`) → lấy SPID từ V$PROCESS

**Anti-patterns:**
- Kết luận CPU bottleneck từ load average mà không xem r/b/%wa
- Bỏ qua I/O bottleneck vì `%wa` thấp trên máy nhiều core (phải xem iostat per-device)
- Coi swapping trên DB server là chuyện nhỏ
- Cài OSWatcher lúc sự cố đang diễn ra rồi kỳ vọng thấy được quá khứ
- Đọc `iostat` không option (số tích lũy từ boot) rồi tưởng là tải hiện tại

---

## 5. Key SQL / Commands

```bash
# 5.1 Tong quan nhanh (delta moi 2s, co timestamp)
vmstat -t 2            # r,b (queue) | si,so (swap) | bi,bo (block IO) | us,sy,id,wa (CPU)
free -m                # memory/swap tuyet doi

# 5.2 CPU
mpstat 2               # %usr %sys %iowait %idle %steal — per interval
mpstat -P ALL 2        # tung core (lech tai giua core?)
iostat -c 2            # CPU avg

# 5.3 Process nong (CPU)
top                    # tuong tac: Shift+P (CPU), Shift+M (mem), z, c, k(kill), q
top -bc -d 5 | head -30            # batch mode -> file/pipe
ps -e -o pcpu,pid,user,args | sort -nrk1 | head   # top CPU processes
ps -ef | grep pmon                 # instance dang chay?

# 5.4 Disk I/O
iostat -xyd 2 <dev>    # %util, await, avgqu-sz, r/s w/s rkB/s wkB/s (delta)
iotop -o -b -k -d 2    # process nao dang I/O (root)

# 5.5 Network
ip -s link             # RX/TX packets, errors, dropped (ifconfig da obsolete)
netstat -s -t          # retransmit/bad segment (healthy: <0.1%)
sar -n DEV 2           # throughput per interface theo thoi gian

# 5.6 OSWatcher
cd ~/oswbb
nohup ./startOSWbb.sh 10 48 &      # sample moi 10s, giu 48h (nen: 30 336 cho prod)
tail -f nohup.out                  # heartbeat
./stopOSWbb.sh
export PATH=$ORACLE_HOME/jdk/jre/bin:$PATH   # Java 8 cho analyzer
java -jar oswbba.jar -i ~/oswbb/archive      # analyzer: so -> graph, d -> dashboard
```

```sql
-- 5.7 CAU NOI SPID: map OS process (PID nong) -> DB session/SQL
SELECT s.sid, s.serial#, s.username, s.osuser, s.machine,
       s.program, s.module, s.status, p.spid,
       s.sql_id, q.sql_text
FROM   v$session s
JOIN   v$process p ON s.paddr = p.addr
LEFT   JOIN v$sql q ON s.sql_id = q.sql_id
WHERE  p.spid = '&os_pid';          -- PID lay tu top/ps

-- 5.8 Nguoc lai: session Oracle nong -> SPID de trace o OS
SELECT s.sid, s.sql_id, p.spid, p.program
FROM   v$session s JOIN v$process p ON s.paddr = p.addr
WHERE  s.sid = &db_sid;             -- roi: strace -p <spid> / pstack <spid>

-- 5.9 Datafile nam tren device nao (de doc dung iostat)
SELECT name FROM v$datafile;        -- -> df <path> -> device -> iostat -x <device>
```

---

## 6. Senior Checklist

1. **Bắt đầu bằng `vmstat -t 2`:** đọc r/b (queue), si/so (swap), %us/%wa (CPU vs I/O) trước — phân loại nút thắt trong 5 giây
2. **Không kết luận CPU từ load average:** tách bằng r (CPU) vs b/%wa (I/O); load gồm cả D-state chờ I/O
3. **Swapping = P1 trên DB server:** si/so > 0 liên tục nghĩa SGA/PGA bị paged → thảm họa; kiểm HugePages ngay
4. **I/O: đọc per-device đúng mount của datafile:** `V$DATAFILE`→path→df→device→`iostat -x`; đừng tin `%wa` đơn lẻ trên máy nhiều core
5. **VM: kiểm %st (steal):** DB metric bình thường mà vẫn chậm → hypervisor lấy CPU; chỉ OS tool thấy được
6. **Map SPID hai chiều:** OS PID nóng → `V$PROCESS.SPID`→session/SQL; session nóng → SPID→`strace`/`pstack`; đây là kỹ năng nối OS-DB
7. **OSWatcher phải chạy TRƯỚC sự cố:** AWR không lưu metric OS; không có collector lịch sử thì không điều tra được quá khứ; cài sẵn 24/7, analyzer cần Java 8

---

# LAB EXERCISES

## Exercise 1 — Phân loại nút thắt: CPU vs I/O vs Memory bằng vmstat/mpstat/iostat

**Scenario:** Người dùng báo "server chậm". Bạn có 60 giây để phân loại nút thắt trước khi đào sâu. Cần chứng minh vì sao load average một mình không đủ, và mỗi loại stress hiện ra ở metric nào.

**Tasks:**
1. Chạy `vmstat -t 2` ở cửa sổ monitoring.
2. Áp CPU stress (busy loop) → quan sát `r`, `%us` tăng; `%wa`, `b` không đổi.
3. Dừng, áp I/O stress (`dd` ghi liên tục) → quan sát `b`, `%wa`, `bo` tăng; `%us` không tăng nhiều.
4. Đối chiếu load average giữa hai trường hợp — chỉ ra vì sao cùng "load cao" nhưng nút thắt khác nhau.
5. Với I/O stress, dùng `iostat -xyd 2 <dev>` xác định device + đọc `%util`, `await`.

**Expected Findings:**
- CPU stress: `r` > #CPU, `%us` cao, `%wa` ~0.
- I/O stress: `b` cao, `%wa` cao, `%us` thấp; `iostat %util` device gần 100%, `await` tăng.
- Load average tăng ở CẢ HAI nhưng vmstat phân biệt được nguồn (r vs b/%wa).

**Debrief Questions:**
- Vì sao load average không đủ để kết luận CPU bottleneck?
- Trên máy 32-core, một tiến trình I/O-bound làm `%wa` chỉ 3% — bạn kiểm tra ở đâu để không bỏ sót?
- `si/so > 0` xuất hiện — vì sao đây là báo động đỏ riêng trên DB server?

---

## Exercise 2 — Cầu nối SPID: từ process OS nóng về SQL trong DB

**Scenario:** `top` cho thấy một tiến trình `oracle<SID>` chiếm ~100% CPU. Bạn cần biết đó là session nào, user nào, chạy SQL gì — để quyết định kill hay tune, thay vì kill mù theo PID.

**Tasks:**
1. Từ một session `soe`, chạy vòng lặp PL/SQL đốt CPU (`WHILE TRUE ... SQRT(...)`).
2. Ở cửa sổ monitoring, `ps -e -o pcpu,pid,user,args | sort -nrk1 | head` → lấy PID nóng.
3. Với PID đó, chạy `map_os_to_db.sql` (SYS) → xác định SID/SERIAL#/USERNAME/MODULE/SQL_TEXT.
4. Ngược lại: từ SID vừa tìm, lấy lại `V$PROCESS.SPID`, xác nhận khớp PID ban đầu.
5. (Tùy chọn) Với SPID, chạy `pstack <spid>` vài lần xem call stack Oracle.

**Expected Findings:**
- PID nóng là process `oracle<SID>` (foreground của session soe).
- `map_os_to_db.sql` trả về đúng session soe + SQL_TEXT là block PL/SQL đốt CPU.
- SPID từ V$PROCESS khớp PID từ OS (mapping hai chiều nhất quán).

**Debrief Questions:**
- Cột nào trong `V$PROCESS` là cầu nối tới PID của OS?
- Vì sao kill theo PID ở OS (`kill -9`) nguy hiểm hơn `ALTER SYSTEM KILL SESSION`?
- Nếu process nóng là `ora_lgwr_<SID>` (background) thay vì foreground, cách điều tra khác gì?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Thứ Ba 09:20. Batch nightly kết thúc muộn, và sáng nay OLTP phản hồi chậm rời rạc. Sự cố "đỉnh điểm lúc 03:10–03:40" đã qua — không còn tái hiện lúc bạn vào lúc 09:20. AWR cho khoảng 03:00–04:00 cho thấy DB Time bình thường, top event là `SQL*Net message from client` (idle) và một ít `db file sequential read`. Junior DBA kết luận "DB ổn, chắc do mạng". Bạn không tin.

**Evidence Provided:**

AWR 03:00–04:00 (Host CPU section):
```
%User   %System   %WIO   %Idle   Load Average Begin/End
  22        8       51      19        6.2 / 41.8
```

OSWatcher archive (đang chạy sẵn), trích `oswvmstat` quanh 03:10–03:40:
```
time      r   b     swpd   free    si   so    bi      bo     us sy id wa st
03:08:02  2   1        0  812340    0    0    120    1400    20  7 68  5  0
03:12:04  3  38        0  120440    0    0    240  512880     8  9  4 79  0   ← b=38, wa=79
03:20:06  4  44        0   98220   40  180    180  548200     7 10  3 80  0   ← si/so>0
03:36:08  3  41        0  110300    0    0    210  530400     8  9  4 79  0
03:52:10  2   0        0  790120    0    0    140    1600    19  6 70  5  0
```

OSWatcher `oswiostat` (device chứa datafile, quanh 03:12):
```
Device   r/s   w/s   rkB/s    wkB/s   await  avgqu-sz  %util
sdb      12    980    480    510000   210.0     58.0    100.00
```

`V$DATAFILE`: datafile chính nằm trên mount `/u02` → device `sdb`.
AWR không có metric OS nào cho khoảng này (chỉ Host CPU tổng hợp begin/end).

**Your Mission:**
1. Junior nói "DB ổn, do mạng" dựa trên AWR top event `SQL*Net message from client`. Bác bỏ hoặc xác nhận bằng bằng chứng OSWatcher.
2. Từ `oswvmstat`, phân loại chính xác nút thắt lúc 03:10–03:40. Đọc r, b, %wa, si/so.
3. `si/so > 0` lúc 03:20 nói lên điều gì thêm? Tại sao nó làm mọi thứ tệ hơn?
4. `iostat` cho `sdb`: `%util=100`, `await=210ms`, `w/s=980`, `wkB/s≈500MB/s`. Đây là I/O của cái gì (batch ghi lớn) và vì sao OLTP bị vạ lây?
5. Vì sao AWR **không đủ** để chẩn đoán sự cố này, còn OSWatcher thì được? Đề xuất fix + phòng ngừa.

**Evaluation Criteria:**
- Bác bỏ "do mạng": `SQL*Net message from client` là **idle wait** (server chờ client) — không phải nguyên nhân; AWR Host CPU cho thấy `%WIO=51%` và Load Average End=41.8 → dấu hiệu I/O bottleneck rõ, không phải mạng. Junior đọc nhầm idle event thành thủ phạm.
- Phân loại nút thắt: `oswvmstat` lúc 03:12–03:36 có `b=38-44` (nhiều tiến trình blocked chờ I/O), `wa=79-80%` (CPU gần như chỉ ngồi chờ I/O), `r` thấp (2-4) → **I/O bottleneck**, KHÔNG phải CPU. `bo` (block out) ~500k+ = ghi ồ ạt.
- `si/so > 0` lúc 03:20 + `free` tụt còn ~98MB → **memory pressure gây swapping** chồng lên I/O bottleneck; SGA/PGA có nguy cơ bị paged → OLTP càng chậm; đây là nút thắt thứ hai, làm mọi thứ tệ hơn.
- `sdb` `%util=100`, `await=210ms`, `wkB/s≈500MB/s`, `w/s=980`: batch nightly đang ghi khối lượng khổng lồ lên chính device chứa datafile → device bão hòa (await 210ms >> 10ms) → mọi `db file sequential read` của OLTP xếp hàng sau → OLTP chậm rời rạc. OLTP vạ lây vì **chung device** với batch.
- AWR không đủ: chỉ có Host CPU **begin/end** tổng hợp, không có chuỗi thời gian OS, không có iostat per-device, không thấy swapping — không thể chỉ ra device `sdb` bão hòa lúc 03:12. OSWatcher có chuỗi vmstat/iostat theo thời gian → chẩn đoán được sự cố **đã qua**. Đây chính là lý do OSWatcher phải chạy sẵn.
- Fix/phòng ngừa: (1) tách I/O batch khỏi device datafile OLTP (mount/ASM diskgroup riêng, hoặc lịch batch lệch giờ OLTP); (2) xử lý memory pressure (thêm RAM/điều chỉnh PGA_AGGREGATE, HugePages cho SGA để không swap); (3) giữ OSWatcher chạy 24/7 + cân nhắc I/O Resource Manager giới hạn batch; (4) alert theo `await`/`%util` per-device, không chỉ load average.
- **Bonus:** chỉ ra map ngược: từ `oswtop`/`ps` trong archive tìm PID ghi nhiều (batch process), map SPID → session batch để xác nhận đúng thủ phạm; và cảnh báo `%st` nếu đây là VM (kiểm cột st — ở đây st=0 nên loại trừ hypervisor).


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_34_os_performance_senior_guide.md`
