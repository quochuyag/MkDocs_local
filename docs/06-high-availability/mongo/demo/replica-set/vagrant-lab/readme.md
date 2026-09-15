---
title: Demo Replica Set PSS — Vagrant lab (3 VMs Ubuntu, full automation)
course: 06-high-availability
source: HA/mongo/demo/replica-set/vagrant-lab/README.md
---

# Demo Replica Set PSS — Vagrant lab (3 VMs Ubuntu, full automation)

Lab production-like để **hiểu sâu** cách Replica Set hoạt động trên môi trường thật (3 VMs Ubuntu 22.04, 3 mongod processes riêng biệt, network host-only). Mọi thứ tự động hoá — chỉ cần `make demo`.

## Khác gì với 2 demo path khác

| Path | Setup | Realistic | Best for |
|---|---|---|---|
| [../docker-compose.yml](../docker-compose.yml) | 1 phút, ~1.5 GB RAM | Thấp (3 containers) | Smoke test, CI, demo nhanh |
| **vagrant-lab này** | ~10 phút, ~6 GB RAM | Cao (3 VMs Ubuntu) | Hiểu sâu HA, test scenario thực |
| [../../../vagrant/](../../../vagrant/) (main) | ~15 phút, ~9 GB RAM | Cao (4 VMs) | Chạy tất cả Runbook 01-06 |

## Yêu cầu

- **Vagrant 2.3+** và **VirtualBox 7.0+** (xem [Runbook 08 §2](../../../runbooks/008-vagrant-lab.md) cho cài đặt chi tiết)
- Host RAM ≥ 8 GB (3 VMs × 2GB = 6 GB)
- Subnet `192.168.30.0/24` rảnh (lab này dùng, khác với main lab `192.168.20.0/24`)
- Bash (Git Bash trên Windows, hoặc WSL)

## Quick start (1 lệnh)

### Windows (PowerShell, native — không cần `make`)

```powershell
cd demo\replica-set\vagrant-lab
.\demo.ps1                     # full demo
.\demo.ps1 failover            # demo failover sau khi xong
.\demo.ps1 help                # xem tất cả lệnh
```

### Linux / macOS / Git Bash (có `make`)

```bash
cd demo/replica-set/vagrant-lab
make demo
make failover
```

### Cả 2 path chạy cùng pipeline

1. **Sinh keyFile** — `.\demo.ps1 keyfile` hoặc `make keyfile`
2. **vagrant up** — boot 3 VMs Ubuntu, provisioner tự:
   - Cài MongoDB 7.0 community
   - Copy keyFile (mode 400, owner mongodb)
   - Ghi `/etc/mongod.conf` với `replSet=rs0`, `keyFile`, `authorization=enabled`
   - **Chỉ trên rs-node1**: `rs.initiate()`, tạo `admin`/`appuser`, insert sample data
3. **Smoke test** — verify từ host: rs.status, count documents trên primary + secondary, oplog window

Total: **~10 phút** lần đầu (download box + cài MongoDB), **~3 phút** lần sau (đã cache box).

## Test failover

```powershell
.\demo.ps1 failover            # Windows
# hoặc
make failover                  # Linux/macOS/Git Bash
```

Pipeline tự động:

1. Tìm PRIMARY hiện tại
2. `vagrant halt` VM primary (giả lập crash thật, không chỉ stop process)
3. Đợi 15s → kiểm tra PRIMARY mới
4. Insert document qua PRIMARY mới
5. `vagrant up` VM cũ → verify rejoin làm SECONDARY + replication ngược

## Topology

```text
  Host (Windows / Linux)
  │
  ├─ VirtualBox host-only network 192.168.30.0/24
  │
  ├─ VM rs-node1 (192.168.30.11)  priority=2  ← thường là PRIMARY
  ├─ VM rs-node2 (192.168.30.12)  priority=1
  └─ VM rs-node3 (192.168.30.13)  priority=1
```

Replica set: `rs0`, oplog 256 MB, WiredTiger cache 0.5 GB (lab).

## Users tự động tạo

| User | DB | Roles | Password env var |
|---|---|---|---|
| `admin` | admin | `root` | `DEMO_ADMIN_PWD` (default: `DemoAdmin#2026`) |
| `appuser` | demo | `readWrite@demo` | `DEMO_APP_PWD` (default: `DemoApp#2026`) |

