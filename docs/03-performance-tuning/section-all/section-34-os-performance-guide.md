---
title: Section 34 — OS Performance (Linux, OSWatcher)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_34_os_performance_guide.md
---

# Section 34 — OS Performance (Linux, OSWatcher)

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 35 (Linux Utilities) + 36 (OSWatcher Black Box)  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 34

Section 34 trang bị kỹ năng giám sát hiệu năng **hệ điều hành Linux** — lớp ngoài cùng của stack Oracle. Khi database metrics (AWR, ASH) chỉ ra bottleneck nhưng không rõ nguyên nhân, cần nhìn xuống OS để xem CPU/memory/disk/network đang ở trạng thái gì. Hai phần chính:

- **Practice 35**: Các Linux utilities tương tác — `vmstat`, `top`, `iostat`, `mpstat`, `iotop`, `ps`, `ifconfig`, `netstat`
- **Practice 36**: OSWatcher Black Box — công cụ thu thập và phân tích OS metrics theo thời gian, vẽ đồ thị

---

## Phần 1 — Linux Utilities

### Kiến trúc theo dõi

```
Oracle DB Performance Issue
         ↓
  AWR / ASH — xác định bottleneck type
         ↓
  OS Utilities — đào sâu vào OS layer
  ┌──────────────────────────────────────┐
  │  CPU high?  → iostat -c, mpstat, top │
  │  Memory low? → vmstat (si/so)        │
  │  Disk I/O?  → iostat -d, iotop       │
  │  Network?   → ifconfig, netstat      │
  │  Process?   → top, ps                │
  └──────────────────────────────────────┘
         ↓
  Map OS Process → DB Process
  (SPID in V$PROCESS)
```

---

## Giám sát tổng thể hệ thống

### vmstat — Toàn cảnh nhanh

**vmstat** cho thấy snapshot toàn bộ hệ thống: memory, CPU, disk I/O, swapping.

```bash
# Snapshot một lần
vmstat

# Cập nhật mỗi 2 giây (liên tục)
vmstat 2

# Có timestamp
vmstat -t 2

# I/O statistics theo disk device (accumulated)
vmstat -d 2
```

**Các cột quan trọng:**

| Cột | Section | Ý nghĩa | Dấu hiệu vấn đề |
|-----|---------|---------|----------------|
| `r` | procs | Số processes đang chờ run time | > 0 liên tục → CPU bận |
| `b` | procs | Số processes trong uninterruptible sleep | Cao → disk I/O blocking |
| `free` | memory | Free memory (KB) | < ~100 MB → memory thấp |
| `si` | swap | Memory swapped in từ disk | > 0 liên tục → **memory bottleneck** |
| `so` | swap | Memory swapped out to disk | > 0 liên tục → **memory bottleneck** |
| `bi` | io | Blocks received từ block device (reads) | Cao → disk read heavy |
| `bo` | io | Blocks sent to block device (writes) | Cao → disk write heavy |
| `us` | cpu | User CPU time % | Cao → CPU bận vì user process |
| `sy` | cpu | System CPU time % | Cao → kernel overhead |
| `id` | cpu | CPU idle % | Thấp → CPU saturation |
| `wa` | cpu | I/O wait % | Cao → disk I/O là bottleneck |

**Tóm tắt quick check:**
- `si` + `so` > 0 thường xuyên → **memory shortage**
- `r` cao + `us` cao → **CPU bottleneck**
- `bi` + `bo` cao → **disk I/O bottleneck**

```bash
# dstat — phiên bản thân thiện hơn của vmstat
dstat
```

---

### top — Task Manager của Linux

**top** hiển thị liên tục trạng thái hệ thống + danh sách processes sắp xếp theo CPU.

```bash
# Interactive mode
top

# Hiển thị processes của user oracle
top -u oracle

# Batch mode — output có thể pipe/redirect
top -bc | head -20

# Batch mode, sắp xếp theo memory
top -bc -a | head -n 20
```

**Header của top:**

| Phần | Ý nghĩa |
|------|---------|
| `load average: 1.2, 0.8, 0.5` | Load trung bình 1/5/15 phút — cao và tăng → vấn đề |
| `Tasks` | Số processes running/sleeping/stopped/zombie |
| `Cpu(s): %us, %sy, %id, %wa` | CPU breakdown — **%wa** là I/O wait |
| `Mem` | Total/used/free physical memory |
| `Swap` | Swap usage — > 0 thường xuyên = vấn đề |

**Columns trong process list:**

