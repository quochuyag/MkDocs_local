---
title: Demo Backup & Point-In-Time Recovery — Vagrant lab (4 VMs Ubuntu, full automation)
course: 06-high-availability
source: HA/mongo/demo/backup-pitr/vagrant-lab/README.md
---

# Demo Backup & Point-In-Time Recovery — Vagrant lab (4 VMs Ubuntu, full automation)

Lab production-like để **hiểu sâu** cách giải pháp Backup + PITR hoạt động: base dump + continuous oplog backup + restore tới một thời điểm cụ thể trước khi xảy ra sự cố. Mọi thứ tự động hoá — chỉ cần `.\demo.ps1` hoặc `make demo`.

## Khác gì với 3 demo trước

| Demo | Topology | Đặc trưng |
|---|---|---|
| [../../replica-set/vagrant-lab/](../../replica-set/vagrant-lab/) | 3 VMs PSS | HA cơ bản — auto failover |
| [../../sharded-cluster/vagrant-lab/](../../sharded-cluster/vagrant-lab/) | 4 VMs (3 data + 1 mongos) | Horizontal scaling — shard by `userId` hashed |
| [../../hidden-delayed/vagrant-lab/](../../hidden-delayed/vagrant-lab/) | 4 VMs (3 visible + 1 hidden/delayed) | Phục hồi xoá nhầm + dedicated backup |
| **backup-pitr (lab này)** | 4 VMs (3 RS data + 1 backup operator) | **Backup logical + PITR tới timestamp cụ thể** |

Đây là **bổ sung trên top** của Replica Set thường — Runbook 05 yêu cầu Replica Set PSS (Runbook 01) làm tiền đề.

## Yêu cầu

- **Vagrant 2.3+** và **VirtualBox 7.0+**
- Host RAM ≥ **9 GB** (3×2GB + 1×1.5GB + overhead)
- Subnet `192.168.60.0/24` rảnh (lab này dùng — khác replica-set `.30`, sharded `.40`, hidden-delayed `.50`)

## Quick start

### Windows (PowerShell, native)

```powershell
cd demo\backup-pitr\vagrant-lab
.\demo.ps1                 # full demo: keyfile + up + smoke + logs (~15 phút)
.\demo.ps1 backup          # base mongodump --oplog từ SECONDARY
.\demo.ps1 oplog-tail      # 1 chu kỳ continuous oplog backup
.\demo.ps1 pitr            # ⭐ phục hồi tới point-in-time TRƯỚC sự cố
.\demo.ps1 failover        # RS election cơ bản
.\demo.ps1 help            # xem tất cả lệnh
```

### Linux / macOS / Git Bash

```bash
cd demo/backup-pitr/vagrant-lab
make demo
make backup
make oplog-tail
make pitr
make failover
```

## Topology

```text
                Application driver
                       │
                       ▼
  ┌────────────── Replica Set rs0 (PSS) ──────────────────────────────┐
  │   bp-node1   192.168.60.11:27017   priority=2  → PRIMARY thường   │
  │   bp-node2   192.168.60.12:27017   priority=1  → SECONDARY        │
  │   bp-node3   192.168.60.13:27017   priority=1  → SECONDARY        │
  └────────────────┬──────────────────────────────────────────────────┘
                   │ oplog replication
                   ▼
  ┌────────────── BACKUP OPERATOR (KHÔNG join cluster) ───────────────┐
  │   bp-backup  192.168.60.20                                        │
  │   - mongosh + mongodump + mongorestore (mongod disabled)          │
  │   - /backup/dumps/   ← base mongodump --oplog --gzip              │
  │   - /backup/oplog/   ← archive .bson.gz từng chu kỳ tail          │
  │   - /backup/scripts/ ← mongodump.sh / oplog-tail.sh / pitr-...    │
  │   - Target backup: bp-node2 (SECONDARY) — không impact primary    │
  └───────────────────────────────────────────────────────────────────┘
```

Replica set: `rs0`, oplog 1024 MB (lab), WiredTiger cache 0.5 GB, db `bank.accounts`.

