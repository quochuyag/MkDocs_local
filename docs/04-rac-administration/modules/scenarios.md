---
title: 🧩 10 tình huống thực tế Oracle RAC & cách giải quyết
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/scenarios.md
---

# 🧩 10 tình huống thực tế Oracle RAC & cách giải quyết

> Rút ra từ 14 module của khóa *Oracle Database RAC Administration* (Ahmed Baraka). Mỗi tình huống gồm: **bối cảnh → phân tích → cách giải quyết (lệnh) → module liên quan**.
> Môi trường tham chiếu: database `rac`, instance `rac1`/`rac2`, node `srv1`/`srv2`, SCAN `srv-scan`, diskgroup `+DATA`/`+FRA`.

---

## 1️⃣ Một node/instance chết đột ngột — dịch vụ có bị mất?

**Bối cảnh:** Instance `rac1` trên `srv1` crash lúc cao điểm. Ứng dụng báo lỗi một số kết nối.

**Phân tích:** RAC vẫn available vì `rac2` còn chạy. Clusterware sẽ tự **restart** instance chết và **relocate service** sang node còn sống nếu service có `available` node.

**Giải quyết:**

```bash
# kiểm tra trạng thái
srvctl status database -d rac
srvctl status service  -d rac -s soesrv     # đang chạy ở node nào?
ps -ef | grep ora_pmon                       # xác nhận instance đã tự start lại chưa

# nếu service chưa về đúng chỗ sau khi rac1 hồi phục:
srvctl relocate service -db rac -service soesrv -oldinst rac2 -newinst rac1
```

> 💡 Để ứng dụng **không thấy lỗi** khi mất node: dùng **FAN/FCF** hoặc **TAF/Application Continuity** (xem tình huống 6). 📘 Module 04, 06.

---

## 2️⃣ Một report chạy rất chậm dù OLTP vẫn bình thường

**Bối cảnh:** Người dùng OLTP không phàn nàn, nhưng một report trả ít dữ liệu lại chạy rất lâu.

**Phân tích:** Đây là bài toán **tune một session cụ thể**, không phải tune cả hệ thống. Dùng EM Express để khoanh vùng theo module/action rồi để ADDM đề xuất.

**Giải quyết:**

```sql
-- gắn nhãn để nhận diện session report
EXEC DBMS_APPLICATION_INFO.SET_MODULE('REPORTING','Customer Report');
```

1. EM Express → **Performance Hub → Activity** → `Wait Class` → **Top Dimensions → Action** → chọn `Customer Report`.
2. Click **Top SQL ID** → **Tune SQL** → ADDM đề xuất (thường **tạo index**, cải thiện > 99%).
3. **View Details** (so explain plan trước/sau) → **Implement**.

> ⚠️ Nếu Implement báo lỗi do bảng đang bị khóa, đóng bớt session đang giữ lock rồi thử lại. 📘 Module 05 (Practice 7).

---

## 3️⃣ Ứng dụng insert dồn dập, xuất hiện nhiều wait `gc` và `enq: TX/HW`

**Bối cảnh:** Nhiều instance cùng insert vào một bảng khóa chính tăng dần → nhiều block current/CR chuyển qua interconnect; thấy `enq: HW - contention`, `gc current grant`.

**Phân tích:** Sinh khóa chính bằng bảng đếm hoặc **sequence không cache** gây **leaf block contention**; heavy insert tại HWM gây HW enqueue.

**Giải quyết:**

```sql
-- bật/tăng cache sequence (đánh đổi: số không tuần tự giữa các instance)
CREATE SEQUENCE seq_pk CACHE 1000;
-- hoặc mỗi instance dùng dải riêng dựa trên INSTANCE_NUMBER
```

Với HW contention: dùng **extent size lớn, đồng nhất** hoặc **partition** để phân tán insert.

> 📘 Module 05 (RAC Tuning Tips + Practice 7 Case Study sequence).

---

## 4️⃣ Cần áp bản vá bảo mật (PSU) mà gần như không downtime

**Bối cảnh:** Yêu cầu áp PSU lên cả GI home và DB home của cluster production.

**Phân tích:** Nếu patch hỗ trợ **rolling**, áp lần lượt từng node bằng **opatchauto**; service/TAF sẽ failover khi CRS của node đang patch bị hạ.

**Giải quyết:**

