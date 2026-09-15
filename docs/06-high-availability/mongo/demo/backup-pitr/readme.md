---
title: 'Demo — Backup & Point-In-Time Recovery (1 path: Vagrant)'
course: 06-high-availability
source: HA/mongo/demo/backup-pitr/README.md
---

# Demo — Backup & Point-In-Time Recovery (1 path: Vagrant)

Giải pháp **backup logical (mongodump) + continuous oplog backup + restore tới thời điểm bất kỳ** — runbook 05. Lab có 4 VMs: 3 mongod RS + 1 backup operator host (tách rời cluster, chỉ chạy tools).

| Path | Setup | RAM | Mục tiêu |
|---|---|---|---|
| [**Vagrant lab tự động**](vagrant-lab/) | ~15 phút | ~9 GB | Hiểu sâu chuỗi base dump + oplog tail + PITR restore với `--oplogLimit` |

**Fully automated** — `.\demo.ps1` (Windows) hoặc `make demo` (Linux/macOS/Git Bash).

## Khi nào dùng demo này

- Cluster nhỏ (< 500 GB) cần backup logical + PITR
- Muốn hiểu cơ chế bên trong: `mongodump --oplog` capture gì, `oplog-tail` query gì, `--oplogLimit` hoạt động ra sao
- Cần training DBA: kịch bản fat-finger `dropDatabase` + phục hồi chính xác

❌ **KHÔNG cần** demo này nếu:

- Dùng Atlas / managed MongoDB → đã có continuous backup + PITR tới 5 phút
- Cluster > 500 GB → chuyển sang **filesystem snapshot** (LVM/EBS) hoặc **Percona PBM**
- Sharded cluster → bắt buộc PBM (coordinated backup config + shard cùng lúc)

## Quick start

```powershell
cd demo\backup-pitr\vagrant-lab
.\demo.ps1                # full pipeline (~15 phút)
.\demo.ps1 backup         # base mongodump --oplog từ SECONDARY
.\demo.ps1 oplog-tail     # 1 chu kỳ continuous oplog backup
.\demo.ps1 pitr           # ⭐ phục hồi tới point-in-time TRƯỚC sự cố (đặc trưng)
.\demo.ps1 failover       # RS election cơ bản (sanity)
```

Xem chi tiết tại [vagrant-lab/README.md](vagrant-lab/readme.md).

## So sánh với 3 demo trước

| | Replica Set | Sharded Cluster | Hidden+Delayed | **Backup+PITR (đây)** |
|---|---|---|---|---|
| VMs | 3 | 4 (3 data + 1 mongos) | 4 (3 visible + 1 hidden) | 4 (3 RS + **1 operator tách rời**) |
| RAM | ~6 GB | ~10 GB | ~10 GB | ~9 GB |
| Subnet | 192.168.30.0/24 | 192.168.40.0/24 | 192.168.50.0/24 | 192.168.60.0/24 |
| App connect | thấy 3 nodes | qua mongos | chỉ thấy 3 visible | thấy 3 nodes |
| Use case unique | HA cơ bản | Horizontal scaling | Phục hồi xoá nhầm tức thì | **Phục hồi tới timestamp bất kỳ** |
| Recovery window | Không có | Không có | `secondaryDelaySecs` (lab: 60s, prod: 24h) | Toàn bộ oplog history (vài giờ–vài ngày) |

## Demo flows đặc trưng

- `.\demo.ps1 backup`     — `/backup/scripts/mongodump.sh` từ bp-node2 (SECONDARY) → `/backup/dumps/dump-<ts>/`
- `.\demo.ps1 oplog-tail` — `/backup/scripts/oplog-tail.sh` archive oplog window `(last_ts, now]` → `/backup/oplog/oplog-<from>-<to>.bson.gz`
- `.\demo.ps1 pitr`       — **11 bước**: baseline → base dump → legit txns → archive 1 → capture safe_ts → drop → archive 2 → pitr-restore = base + archive 1 (skip archive 2 vì to_ts > safe_ts) → verify

## So sánh với Hidden+Delayed (cùng nhằm "phục hồi sau sự cố")

| | Hidden+Delayed | Backup+PITR (đây) |
|---|---|---|
| Cơ chế | 1 RS member apply oplog chậm N giây | Snapshot + oplog archives lưu offline |
| Recovery window | Cố định = `secondaryDelaySecs` | Tới ts bất kỳ trong oplog history |
| Storage | Bằng kích thước data (member full copy) | Compressed dump + oplog archives (nén tốt) |
| Recovery time | ~ thời gian `mongodump` từ delayed | ~ thời gian `mongorestore` base + replay archives |
| Lostness | Mất khi delayed member crash + chưa kịp dump | Bền hơn — dump nằm ở /backup, có thể S3 |
| Operational | Chỉ cần `fsyncLock` + `mongodump` | Cron 2 lớp (daily dump + 5-min oplog) |

**Kết hợp tốt nhất**: dùng cả hai. Hidden+delayed cho recovery tức thì trong window 24h; PITR cho recovery xa hơn (vài ngày–vài tuần).

## Tham khảo

- [Runbook 05 — Backup & Point-In-Time Recovery](../../runbooks/005-backup-and-pitr.md)
- [demo/replica-set/](../replica-set/) — RS PSS thuần (tiền đề)
- [demo/hidden-delayed/](../hidden-delayed/) — giải pháp recovery window cố định
- [scripts/backup-pitr/](../../scripts/backup-pitr/) — scripts production gốc (mongodump.sh / oplog-tail.sh / pitr-restore.sh)


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/backup-pitr/README.md`
