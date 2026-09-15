---
title: Hướng dẫn SSH vào VM srv1 & thực hành trực tiếp trong Linux
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/ke_hoach/05_huong_dan_ssh_vm.md
---

# Hướng dẫn SSH vào VM srv1 & thực hành trực tiếp trong Linux

> Tạo ngày: 2026-07-14 (buổi 9) · Môi trường: VM `srv1` (Vagrant, OL7.9, Oracle 19c EE)
> Bổ sung cho [03_phase2_setup_log.md](003-phase2-setup-log.md) — tập trung vào làm việc BÊN TRONG VM.
> Scripts lab được mount sẵn tại **`/labs`** trong VM (cấu hình ở mục 4).

---

## 1. Bảng tài khoản / mật khẩu / host (tra cứu nhanh)

### SSH vào VM

| Thông số | Giá trị |
|---|---|
| Host | `127.0.0.1` (localhost) |
| Port SSH | `2222` (VirtualBox forward 2222 → 22) |
| User OS | `vagrant` |
| Xác thực | **Key** (không cần password): `D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\.vagrant\machines\srv1\virtualbox\private_key` |
| Password dự phòng | user `vagrant` / pass `vagrant` (mặc định của box, chỉ dùng được nếu sshd cho phép password auth) |
| User chạy Oracle | `oracle` — **không có password**, vào bằng `sudo` từ vagrant (mục 2.3) |
| root | `sudo -i` từ vagrant (NOPASSWD) |

### Tài khoản database (PDB `ORADB`)

| Tài khoản | Password | Dùng cho |
|---|---|---|
| `sys` (as sysdba) | `oracle_4U` | Grant trên object SYS, thí nghiệm 32K (qua CDB `ORCLCDB`) |
| `system` | `oracle_4U` | Toolkit chẩn đoán, DBA thường ngày |
| `pdbadmin` | `oracle_4U` | Admin riêng PDB (ít dùng) |
| `soe` | `soe` | Schema thực hành (lab, Swingbench) |

### Connect string — TRONG VM khác NGOÀI HOST

| Từ đâu | Connect string | Ghi chú |
|---|---|---|
| **Trong VM** | `//localhost:1521/ORADB` | Listener chuẩn 1521 |
| **Trong VM** (CDB root) | `//localhost:1521/ORCLCDB` | Cho thí nghiệm cần instance-level |
| **Trong VM** (user oracle) | `sqlplus / as sysdba` | Vào thẳng CDB root, không cần password |
| Từ host Windows | `//localhost:15210/ORADB` | ⚠️ 15210, KHÔNG phải 1521 (host có tnslsnr local chiếm 1521) |

---

## 2. Ba cách SSH vào VM

### 2.1. `vagrant ssh` — cách chuẩn, khuyên dùng

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0   # BẮT BUỘC đứng ở thư mục project
vagrant up      # nếu VM chưa chạy
vagrant ssh     # → vào thẳng shell của user vagrant
```

### 2.2. SSH trực tiếp bằng key — không cần đứng ở thư mục Vagrant

Dùng khi muốn SSH từ terminal bất kỳ, hoặc cấu hình cho MobaXterm/PuTTY/WinSCP:

```powershell
ssh -i "D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\.vagrant\machines\srv1\virtualbox\private_key" `
    -p 2222 -o StrictHostKeyChecking=no vagrant@127.0.0.1
```

Tiện hơn: thêm block sau vào `C:\Users\HHC_HOME\.ssh\config`, từ đó chỉ cần gõ **`ssh srv1`** (VS Code Remote-SSH cũng nhận):

```text
Host srv1
  HostName 127.0.0.1
  Port 2222
  User vagrant
  IdentityFile D:/Dba_project/vagrant-projects/OracleDatabase/19.3.0/.vagrant/machines/srv1/virtualbox/private_key
  StrictHostKeyChecking no
  UserKnownHostsFile NUL
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa
```

> 2 dòng cuối bắt buộc: key của box là ssh-rsa, OpenSSH mới mặc định từ chối.
> ⚠️ Key này bị Vagrant thay mới nếu `vagrant destroy && vagrant up` — khi đó chỉ cần giữ nguyên config, key tự trỏ đúng file.

### 2.3. Chạy lệnh một phát từ host (không cần vào shell)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant ssh -c "sudo -u oracle -i bash -c 'sqlplus -S / as sysdba @/labs/_toolkit/00_env_check.sql'"
```

---

## 3. Trở thành user `oracle` và môi trường sẵn có

```bash
# Sau khi SSH vào (đang là vagrant):
sudo -u oracle -i        # -i = login shell → tự nạp ORACLE_HOME, PATH, ORACLE_SID