Đổi password:

```bash
DEMO_ADMIN_PWD='MyStrongAdmin' DEMO_APP_PWD='MyStrongApp' make demo
```

## Connect từ host

Sau khi `make demo` xong, connect string từ host máy bạn:

```text
mongodb://appuser:DemoApp#2026@192.168.30.11:27017,192.168.30.12:27017,192.168.30.13:27017/demo?replicaSet=rs0
```

Cần `mongosh` trên host:

```bash
mongosh "mongodb://admin:DemoAdmin#2026@192.168.30.11:27017/admin?replicaSet=rs0"
```

Hoặc query trong VM:

```bash
make ssh-node1
# Inside VM:
mongosh -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
```

## Khám phá sâu hơn

### Xem oplog hoạt động real-time

```bash
make ssh-node1
mongosh -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
# Inside mongosh:
use local
db.oplog.rs.find().sort({$natural:-1}).limit(5).pretty()   // 5 op gần nhất
```

### Test write concern w:majority

```bash
make ssh-node1
mongosh -u appuser -p 'DemoApp#2026' demo
# Inside:
db.events.insertOne({test:1}, {writeConcern:{w:"majority", wtimeout:5000}})
# halt 2 secondaries → write block đến timeout
```

### Force step down

```bash
make ssh-node1
mongosh -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
# Inside:
rs.stepDown(60)    // primary tự chuyển sang secondary trong 60s, election trigger
```

### Add 4th member trong lúc cluster đang chạy

Phức tạp hơn — cần thêm VM. Xem [Runbook 01 §5](../../../runbooks/001-replica-set.md#5-vận-hành-opssh).

## Cleanup

```bash
make destroy       # vagrant destroy -f (xoá 3 VMs)
make clean         # destroy + xoá keyfile
```

VMs lưu tại đường dẫn cấu hình bởi VirtualBox machinefolder. Để lưu vào `D:\VM VirtualBox\mongo-rs-demo`:

```powershell
VBoxManage setproperty machinefolder "D:\VM VirtualBox\mongo-rs-demo"
# (chạy trước make demo)
```

Xem [Runbook 08 §3](../../../runbooks/008-vagrant-lab.md#3-đổi-nơi-lưu-vm-files-sang-d-vm-virtualboxmongo-ha) cho chi tiết.

## Cấu trúc folder

```text
vagrant-lab/
├── Vagrantfile               # 3 VMs Ubuntu 22.04 + inline provisioner cài Mongo + rs.initiate
├── Makefile                  # make demo / failover / destroy
├── demo-smoke-test.sh        # verify từ host sau khi up
├── demo-failover.sh          # demo auto-failover (halt primary, observe election)
├── provision/
│   ├── setup-keyfile.sh      # sinh keyfile shared (chạy 1 lần trên host)
│   └── keyfile               # GITIGNORED — sinh ra bởi setup-keyfile.sh
└── README.md                 # file này
```

## Troubleshooting

| Triệu chứng | Nguyên nhân + Fix |
|---|---|
| `make demo` báo "machine folder not found" | Tạo thư mục đích trước: `New-Item -ItemType Directory "D:\VM VirtualBox\mongo-rs-demo"` |
| `vagrant up` báo IP `192.168.30.x` conflict | Đổi IP trong Vagrantfile `NODES` (vd. 192.168.40.x) |
| Provisioner báo "rs.initiate failed: NotYetInitialized" rồi succeed | Bình thường — script retry. Nếu fail hẳn: `vagrant destroy -f && make demo` |
| Secondary stuck STARTUP2 sau failover | Initial sync chạy; chờ ~30s; kiểm `rs.status()` thấy state PROGRESS |
| `mongosh` từ host fail "connection refused" | Verify firewall trên VM mở 27017: `vagrant ssh rs-node1 -c "sudo ss -tlnp \| grep 27017"` |
| `vagrant halt rs-node1` rồi tự nó power-on lại | VirtualBox auto-restart setting? Tắt trong GUI. Hoặc dùng `vagrant suspend` thay |


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/replica-set/vagrant-lab/README.md`
