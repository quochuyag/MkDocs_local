---
title: 📚 Hướng dẫn học Section 34 — OS Performance (Linux Utilities & OSWatcher)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_34/HUONG_DAN_HOC_SECTION_34.md
---

# 📚 Hướng dẫn học Section 34 — OS Performance (Linux Utilities & OSWatcher)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 35+36 + Linux/Oracle internals.
> Thời lượng gợi ý: ~90 phút (lecture 20' + Linux tools 45' + OSWatcher 15' + debrief 15').
> Nguồn: Practice 35 (Linux Utilities) + Practice 36 (OSWatcher) + [senior guide](../../section-all-new/section-34-os-performance-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

Các view DB **chỉ thấy Oracle**. Khi nút thắt ngoài Oracle hoặc cần biết **tài nguyên OS nào** cạn → dùng công cụ OS. Khung **USE** (Utilization/Saturation/Errors):

| Tài nguyên | Utilization | Saturation | Công cụ |
|---|---|---|---|
| CPU | %us+%sy | run queue `r` > #CPU | mpstat, vmstat, top |
| Memory | used/free | swap `si/so` > 0 | vmstat, free |
| Disk | `%util` per device | `await`, `avgqu-sz` | iostat -x, iotop |
| Network | throughput | retransmit, RX-ERR | netstat, ip -s |

**3 bẫy đọc số quan trọng:**
- **Load average** = run queue + tiến trình D-state (chờ I/O) → load cao ≠ CPU bound. Tách bằng vmstat `r` (CPU) vs `b`/`%wa` (I/O).
- **`%wa`** = CPU rảnh chờ I/O; là chỉ báo I/O duy nhất trong top. Trên máy nhiều core, `%wa` thấp vẫn có thể I/O bottleneck → xem `iostat -x` per-device.
- **`si/so > 0`** trên DB server = SGA/PGA bị swap → thảm họa.

**Cầu SPID:** process nóng `oracle<SID>` trong top → PID → `V$PROCESS.SPID` → `V$SESSION` → biết SQL nào.

---

## 1. Khởi động (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_34
./01_setup.sh
```
**Kỳ vọng:** danh sách công cụ PASS/THIẾU + số vCPU (2) + dòng pmon. Nếu `iostat`/`mpstat`/`iotop` THIẾU → cài (bằng root): `yum install -y sysstat iotop`.

> Cần **2 cửa sổ SSH**: một **monitoring** (chạy công cụ), một **stress** (sinh tải). Mở thêm: `vagrant ssh` lần nữa, hoặc `tmux`.

---

## 2. Đi qua từng công cụ (monitoring window, ~45 phút)

### 2.1. vmstat — tổng quan nhanh

🤔 **Dự đoán:** Khi CPU stress vs I/O stress, cột nào của vmstat sẽ nhảy?

**Monitoring:**
```bash
vmstat -t 2        # in mỗi 2s kèm timestamp
```
**Stress window — CPU:**
```bash
cd /labs/section_34 && ./os_stress.sh cpu 60 2
```
**Kỳ vọng:** `r` (run queue) > 2, `us` cao, `wa`~0, `si/so`=0.

**Stress window — I/O** (sau khi CPU xong):
```bash
./os_stress.sh io 60
```
**Kỳ vọng:** `b` (blocked) cao, `wa` cao, `bo` (block out) lớn, `us` không tăng nhiều. 💡 Cùng "load cao" nhưng vmstat phân biệt được nguồn: CPU (`r`) vs I/O (`b`/`wa`).

### 2.2. top — process nào nặng

```bash
top
```
Đọc header: **load average** (1/5/15'), **%Cpu(s)** (us/sy/**wa**/**st**), Mem/Swap. Danh sách process sắp theo %CPU. Phím tương tác: `Shift+P` (sort CPU), `Shift+M` (mem), `z` (màu), `c` (đường dẫn), `k` (kill), `q` (thoát). Batch: `top -bc -d 5 | head -20`.

### 2.3. mpstat / iostat -c — CPU per-core

```bash
mpstat -P ALL 2        # từng core: %usr %sys %iowait %idle %steal
```
Stress CPU 1 core → một core %usr ~100%, core kia rảnh (lệch tải). Stress 2 core → cả hai ~100%.

### 2.4. iostat -x — disk per-device

```bash
iostat -xyd 2 sda      # (đổi sda thành device thật; xem V$DATAFILE→df)
```
Stress I/O → `%util`~100%, `await` tăng (ms/IO), `w/s`+`wkB/s` lớn. 💡 Đây là bằng chứng device bão hòa mà `%wa` toàn hệ thống có thể che giấu trên máy nhiều core.

### 2.5. iotop — process nào đang I/O

```bash
sudo iotop -o -b -k -d 2      # -o chỉ process đang I/O
```
Stress I/O → thấy tiến trình `dd` ở đầu "DISK WRITE".

### 2.6. ps — top CPU process

```bash
ps -e -o pcpu,pid,user,args | sort -nrk1 | head
ps -ef | grep pmon            # instance đang chạy?
```

### 2.7. netstat — sức khỏe mạng

```bash
netstat -s -t | grep -i retrans    # retransmit (healthy < 0.1%)
ip -s link                         # RX/TX errors, dropped (nên = 0)
```

---

## 3. Cầu SPID — map process OS nóng về DB (Exercise 2, ~15 phút)

🤔 **Dự đoán:** Nếu `top` thấy `oracle<SID>` ăn 100% CPU, làm sao biết đó là session nào, SQL gì?

**Stress window (soe) — PL/SQL đốt CPU** (Practice 35 bước 61):
```bash
sqlplus soe/soe@//localhost:1521/ORADB
```
```sql
DECLARE n NUMBER; BEGIN WHILE (TRUE) LOOP n := SQRT(DBMS_RANDOM.VALUE(1,10000)); END LOOP; END;
/
```
**Monitoring window — lấy PID nóng:**
```bash
ps -e -o pcpu,pid,user,args | sort -nrk1 | head
```
**Map về DB (SYS):**
```bash
sqlplus / as sysdba @02_map_os_to_db.sql
# nhập PID vừa lấy
```
**Kỳ vọng:** trả về SID/SERIAL#, USERNAME=SOE, PROGRAM=sqlplus, SQL_TEXT là block PL/SQL đốt CPU. 💡 `V$PROCESS.SPID = PID của OS` là cầu nối. Ctrl+C block PL/SQL khi xong.

---

## 4. OSWatcher Black Box (Practice 36 — tùy chọn, ~10 phút)

**Vì sao:** AWR **không lưu** metric OS (iostat, swap, external CPU). Không có collector lịch sử → không điều tra được sự cố OS đã qua.

Nếu có sẵn `~/oswbb` (từ file đính kèm `oswbb840.tar` của khóa học):
```bash
cd ~/oswbb
nohup ./startOSWbb.sh 10 1 &     # sample mỗi 10s, giữ 1h (test); prod: 30 336
tail -f nohup.out                # heartbeat mỗi 10s
# ... chờ vài phút thu số ...
./stopOSWbb.sh
ls archive/                      # oswvmstat/ oswiostat/ oswtop/ oswnetstat/ ...
```
Analyzer (cần **Java 8**):
```bash
export PATH=$ORACLE_HOME/jdk/jre/bin:$PATH    # ⚠️ bẫy: Java OS có thể sai version
java -jar oswbba.jar -i ~/oswbb/archive       # gõ số → graph; d → dashboard HTML
```
💡 Dashboard HTML ở `~/oswbb/analysis`. Graph hiển thị tới thời điểm chạy tool (không real-time).

---

## 5. Dọn dẹp (BẮT BUỘC)

```bash
./99_cleanup.sh        # xóa /tmp/test1.img, kill busy loop, stop OSWatcher
```
Kill session PL/SQL đốt CPU (nếu còn) trong SQL*Plus: `ALTER SYSTEM KILL SESSION '<sid>,<serial#>' IMMEDIATE;`
```bash
exit
exit
```
```powershell
vagrant halt
```

---

## 6. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Vì sao load average không đủ để kết luận CPU bottleneck? Tách bằng cột nào?
2. `%wa` cao nghĩa gì? Vì sao máy nhiều core `%wa` thấp vẫn có thể I/O bottleneck?
3. `si/so > 0` trên DB server — vì sao báo động đỏ?
4. Cột nào trong V$PROCESS nối tới PID OS? Map hai chiều thế nào?
5. `%st` (steal) là gì? Vì sao DB metric bình thường mà máy vẫn chậm?
6. Vì sao OSWatcher phải chạy **trước** sự cố, AWR không thay được?

<details>
<summary>📖 Đáp án</summary>

1. Load average = số tiến trình trong run queue **cộng** tiến trình uninterruptible sleep (D-state, chờ I/O). Load cao có thể do CPU hoặc I/O. Tách bằng vmstat `r` (đói CPU) vs `b`/`%wa` (chờ I/O).
2. `%wa` = % thời gian CPU rảnh mà có I/O đang chờ → storage là nút thắt. Trên máy nhiều core, `%wa` là số **toàn hệ thống**: một tiến trình I/O-bound làm `%wa` chỉ vài % (core khác bận việc khác) nhưng device đó `iostat %util`=100%. Phải xem iostat per-device + iotop.
3. `si/so > 0` = swapping → SGA/PGA bị đẩy ra đĩa → mọi truy cập bộ nhớ Oracle thành I/O đĩa → thảm họa hiệu năng. Trên DB server dùng HugePages để ghim SGA, không bao giờ swap.
4. `V$PROCESS.SPID` = PID của OS. OS→DB: từ PID nóng (top/ps) `WHERE p.spid='<pid>'` JOIN V$SESSION (S.PADDR=P.ADDR) → session/SQL. DB→OS: từ session nóng lấy SPID để `strace`/`pstack`.
5. `%st` (steal) = CPU mà hypervisor lấy cho VM khác (noisy neighbor). Bên trong guest, Oracle không thấy — Time Model chỉ đo CPU dùng được. `%st` cao giải thích "DB chậm mà mọi metric Oracle bình thường". Chỉ công cụ OS thấy được.
6. AWR **không lưu** metric OS (iostat, swap, external CPU, per-device I/O). Muốn điều tra sự cố OS **đã qua** cần chuỗi thời gian OS → OSWatcher archive. Real-time tools chỉ thấy hiện tại. Vì vậy OSWatcher phải chạy sẵn 24/7 TRƯỚC sự cố.

</details>

---

## 7. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `iostat/mpstat: command not found` | `yum install -y sysstat` (bằng root) |
| `iotop: command not found` | `yum install -y iotop` |
| `os_stress.sh: bad interpreter ^M` | CRLF → `sed -i 's/\r$//' os_stress.sh` |
| `02_map_os_to_db.sql` không ra dòng | PID là background (ora_*) không có session; hoặc process đã chết → lấy PID mới |
| `oswbba.jar` lỗi Java version | `export PATH=$ORACLE_HOME/jdk/jre/bin:$PATH` (Java 8) trước khi chạy |
| `%util` 100% nhưng SSD/array không chậm | %util trên storage nhiều queue không = bão hòa; xem `await`/`avgqu-sz` |
| Không tìm được device của datafile | `V$DATAFILE` → path → `df <path>` → device → `iostat -x <device>` |

---

## 8. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi output thật
- [ ] Đã xong Giai đoạn 5-6 phần lớn; còn Section 35 (SQL Performance Analyzer) + 36 (Database Replay)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_34/HUONG_DAN_HOC_SECTION_34.md`