## Pipeline `vagrant up`

1. **Sinh keyFile** — `.\demo.ps1 keyfile` hoặc `make keyfile`
2. **vagrant up** — boot 4 VMs Ubuntu 22.04, provisioner tự:
   - Cài MongoDB 8.0 community (mọi node)
   - Copy keyFile (mode 400, owner mongodb)
   - **bp-node1/2/3:** ghi `/etc/mongod.conf` với `replSet=rs0`, `keyFile`, `authorization=enabled`, `oplogSizeMB=1024`
   - **bp-backup:** `systemctl disable mongod`, tạo `/backup/{dumps,oplog,scripts}`, ghi 3 scripts (`mongodump.sh`, `oplog-tail.sh`, `pitr-restore.sh`) + `/backup/env.sh`
   - **Chỉ trên bp-node1:**
     1. `rs.initiate()` với 3 members PSS
     2. Tạo `admin` / `appuser` / **`backupuser`** (role `backup` + `restore` + `read on local`)
     3. Insert 5 baseline accounts vào `bank.accounts`

Total: **~15 phút** lần đầu (download box + cài MongoDB × 4 VMs).

## Demo flows đặc trưng

### `pitr` — Phục hồi tới Point-In-Time ⭐

Đây là use case **#1** cho Backup+PITR:

```powershell
.\demo.ps1 pitr   # hoặc: make pitr
```

Pipeline 11 bước:

1. Reset `bank` DB — bắt đầu sạch
2. Insert 5 baseline accounts (`A001..A005`)
3. **Base mongodump** `--oplog --gzip` → `/backup/dumps/dump-<ts>/`
4. 3 transactions LEGIT (deposit + withdraw) — cần được PHỤC HỒI
5. **oplog-tail ARCHIVE-1** (chứa 3 txn legit)
6. Capture `SAFE_TS` = oplog ts hiện tại
7. ⚠ **DISASTER:** `dropDatabase('bank')` trên PRIMARY
8. **oplog-tail ARCHIVE-2** (chứa lệnh drop)
9. Verify cluster: dữ liệu MẤT SẠCH
10. `pitr-restore.sh BASE_DUMP SAFE_TS` → restore base + replay ARCHIVE-1 (skip ARCHIVE-2)
11. Verify: baseline + 3 legit txns hiện diện, drop KHÔNG được apply

**Cốt lõi:** `mongorestore --oplogReplay --oplogLimit=<SAFE_TS>:0` đảm bảo replay dừng ngay tại safe point.

### `backup` — Base mongodump

```powershell
.\demo.ps1 backup    # hoặc: make backup
```

Chạy `/backup/scripts/mongodump.sh` từ bp-backup:
- Target `bp-node2` (SECONDARY) → không impact PRIMARY
- `--oplog` capture oplog window → consistent point-in-time snapshot
- `--gzip` compress for storage efficiency
- Output: `/backup/dumps/dump-<UTC-ts>/{bank,oplog.bson}`

### `oplog-tail` — Continuous oplog backup

```powershell
.\demo.ps1 oplog-tail   # hoặc: make oplog-tail
```

1 chu kỳ:
- Đọc `/backup/oplog/.last-ts` (checkpoint ts cuối)
- Query `local.oplog.rs` cho khoảng `(last_ts, current_ts]`
- Dump archive `.bson.gz` ra `/backup/oplog/oplog-<from>-<to>.bson.gz`
- Cập nhật `.last-ts = current_ts`

Production: `*/5 * * * *` (RPO ≤ 5 phút).

### `failover` — RS election cơ bản

```powershell
.\demo.ps1 failover   # hoặc: make failover
```

Halt PRIMARY → đợi 20s → verify PRIMARY mới → boot lại member cũ. Demonstrate cluster vẫn dùng được sau failover; oplog-tail tiếp tục từ checkpoint cũ.

## Cấu hình quan trọng

