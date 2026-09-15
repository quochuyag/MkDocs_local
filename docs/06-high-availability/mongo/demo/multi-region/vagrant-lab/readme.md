---
title: Demo Multi-Region (Stretched Replica Set) — Vagrant lab (4 VMs, full automation)
course: 06-high-availability
source: HA/mongo/demo/multi-region/vagrant-lab/README.md
---

# Demo Multi-Region (Stretched Replica Set) — Vagrant lab (4 VMs, full automation)

Lab production-like để **hiểu sâu** giải pháp HA cross-region: 1 replica set kéo dài 2 "data center", mất hoàn toàn 1 DC vẫn phục hồi được bằng force-reconfig. Mọi thứ tự động hoá — chỉ cần `.\demo.ps1` (Windows) hoặc `make demo` (Linux/macOS/Git Bash).

## Khác gì với 4 demo trước

| Demo | Topology | Đặc trưng |
|---|---|---|
| [../../replica-set/vagrant-lab/](../../replica-set/vagrant-lab/) | 3 VMs PSS | HA cơ bản — auto failover trong 1 DC |
| [../../sharded-cluster/vagrant-lab/](../../sharded-cluster/vagrant-lab/) | 4 VMs (3 data + 1 mongos) | Horizontal scaling — shard by `userId` hashed |
| [../../hidden-delayed/vagrant-lab/](../../hidden-delayed/vagrant-lab/) | 4 VMs (3 visible + 1 hidden+delayed) | Phục hồi xoá nhầm + dedicated backup |
| [../../backup-pitr/vagrant-lab/](../../backup-pitr/vagrant-lab/) | 4 VMs (3 mongod + 1 backup operator) | mongodump + oplog tail + PITR |
| **multi-region (lab này)** | 4 VMs (3 DC-A voters + 1 DC-B DR) | **DR cross-region — force-reconfig khi 1 DC mất** |

Đây là **bổ sung trên top** của Replica Set thường — runbook 06 yêu cầu Replica Set PSS (runbook 01) làm tiền đề, mở rộng sang 2 region.

## Yêu cầu

- **Vagrant 2.3+** và **VirtualBox 7.0+**
- Host RAM ≥ **10 GB** (4 VMs × 2 GB = 8 GB + overhead)
- Subnet `192.168.70.0/24` rảnh (khác replica-set `.30`, sharded `.40`, hidden-delayed `.50`, backup-pitr `.60`)

## Quick start

### Windows (PowerShell, native)

```powershell
cd demo\multi-region\vagrant-lab
.\demo.ps1                  # full demo: keyfile + up + smoke + logs (~15 phút)
.\demo.ps1 latency          # đo w:majority vs cross-region read latency
.\demo.ps1 dr-failover      # ⭐ DC-A chết toàn bộ, promote mr-dr
.\demo.ps1 dr-failback      # khôi phục DC-A, restore topology
.\demo.ps1 failover         # intra-DC failover, mr-dr KHÔNG lên primary
.\demo.ps1 help             # xem tất cả lệnh
```

### Linux / macOS / Git Bash

```bash
cd demo/multi-region/vagrant-lab
make demo
make latency
make dr-failover
make dr-failback
make failover
```

## Topology — Pattern A (Stretched Replica Set)

```text
            App driver từ DC-A (chỉ connect 3 hosts DC-A)
                                │
                                ▼
  ┌──────────────── DC-A (primary region, 3 voters) ───────────────────┐
  │   mr-node1  192.168.70.11:27017   priority=2  votes=1  → PRIMARY   │
  │   mr-node2  192.168.70.12:27017   priority=1  votes=1  → SECONDARY │
  │   mr-node3  192.168.70.13:27017   priority=1  votes=1  → SECONDARY │
  │   Latency local DC-A: ~0 ms                                        │
  └─────────┬──────────────────────────────────────────────────────────┘
            │ oplog replication
            │ (cross-region — NETEM ${REGION_LATENCY_MS}ms RTT)
            ▼
  ┌──────────────── DC-B (DR region, 1 member, KHÔNG vote) ────────────┐
  │   mr-dr     192.168.70.14:27017   priority=0  votes=0  → SECONDARY │
  │   - Chỉ replicate, KHÔNG vote, KHÔNG tự thành primary              │
  │   - DR procedure: force-reconfig promote khi DC-A chết hoàn toàn   │
  └────────────────────────────────────────────────────────────────────┘
```