# Kiểm tra môi trường đã nạp:
echo $ORACLE_HOME        # /opt/oracle/product/19c/dbhome_1
echo $ORACLE_SID         # ORCLCDB
which sqlplus            # $ORACLE_HOME/bin/sqlplus
```

Không đặt password cho `oracle` — `sudo -u oracle -i` là đủ và an toàn hơn (lab VM chỉ NAT, nhưng tạo thói quen tốt).

Các đường dẫn quan trọng trong VM:

| Đường dẫn | Là gì |
|---|---|
| `/labs` | **Scripts lab mount từ host** (mục 4) |
| `/vagrant` | Thư mục Vagrant project trên host (trao đổi file chung) |
| `/opt/oracle/product/19c/dbhome_1` | ORACLE_HOME |
| `/opt/oracle/oradata/ORCLCDB/ORADB/` | Datafiles của PDB ORADB (kể cả `soetbs01.dbf`, `tbs32k.dbf`) |
| `/opt/oracle/diag/rdbms/orclcdb/ORCLCDB/trace/` | Alert log + trace files (`alert_ORCLCDB.log`) |
| `/home/oracle` | Chỗ đặt file cần I/O thật (dump của impdp — vboxsf không hỗ trợ async I/O) |

---

## 4. Mount `/labs` — scripts lab dùng trực tiếp trong VM

### Cơ chế (đã cấu hình xong 2026-07-14)

- `Vagrantfile` thêm tham số `VM_LABS_DIR` + `config.vm.synced_folder VM_LABS_DIR, "/labs"`
- `config.local.yaml` đặt: `VM_LABS_DIR: 'D:/Dba_project/The-Oracle-Database-Performance-Tuning-Course/labs'`
- Áp dụng thay đổi: `vagrant reload` (chỉ cần 1 lần; các lần `vagrant up` sau tự mount)

**Lợi ích:** sửa script trên host (VS Code) → hiệu lực NGAY trong VM, không copy qua lại; `@../_toolkit/` giữ nguyên cấu trúc nên lab chạy y hệt như từ host.

### Chạy lab hoàn toàn trong VM

```bash
sudo -u oracle -i                # thành oracle
cd /labs/section_28              # BẮT BUỘC đứng trong thư mục lab (script gọi ../_toolkit/)

# Lab chính (user soe):
sqlplus soe/soe@//localhost:1521/ORADB
@01_setup.sql
@02_workload.sql 100000
@03_diagnose.sql
@04_fix.sql 100000

# Mở rộng 32K + dọn dẹp (SYS qua CDB root — trong VM dùng "/ as sysdba" là xong):
sqlplus / as sysdba
@05_row_chaining_32k.sql
@99_cleanup.sql
```

> Trong VM, `sqlplus / as sysdba` vào thẳng CDB root — thay được cách connect `sys/oracle_4U@//localhost:15210/ORCLCDB as sysdba` từ host.

Toolkit chẩn đoán trong VM (user system):

```bash
cd /labs/_toolkit
sqlplus system/oracle_4U@//localhost:1521/ORADB
@time_model.sql
@top_waits.sql
@ash_now.sql
@top_sql.sql ELAPSED
```

### Lưu ý vboxsf (quan trọng)

- ❌ **KHÔNG** để Data Pump đọc/ghi dump trên `/labs` hay `/vagrant` (ORA-27061, async I/O) → copy vào `/home/oracle` trước
- ❌ KHÔNG đặt datafile/redo/tempfile trên vboxsf
- ⚠️ `SPOOL` từ sqlplus ra `/labs/...` sẽ ghi thẳng vào repo trên host — muốn giữ output tạm thì spool ra `/tmp/` hoặc `/home/oracle/`
- ✅ Đọc script `.sql`, file config, README: hoàn toàn ổn

---

## 5. Công cụ OS trong VM cho các section sau

| Lệnh | Section | Ghi chú |
|---|---|---|
| `sar -u 5 3`, `sar -d`, `sar -r` | 34 | sysstat đã bật (`systemctl status sysstat`) |
| `iostat -xm 5`, `vmstat 5`, `top` | 25/26/34 | có sẵn |
| `stress-ng --cpu 2 --timeout 60s` | 25 | tạo CPU load nhân tạo |
| `tail -f /opt/oracle/diag/rdbms/orclcdb/ORCLCDB/trace/alert_ORCLCDB.log` | nhiều | theo dõi alert log khi chạy lab |

---

## 6. Xử lý sự cố nhanh

| Triệu chứng | Xử lý |
|---|---|
| `vagrant ssh` báo "not created" | Đứng sai thư mục — `cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0` |
| SSH trực tiếp bị từ chối key | Thiếu 2 dòng `+ssh-rsa` trong ssh config (mục 2.2) |
| `/labs` trống hoặc không có | `vagrant reload` (mount chỉ áp dụng sau reload); kiểm tra `VM_LABS_DIR` trong `config.local.yaml` |
| sqlplus trong VM: "command not found" | Chưa vào login shell — dùng `sudo -u oracle -i` (có `-i`) |
| ORA-12541 trong VM | DB/listener chưa start: `sudo systemctl status oracle-rdbms` rồi `sudo systemctl start oracle-rdbms` |
| Shared folder lỗi sau update VirtualBox | Cảnh báo Guest Additions lệch version — thường vẫn chạy; nếu hỏng thật: `vagrant plugin install vagrant-vbguest` rồi reload |
| Output sqlplus trong VM hiện `???` thay cho dấu `—` | Locale terminal của VM không render UTF-8 tiếng Việt — vô hại, chỉ là hiển thị |

---

## 7. Đã kiểm chứng (2026-07-14)

- `vagrant reload` → mount `/labs` OK (cả `/vagrant` giữ nguyên)
- User `oracle` đọc được `/labs`, chạy `@../_toolkit/00_env_check.sql` từ `/labs/section_28` → **8/8 PASS**
- Sửa script trên host bằng VS Code → thấy ngay trong VM (không cần reload)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/ke_hoach/05_huong_dan_ssh_vm.md`