| Cột | Ý nghĩa |
|-----|---------|
| `PID` | Process ID |
| `USER` | Process owner |
| `%CPU` | CPU % từ lần refresh trước |
| `%MEM` | Memory % |
| `VIRT` | Total virtual memory |
| `RES` | Non-swapped physical memory |
| `TIME+` | Tổng CPU time (giây.centisec) |
| `COMMAND` | Tên lệnh/process |

**Phím tắt trong interactive mode:**

| Phím | Tác động |
|------|---------|
| `[Shift]+[P]` | Sắp xếp theo CPU |
| `[Shift]+[O]` | Chọn cột để sort (memory, swap, ...) |
| `z` | Highlight running processes |
| `c` | Hiển thị full path của process |
| `d` | Thay đổi refresh interval (default: 3s) |
| `k` | Kill process theo PID |
| `q` | Quit |

---

## Giám sát CPU

### iostat — CPU + I/O Statistics

```bash
# Chỉ xem CPU (cập nhật mỗi 2 giây)
iostat -c 2

# Xem thông tin CPUs
cat /proc/cpuinfo
```

**Cột CPU trong iostat:**

| Cột | Ý nghĩa |
|-----|---------|
| `%user` | CPU time cho user processes |
| `%system` | CPU time cho kernel |
| `%iowait` | CPU idle chờ I/O |
| `%idle` | CPU hoàn toàn nhàn rỗi |

**Quan sát:** Với 2 CPUs, stress 1 CPU → `%user` ≈ 50%; stress 2 CPUs → `%user` ≈ 98%.

### mpstat — CPU per-core Statistics

```bash
# Báo cáo mỗi 2 giây
mpstat 2
```

**Khác với iostat:** mpstat có thể hiển thị stats theo từng CPU core riêng lẻ, useful khi muốn biết load phân phối đều không.

**Kết luận:** `iostat` + `mpstat` đo CPU workload nhưng không cho biết process nào đang tiêu thụ — dùng `top` hoặc `ps` để biết process cụ thể.

---

## Giám sát Processes

### ps — Process Snapshot

```bash
# Liệt kê tất cả processes (System V syntax)
ps -ef

# BSD syntax — có %CPU column (% lifetime)
ps aux

# Top 10 processes tiêu thụ CPU nhiều nhất
ps aux | sort -nrk 3,3 | head -n 10
ps -e -o pcpu,pid,user,tty,args | sort -n -k 1 -r | head -n 10
```

**Lưu ý quan trọng — DBA trick:**
```bash
# Kiểm tra Oracle instance có đang chạy không
ps -ef | grep pmon
# Nếu thấy "ora_pmon_<DBNAME>" → instance đang up
```

**Khác biệt `ps` vs `top`:**
- `ps`: snapshot tại thời điểm chạy, `TIME` = accumulated CPU time từ khi process start
- `top`: continuous refresh, `%CPU` = % trong interval vừa rồi

---

## Giám sát Disk I/O

### iostat — I/O per Device

```bash
# Snapshot cơ bản (accumulated từ boot — ít hữu ích)
iostat

# Delta values mỗi 2 giây, cho disk sda, extended info
iostat -ykx sda -d 2
# -y: bỏ report đầu (accumulated from boot)
# -k: KB
# -x: extended info
# -d: disk stats only
```

**Cột quan trọng trong iostat extended:**

| Cột | Ý nghĩa | Dấu hiệu vấn đề |
|-----|---------|----------------|
| `kB_read/s` | KB đọc mỗi giây | Cao → heavy read |
| `kB_wrtn/s` | KB ghi mỗi giây | Cao → heavy write |
| `%util` | % thời gian disk đang xử lý I/O request | > 90% → disk saturation |
| `await` | Thời gian trung bình (ms) để I/O request hoàn thành | Cao → disk chậm hoặc queue |

**Kết luận:** `iostat -d` cho biết **disk/partition nào** đang chịu I/O nặng.

### iotop — I/O per Process (như top nhưng cho I/O)

```bash
# Interactive mode (cần root)
iotop

# Batch mode
iotop -o -b -k -d 2
# -o: chỉ hiển thị processes đang có I/O
# -b: batch mode
# -k: kilobytes
# -d: interval 2s
```

**Phím tắt interactive mode:**

| Phím | Tác động |
|------|---------|
| `o` | Chỉ hiển thị processes đang perform I/O |
| `[→]` / `[←]` | Đổi sort column |
| `r` | Đảo chiều sort |
| `q` | Quit |

**Kết luận:** `iotop` cho biết **process nào** đang gây I/O cao → complement với `iostat` (device nào).

---

## Giám sát Network

### ifconfig — Network Interface Status

```bash
ifconfig
```

**Xem:**
- Cấu hình IP, subnet, gateway
- Packets có errors, dropped, overrun → trong hệ thống healthy: **tất cả = 0**
- Collisions → phải = 0

