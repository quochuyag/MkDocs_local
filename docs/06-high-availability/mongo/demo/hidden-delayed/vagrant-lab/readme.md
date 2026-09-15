---
title: Demo Hidden + Delayed Member — Vagrant lab (4 VMs Ubuntu, full automation)
course: 06-high-availability
source: HA/mongo/demo/hidden-delayed/vagrant-lab/README.md
---

# Demo Hidden + Delayed Member — Vagrant lab (4 VMs Ubuntu, full automation)

Lab production-like để **hiểu sâu** cách giải pháp Hidden + Delayed hoạt động: phục hồi data sau xoá nhầm + dedicated backup host. Mọi thứ tự động hoá — chỉ cần `.\demo.ps1` hoặc `make demo`.

## Khác gì với 2 demo trước

| Demo | Topology | Đặc trưng |
|---|---|---|
| [../../replica-set/vagrant-lab/](../../replica-set/vagrant-lab/) | 3 VMs PSS | HA cơ bản — auto failover |
| [../../sharded-cluster/vagrant-lab/](../../sharded-cluster/vagrant-lab/) | 4 VMs (3 data + 1 mongos) | Horizontal scaling — shard by `userId` hashed |
| **hidden-delayed (lab này)** | 4 VMs (3 visible + 1 hidden+delayed) | **Phục hồi xoá nhầm + dedicated backup** |

Đây là **bổ sung trên top** của Replica Set thường — runbook 04 yêu cầu Replica Set PSS (runbook 01) làm tiền đề.

## Yêu cầu

- **Vagrant 2.3+** và **VirtualBox 7.0+**
- Host RAM ≥ **10 GB** (4 VMs × 2 GB = 8 GB + overhead)
- Subnet `192.168.50.0/24` rảnh (lab này dùng — khác replica-set `.30` và sharded `.40`)

## Quick start

### Windows (PowerShell, native)

```powershell
cd demo\hidden-delayed\vagrant-lab
.\demo.ps1                 # full demo: keyfile + up + smoke + logs (~15 phút)
.\demo.ps1 recover         # ⭐ demo phục hồi data sau xoá nhầm
.\demo.ps1 backup          # ⭐ demo mongodump không impact primary
.\demo.ps1 failover        # priority=0 chặn election
.\demo.ps1 help            # xem tất cả lệnh
```

### Linux / macOS / Git Bash

```bash
cd demo/hidden-delayed/vagrant-lab
make demo
make recover
make backup
make failover
```

## Topology

```text
                Application driver (chỉ thấy 3 visible members)
                                │
                                ▼
  ┌──────────────────────── Visible RS members ──────────────────────┐
  │   hd-node1  192.168.50.11:27017   priority=2  → PRIMARY thường   │
  │   hd-node2  192.168.50.12:27017   priority=1  → SECONDARY        │
  │   hd-node3  192.168.50.13:27017   priority=1  → SECONDARY        │
  └────────────────┬──────────────────────────────────────────────────┘
                   │ heartbeat + oplog (DELAYED ${DELAY}s)
                   ▼
  ┌──────────────────── HIDDEN (driver KHÔNG thấy) ──────────────────┐
  │   hd-node4  192.168.50.14:27017   priority=0  hidden=true        │
  │                                   secondaryDelaySecs=60 (lab)    │
  │                                                  86400 (prod)    │
  │   → Bảo hiểm xoá nhầm + dedicated mongodump host                 │
  └──────────────────────────────────────────────────────────────────┘
```

Replica set: `rs0`, oplog 2048 MB (lab — đủ cho delay 60s × 30×), WiredTiger cache 0.5 GB.

## Pipeline `vagrant up`

1. **Sinh keyFile** — `.\demo.ps1 keyfile` hoặc `make keyfile`
2. **vagrant up** — boot 4 VMs Ubuntu, provisioner tự:
   - Cài MongoDB 8.0 community
   - Copy keyFile (mode 400, owner mongodb)
   - Ghi `/etc/mongod.conf` với `replSet=rs0`, `keyFile`, `authorization=enabled`, `oplogSizeMB=2048`
   - **Chỉ trên hd-node1**: 
     1. `rs.initiate()` với 4 members (node4 priority=0 ngay từ đầu, CHƯA hidden/delayed)
     2. Tạo `admin` / `appuser` / `backupuser`
     3. Insert 5 sample docs vào `demo.events`
     4. **Đợi hd-node4 thành SECONDARY** (initial sync xong)
     5. `rs.reconfig` → bật `hidden=true` + `secondaryDelaySecs=60` trên hd-node4

Total: **~15 phút** lần đầu (download box + cài MongoDB × 4 VMs).

## Demo flows đặc trưng

### `recover` — Phục hồi data sau xoá nhầm ⭐

Đây là use case **#1** cho Hidden+Delayed:

```powershell
.\demo.ps1 recover   # hoặc: make recover
```

Pipeline 10 bước:

1. Insert 50 docs vào `demo.recovery_test` trên PRIMARY
2. Đợi (delay + 10s) → hd-node4 đã có 50 docs
3. Verify count = 50 trên hd-node4
4. **⚠ Mô phỏng fat-finger**: `deleteMany({})` trên PRIMARY
5. Kiểm tra hd-node4: **vẫn còn 50 docs** (delete chưa propagate, còn `delay` s buffer)
6. `fsyncLock` hd-node4 → đóng băng để chắc chắn
7. `mongodump` từ hd-node4 → `/tmp/recovery`
8. `fsyncUnlock` hd-node4
9. `mongorestore` → `demo.recovery_restored` trên PRIMARY
10. Verify

**Window phục hồi = delay (60s lab / 24h production)**.

### `backup` — mongodump không impact primary ⭐

```powershell
.\demo.ps1 backup    # hoặc: make backup
```

Dump trực tiếp từ hd-node4 (`hidden=true` → traffic 0):
- `mongodump --oplog --gzip` → consistent point-in-time snapshot
- Authenticate với `backupuser` (role `backup` + `restore`)
- KHÔNG ảnh hưởng IO/CPU của PRIMARY

### `failover` — assert priority=0 hoạt động

```powershell
.\demo.ps1 failover  # hoặc: make failover
```

1. Halt PRIMARY + 1 visible secondary → chỉ còn 1 visible + hd-node4
2. Đợi election (20s)
3. Verify PRIMARY mới là **visible secondary** (KHÔNG phải hd-node4)
4. Verify hd-node4 vẫn `SECONDARY` dù còn data tươi nhất

## Tinh chỉnh

### Đổi delay (mặc định 60s)

```powershell
# Windows
$env:DEMO_DELAY_SECS = '120'
.\demo.ps1 demo

# Production khuyến nghị: 86400 (24h)
$env:DEMO_DELAY_SECS = '86400'
.\demo.ps1 demo
# Lưu ý: phải tăng oplogSizeMB tương ứng (xem Vagrantfile)
```

### Đổi password

```powershell
$env:DEMO_ADMIN_PWD = 'MyStrong'
$env:DEMO_APP_PWD   = 'AppStrong'
.\demo.ps1 demo
```

## Cấu hình quan trọng

| Knob | Lab | Production khuyến nghị |
|---|---|---|
| `secondaryDelaySecs` | 60 | 86400 (24h) |
| `oplogSizeMB` | 2048 | ≥ delay × 2 × peakWriteRate |
| `votes` (hd-node4) | 1 | 0 nếu muốn 3-voter cluster (tránh even voters) |
| `priority` (hd-node4) | 0 | 0 (hard) |
| `hidden` (hd-node4) | true | true (hard) |
| disk size (hd-node4) | ≈ primary | ≈ primary + 20% buffer |

## Khi nào KHÔNG dùng Hidden+Delayed

- Có Atlas / managed backup tự động → đã có PITR (point-in-time restore) tới 5 phút trước → đơn giản hơn
- Workload write rất cao (>10k writes/s) + delay 24h → oplog phải khổng lồ
- Chỉ có 3 nodes total → bỏ 1 thành hidden → giảm fault tolerance còn 2/3 vs 3/4

Xem **runbook 04** (`runbooks/04-hidden-delayed.md`) cho chi tiết trade-offs.

## Cleanup

```powershell
.\demo.ps1 destroy     # chỉ xoá VMs
.\demo.ps1 clean       # destroy + xoá keyfile + .vagrant/
.\demo.ps1 clean-all   # clean + kill stale VBox + (giữ box image)
```

## Cấu trúc thư mục

```
demo/hidden-delayed/vagrant-lab/
├── Vagrantfile              # 4 VMs + auto initiate + reconfig hidden+delayed
├── demo.ps1                 # PowerShell wrapper (14 actions)
├── Makefile                 # bash equivalents
├── demo-smoke-test.sh       # verify rs.conf + db.hello + oplog
├── demo-recovery.sh         # ⭐ phục hồi data từ delayed member
├── demo-backup.sh           # ⭐ mongodump từ hidden member
├── demo-failover.sh         # assert priority=0 hoạt động
├── provision/
│   ├── setup-keyfile.sh     # sinh shared keyFile
│   └── keyfile              # (gitignored — sinh local)
├── logs/                    # dump per-run (auto-created bởi action `logs`)
└── README.md                # file này
```

## Tham khảo

- Runbook: [`runbooks/04-hidden-delayed.md`](../../../runbooks/004-hidden-delayed.md)
- Scripts production: [`scripts/hidden-delayed/`](../../../scripts/hidden-delayed/)
- MongoDB docs:
  - https://www.mongodb.com/docs/manual/core/replica-set-hidden-member/
  - https://www.mongodb.com/docs/manual/core/replica-set-delayed-member/


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/hidden-delayed/vagrant-lab/README.md`
