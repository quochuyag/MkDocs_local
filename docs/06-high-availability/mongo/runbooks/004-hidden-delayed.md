---
title: Runbook 04 — Hidden & Delayed Member
course: 06-high-availability
source: HA/mongo/runbooks/04-hidden-delayed.md
---

# Runbook 04 — Hidden & Delayed Member

## 1. Khi nào dùng

Bổ sung trên top của **Replica Set (Runbook 01)** — chuyển 1 secondary thành:
- **hidden=true**: driver app không thấy → không route đọc → traffic 0.
- **priority=0**: không bao giờ thành primary (kể cả khi primary chết).
- **secondaryDelaySecs=N**: chậm N giây so với primary (phổ biến: 24h = 86400).

Mục đích:
1. **Bảo hiểm xoá nhầm**: 30 phút sau khi ai đó `db.users.deleteMany({})` trên primary, vẫn còn data lành lặn trên delayed secondary để dump.
2. **Backup dedicated host**: hidden+priority=0 → không phục vụ traffic → chạy `mongodump` thoải mái mà không tốn IO primary.
3. **Reporting/ETL**: hidden member chỉ phục vụ 1 job batch nightly (read pref tag).

## 2. Tiền đề

- RS PSS đã chạy (Runbook 01).
- Đã có member thứ 4 hoặc dùng 1 trong 3 members hiện tại (giảm fault tolerance — nếu muốn giữ 3 voters thì add thêm node4).

## 3. Các bước

### Trường hợp A — Dùng member hiện tại (3 nodes, chấp nhận 2/3 voters bình thường)
```bash
# Trên node1 (primary), chuyển node3 thành hidden+delayed 24h:
bash /vagrant/scripts/hidden-delayed/add-delayed-member.sh node3:27017 86400
```

### Trường hợp B — Thêm node thứ 4 dành riêng (khuyến nghị production)
```bash
# Cài MongoDB trên node4 (xem common scripts), join RS:
bash /vagrant/scripts/replica-set/ops.sh add node4:27017 0
# Chuyển thành hidden + delayed:
bash /vagrant/scripts/hidden-delayed/add-delayed-member.sh node4:27017 86400
```

## 4. Verify

```bash
mongosh -u admin -p --eval 'rs.conf().members.forEach(m => print(m.host + " pri=" + m.priority + " hidden=" + !!m.hidden + " delay=" + (m.secondaryDelaySecs||0) + "s"))'
```
Output kỳ vọng cho member delayed:
```
node3:27017 pri=0 hidden=true delay=86400s
```

## 5. Vận hành — Recovery khi xoá nhầm

Giả sử lúc 10:00 ai đó chạy `db.events.deleteMany({})` trên primary. Bạn nhận alert lúc 10:05.

```bash
# B1. Stop replication trên delayed member để "đóng băng" state lúc 09:00 (24h trước):
mongosh -u admin -p --host node3:27017 --eval 'db.adminCommand({fsync:1, lock:true})'

# B2. Dump collection từ delayed member:
mongodump --host node3:27017 -u admin -p ... --authenticationDatabase admin \
  --db appdb --collection events --out /tmp/recovery

# B3. Unlock delayed member:
mongosh -u admin -p --host node3:27017 --eval 'db.fsyncUnlock()'

# B4. Restore lên primary (collection riêng để không đè nguyên primary):
mongorestore --host node1:27017 -u admin -p ... --authenticationDatabase admin \
  --nsFrom 'appdb.events' --nsTo 'appdb.events_recovered' /tmp/recovery

# B5. Merge/swap collection trong app logic.
```

## 6. Vận hành — Backup từ hidden member

```bash
# Backup không impact primary:
mongodump --host node3:27017 -u backupuser -p ... --authenticationDatabase admin \
  --oplog --gzip --out /var/backups/mongo/dump-$(date -u +%Y%m%dT%H%M%SZ)
```

## 7. Trade-offs

| Khía cạnh | Tác động |
|---|---|
| Voters | Member hidden vẫn vote (mặc định). Set `votes:0` nếu không muốn nó tham gia election. |
| Disk | Delayed member chứa data hiện tại + chậm N giây. Cần disk ≈ primary. |
| Oplog | Oplog window của delayed member phải > delay + buffer (24h delay → cần oplog ≥ 48h). |
| Failover | Hidden + priority=0 → không bao giờ thành primary. Nếu cần promote (DR): `force-reconfig` để clear hidden + priority. |

## 8. Promote delayed → primary (DR scenario)

```bash
# Khi primary + secondary thường mất hết, chỉ còn delayed member:
mongosh -u admin -p --host node3:27017 --eval '
var cfg = rs.conf();
cfg.members = cfg.members.filter(m => m.host === "node3:27017");
cfg.members[0].priority = 1;
cfg.members[0].hidden = false;
cfg.members[0].secondaryDelaySecs = 0;
rs.reconfig(cfg, {force:true});
'
# CHẤP NHẬN MẤT ≤24h data — delayed member chậm 24h.
```

## 9. Tham khảo

- https://www.mongodb.com/docs/manual/core/replica-set-hidden-member/
- https://www.mongodb.com/docs/manual/core/replica-set-delayed-member/


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/04-hidden-delayed.md`