> **Lưu ý:** `ifconfig` đã obsolete trên Oracle Linux mới — thay bằng `ip addr`.

### netstat — Network Connections & Statistics

```bash
# Xem tất cả connections (TCP + UNIX sockets)
netstat

# Kết hợp options: -a (all), -t (TCP), -e (extended), -u (UDP)
netstat -ate

# Statistics TCP (healthy: retransmit/send < 0.1%, bad/received < 0.1%)
netstat -s -t

# Packet stats per network interface, cập nhật mỗi 1 giây
netstat -i 1
```

**Options netstat:**

| Option | Tác động |
|--------|---------|
| `-a` | Active TCP + listening states + UDP |
| `-t` | TCP only |
| `-u` | UDP only |
| `-p` | Hiển thị process name |
| `-n` | IP addresses thay vì hostnames (tránh DNS lookup timeout) |
| `-i` | Packet stats per network interface |
| `-e` | Extended details |

**Health check:**
```
segments_retransmitted / segments_sent < 0.1%  → OK
bad_segments_received / segments_received < 0.1% → OK
RX-ERR, RX-DRP, RX-OVR = 0 → OK
```

**Kết luận:** `ifconfig` + `netstat` dùng kiểm tra sức khỏe network nhưng khó dùng để đo load theo thời gian — dùng OSWatcher để vẽ đồ thị.

---

## Map OS Process → Database Process

Khi `top` hoặc `ps` cho thấy một Oracle process đang tiêu thụ CPU/memory cao, cần xác định đây là session/SQL gì trong database.

### Bước 1: Tìm PID của process Oracle ở OS

```bash
# Tìm top CPU processes
ps -e -o pcpu,pid,user,tty,args | sort -n -k 1 -r | head
# → Thấy: 98.5  1234  oracle  ...  oracleORADB (LOCAL=NO)
```

### Bước 2: Map PID sang database session

```sql
-- Kết nối sysdba, thay &PID_FROM_OS bằng PID lấy từ bước 1
SELECT
  'USERNAME : '    || S.USERNAME   || CHR(10) ||
  'SCHEMA : '      || S.SCHEMANAME || CHR(10) ||
  'OSUSER : '      || S.OSUSER     || CHR(10) ||
  'PROGRAM : '     || S.PROGRAM    || CHR(10) ||
  'SPID : '        || P.SPID       || CHR(10) ||
  'SID : '         || S.SID        || CHR(10) ||
  'SERIAL# : '     || S.SERIAL#    || CHR(10) ||
  'MACHINE : '     || S.MACHINE    || CHR(10) ||
  'TYPE : '        || S.TYPE       || CHR(10) ||
  'SQL TEXT : '    || Q.SQL_TEXT   AS INFO
FROM V$SESSION S, V$PROCESS P, V$SQL Q
WHERE S.PADDR = P.ADDR
  AND P.SPID = '&PID_FROM_OS'
  AND S.SQL_ID = Q.SQL_ID(+)
  AND S.STATUS = 'ACTIVE';
```

**Nguyên tắc:** `V$PROCESS.SPID` = OS Process ID. Join `V$SESSION` qua `PADDR = ADDR` để lấy session info. Join `V$SQL` để lấy SQL text.

---

## Phần 2 — OSWatcher Black Box

### OSWatcher là gì?

**OSWatcher Black Box (oswbb)** là công cụ của Oracle thu thập OS metrics định kỳ (vmstat, iostat, netstat, top output) vào log files, sau đó **vẽ đồ thị** qua Java GUI analyzer. Đặc biệt hữu ích khi:

- Cần theo dõi OS performance trong thời gian dài (hours/days)
- Muốn so sánh OS metrics với thời điểm xảy ra incident
- Muốn visualize xu hướng thay vì số liệu real-time

### Cài đặt OSWatcher

```bash
# Download từ MOS Doc ID 301137.1 (tên file: oswbb840.tar)
# Copy vào server, giải nén
cp oswbb840.tar ~
cd ~
tar xvf oswbb840.tar
cd oswbb
chmod 774 *
```

### Khởi động và dừng OSWatcher

```bash
# Test — thu thập mỗi 10 giây, giữ 1 giờ data
./startOSWbb.sh 10 1
# Syntax: startOSWbb.sh <interval_seconds> <archive_hours>

# Chạy background (production)
nohup ./startOSWbb.sh 10 1 &

# Xem heartbeat
tail -f nohup.out

# Kiểm tra OSWatcher đang chạy
ps -ef | grep -i oswat

# Dừng OSWatcher
./stopOSWbb.sh
```

