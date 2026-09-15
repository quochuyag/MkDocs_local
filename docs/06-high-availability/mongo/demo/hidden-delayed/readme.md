---
title: 'Demo — Hidden + Delayed Member (1 path: Vagrant)'
course: 06-high-availability
source: HA/mongo/demo/hidden-delayed/README.md
---

# Demo — Hidden + Delayed Member (1 path: Vagrant)

Giải pháp **bảo hiểm xoá nhầm + dedicated backup host** — bổ sung trên top của Replica Set thường. 1 member trong RS được cấu hình `priority=0 + hidden=true + secondaryDelaySecs=N` → không phục vụ traffic ứng dụng, chạy chậm hơn primary N giây (thường 24h cho production).

| Path | Setup | RAM | Mục tiêu |
|---|---|---|---|
| [**Vagrant lab tự động**](vagrant-lab/) | ~15 phút | ~10 GB | Hiểu sâu hidden+delayed + thực hành phục hồi xoá nhầm |

**Fully automated** — `.\demo.ps1` (Windows) hoặc `make demo` (Linux/macOS/Git Bash).

## Khi nào dùng demo này

- Có dataset quan trọng + lo bị xoá/update nhầm → cần "thời gian quay lui" mà không cần restore từ backup
- Muốn dedicated host để chạy `mongodump` định kỳ mà KHÔNG impact primary
- Test trade-off: thêm 1 node hidden có tăng fault tolerance không (có — 4 voters)

❌ **KHÔNG cần** demo này nếu:

- Dùng Atlas / managed MongoDB → đã có PITR (point-in-time restore) tự động
- App write rate quá cao → oplog phải khổng lồ để chứa delay window

## Quick start

```powershell
cd demo\hidden-delayed\vagrant-lab
.\demo.ps1                # full pipeline
.\demo.ps1 recover        # ⭐ demo phục hồi data sau xoá nhầm
.\demo.ps1 backup         # ⭐ mongodump không impact primary
.\demo.ps1 failover       # priority=0 chặn election
```

Xem chi tiết tại [vagrant-lab/README.md](vagrant-lab/readme.md).

## So sánh với 2 demo trước

| | Replica Set | Sharded Cluster | **Hidden+Delayed (đây)** |
|---|---|---|---|
| VMs | 3 (rs-node1/2/3) | 4 (sc-node1/2/3 + sc-mgmt) | 4 (hd-node1/2/3 visible + hd-node4 hidden) |
| RAM | ~6 GB | ~10 GB | ~10 GB |
| Subnet | 192.168.30.0/24 | 192.168.40.0/24 | 192.168.50.0/24 |
| App connect | thấy 3 nodes | qua mongos | **chỉ thấy 3 visible** (hd-node4 hidden) |
| Election | bất kỳ node | bất kỳ trong shard | hd-node4 KHÔNG BAO GIỜ thành primary |
| Use case unique | HA cơ bản | Horizontal scaling | **Phục hồi xoá nhầm + dedicated backup** |

## Demo flows đặc trưng

- `.\demo.ps1 recover` — 10 bước phục hồi 50 docs sau `deleteMany({})` trên primary
- `.\demo.ps1 backup`  — `mongodump --oplog --gzip` từ hd-node4 (priority=0, hidden=true → IO node này rảnh)
- `.\demo.ps1 failover` — halt 2 visible members, assert hd-node4 KHÔNG election win

## Tham khảo

- [Runbook 04 — Hidden + Delayed Member](../../runbooks/004-hidden-delayed.md) — chi tiết trade-offs + recovery procedure.
- [demo/replica-set/](../replica-set/) — RS PSS thuần (tiền đề cho giải pháp này).
- [scripts/hidden-delayed/](../../scripts/hidden-delayed/) — scripts production để add hidden+delayed member thủ công.


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/hidden-delayed/README.md`
