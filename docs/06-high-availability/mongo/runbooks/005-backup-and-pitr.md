---
title: Runbook 05 — Backup & Point-In-Time Recovery (PITR)
course: 06-high-availability
source: HA/mongo/runbooks/05-backup-and-pitr.md
---

# Runbook 05 — Backup & Point-In-Time Recovery (PITR)

## 1. Tổng quan

3 chiến lược backup chính của MongoDB:

| Phương thức | Tốc độ | Storage | PITR | Khi nào dùng |
|---|---|---|---|---|
| `mongodump --oplog` (logical) | Chậm (re-read mọi doc) | Nén tốt | Có (--oplogReplay) | Cluster nhỏ < 500 GB |
| Filesystem snapshot (LVM/EBS) | Nhanh (~vài phút) | Bằng disk usage | Có (cộng oplog tail) | Production size lớn |
| Percona PBM / Ops Manager | Tích hợp | Variable | Có | Sharded cluster, multi-RS |

Tài liệu này cover 2 phương pháp đầu — tự host bằng scripts.

## 2. Logical backup (mongodump)

### B1. Dump consistent snapshot
```bash
# Chạy trên mgmt host (hoặc hidden member để giảm impact):
bash /vagrant/scripts/backup-pitr/mongodump.sh node3:27017
# Output: /var/backups/mongo/dump-20260515T120000Z/
```
`--oplog` flag dump kèm oplog window trong lúc dump → restore lại có thể replay để đạt consistency point cuối dump.

### B2. Restore toàn bộ
```bash
bash /vagrant/scripts/backup-pitr/mongorestore.sh /var/backups/mongo/dump-20260515T120000Z node1:27017
```

### B3. Lịch chạy (cron)
```cron
# /etc/cron.d/mongo-backup — mỗi ngày 02:00 dump từ hidden member
0 2 * * * root bash /vagrant/scripts/backup-pitr/mongodump.sh node3:27017 >> /var/log/mongo-backup.log 2>&1
```

## 3. Filesystem snapshot (production)

### Tiền đề
- `dbPath` (`/var/lib/mongodb`) nằm trên **LVM logical volume** hoặc **EBS volume**.
- Chạy snapshot trên **SECONDARY** (không phải primary) — `fsyncLock()` block writes.

### B1. Snapshot
```bash
# Trên secondary node2:
bash /vagrant/scripts/backup-pitr/fs-snapshot.sh --vg vg_mongo --lv lv_data
# Script: fsyncLock → lvcreate snapshot → fsyncUnlock
```

### B2. Copy snapshot sang storage backup
```bash
mount /dev/vg_mongo/lv_data-snap-20260515T120000Z /mnt/snap
tar czf /var/backups/mongo/snap-20260515T120000Z.tar.gz -C /mnt/snap .
umount /mnt/snap
lvremove -f /dev/vg_mongo/lv_data-snap-20260515T120000Z
```

### B3. Restore
```bash
# Stop mongod, replace data dir:
systemctl stop mongod
mv /var/lib/mongodb /var/lib/mongodb.broken
mkdir /var/lib/mongodb
tar xzf /var/backups/mongo/snap-20260515T120000Z.tar.gz -C /var/lib/mongodb
chown -R mongodb:mongodb /var/lib/mongodb
systemctl start mongod
# Node sẽ rejoin RS qua initial sync nếu lag quá oplog window.
```

## 4. PITR — Continuous oplog tail + replay

Mục tiêu RPO ≈ 5 phút (theo cron) hoặc < 1 phút (daemon).

### B1. Setup oplog tail (cron mỗi 5 phút)
```cron
# /etc/cron.d/mongo-oplog
*/5 * * * * root bash /vagrant/scripts/backup-pitr/oplog-tail.sh node2:27017 >> /var/log/mongo-oplog.log 2>&1
```
Script lưu state ở `${OPLOG_BACKUP_DIR}/.last-ts` và dump oplog từ ts đó tới hiện tại.

### B2. Restore tới một thời điểm cụ thể
```bash
# Giả sử sự cố lúc 14:32:17 UTC = 1758804737 Unix.
# Có:  base dump lúc 02:00 = dump-20260515T020000Z
#      oplog archives mỗi 5 phút từ 02:05 đến hiện tại trong /var/backups/mongo/oplog/
bash /vagrant/scripts/backup-pitr/pitr-restore.sh \
  /var/backups/mongo/dump-20260515T020000Z \
  1758804737 \
  node1:27017
# Script: restore dump base, sau đó apply lần lượt các archive oplog có toT ≤ target_ts.
```

### B3. Verify
```bash
# So sánh document count trước/sau, hoặc check 1 row vừa được tạo trước thời điểm cố:
mongosh "mongodb://admin:<pwd>@node1:27017/admin" --eval '
db.getSiblingDB("appdb").events.find({createdAt: {$lt: ISODate("2026-05-15T14:32:18Z")}}).sort({createdAt:-1}).limit(1)
'
```

## 5. Test restore monthly (BẮT BUỘC)

Backup không test = không backup. Lịch trình:
- **Hàng tuần**: restore vào sandbox VM, đếm record, verify checksum 1 collection.
- **Hàng tháng**: PITR đầy đủ, app smoke test (login, write, read).
- **Hàng quý**: chaos test — destroy primary + restore từ backup.

Sample test:
```bash
vagrant ssh mgmt
bash /vagrant/scripts/backup-pitr/mongorestore.sh /var/backups/mongo/dump-latest node1:27017
mongosh -u appuser -p ... --host node1:27017/appdb --eval 'db.events.countDocuments()'
```

## 6. Sharded cluster — special considerations

- **Stop balancer** trước khi snapshot, otherwise chunks di chuyển trong lúc backup → metadata inconsistent.
- Snapshot **đồng thời** config server + tất cả shards (timestamp lệch nhau ≤ vài giây).
- Production: dùng **Percona Backup for MongoDB (PBM)** — coordinator backup nhất quán cho sharded cluster:
  ```bash
  # Trên mỗi node + mongos:
  apt install percona-backup-mongodb
  pbm config --file pbm-config.yml
  pbm backup --type=physical    # full
  pbm restore <backup-name>
  ```

## 7. Retention policy đề xuất

| Backup type | Retention | Storage |
|---|---|---|
| Dump hàng ngày | 7 days | Local + S3 |
| Filesystem snapshot | 14 days | S3 / NAS |
| Oplog archive | 30 days | S3 |
| Backup tháng (full) | 12 months | S3 Glacier |

## 8. Tham khảo

- https://www.mongodb.com/docs/manual/core/backups/
- https://www.mongodb.com/docs/database-tools/mongodump/
- https://docs.percona.com/percona-backup-mongodb/


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/05-backup-and-pitr.md`