**Archive directory:** `~/oswbb/archive/` — chứa các thư mục con:
- `oswiostat/` — iostat data
- `oswvmstat/` — vmstat data
- `oswnetstat/` — netstat data
- `oswtop/` — top data

### Phân tích bằng OSWatcher Analyzer (GUI)

```bash
# Cần Java 8 (Oracle JDK thường đi kèm Oracle software)
export PATH=$ORACLE_HOME/jdk/jre/bin:$PATH
cd ~/oswbb
java -jar oswbba.jar -i /home/oracle/oswbb/archive
```

**Trong tool prompt:**

| Phím | Tác động |
|------|---------|
| Số (1, 2, 3...) | Mở graph tương ứng (CPU, memory, I/O, network...) |
| `d` | Generate dashboard HTML page |
| `r` | Đóng graphs đang mở |
| `q` | Quit |

**Dashboard HTML:** Lưu tại `~/oswbb/analysis/` — mở bằng browser để xem tất cả graphs.

---

## Quy trình điều tra OS bottleneck

```
Bước 1: Quick overview
  vmstat 2 hoặc dstat
  → Xác định khu vực: CPU? Memory? Disk? Swap?
        ↓
Bước 2: Drill down theo khu vực

  CPU cao (us/sy cao, id thấp):
    iostat -c 2     → xác nhận CPU %
    mpstat 2        → xem per-core distribution
    top / ps aux    → tìm process thủ phạm
        ↓
  Memory thấp (free thấp, si/so > 0):
    vmstat (free column)
    free -m
    top (Mem/Swap section)
        ↓
  Disk I/O cao (bi/bo cao, %wa cao):
    iostat -ykx sda -d 2  → xác nhận disk device
    iotop -o              → tìm process thủ phạm
        ↓
  Network issue:
    ifconfig              → errors, dropped = 0?
    netstat -s -t         → retransmit < 0.1%?
    netstat -i 1          → packet rate

Bước 3: Map sang Oracle (nếu process là Oracle)
  ps -e -o pcpu,pid | sort → lấy PID
  SQL trên V$PROCESS + V$SESSION + V$SQL → lấy SQL text

Bước 4: OSWatcher (phân tích lịch sử)
  Nếu cần trend hoặc correlation với incident time
  java -jar oswbba.jar -i /archive → vẽ đồ thị
```

---

## Bảng tóm tắt Utilities

| Mục tiêu | Utilities |
|---------|-----------|
| Tổng quan toàn hệ thống | `vmstat`, `dstat`, `top` |
| Giám sát CPU workload | `iostat -c`, `mpstat` |
| Tìm process tiêu thụ CPU | `top`, `ps aux \| sort` |
| Giám sát Disk I/O (device) | `iostat -ykx -d` |
| Tìm process gây I/O | `iotop -o` |
| Kiểm tra Network health | `ifconfig`, `netstat -s -t` |
| Theo dõi network connections | `netstat -ate` |
| Mapping OS process → DB session | `V$PROCESS.SPID` + `V$SESSION` |
| Thu thập & vẽ đồ thị long-term | OSWatcher Black Box + `oswbba.jar` |

---

## Các thống số health check nhanh

```
Memory OK?     → vmstat: si=0, so=0 && free > 100MB
CPU OK?        → vmstat: r nhỏ, id > 20%, wa < 10%
Disk OK?       → iostat: %util < 90%, await thấp
Network OK?    → netstat -s -t: retransmit/sent < 0.1%
               → ifconfig: errors=0, dropped=0
Oracle up?     → ps -ef | grep pmon
```

---

## Câu hỏi ôn tập

1. `vmstat` cho thấy `si > 0` và `so > 0` liên tục. Điều này có nghĩa là gì? Cần xử lý như thế nào?
2. `%wa` trong `top` và `iostat` đo lường gì? Tại sao đây là chỉ số quan trọng cho DBA Oracle?
3. Sự khác biệt giữa `iostat` và `iotop` khi giám sát Disk I/O? Dùng cái nào để biết **process nào** đang gây I/O cao?
4. Khi `top` cho thấy một process `oracleORADB` đang dùng 95% CPU, làm thế nào để biết đó là Oracle session nào và đang chạy SQL gì?
5. `V$PROCESS.SPID` lưu gì? Tại sao cần join `V$PROCESS` và `V$SESSION` để map OS process sang DB session?
6. OSWatcher Black Box khác với `vmstat` + `iostat` trực tiếp ở điểm gì? Khi nào nên dùng OSWatcher?
7. Lệnh `ps -ef | grep pmon` thường được DBA dùng để làm gì?
8. Trong `netstat -s -t`, tỷ lệ `segments retransmitted / segments sent` nên dưới ngưỡng nào để network được coi là healthy?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_34_os_performance_guide.md`