Replica set: `rs0`, oplog 2048 MB, WiredTiger cache 0.5 GB. NETEM ${REGION_LATENCY_MS}ms áp dụng trên `eth1` của mr-dr (mô phỏng RTT cross-DC).

## Pipeline `vagrant up`

1. **Sinh keyFile** — `.\demo.ps1 keyfile` hoặc `make keyfile`
2. **vagrant up** — boot 4 VMs Ubuntu, provisioner tự:
   - Cài MongoDB 8.0 community + iproute2
   - Copy keyFile (mode 400, owner mongodb)
   - Ghi `/etc/mongod.conf` với `replSet=rs0`, `keyFile`, `authorization=enabled`, `oplogSizeMB=2048`
   - **Chỉ trên mr-dr**: apply `tc qdisc netem delay 80ms` trên eth1 + systemd unit để persistent
   - **Chỉ trên mr-node1**:
     1. `rs.initiate()` với 4 members (3 DC-A voters + 1 DC-B priority=0 votes=0)
     2. Tạo `admin` / `appuser` / `backupuser` / `clusteradmin`
     3. Insert 5 sample docs vào `demo.events`
     4. Đợi mr-dr thành SECONDARY (initial sync xong qua netem)

Total: **~15 phút** lần đầu (download box + cài MongoDB × 4 VMs).

## Demo flows đặc trưng

### `dr-failover` — DC-A chết toàn bộ, promote mr-dr ⭐

Đây là use case **#1** cho Multi-Region:

```powershell
.\demo.ps1 dr-failover   # hoặc: make dr-failover
```

Pipeline 11 bước:

1. Verify topology ban đầu
2. Insert mark data với `w:majority` (giúp đo RPO)
3. Đợi 5s để mr-dr catch up qua netem
4. **⚠ Halt mr-node1/2/3** (mô phỏng DC-A chết)
5. Đợi 15s để mr-dr nhận ra mất kết nối
6. Verify cluster — mr-dr stuck SECONDARY (1/4 voters)
7. **⭐ `rs.reconfig({force: true})`** — promote mr-dr standalone PRIMARY
8. Đợi 20s
9. Verify mr-dr là standalone PRIMARY
10. Verify data từ before-disaster còn nguyên
11. Write mới TRỰC TIẾP vào mr-dr (proof of life)

**Khái niệm cốt lõi:**
- `votes=0` → mr-dr KHÔNG gửi vote → election quorum hoàn toàn local DC-A
- `priority=0` → mr-dr KHÔNG bao giờ tự thành primary
- → Khi cả DC-A chết, mr-dr stuck SECONDARY → **bắt buộc** can thiệp manual

### `dr-failback` — DC-A khôi phục, restore topology gốc

```powershell
.\demo.ps1 dr-failback   # hoặc: make dr-failback
```

Pipeline 10 bước: vagrant up DC-A → `rs.add` 3 nodes → đợi initial sync → reset priority/votes → `stepDown` mr-dr → election trong DC-A.

### `latency` — đo cross-region impact

```powershell
.\demo.ps1 latency
```

5 bước: ping DC-A↔DC-B, đo w:majority commit (KHÔNG đợi mr-dr), đo read local vs cross-region.

**Bài học chính:** `w:majority` trong stretched RS với mr-dr `votes=0` **KHÔNG bị ảnh hưởng** bởi latency cross-region — quorum hoàn toàn local DC-A.

### `failover` — intra-DC failover (giống RS thường)

```powershell
.\demo.ps1 failover
```

Halt PRIMARY DC-A → election trong DC-A → 1 DC-A secondary lên primary → assert mr-dr vẫn SECONDARY.

## Tinh chỉnh

### Đổi cross-region latency (mặc định 80ms)

