---
title: '📘 Module 02: Nền tảng Backup & Recovery'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_02/module_02_guide.md
---

# 📘 Module 02: Nền tảng Backup & Recovery

> **Module**: 02/17
> **Phạm vi**: Bài 06 & Bài 07 trong khóa học Oracle Database 12c Backup and Recovery using RMAN
> **Giảng viên**: Ahmed Baraka (Packt Publishing)
> **Thời gian học ước tính**: 2-3 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 01 (Giới thiệu & Chuẩn bị môi trường)
> **Nguồn PDF**: `pdf_extracted/module_02/`

---

## 📑 Mục lục

- [Bài 06: Introduction to Oracle Backup and Recovery Solutions](#-bài-06-introduction-to-oracle-backup-and-recovery-solutions)
- [Bài 07: Configuring Oracle Database for Backup and Recovery](#-bài-07-configuring-oracle-database-for-backup-and-recovery)
- [Bảng tổng hợp Module 02](#-bảng-tổng-hợp-module-02)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 06: Introduction to Oracle Backup and Recovery Solutions
> 📄 Nguồn: `Introduction to Oracle Backup and Recovery Solutions.pdf` — 13 slides

## 🎯 Mục tiêu bài học (Objectives - Slide 2)
Theo bài giảng gốc, sau bài này bạn sẽ nắm được:
- ✅ Mục đích của **chiến lược backup và recovery** (backup and recovery strategy)
- ✅ Danh sách các **loại failure** có thể xảy ra
- ✅ Khái niệm **Recovery Point Objective (RPO)**
- ✅ Khái niệm **Recovery Time Objective (RTO)**
- ✅ Các **giải pháp bảo vệ dữ liệu** của Oracle (Oracle data protection solutions)
- ✅ Giới thiệu về **Oracle Recovery Manager (RMAN)**
- ✅ Các **kỹ thuật backup và recovery** của Oracle database

## 📚 Kiến thức nền tảng cần biết
- Hiểu cơ bản về Oracle Database architecture
- Biết các thành phần: datafiles, control files, redo logs
- Khái niệm SQL cơ bản

---

## 📋 Nội dung chính

### 1. Backup and Recovery Targets (Slide 3)

> [!IMPORTANT]
> Backup & Recovery là việc **thiết lập các quy trình và chiến lược** để bảo vệ database khỏi mất dữ liệu do sự cố, lỗi thành phần, hoặc lỗi con người. Đây là **nhiệm vụ then chốt (crucial task)** của DBA.

Trong bất kỳ tổ chức nào sử dụng Oracle Database, dữ liệu là tài sản quý giá nhất. Một DBA được thuê không chỉ để quản lý database hoạt động trơn tru, mà quan trọng nhất là **đảm bảo dữ liệu không bao giờ bị mất**. Dù hệ thống chạy ổn 99.99% thời gian, chỉ cần 0.01% sự cố mà không có chiến lược backup → toàn bộ doanh nghiệp có thể bị ảnh hưởng nghiêm trọng.

Theo slides gốc:
- Set procedures and strategies involved in **protecting the database against data loss** caused by incidents, component failures, or human errors
- **A crucial DBA task** — nhiệm vụ tối quan trọng của DBA

**Trong production**: Một công ty thương mại điện tử có database 500GB chứa đơn hàng, thông tin khách hàng, inventory. Nếu disk chứa datafile hỏng mà không có backup → mất toàn bộ dữ liệu → công ty có thể phải đóng cửa. Chi phí mất dữ liệu **luôn cao hơn** chi phí triển khai backup.

---

### 2. Possible Failure Categories (Slide 4) ⚠️

Oracle phân loại các sự cố thành **12 loại failure**. Mỗi loại có mức độ nghiêm trọng khác nhau và cần phương pháp xử lý riêng. Hiểu rõ từng loại giúp DBA chuẩn bị kế hoạch recovery phù hợp — không phải loại failure nào cũng cần đến RMAN, nhưng khi cần thì RMAN là công cụ chủ chốt.

| # | Loại Failure | Giải thích chi tiết | Cách xử lý | Cần RMAN? |
|---|-------------|---------------------|-----------|----------|
| 1 | **User process failure** | Session của user bị ngắt bất thường (user tắt app, kill session). Ví dụ: nhân viên đóng SQL Developer khi query đang chạy | Oracle tự cleanup qua **PMON process** | ❌ |
| 2 | **Network failure** | Mất kết nối mạng giữa application server và database server. Ví dụ: switch mạng bị lỗi | Sửa mạng, reconnect. Oracle tự rollback uncommitted transactions | ❌ |
| 3 | **Instance failure** | Oracle instance bị crash đột ngột — do mất điện, OS crash, hoặc bug. Toàn bộ SGA bị mất | **Instance Recovery** tự động khi startup lại: áp dụng redo logs để redo committed, undo uncommitted | ❌ (tự phục hồi) |
| 4 | **Media failure** | **Nghiêm trọng!** Disk vật lý hỏng → datafile, control file, hoặc redo log bị mất/không đọc được | **RMAN RESTORE + RECOVER** | ✅ **BẮT BUỘC** |
| 5 | **Inaccessible components** | File hệ thống DB bị lock bởi process khác, hoặc permission bị thay đổi | Kiểm tra OS permissions, kill process giữ lock | ❌ |
| 6 | **Physical corruptions** | Block dữ liệu trên disk bị hỏng ở mức vật lý — bad sector, write incomplete. Ví dụ: `ORA-01578: ORACLE data block corrupted` | **RMAN block media recovery** | ✅ |
| 7 | **Logical corruptions** | Dữ liệu hợp lệ về mặt vật lý nhưng nội dung sai logic — ví dụ: index trỏ sai row | `DBMS_REPAIR`, rebuild index, hoặc RMAN | Có thể |
| 8 | **Inconsistencies** | Dữ liệu không nhất quán giữa các file — SCN không khớp giữa datafile headers | RMAN recover | ✅ |
| 9 | **I/O failures** | Lỗi đọc/ghi ổ đĩa — disk controller lỗi, cable loose | Sửa hardware, sau đó RMAN recover nếu data bị mất | Có thể |
| 10 | **Disaster** | Thảm họa tự nhiên hoặc nhân tạo: cháy datacenter, lũ lụt, động đất | **Oracle Data Guard** (standby database ở site khác) | ✅ |
| 11 | **External Incidents** | Tấn công mạng, ransomware, mất điện kéo dài | Restore từ backup, recovery catalog | ✅ |
| 12 | **User error** | **Rất phổ biến!** User/dev chạy nhầm: `DROP TABLE`, `DELETE FROM ... WHERE 1=1`, `TRUNCATE` | **Flashback Technologies** hoặc RMAN PITR | ✅ |

```
Phân loại theo mức độ nghiêm trọng và phương pháp xử lý:

   Tự phục hồi (Oracle xử lý)          Cần DBA can thiệp
   ┌──────────────────────┐    ┌─────────────────────────────┐
   │ User process failure │    │ Media failure   → RMAN      │
   │ Network failure      │    │ Corruption      → RMAN      │
   │ Instance failure     │    │ User error      → Flashback │
   │ (PMON, SMON cleanup) │    │ Disaster        → DataGuard │
   └──────────────────────┘    └─────────────────────────────┘
```

**Ví dụ thực tế — Media Failure**: Bạn là DBA của ngân hàng. Sáng thứ Hai, monitoring alert báo datafile `users01.dbf` không truy cập được. Kiểm tra OS thấy disk `/u03` bị bad sector. Lúc này bạn cần:
1. Kiểm tra backup gần nhất: `RMAN> LIST BACKUP OF DATAFILE '/u03/oradata/orcl/users01.dbf';`
2. Restore: `RMAN> RESTORE DATAFILE '/u03/oradata/orcl/users01.dbf';`
3. Recover: `RMAN> RECOVER DATAFILE '/u03/oradata/orcl/users01.dbf';`
4. Online lại: `SQL> ALTER DATABASE DATAFILE '/u03/oradata/orcl/users01.dbf' ONLINE;`

**Ví dụ thực tế — User Error**: Developer chạy nhầm `DELETE FROM orders WHERE status = 'PENDING'` thay vì `DELETE FROM orders_temp WHERE status = 'PENDING'` → xóa hết 50,000 đơn hàng pending. Giải pháp:
```sql
-- Dùng Flashback Query để xem data trước khi bị xóa
SELECT * FROM orders AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE)
WHERE status = 'PENDING';

-- Dùng Flashback Table để khôi phục
ALTER TABLE orders ENABLE ROW MOVEMENT;
FLASHBACK TABLE orders TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE);
```

> [!TIP]
> **Media failure** và **Disaster** là 2 loại cần **backup/recovery** nhất — đây là trọng tâm của toàn bộ khóa học! **User error** cũng rất phổ biến và sẽ học Flashback Technologies ở Module 12.

---

### 3. Defining Recovery Requirements (Slide 5) ⭐

Đây là 2 khái niệm **CỰC KỲ QUAN TRỌNG** mà mọi DBA phải nắm vững. RPO và RTO không phải là thuật ngữ kỹ thuật thuần túy — chúng là **yêu cầu của business** mà DBA phải đáp ứng. Khi phỏng vấn DBA, đây thường là câu hỏi đầu tiên: "RPO và RTO của hệ thống trước đó là bao nhiêu?"

#### 3.1 RPO — Recovery Point Objective
> **"How long worth of lost data the business tolerates to lose"**
> → Doanh nghiệp **chấp nhận mất bao nhiêu dữ liệu**?

RPO trả lời câu hỏi: "Nếu xảy ra sự cố, chúng ta có thể mất **tối đa** bao nhiêu dữ liệu?". RPO được đo bằng **thời gian** — RPO = 1 giờ nghĩa là chấp nhận mất tối đa 1 giờ giao dịch gần nhất.

```
Ví dụ minh họa RPO — Database ngân hàng:

Timeline:    8:00 ──── 9:00 ──── 10:00 ──── 11:00 ──── 12:00
              │                                │          │
         Mở cửa                           Backup cuối  💥 Crash!
         500 giao dịch/giờ               (incremental)
                                              
RPO = 1 giờ → Mất tối đa ~500 giao dịch (từ 11:00-12:00)
RPO = 15 phút → Mất tối đa ~125 giao dịch
RPO = 0 (zero data loss) → KHÔNG mất giao dịch nào
```

**RPO theo từng giải pháp Oracle:**

| RPO | Giải pháp | Chi phí | Ví dụ áp dụng |
|-----|----------|---------|---------------|
| 0 (zero loss) | Data Guard **SYNC** mode | 💰💰💰💰 | Ngân hàng, chứng khoán |
| Vài giây | Data Guard **ASYNC** mode | 💰💰💰 | Thanh toán online |
| 15-30 phút | RMAN Archivelog backup thường xuyên | 💰💰 | ERP, CRM doanh nghiệp |
| 1-24 giờ | RMAN Full/Incremental backup hàng ngày | 💰 | Hệ thống nội bộ, dev/test |

#### 3.2 RTO — Recovery Time Objective
> **"How long it takes you to make the system up and running again"**
> → Mất bao lâu để **hệ thống hoạt động lại**?

RTO trả lời câu hỏi: "Khi xảy ra sự cố, **mất bao lâu** để database hoạt động trở lại?". Theo slides, thời gian downtime gồm 3 giai đoạn, mỗi giai đoạn đều có thể tối ưu:

1. **Problem identification** — Phát hiện sự cố → Tối ưu bằng monitoring tools (OEM, Nagios, Zabbix)
2. **Recovery planning** — Lên kế hoạch recovery → Tối ưu bằng **runbook** có sẵn, luyện tập DR drill
3. **Recovery time** — Thời gian thực hiện recovery → Tùy thuộc kích thước DB, loại backup, bandwidth

```
RTO Timeline — Ví dụ DB 200GB bị media failure:

💥 Crash!  ──>  Phát hiện  ──>  Lên kế hoạch  ──>  RMAN Recovery      ──>  ✅ Online
   │            (5 phút)       (10 phút)          (45 phút)                │
   │            │               │                  │                       │
   │         OEM alert       Check backup        RESTORE + RECOVER        │
   │         gửi SMS         gần nhất            + apply archivelogs      │
   │                                                                      │
   └──────────────────── RTO = 60 phút ──────────────────────────────────┘
```

**RTO theo từng giải pháp Oracle:**

| RTO | Giải pháp | Mô tả |
|-----|----------|-------|
| Vài giây | **Oracle RAC** | Failover tự động sang node khác |
| Vài giây - phút | **Data Guard** Switchover/Failover | Standby DB lên làm primary |
| Phút | **Flashback Database** | "Tua lại" DB về thời điểm trước |
| Giờ | **RMAN Restore + Recover** | Restore full + apply archivelogs |
| Ngày | **RMAN full restore** từ tape | Đọc từ tape chậm hơn disk nhiều |

> [!WARNING]
> **RPO và RTO càng nhỏ → chi phí càng cao!** Ví dụ:
> - RPO = 0 + RTO = vài giây → cần Data Guard + RAC → **license hàng trăm ngàn USD**
> - RPO = 4 giờ + RTO = 2 giờ → chỉ cần RMAN + FRA → **miễn phí** (RMAN không cần license riêng)
> 
> DBA phải cân bằng giữa yêu cầu business và chi phí triển khai, sau đó **document rõ ràng** RPO/RTO đã thỏa thuận.

---

### 4. Backup and Recovery Plan Components (Slide 6)

Một kế hoạch backup/recovery không chỉ là "cài RMAN rồi chạy backup" — cần chuẩn bị đầy đủ về hạ tầng, phần mềm, và quy trình. Slides liệt kê 4 thành phần, tôi bổ sung giải thích chi tiết:

| Thành phần | Slides gốc | Giải thích chi tiết | Ví dụ thực tế |
|-----------|-----------|-------------------|---------------|
| **Technology licenses** | Giấy phép phần mềm | Xác định cần license gì. RMAN miễn phí, nhưng Data Guard, RAC cần **Enterprise Edition** license | Enterprise Edition: ~$47,500/processor |
| **Hardware - Disk** | Disk storage | Disk lưu backup trên local. Nên dùng disk khác với disk chứa database | NAS/SAN riêng cho backup, tối thiểu 2x kích thước DB |
| **Hardware - Tape** | Tape library + management software | Tape dùng cho long-term backup (giữ backup hàng tháng/năm). Rẻ hơn disk nhưng chậm hơn | Oracle Secure Backup + tape library HP/IBM |
| **Backup location** | Vị trí hệ thống backup | Backup nên ở **vị trí vật lý khác** database (khác phòng server, khác tòa nhà, hoặc cloud) | Offsite backup: backup gửi qua datacenter khác |
| **Connection** | Kết nối mạng | Bandwidth đủ lớn để truyền backup. DB 500GB cần ít nhất 1Gbps LAN | 10Gbps cho database lớn, dedicated backup network |

**Trong production — Ví dụ kế hoạch backup DB 1TB:**
```
Phương án Backup cho database ERP (1TB):

┌─ Hàng ngày ──────────────────────────────────┐
│  22:00  RMAN Incremental Level 1 → Disk      │
│         (Khoảng 15-50GB, mất ~30 phút)       │
└──────────────────────────────────────────────┘
┌─ Hàng tuần ──────────────────────────────────┐
│  Chủ nhật 02:00  RMAN Full Level 0 → Disk    │
│                  (1TB, mất ~3 giờ)           │
│  Sau đó copy backup từ Disk → Tape           │
└──────────────────────────────────────────────┘
┌─ Hàng tháng ─────────────────────────────────┐
│  Ngày 1: Copy tape backup → Offsite storage  │
│  Giữ lại 12 tháng gần nhất                   │
└──────────────────────────────────────────────┘

Yêu cầu phần cứng:
- Disk backup: NAS 4TB (4x database size)
- Tape library: 1 drive, 20 tape slots (LTO-8, 12TB/tape)
- Network: 10Gbps dedicated backup VLAN
- License: Enterprise Edition (cho RMAN incremental)
```

---

### 5. Oracle Data Protection Solutions (Slide 7) ⭐

Đây là bảng **cực kỳ quan trọng** — nó giúp bạn chọn đúng giải pháp dựa trên yêu cầu RPO/RTO. Trong phỏng vấn DBA, bạn sẽ được hỏi: "Với yêu cầu RTO = 5 phút, bạn chọn giải pháp gì?" → Phải trả lời được ngay.

| Mục tiêu B\&R | RTO | Giải pháp Oracle | Khi nào dùng |
|----------------|-----|------------------|-------------|
| **Physical data protection** | hours/days | 🔧 **RMAN**, Oracle Secure Backup | Mọi database cần backup định kỳ |
| **Physical data protection** | seconds/minutes | 🚀 **Data Guard**, GoldenGate, RAC | Database mission-critical, cần HA |
| **Human Errors** | minutes/hours | ⏪ **Flashback Technologies**, RMAN | Khi dev/user xóa nhầm data |
| **Recovery analysis** | Minimize diagnosis time | 🔍 **Data Recovery Advisor** | Tự động phân tích và đề xuất fix |

```
Oracle Data Protection - Chọn giải pháp theo RTO:

   RTO: seconds    │  Oracle Data Guard + GoldenGate + RAC
   ─────────────────┤  → Tự động failover, standby sẵn sàng
   RTO: minutes     │  Flashback Technologies
   ─────────────────┤  → "Tua lại" database, không cần restore  
   RTO: hours       │  RMAN + Oracle Secure Backup
   ─────────────────┤  → Restore từ disk, apply archivelogs
   RTO: days        │  RMAN (full restore từ tape)
                    │  → Đọc tape chậm, restore lâu
```

**So sánh chi tiết các giải pháp:**

| Giải pháp | RPO | RTO | License cần | Độ phức tạp | Module học |
|-----------|-----|-----|------------|------------|------------|
| **RMAN** | Phút-giờ | Giờ | ❌ Free | ⭐ Thấp | Module 04-11 (khóa này) |
| **Flashback** | Phút | Phút | ❌ Free | ⭐⭐ Trung bình | Module 12 |
| **Data Guard** | Giây-0 | Giây-phút | 💰 Enterprise | ⭐⭐⭐ Cao | Khóa khác |
| **RAC** | 0 (cho server failure) | Giây | 💰💰 Enterprise + RAC | ⭐⭐⭐⭐ Rất cao | Khóa khác |
| **GoldenGate** | Giây | Giây | 💰💰💰 Riêng | ⭐⭐⭐⭐ Rất cao | Khóa khác |

---

### 6. About Oracle Recovery Manager - RMAN (Slide 8)

Theo slides gốc, RMAN là:
- 📌 **A database utility** to perform database backup and recovery activities
- 📌 **No separate license is needed** — Không cần mua license riêng (miễn phí!)
- 📌 **Provides command prompt interface** — Giao diện dòng lệnh
- 📌 **Called by Oracle Enterprise Manager Cloud Control** — Tích hợp với OEM
- 📌 **Integrated with Oracle Secure Backup (OSB) and Oracle Backup Cloud Module**

```
RMAN Integration Architecture (từ Slide 10):

   ┌──────────────┐     ┌──────────────┐
   │    Linux     │     │   Windows    │
   │   Servers    │     │   Servers    │
   └──────┬───────┘     └──────┬───────┘
          │                    │
          ▼                    ▼
   ┌──────────────────────────────────┐
   │     Oracle Recovery Manager      │
   │           (RMAN)                 │
   └───┬──────────┬──────────┬───────┘
       │          │          │
       ▼          ▼          ▼
   ┌───────┐ ┌────────┐ ┌────────────┐
   │ Disk  │ │  OSB   │ │Cloud Backup│
   │Storage│ │(Tapes) │ │  Module    │
   └───────┘ └────────┘ └────────────┘
```

---

### 7. About Oracle Secure Backup (Slide 9)

Theo slides:
- **Centralized tape backup management software** — phần mềm quản lý backup băng từ tập trung
- Provides tape backup for **application files as well as database**
- **One central console** to manage servers and tape devices
- Allows RMAN to **directly communicate with tape devices**
- ⚠️ **Not covered by this course** — Không nằm trong phạm vi khóa học

---

### 8. Other Recovery Solutions (Slide 11)

| Giải pháp | Mục đích | RPO/RTO |
|-----------|---------|---------|
| **Oracle Data Guard** | Database disaster recovery solution | Best RPO và RTO |
| **Oracle GoldenGate** | Database disaster recovery solution | Best RPO và RTO |
| **Oracle RAC** | Recovery solution against **server failure** | Tự động failover |

---

### 9. Backup and Recovery Techniques (Slide 12)

Slides so sánh 2 kỹ thuật:

| Kỹ thuật | Đặc điểm | Trạng thái |
|----------|----------|-----------|
| **Recovery Manager (RMAN)** | Simplifies backup administration, tích hợp OEM + Tape Library | ✅ **Khuyến nghị dùng** |
| **User-Managed techniques** | Fully supported by Oracle | ❌ **Not recommended**, không dạy trong khóa này |

> [!NOTE]
> Khóa học tập trung hoàn toàn vào **RMAN** — User-Managed backup (dùng OS copy) **không được khuyến nghị** và **không được dạy** trong khóa này.

---

### 📌 Summary bài 06 (Slide 13)

Tóm tắt theo đúng slides:
1. ✅ The purpose of **backup and recovery strategy**
2. ✅ List of possible **failure categories** (12 loại)
3. ✅ **Recovery Point Objective (RPO)** — chấp nhận mất bao nhiêu data
4. ✅ **Recovery Time Objective (RTO)** — mất bao lâu để khôi phục
5. ✅ **Oracle data protection solutions** — RMAN, DataGuard, RAC, Flashback...
6. ✅ About **Oracle Recovery Manager (RMAN)** — miễn phí, dòng lệnh, tích hợp
7. ✅ **Backup and recovery techniques** — RMAN vs User-Managed

### ❓ Câu hỏi ôn tập Bài 06

1. **RPO vs RTO**: Giải thích sự khác biệt? Cho ví dụ cụ thể cho database ngân hàng.
2. **Liệt kê ít nhất 8 loại failure** mà slides đề cập. Loại nào cần RMAN để recovery?
3. **Oracle Data Protection Solutions**: Giải pháp nào cho RTO = seconds? Giải pháp nào cho RTO = hours?
4. **RMAN vs User-Managed**: Tại sao Oracle **không khuyến nghị** User-Managed backup?
5. **Backup Plan Components**: Kể tên 4 thành phần cần có trong kế hoạch backup.

---
---

# 📖 Bài 07: Configuring Oracle Database for Backup and Recovery
> 📄 Nguồn: `Configuring Oracle Database for Backup and Recovery.pdf` — 13 slides

## 🎯 Mục tiêu bài học (Objectives - Slide 2)
Theo bài giảng gốc, sau bài này bạn sẽ nắm được:
- ✅ **Basics of Oracle database server architecture** — Kiến trúc cơ bản Oracle
- ✅ **Using Fast Recovery Area (FRA)** — Sử dụng FRA
- ✅ **Multiplexing control files** — Nhân bản control files
- ✅ **Multiplexing redo log files** — Nhân bản redo log files
- ✅ **Enabling ARCHIVELOG mode** — Bật chế độ ARCHIVELOG
- ✅ **Database checkpoints** — Điểm kiểm tra database
- ✅ **Database parameters that affect RMAN operations** — Tham số ảnh hưởng RMAN

---

## 📋 Nội dung chính

### 1. Oracle Database Server Architecture (Slide 3) ⭐

Sơ đồ kiến trúc từ slides gốc:

```
┌─────────────────────────── Instance ───────────────────────────┐
│                                                                │
│  ┌──────────────────────── SGA ──────────────────────────┐     │
│  │                                                       │     │
│  │  ┌──────────────┐  ┌──────────┐  ┌────────────────┐  │     │
│  │  │ Data Buffer  │  │  Redo    │  │   Library      │  │     │
│  │  │   Cache      │  │  Buffer  │  │    Cache       │  │     │
│  │  └──────────────┘  └──────────┘  └────────────────┘  │     │
│  └───────────────────────────────────────────────────────┘     │
│                                                                │
│  ┌─────────────── Background Processes ───────────────────┐    │
│  │  CKPT    DBWR    LGWR    PMON    + others              │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌─────────── PGA ──────────┐                                  │
│  │  SP  │  SP  │  SP        │  (Server Processes)              │
│  └──────────────────────────┘                                  │
└────────────────────────────────────────────────────────────────┘
                          │
               ┌──────────┼──────────────────────┐
               ▼          ▼                      ▼
┌─────────────────────── Database Storage ──────────────────────┐
│                                                               │
│  📁 SYSTEM & SYSAUX      📁 User data files                  │
│     data files                                                │
│                                                               │
│  📁 Control files         📁 Online redo log files            │
│                                                               │
│  📁 Archived redo log files                                   │
│                                                               │
│  📄 (S)PFILE, Password file, Keystore, Alert log files        │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> Các **Background Processes** quan trọng cho backup/recovery:
> - **CKPT** (Checkpoint) — ghi SCN vào datafile headers & control files
> - **DBWR** (Database Writer) — ghi dirty buffers từ SGA xuống datafiles
> - **LGWR** (Log Writer) — ghi redo buffer xuống online redo log files
> - **PMON** (Process Monitor) — cleanup failed user processes

---

### 2. About Fast Recovery Area - FRA (Slide 4-5) ⭐

Fast Recovery Area (FRA) — trước đây gọi là Flash Recovery Area — là một **vùng lưu trữ trên disk được Oracle quản lý tự động**, dành riêng cho các file liên quan đến backup và recovery. Thay vì bạn phải tự quản lý thư mục backup, xóa file cũ, lo disk đầy... Oracle sẽ **tự động** làm tất cả trong FRA.

Tại sao FRA quan trọng? Bởi vì nếu không có FRA, DBA phải tự tay quản lý:
- Archived redo logs → dễ bị quên xóa → disk đầy → database HANG
- Backup files → nằm rải rác → khó tìm khi cần recover
- Control file autobackup → không biết lưu ở đâu

Với FRA, Oracle gom tất cả vào 1 nơi và tự dọn dẹp khi cần.

#### FRA chứa 2 loại file:

| Loại | Files | Giải thích | Ví dụ |
|------|-------|-----------|------|
| **Permanent files** (Cố định) | Multiplexed control files, Multiplexed online redo logs | Oracle **KHÔNG bao giờ** tự xóa, luôn hiện diện | `control02.ctl`, `redo01b.log` |
| **Transient files** (Tạm thời) | Archived redo logs, data file copies, control file copies, control file autobackups, backup pieces, flashback logs | Oracle **có thể tự xóa** khi hết hạn hoặc đã backup ra tape | `arch_1_001.arc`, `backup_ORCL_daily.bkp` |

```
FRA Directory Structure (ví dụ thực tế):

/u02/fra/ORCL/                           ← DB_RECOVERY_FILE_DEST
├── archivelog/                          ← Archived redo logs
│   ├── 2026_04_10/
│   │   ├── o1_mf_1_100_abc123.arc      (15 MB)
│   │   ├── o1_mf_1_101_def456.arc      (18 MB)
│   │   └── o1_mf_1_102_ghi789.arc      (12 MB)
│   └── 2026_04_11/
│       └── o1_mf_1_103_jkl012.arc      (20 MB)
├── backupset/                           ← RMAN backup pieces
│   └── 2026_04_11/
│       ├── o1_mf_nnndf_DAILY_xxx.bkp   (2.1 GB)
│       └── o1_mf_annnn_DAILY_yyy.bkp   (45 MB)
├── controlfile/                         ← Control file autobackup
│   └── o1_mf_s_12345_zzz.bkp           (18 MB)
├── onlinelog/                           ← Multiplexed redo logs
│   ├── o1_mf_1_aaa.log                 (200 MB)
│   ├── o1_mf_2_bbb.log                 (200 MB)
│   └── o1_mf_3_ccc.log                 (200 MB)
└── flashback/                           ← Flashback logs
    └── o1_mf_ddd.flb                    (500 MB)
```

#### Cấu hình FRA (Slide 5)

```sql
-- Hai tham số cần thiết:
-- 1. Vị trí FRA (nên đặt trên DISK KHÁC với database)
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '/u02/fra' SCOPE=BOTH;

-- 2. Kích thước FRA
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 50G SCOPE=BOTH;

-- Kiểm tra cấu hình hiện tại:
SHOW PARAMETER DB_RECOVERY_FILE_DEST;
```

**Output mẫu:**
```
NAME                                TYPE        VALUE
----------------------------------- ----------- ------------------
db_recovery_file_dest               string      /u02/fra
db_recovery_file_dest_size          big integer 50G
```

> [!CAUTION]
> Slides cảnh báo: **"Wrong FRA sizing may lead to database hang."**
> 
> **Tại sao database hang?** Khi FRA đầy 100% và Oracle không thể xóa thêm file nào (tất cả đều cần thiết), LGWR không thể archive redo log → redo log đầy → LGWR không thể ghi tiếp → **toàn bộ database bị treo**, không ai INSERT/UPDATE/DELETE được.

**Quy tắc sizing FRA trong production:**
- **Tối thiểu**: 2x kích thước database (DB 100GB → FRA 200GB)
- **Khuyến nghị**: Đủ chứa 1 full backup + 7 ngày incremental + 7 ngày archivelogs
- **Công thức ước tính**: FRA = Full backup size + (7 × daily incremental) + (7 × daily archivelog volume)

**Lỗi thường gặp:**
```
-- Khi FRA đầy:
ORA-19809: limit exceeded for recovery files
ORA-19804: cannot reclaim 52428800 bytes disk space from 53687091200 limit

-- Khi database bị hang do FRA đầy:
-- Alert log sẽ ghi:
ARCH: Error 19809 Creating archive log file to '/u02/fra/ORCL/archivelog/...
```

---

### 3. FRA Space Management (Slide 6) 

Oracle **chủ động** quản lý dung lượng FRA bằng cách phát cảnh báo sớm và tự động xóa file không cần thiết. Điều này giúp DBA không bị bất ngờ khi disk đầy.

Theo slides gốc, Oracle sẽ phát cảnh báo:
- ⚠️ **Warning alert** at **85%** usage → "Cần chú ý, sắp đầy"
- 🔴 **Critical alert** at **97%** usage → "KHẨN CẤP, sắp bị hang"

Khi cần thêm dung lượng, Oracle tự động xóa **obsolete files** (file backup/archivelog đã hết hạn theo retention policy).

**Remedy (Cách xử lý)** theo slides + giải thích chi tiết:

| Cách xử lý | Lệnh | Khi nào dùng |
|-----------|------|-------------|
| 1. Xóa file không cần | `RMAN> DELETE OBSOLETE;` | Khi có backup cũ đã hết hạn |
| 2. Xóa archivelog cũ | `RMAN> DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';` | Khi archivelog chiếm nhiều |
| 3. Thêm disk / tăng size | `ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 100G;` | Khi disk vật lý còn chỗ |
| 4. Đổi retention policy | `RMAN> CONFIGURE RETENTION POLICY TO REDUNDANCY 1;` | Giảm số backup giữ lại |

```sql
-- Kiểm tra alerts liên quan FRA
SELECT OBJECT_TYPE, MESSAGE_TYPE, MESSAGE_LEVEL,
       REASON, SUGGESTED_ACTION
FROM DBA_OUTSTANDING_ALERTS;
```

**Output mẫu khi FRA gần đầy:**
```
OBJECT_TYPE        MESSAGE_TYPE  MESSAGE_LEVEL  REASON                                    SUGGESTED_ACTION
------------------ ------------- -------------- ----------------------------------------- --------------------------
TABLESPACE         WARNING       16             db_recovery_file_dest is 87% full          Increase DB_RECOVERY_FILE_
                                                                                           DEST_SIZE or delete files
```

---

### 4. Monitoring FRA Space Usage (Slide 7)

Hai câu query dưới đây là công cụ chính để giám sát FRA — DBA nên chạy hàng ngày hoặc tích hợp vào monitoring script.

```sql
-- Query 1: Xem thông tin tổng quát FRA
SELECT NAME, SPACE_LIMIT, SPACE_USED, 
       SPACE_RECLAIMABLE, NUMBER_OF_FILES
FROM V$RECOVERY_FILE_DEST;
```

**Output mẫu:**
```
NAME       SPACE_LIMIT      SPACE_USED  SPACE_RECLAIMABLE  NUMBER_OF_FILES
---------- --------------- ------------ ------------------ ---------------
/u02/fra    53687091200     45112345600        3221225472              127
```

**Giải thích từng cột:**
| Cột | Ý nghĩa | Giá trị ví dụ |
|-----|---------|---------------|
| `NAME` | Đường dẫn FRA | `/u02/fra` |
| `SPACE_LIMIT` | Giới hạn tối đa (bytes) | 53,687,091,200 = **50GB** |
| `SPACE_USED` | Đã sử dụng (bytes) | 45,112,345,600 = **42GB** (84%) |
| `SPACE_RECLAIMABLE` | Dung lượng có thể thu hồi (bytes) | 3,221,225,472 = **3GB** (là file obsolete chưa xóa) |
| `NUMBER_OF_FILES` | Tổng số file trong FRA | 127 files |

```sql
-- Query 2: Xem phần trăm sử dụng theo loại file
SELECT FILE_TYPE, PERCENT_SPACE_USED, 
       PERCENT_SPACE_RECLAIMABLE, NUMBER_OF_FILES
FROM V$RECOVERY_AREA_USAGE;
```

**Output mẫu:**
```
FILE_TYPE               PERCENT_SPACE_USED  PERCENT_SPACE_RECLAIMABLE  NUMBER_OF_FILES
----------------------- ------------------- ------------------------- ---------------
CONTROL FILE                          0.18                          0               1
REDO LOG                              2.34                          0               3
ARCHIVED LOG                         52.67                       8.45              85
BACKUP PIECE                         28.15                       5.20              35
IMAGE COPY                            0.00                       0.00               0
FLASHBACK LOG                         1.02                       0.00               3
FOREIGN ARCHIVED LOG                  0.00                       0.00               0
```

**Phân tích output:** Archived log chiếm **52.67%** — đây là "thủ phạm" chính. Trong đó **8.45%** có thể thu hồi (reclaimable). Nên chạy `RMAN> DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';` để giải phóng.

> [!TIP]
> Hai view `V$RECOVERY_FILE_DEST` và `V$RECOVERY_AREA_USAGE` **bắt buộc phải nhớ** — là công cụ chính để giám sát FRA! Nên tạo script monitoring chạy hàng ngày gửi email khi FRA > 80%.

---

### 5. Multiplexing Control Files (Slide 8) ⭐

Theo slides gốc:
- Control files are **vital to database operation** — cực kỳ quan trọng
- **At least two** control files should be configured — tối thiểu 2 bản
- **One can be used to recover the other** — dùng bản còn lại để khôi phục
- **Recovery from losing ALL control files is difficult** — mất hết thì rất khó recovery

```sql
-- Kiểm tra control files hiện tại
SELECT NAME FROM V$CONTROLFILE;

-- Thêm control file: thay đổi SPFILE
ALTER SYSTEM SET CONTROL_FILES = 
    '/u01/oradata/orcl/control01.ctl',
    '/u02/oradata/orcl/control02.ctl',
    '/u03/oradata/orcl/control03.ctl'
    SCOPE=SPFILE;

-- ⚠️ Phải SHUTDOWN → copy file bằng OS → STARTUP
```

```
Multiplexing Control Files - Best Practice:

   Disk A: control01.ctl  ←─┐
   Disk B: control02.ctl  ←─┤── 3 bản trên 3 disk khác nhau
   Disk C: control03.ctl  ←─┘

   → Bất kỳ 1 disk hỏng → vẫn còn 2 bản
   → Mất hết 3 bản = THẢM HỌA
```

---

### 6. Multiplexing Redo Log Files (Slide 9) ⭐

Theo slides gốc:
- Each database has **redo log groups and members** within them
- **Best practice: three redo groups and two members in each group**
- **Store the members in fastest disks, like SSD** — Lưu trên ổ nhanh nhất

Sơ đồ từ slides:
```
             Disk A              Disk B
           ┌────────┐         ┌────────┐
Group 1 →  │ LOG_11 │         │ LOG_12 │    ← 2 members
           ├────────┤         ├────────┤
Group 2 →  │ LOG_21 │         │ LOG_22 │    ← 2 members  
           ├────────┤         ├────────┤
Group 3 →  │ LOG_31 │         │ LOG_32 │    ← 2 members
           └────────┘         └────────┘

Best Practice: 3 groups × 2 members = 6 redo log files
Mỗi group: members trên DISK KHÁC nhau
```

```sql
-- Thêm member cho group (KHÔNG cần shutdown)
ALTER DATABASE ADD LOGFILE MEMBER
    '/u02/oradata/orcl/redo01b.log' TO GROUP 1;

ALTER DATABASE ADD LOGFILE MEMBER
    '/u02/oradata/orcl/redo02b.log' TO GROUP 2;

ALTER DATABASE ADD LOGFILE MEMBER
    '/u02/oradata/orcl/redo03b.log' TO GROUP 3;

-- Kiểm tra
SELECT GROUP#, MEMBER FROM V$LOGFILE ORDER BY GROUP#;
```

---

### 7. About ARCHIVELOG Mode (Slide 10) ⭐⭐⭐

> [!IMPORTANT]
> Slides ghi rõ: **"Most production OLTP databases run in ARCHIVELOG mode"**
> → Hầu hết database production OLTP đều chạy ARCHIVELOG mode!

#### Các bước enable ARCHIVELOG mode (theo slides):

```sql
-- ============================================
-- ENABLE ARCHIVELOG MODE (Theo slides gốc)
-- ============================================

-- Bước 1: Mount the database
SQL> SHUTDOWN IMMEDIATE;
SQL> STARTUP MOUNT;

-- Bước 2: Define the destination (không cần nếu đã có FRA)
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=/u01/archive';

-- Bước 3: (Optional) Set the archivelog file name format
-- LOG_ARCHIVE_FORMAT = arch_%t_%s_%r.arc
--   %t = thread number
--   %s = sequence number  
--   %r = resetlogs ID

-- Bước 4: Change the database archiving mode
ALTER DATABASE ARCHIVELOG;

-- Bước 5: Startup the database
ALTER DATABASE OPEN;
```

```
ARCHIVELOG Mode Flow:

   Online Redo Logs                    Archive Destination
   ┌─────────┐                        ┌──────────────────┐
   │ Group 1 │──── Log Switch ────►   │ arch_1_001.arc   │
   │ Group 2 │──── Log Switch ────►   │ arch_1_002.arc   │
   │ Group 3 │──── Log Switch ────►   │ arch_1_003.arc   │
   └─────────┘                        │ ...              │
       │                              └──────────────────┘
       │
   LGWR ghi redo          ARCn process tự động
   vào current group      archive log đã đầy
```

> [!WARNING]
> Nếu **KHÔNG bật ARCHIVELOG mode**:
> - ❌ Không thể hot backup
> - ❌ Không thể point-in-time recovery
> - ❌ Không thể dùng DataGuard
> - ❌ Khi log switch, redo log CŨ bị **ghi đè** → mất lịch sử thay đổi

---

### 8. Reviewing Checkpoint Process - CKPT (Slide 11)

Checkpoint là quá trình **đồng bộ dữ liệu** giữa memory (SGA) và disk (datafiles). Khi Oracle chạy, dữ liệu thay đổi nằm trong **buffer cache** (SGA) — chưa ghi xuống disk. Checkpoint buộc DBWR ghi tất cả **dirty buffers** xuống datafiles, sau đó CKPT process cập nhật SCN vào control file và datafile headers.

**Tại sao Checkpoint quan trọng cho Backup/Recovery?** Vì SCN trong datafile headers cho RMAN biết: "Datafile này được cập nhật đến thời điểm nào". Khi recovery, RMAN so sánh SCN trong backup với SCN trong archivelog để biết cần apply bao nhiêu redo.

#### Hai loại checkpoint:

| Loại Checkpoint | SCN ghi vào đâu? | Khi nào xảy ra | Tác động |
|----------------|------------------|---------------|----------|
| **Full checkpoint** | Data file headers **VÀ** control files | `ALTER SYSTEM CHECKPOINT;`, shutdown, log switch | Nặng — ghi hết dirty buffers |
| **Incremental checkpoint** | **Chỉ** control files | Tự động, định kỳ | Nhẹ — chỉ ghi checkpoint position |

```
Checkpoint Flow — Chi tiết:

   SGA
   ┌──────────────────────────────┐
   │ Database Buffer Cache        │
   │                              │
   │  [Block A - dirty]  ←── đã thay đổi, chưa ghi disk
   │  [Block B - clean]  ←── đã ghi disk rồi
   │  [Block C - dirty]  ←── đã thay đổi, chưa ghi disk
   └──────────┬───────────────────┘
              │
        CHECKPOINT xảy ra!
              │
   ┌──────────┼──────────────────┐
   │          │                  │
   ▼          ▼                  ▼
  DBWR       CKPT              CKPT
   │          │                  │
   │     Ghi SCN=12345      Ghi SCN=12345
   │     vào                vào
   ▼          ▼                  ▼
 Data      Control           Data File
 Files     File              Headers
(Block A,C  (SCN position)   (checkpoint SCN)
 ghi xuống)
```

**SCN (System Change Number)** — "đồng hồ" của Oracle:

```sql
-- Xem SCN hiện tại của database
SELECT CURRENT_SCN FROM V$DATABASE;

-- Output mẫu:
CURRENT_SCN
-----------
    2847561

-- Xem checkpoint SCN trong datafile headers
SELECT FILE#, NAME, CHECKPOINT_CHANGE# AS CHECKPOINT_SCN,
       TO_CHAR(CHECKPOINT_TIME, 'YYYY-MM-DD HH24:MI:SS') AS CKPT_TIME
FROM V$DATAFILE;

-- Output mẫu:
FILE# NAME                                    CHECKPOINT_SCN  CKPT_TIME
----- --------------------------------------- -------------- -------------------
    1 /u01/oradata/orcl/system01.dbf                2847500  2026-04-11 21:30:15
    2 /u01/oradata/orcl/sysaux01.dbf                2847500  2026-04-11 21:30:15
    3 /u01/oradata/orcl/undotbs01.dbf               2847500  2026-04-11 21:30:15
    4 /u01/oradata/orcl/users01.dbf                 2847500  2026-04-11 21:30:15
```

**Giải thích**: `CHECKPOINT_SCN = 2847500` nghĩa là datafile đã được ghi đến SCN 2847500. Nếu `CURRENT_SCN = 2847561`, có **61 thay đổi** nằm trong memory chưa ghi xuống disk. Khi recovery, RMAN sẽ cần apply redo từ SCN 2847500 đến SCN hiện tại.

> [!NOTE]
> **SCN rất quan trọng trong RMAN**: Khi bạn chạy `RMAN> RECOVER DATABASE;`, RMAN đọc SCN từ backup, so sánh với SCN trong archivelog, rồi apply từng redo entry để "tua nhanh" database về trạng thái mới nhất. Không có SCN, Oracle không biết cần apply redo nào.

---

### 9. Setting Parameters that Affect RMAN (Slide 12)

Các tham số dưới đây **trực tiếp ảnh hưởng** đến hoạt động của RMAN. Cấu hình sai có thể dẫn đến: backup bị mất record, RMAN không tìm thấy backup khi cần recover, hoặc thời gian hiển thị sai gây nhầm lẫn.

#### Database Initialization Parameters:

| Parameter | Mục đích | Default | Khuyến nghị Production |
|-----------|---------|---------|----------------------|
| `CONTROL_FILE_RECORD_KEEP_TIME` | Số ngày giữ record backup/archivelog trong control file | **7 ngày** | **≥ 30 ngày** (hoặc dùng Recovery Catalog) |
| `DB_RECOVERY_FILE_DEST` | Đường dẫn FRA | Không có | Đặt trên disk riêng |
| `DB_RECOVERY_FILE_DEST_SIZE` | Kích thước tối đa FRA | Không có | ≥ 2x kích thước DB |

**Giải thích chi tiết `CONTROL_FILE_RECORD_KEEP_TIME`:**

Đây là tham số **hay gây ra sự cố** nhất. RMAN lưu thông tin backup (tên file, thời gian, SCN...) vào control file. Sau `CONTROL_FILE_RECORD_KEEP_TIME` ngày, Oracle **tự động ghi đè** record cũ. Nếu bạn cần restore từ backup 10 ngày trước mà tham số này là 7 → RMAN sẽ không biết backup đó tồn tại!

```sql
-- Kiểm tra giá trị hiện tại
SHOW PARAMETER CONTROL_FILE_RECORD_KEEP_TIME;
```

**Output mẫu:**
```
NAME                                 TYPE        VALUE
------------------------------------ ----------- -----
control_file_record_keep_time        integer     7
```

```sql
-- Tăng lên 60 ngày cho production
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME = 60 SCOPE=BOTH;

-- Kiểm tra lại
SHOW PARAMETER CONTROL_FILE_RECORD_KEEP_TIME;
-- VALUE = 60  ✅
```

**Lỗi thường gặp khi KEEP_TIME quá ngắn:**
```
-- RMAN không tìm thấy backup (vì record đã bị ghi đè):
RMAN-06409: no backup pieces found
RMAN-06026: some targets not found - aborting restore

-- Xảy ra khi: KEEP_TIME=7 nhưng bạn cần restore backup 10 ngày trước
-- Giải pháp: dùng Recovery Catalog (Module 09) hoặc tăng KEEP_TIME
```

#### Environment Variables:

| Variable | Mục đích | Ảnh hưởng | Giá trị khuyến nghị |
|----------|---------|----------|-------------------|
| `NLS_DATE_FORMAT` | Định dạng ngày giờ | Hiển thị timestamp trong RMAN output | `YYYY-MM-DD:HH24:MI:SS` |
| `NLS_LANG` | Ngôn ngữ và character set | Hiển thị ký tự đặc biệt trong RMAN | `AMERICAN_AMERICA.AL32UTF8` |

```bash
# === LINUX ===
# Thêm vào .bash_profile để áp dụng vĩnh viễn
export NLS_DATE_FORMAT='YYYY-MM-DD:HH24:MI:SS'
export NLS_LANG='AMERICAN_AMERICA.AL32UTF8'

# === WINDOWS (PowerShell) ===
$env:NLS_DATE_FORMAT='YYYY-MM-DD:HH24:MI:SS'

# === WINDOWS (CMD) ===
SET NLS_DATE_FORMAT=YYYY-MM-DD:HH24:MI:SS
```

**Tại sao NLS_DATE_FORMAT quan trọng?** Vì khi bạn chạy RMAN restore/recover đến thời điểm cụ thể:
```sql
-- Nếu NLS_DATE_FORMAT không đúng:
RMAN> RESTORE DATABASE UNTIL TIME "TO_DATE('2026-04-11 15:30:00','YYYY-MM-DD HH24:MI:SS')";
-- → Phải viết TO_DATE dài dòng

-- Nếu NLS_DATE_FORMAT='YYYY-MM-DD:HH24:MI:SS':
RMAN> RESTORE DATABASE UNTIL TIME '2026-04-11:15:30:00';
-- → Gọn hơn, ít lỗi hơn
```

---

### 📌 Summary bài 07 (Slide 13)

Tóm tắt theo đúng slides:
1. ✅ Basics of **Oracle database server architecture** (SGA, processes, storage)
2. ✅ Using **Fast Recovery Area (FRA)** — cấu hình, giám sát, xử lý khi đầy
3. ✅ **Multiplexing control files** — tối thiểu 2, nên 3 trên disk khác nhau
4. ✅ **Multiplexing redo log files** — 3 groups × 2 members, trên SSD
5. ✅ Enabling **ARCHIVELOG mode** — bắt buộc cho production
6. ✅ **Database checkpoints** — Full vs Incremental, SCN
7. ✅ **Database parameters** that affect RMAN — CONTROL_FILE_RECORD_KEEP_TIME, NLS_DATE_FORMAT

### ❓ Câu hỏi ôn tập Bài 07

1. **FRA chứa 2 loại file**: Kể tên và phân biệt **Permanent files** vs **Transient files**?
2. **FRA sizing**: Tại sao slides cảnh báo "wrong FRA sizing may lead to database hang"?
3. **Alerts**: FRA phát Warning alert ở bao nhiêu %? Critical alert ở bao nhiêu %?
4. **ARCHIVELOG mode**: Liệt kê 5 bước enable theo slides? Bước nào là optional?
5. **Checkpoint**: Sự khác biệt giữa **Full checkpoint** và **Incremental checkpoint**?
6. **CONTROL_FILE_RECORD_KEEP_TIME**: Tham số này ảnh hưởng gì đến RMAN?

---

# 📊 Bảng tổng hợp Module 02

| Slide | Chủ đề | Khái niệm chính | Lệnh/View quan trọng |
|-------|--------|-----------------|---------------------|
| 06-S3 | B&R Targets | Protecting database, crucial DBA task | — |
| 06-S4 | Failure Types | 12 loại failure | — |
| 06-S5 | **RPO & RTO** | RPO = data loss tolerance, RTO = recovery time | — |
| 06-S7 | **Data Protection** | RMAN, DataGuard, RAC, Flashback | — |
| 06-S8 | **About RMAN** | Free, command-line, integrated | — |
| 07-S4 | **FRA** | Disk storage cho recovery files | `V$RECOVERY_FILE_DEST` |
| 07-S5 | FRA Config | Location + Size | `DB_RECOVERY_FILE_DEST`, `DB_RECOVERY_FILE_DEST_SIZE` |
| 07-S6 | FRA Alerts | Warning 85%, Critical 97% | `DBA_OUTSTANDING_ALERTS` |
| 07-S7 | FRA Monitor | Percent usage by file type | `V$RECOVERY_AREA_USAGE` |
| 07-S8 | **Multiplex CTL** | At least 2, best 3 | `V$CONTROLFILE`, `CONTROL_FILES` |
| 07-S9 | **Multiplex Redo** | 3 groups × 2 members on SSD | `V$LOGFILE`, `ADD LOGFILE MEMBER` |
| 07-S10 | **ARCHIVELOG** | Must for production OLTP | `ALTER DATABASE ARCHIVELOG` |
| 07-S11 | **Checkpoints** | Full vs Incremental, SCN | — |
| 07-S12 | RMAN Params | CONTROL_FILE_RECORD_KEEP_TIME | `NLS_DATE_FORMAT`, `NLS_LANG` |

---

# 🎯 Câu hỏi ôn tập tổng hợp

## Tình huống thực tế (Scenario-Based)

### Tình huống 1:
> Manager hỏi bạn: "RPO của chúng ta là bao nhiêu?" Bạn kiểm tra thấy database đang ở **NOARCHIVELOG mode** và backup full chạy **mỗi đêm lúc 23:00**. RPO thực tế là bao nhiêu?

<details>
<summary>💡 Gợi ý trả lời</summary>

- RPO = tối đa **24 giờ** (vì nếu crash lúc 22:59, mất toàn bộ data từ 23:00 hôm trước)
- Ở NOARCHIVELOG mode, chỉ có thể restore về thời điểm backup cuối cùng
- Để giảm RPO: bật ARCHIVELOG mode → RPO giảm xuống thời gian giữa 2 lần archive
</details>

### Tình huống 2:
> Alert log báo: **"WARNING: db_recovery_file_dest is 87% used"**. Bạn query `V$RECOVERY_AREA_USAGE` thấy ARCHIVED LOG chiếm 65%. Bạn xử lý thế nào?

<details>
<summary>💡 Gợi ý trả lời</summary>

1. Kiểm tra `PERCENT_SPACE_RECLAIMABLE` — có bao nhiêu % thu hồi được
2. Dùng RMAN xóa archivelog cũ: `DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7'`
3. Hoặc `DELETE OBSOLETE` để xóa backup/archivelog không cần nữa
4. Nếu vẫn thiếu: tăng `DB_RECOVERY_FILE_DEST_SIZE`
5. Xem xét sao chép archivelog ra tape trước khi xóa
</details>

### Tình huống 3:
> Bạn muốn enable ARCHIVELOG mode nhưng hệ thống yêu cầu **zero downtime**. Có cách nào không?

<details>
<summary>💡 Gợi ý trả lời</summary>

- **KHÔNG CÓ CÁCH** — slides nêu rõ phải **MOUNT database** (tức phải shutdown trước)
- Bước bắt buộc: SHUTDOWN → STARTUP MOUNT → ALTER DATABASE ARCHIVELOG → ALTER DATABASE OPEN
- Giải pháp: lên lịch downtime ngoài giờ cao điểm (maintenance window)
- Nếu dùng RAC: có thể rolling (shutdown từng node)
</details>

---

## ➡️ Bài tiếp theo

**Module 03: Làm quen RMAN**
- Bài 08: Introduction to Recovery Manager (RMAN) — Kiến trúc RMAN, cách kết nối, các lệnh cơ bản
- Bài 09: Practice 2 — Thực hành kết nối và sử dụng RMAN

> Bạn muốn **tiếp tục Module 03** hay **ôn lại phần nào** trong Module 02? 😊


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_02/module_02_guide.md`
