---
title: 'Demo — Multi-Region (Stretched Replica Set) (1 path: Vagrant)'
course: 06-high-availability
source: HA/mongo/demo/multi-region/README.md
---

# Demo — Multi-Region (Stretched Replica Set) (1 path: Vagrant)

Giải pháp **DR cross-region** — 1 replica set kéo dài 2 "data center", mất hoàn toàn 1 DC vẫn phục hồi được bằng force-reconfig. 1 member trong RS đặt ở DC-B với `priority=0 votes=0` → chỉ replicate, không bao giờ tự thành primary, không gửi vote (tách hoàn toàn khỏi election quorum cross-region).

| Path | Setup | RAM | Mục tiêu |
|---|---|---|---|
| [**Vagrant lab tự động**](vagrant-lab/) | ~15 phút | ~10 GB | Hiểu sâu stretched RS + thực hành DR failover/failback |

**Fully automated** — `.\demo.ps1` (Windows) hoặc `make demo` (Linux/macOS/Git Bash).

## Khi nào dùng demo này

- Có business cần tolerance mất 1 DC/region (compliance, RTO/RPO < 30 phút geo scale)
- Muốn hiểu trade-off giữa Pattern A (DR-only) và Pattern B (5-node auto-failover)
- Học cách đo impact của cross-region latency lên `w:majority` write performance
- Học cách `rs.reconfig({force:true})` hoạt động và rủi ro split-brain

❌ **KHÔNG cần** demo này nếu:

- Dataset < 100 GB + tolerance RTO 4-8h → mongodump nightly + s3 cross-region đủ
- Atlas Global Clusters → zone sharding managed — đơn giản hơn nhiều
- Workload chỉ trong 1 region (không có user toàn cầu)

## Quick start

```powershell
cd demo\multi-region\vagrant-lab
.\demo.ps1                  # full pipeline
.\demo.ps1 latency          # đo w:majority + cross-region read latency
.\demo.ps1 dr-failover      # ⭐ DC-A chết, promote mr-dr (force-reconfig)
.\demo.ps1 dr-failback      # khôi phục DC-A, restore topology gốc
.\demo.ps1 failover         # intra-DC failover, mr-dr KHÔNG lên primary
```

Xem chi tiết tại [vagrant-lab/README.md](vagrant-lab/readme.md).

## So sánh với 4 demo trước

| | Replica Set | Sharded Cluster | Hidden+Delayed | Backup+PITR | **Multi-Region (đây)** |
|---|---|---|---|---|---|
| VMs | 3 | 4 | 4 | 4 | 4 (3 DC-A + 1 DC-B) |
| RAM | ~6 GB | ~10 GB | ~10 GB | ~9 GB | ~10 GB |
| Subnet | `.30` | `.40` | `.50` | `.60` | `.70` |
| Topology | PSS 1 DC | Shard 1 DC | PSSH 1 DC | PSS + backup ops | **Stretched 2 DC (PSS + DR)** |
| Auto failover | ✅ trong 1 DC | ✅ per shard | ✅ trong 1 DC | ✅ trong 1 DC | ✅ intra-DC, ❌ cross-DC |
| Use case unique | HA cơ bản | Horizontal scaling | Phục hồi xoá nhầm | PITR đến giây cụ thể | **DR khi mất 1 region** |
| Manual intervention | KHÔNG | KHÔNG | KHÔNG (recovery thủ công) | restore thủ công | **force-reconfig khi DR** |

## Demo flows đặc trưng

- `.\demo.ps1 dr-failover` — 11 bước: insert mark → halt DC-A → mr-dr stuck → force-reconfig → mr-dr standalone PRIMARY → verify RPO
- `.\demo.ps1 dr-failback` — 10 bước: bring up DC-A → rs.add → initial sync → reset priority/votes → stepDown → election trong DC-A
- `.\demo.ps1 latency` — đo w:majority commit time (chỉ local DC-A) vs cross-region read latency (qua NETEM 80ms)
- `.\demo.ps1 failover` — intra-DC: halt 1 PRIMARY DC-A → 2/3 voters đủ majority → DC-A secondary lên primary, mr-dr vẫn SECONDARY

## Tham khảo

- [Runbook 06 — Multi-Region](../../runbooks/006-multi-region.md) — chi tiết Pattern A/B/C + zone sharding.
- [demo/replica-set/](../replica-set/) — RS PSS thuần (tiền đề cho giải pháp này).
- [scripts/multi-region/](../../scripts/multi-region/) — scripts production để add cross-region secondary + zone sharding.


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/multi-region/README.md`