```bash
# 0) backup (kể cả VM/shared disk) + tắt cron backup + đọc README
opatch query -all <patch_location> | grep rolling      # xác nhận rolling
# 1) nâng OPatch ở cả GI/DB home, verify:
$ORACLE_HOME/OPatch/opatch lsinventory
# 2) áp trên srv1 (root) — khi thấy "Bringing down CRS..." session failover sang rac2:
export PATH=$PATH:/u01/app/12.2.0/grid/OPatch/
opatchauto apply
# 3) verify rồi lặp lại trên srv2
# 4) hậu kiểm:
```
```sql
SELECT PATCH_ID,VERSION,ACTION,STATUS,DESCRIPTION FROM DBA_REGISTRY_SQLPATCH;
```

> ℹ️ `DBA_REGISTRY_SQLPATCH` chỉ đầy đủ **sau khi patch xong mọi node**. 📘 Module 07 (Practice 11).

---

## 5️⃣ Nâng cấp RAC từ 12.1 lên 12.2

**Bối cảnh:** Cần upgrade toàn bộ stack lên 12.2.

**Phân tích:** Nguyên tắc **GI trước, Database sau**; cài home mới (out-of-place); chạy pre-upgrade tool rồi dùng **DBUA**.

**Giải quyết:**

```bash
# 1) 12.2 cần nhiều dung lượng CRS → mở rộng diskgroup CRS (asmca add disk)
# 2) upgrade GI vào home mới, đặt srv2 = Batch 2 để giữ hệ thống phục vụ:
export ORACLE_HOME=/u01/app/12.2.0/grid ; ./gridSetup.sh   # chọn "Upgrade Oracle GI"
crsctl query crs activeversion
# 3) cài DB 12.2 software only, rồi pre-upgrade:
$OLD_HOME/jdk/bin/java -jar $NEW_HOME/rdbms/admin/preupgrade.jar FILE TEXT DIR /home/oracle/scripts
```
```sql
@/home/oracle/scripts/preupgrade_fixups.sql
EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;  PURGE DBA_RECYCLEBIN;
```
```bash
# 4) DBUA upgrade; 5) post: sửa ORACLE_HOME .bash_profile, postupgrade_fixups.sql, backup lại
```

> 📘 Module 07 (Practice 12).

---

## 6️⃣ Ứng dụng business-critical phải "không gián đoạn" khi mất node

**Bối cảnh:** Giao dịch không được mất và người dùng không được thấy lỗi khi một instance chết.

**Phân tích:** TAF chỉ reconnect + tiếp tục SELECT (rollback transaction). Cần **Application Continuity (AC)** để **replay transaction** và giữ session state.

**Giải quyết:**

```bash
srvctl add service -db rac -service acsrv -preferred rac1 -available rac2 \
  -failovertype TRANSACTION -commit_outcome TRUE \
  -replay_init_time 1800 -failoverretry 30 -failoverdelay 10 \
  -retention 86400 -notification TRUE -rlbgoal SERVICE_TIME -clbgoal SHORT
srvctl start service -db rac -s acsrv
```

Client dùng **JDBC Thin replay driver / UCP**. ⚠️ AC bị vô hiệu nếu dùng **default service**, XA, hoặc một số PL/SQL (UTL_*, autonomous txn...).

> 📘 Module 06 (AC & Transaction Guard, Practice 10).

---

## 7️⃣ Recovery từ node khác bị lỗi vì thiếu snapshot control file

**Bối cảnh:** Luôn backup từ `srv1`; khi cần recover từ `srv2` thì thất bại.

**Phân tích:** Mặc định **snapshot control file** nằm dưới `ORACLE_HOME` của từng node → `srv2` không có bản của `srv1`. Cần đưa về **shared storage**, và bật autobackup vào FRA.

**Giải quyết:**

```sql
-- RMAN
SHOW SNAPSHOT CONTROLFILE NAME;
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '+FRA/RAC/AUTOBACKUP/snapcf_rac.f';
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '+FRA';
```

Khi **restore/recover** trong RAC, cấp channel thủ công tới nhiều instance:

```sql
run {
  ALLOCATE CHANNEL c1 DEVICE TYPE disk CONNECT 'sys/oracle@rac1';
  ALLOCATE CHANNEL c2 DEVICE TYPE disk CONNECT 'sys/oracle@rac2';
  RESTORE DATABASE; RECOVER DATABASE;
}
```

> 📘 Module 04 (Backup & Recovery, Practice 4).

---

## 8️⃣ Hệ thống quá tải — cần thêm node vào cluster (online)