```powershell
# Windows
$env:DEMO_REGION_LATENCY_MS = '250'   # mô phỏng SG↔US-East
.\demo.ps1 demo

# Linux/macOS
DEMO_REGION_LATENCY_MS=250 make demo
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
| `priority` (mr-dr) | 0 | 0 (hard) |
| `votes` (mr-dr) | 0 | 0 nếu không muốn auto-failover xuyên DC; 1 nếu 5-node stretched (Pattern B) |
| NETEM delay | 80ms | KHÔNG dùng — production có latency thật |
| `oplogSizeMB` | 2048 | ≥ (write rate × cross-region downtime tolerance) |
| TLS | Không (lab) | **Bắt buộc** (cross-region public network) |
| disk size mr-dr | ≈ primary | ≈ primary + 20% |

## So sánh các pattern Multi-Region

| Pattern | Cấu hình | Auto-failover xuyên DC | Khi nào dùng |
|---|---|---|---|
| **A — Stretched + DR only (lab này)** | 3 voters DC-A + 1 priority=0 votes=0 DC-B | ❌ (manual force-reconfig) | Đơn giản, DC-B chỉ là dự phòng |
| B — 5-node stretched | 2 voters DC-A + 2 voters DC-B + 1 arbiter DC-C | ✅ tự động | Cần auto-failover xuyên DC, có DC-C neutral |
| C — Zone sharding | Mỗi shard có replica set riêng theo region | ✅ (intra-shard) | Data residency, không muốn cross-region replication |

Lab này demo **Pattern A** (đơn giản nhất, RTO ~30s manual). Production có thể nâng cấp:
- Thêm arbiter DC-C → Pattern B
- Tách thành sharded cluster với zone sharding → Pattern C (xem [runbook 06 §6](../../../runbooks/006-multi-region.md#6-zone-sharding-pattern-c))

## Khi nào KHÔNG dùng Multi-Region

- Dataset < 100 GB + tolerance RTO 4-8h → mongodump nightly + s3 copy cross-region đủ
- Workload chỉ trong 1 region (không có user toàn cầu) → 1 RS PSS đủ
- Atlas Global Clusters → zone sharding tự động — đơn giản hơn nhiều, đáng cân nhắc

Xem **runbook 06** ([`runbooks/06-multi-region.md`](../../../runbooks/006-multi-region.md)) cho chi tiết Pattern A/B/C + zone sharding.

## Cleanup

```powershell
.\demo.ps1 destroy     # chỉ xoá VMs
.\demo.ps1 clean       # destroy + xoá keyfile + .vagrant/
.\demo.ps1 clean-all   # clean + kill stale VBox + (giữ box image)
```

## Cấu trúc thư mục

```
demo/multi-region/vagrant-lab/
├── Vagrantfile               # 4 VMs + auto initiate stretched RS + NETEM trên mr-dr
├── demo.ps1                  # PowerShell wrapper (15 actions)
├── Makefile                  # bash equivalents
├── demo-smoke-test.sh        # verify 4 members + region split + replication lag
├── demo-latency.sh           # đo w:majority + cross-region read latency
├── demo-dr-failover.sh       # ⭐ DC-A chết, force-reconfig mr-dr
├── demo-dr-failback.sh       # khôi phục DC-A, restore topology
├── demo-failover.sh          # intra-DC failover, mr-dr KHÔNG lên primary
├── provision/
│   ├── setup-keyfile.sh      # sinh shared keyFile
│   └── keyfile               # (gitignored — sinh local)
├── logs/                     # dump per-run (auto-created bởi action `logs`)
└── README.md                 # file này
```

## Tham khảo

- Runbook: [`runbooks/06-multi-region.md`](../../../runbooks/006-multi-region.md)
- Scripts production: [`scripts/multi-region/`](../../../scripts/multi-region/)
- MongoDB docs:
  - https://www.mongodb.com/docs/manual/core/replica-set-architecture-geographically-distributed/
  - https://www.mongodb.com/docs/manual/tutorial/force-member-to-be-primary/
  - https://www.mongodb.com/docs/manual/reference/command/replSetReconfig/


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/multi-region/vagrant-lab/README.md`