| Knob | Lab | Production khuyến nghị |
|---|---|---|
| `oplogSizeMB` | 1024 | Cover ≥ khoảng giữa 2 base dump kế tiếp + buffer |
| Chu kỳ `mongodump` | thủ công | Daily 02:00 (cron) |
| Chu kỳ `oplog-tail` | thủ công | `*/5 * * * *` (RPO ≤ 5 phút) |
| Storage tier | local `/backup/` | Local + S3 sync (rclone / aws s3 sync) |
| Retention | tuỳ | Dump 7 ngày, oplog 30 ngày, monthly full 12 tháng |
| Backup target | `bp-node2` SECONDARY | Hidden+delayed member (xem demo `hidden-delayed`) |

## Đổi password

```powershell
$env:DEMO_ADMIN_PWD = 'MyStrong'
$env:DEMO_APP_PWD   = 'AppStrong'
.\demo.ps1 demo
```

## Khi nào KHÔNG dùng giải pháp này

- **Cluster > 500 GB** — `mongodump` quá chậm; chuyển sang **filesystem snapshot** (LVM/EBS) hoặc **Percona PBM**.
- **Sharded cluster** — phải coordinated backup (PBM) để snapshot config + tất cả shard cùng lúc.
- **Atlas / managed** — đã có PITR built-in tới 5 phút (snapshot continuous + oplog tail tự động).

Xem **Runbook 05** (`runbooks/05-backup-and-pitr.md`) cho chi tiết trade-offs và §6 (sharded cluster considerations).

## Cleanup

```powershell
.\demo.ps1 destroy     # chỉ xoá VMs
.\demo.ps1 clean       # destroy + xoá keyfile + .vagrant/
.\demo.ps1 clean-all   # clean + kill stale VBox + (giữ box image)
```

## Cấu trúc thư mục

```
demo/backup-pitr/vagrant-lab/
├── Vagrantfile              # 4 VMs + auto initiate RS + cấu hình bp-backup
├── demo.ps1                 # PowerShell wrapper (14 actions)
├── Makefile                 # bash equivalents
├── demo-smoke-test.sh       # verify rs.status + tools
├── demo-backup.sh           # mongodump --oplog từ secondary
├── demo-oplog-tail.sh       # 1 chu kỳ oplog-tail
├── demo-pitr.sh             # ⭐ phục hồi point-in-time (11 bước)
├── demo-failover.sh         # RS election cơ bản
├── provision/
│   ├── setup-keyfile.sh     # sinh shared keyFile
│   └── keyfile              # (gitignored — sinh local)
├── logs/                    # dump per-run (auto-created bởi action `logs`)
└── README.md                # file này
```

## Scripts trên bp-backup (sinh bởi provisioner)

| File | Mục đích |
|---|---|
| `/backup/env.sh` | Biến chung: RS_NAME, NODE1/2/3, USER/PWD, BACKUP_ROOT, log() |
| `/backup/scripts/mongodump.sh` | Base dump `--oplog --gzip` từ SECONDARY |
| `/backup/scripts/oplog-tail.sh` | Continuous oplog archive (`ts > last_ts && ts <= now`) |
| `/backup/scripts/pitr-restore.sh` | Restore base + replay archives với `--oplogLimit` |
| `/backup/dumps/` | Base dumps (mỗi lần dump 1 thư mục) |
| `/backup/oplog/` | Archives + `.last-ts` checkpoint |

## Tham khảo

- Runbook: [`runbooks/05-backup-and-pitr.md`](../../../runbooks/005-backup-and-pitr.md)
- Scripts production: [`scripts/backup-pitr/`](../../../scripts/backup-pitr/)
- MongoDB docs:
  - https://www.mongodb.com/docs/manual/core/backups/
  - https://www.mongodb.com/docs/database-tools/mongodump/
  - https://www.mongodb.com/docs/manual/tutorial/restore-replica-set-from-backup/
- Percona PBM (sharded cluster): https://docs.percona.com/percona-backup-mongodb/


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/backup-pitr/vagrant-lab/README.md`