**Bối cảnh:** Workload tăng, cần thêm `srv2` mà không được dừng dịch vụ.

**Phân tích:** RAC cho thêm node **online** sau khi node mới đã đạt prerequisite (network, storage, OS user/group). Ba bước: mở rộng GI home → DB home → thêm instance.

**Giải quyết:**

```bash
# 0) cài cvuqdisk trên node mới (bắt buộc)
CVUQDISK_GRP=oinstall; export CVUQDISK_GRP ; rpm -iv cvuqdisk-1.0.10-1.rpm
# 1) mở rộng GI home (grid):
cluvfy stage -pre nodeadd -n srv2
cd $ORACLE_HOME/addnode ; ./addnode.sh      # Node Role HUB, VIP srv2-vip
# 2) mở rộng DB home (oracle): cd $ORACLE_HOME/addnode ; ./addnode.sh
# 3) thêm instance (dbca): RAC instance management → Add an Instance
srvctl status database -d rac                # thấy instance mới
```

> ⚠️ Ngược lại khi **xóa node**: dbca xóa instance → `deinstall -local` DB home → `deinstall -local` GI home → `crsctl delete node -n srv2` (chạy đúng node!). 📘 Module 12.

---

## 9️⃣ Cần bảo trì phần cứng node đang chạy DB nhỏ nhưng quan trọng

**Bối cảnh:** Một database HA nhưng tải nhẹ chạy trên `srv1`; cần bảo trì `srv1` mà không downtime.

**Phân tích:** Nếu là **RAC One Node**, chỉ cần **online relocation** instance sang node khác trước khi bảo trì. Nếu là single-instance thì cân nhắc chuyển sang RAC One Node.

**Giải quyết:**

```bash
# relocate instance sang srv2, cho 15 phút để transaction hoàn tất
srvctl relocate database -db oradb -node srv2 -w 15 -v
srvctl status database -db oradb          # Online relocation: ACTIVE → hoàn tất
# sau bảo trì, relocate về:
srvctl relocate database -db oradb -node srv1 -w 10 -v
```

> 💡 Dùng **AC/FAN/TAF** để client không bị gián đoạn; quá timeout → ORA-3113. 📘 Module 08 (Practice 13).

---

## 🔟 Hợp nhất nhiều ứng dụng, cách ly tài nguyên & ưu tiên dịch vụ

**Bối cảnh:** Nhiều ứng dụng cần gộp vào ít hạ tầng nhưng phải **cách ly** và ưu tiên app quan trọng khi failover.

**Phân tích:** Kết hợp **Multitenant** (mỗi app một **PDB**) + **Policy-Managed** (server pool + IMPORTANCE) để Clusterware tự phân bổ server và ưu tiên đúng.

**Giải quyết:**

```bash
# server pool: app quan trọng có importance cao hơn
srvctl add srvpool -serverpool spool1 -importance 1 -min 1 -max 2
srvctl add srvpool -serverpool spool2 -importance 0 -min 1 -max 1
# service theo PDB + pool (uniform/singleton)
srvctl add service -db rac -pdb crmpdb -service crmsrv -serverpool spool1 -cardinality uniform
```

Khi một node chết, Clusterware **kéo server sang pool importance cao hơn** (app quan trọng được ưu tiên).

> 💡 Nếu cần **DR** cho cụm này: dựng **Data Guard physical standby RAC** (DB_NAME giống, DB_UNIQUE_NAME khác, `RMAN DUPLICATE FOR STANDBY`). 📘 Module 09, 10, 13.

---

## 📌 Bảng tra nhanh tình huống → module

| # | Tình huống | Module |
|---|------------|--------|
| 1 | Node/instance crash, service failover | 04, 06 |
| 2 | Session/report chậm | 05 |
| 3 | Contention insert (sequence/HW/TX) | 05 |
| 4 | Patch rolling gần như zero-downtime | 07 |
| 5 | Upgrade 12.1 → 12.2 | 07 |
| 6 | Ứng dụng không gián đoạn khi failover (AC) | 06 |
| 7 | Snapshot control file & recovery đa node | 04 |
| 8 | Thêm/xóa node online | 12 |
| 9 | Bảo trì node với RAC One Node | 08 |
| 10 | Consolidation + cách ly + ưu tiên + DR | 09, 10, 13 |

---

⬅️ Về [mục lục khóa học](readme.md)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/scenarios.md`
