---
title: Demo Sharded Cluster — Vagrant lab (4 VMs Ubuntu, full automation)
course: 06-high-availability
source: HA/mongo/demo/sharded-cluster/vagrant-lab/README.md
---

# Demo Sharded Cluster — Vagrant lab (4 VMs Ubuntu, full automation)

Lab production-like để **hiểu sâu** cách Sharded Cluster hoạt động trên môi trường thật (4 VMs Ubuntu 22.04, 2 mongod instances mỗi data node + 1 mongos, network host-only). Mọi thứ tự động hoá — chỉ cần `.\demo.ps1` (Windows) hoặc `make demo` (Linux/macOS/Git Bash).

## Khác gì với demo Replica Set

| Demo | Setup | VMs | RAM | Best for |
|---|---|---|---|---|
| [../../replica-set/vagrant-lab/](../../replica-set/vagrant-lab/) | ~10 phút | 3 | ~6 GB | Hiểu Replica Set PSS thuần |
| **Sharded Cluster này** | ~12-15 phút | 4 | ~10 GB | Hiểu Sharding + mongos + config server |
| [../../../vagrant/](../../../vagrant/) (main) | ~15 phút | 4 | ~9 GB | Chạy mọi Runbook 01-06 (toolkit chính) |

## Yêu cầu

- **Vagrant 2.3+** và **VirtualBox 7.0+** (xem [Runbook 08 §2](../../../runbooks/008-vagrant-lab.md))
- Host RAM ≥ 12 GB (3 data × 3GB + 1 mgmt × 1GB = 10 GB cho VMs)
- Subnet `192.168.40.0/24` rảnh (khác replica-set demo `192.168.30.0/24` và main lab `192.168.20.0/24`)
- **Hyper-V phải TẮT** (xem đầu Vagrantfile cho chi tiết)

## Quick start (1 lệnh)

### Windows (PowerShell, native)

```powershell
cd demo\sharded-cluster\vagrant-lab
.\demo.ps1                     # full demo
.\demo.ps1 failover            # demo shard primary failover
.\demo.ps1 logs                # dump setup-recipe.md + .sh + per-node reports
.\demo.ps1 help                # xem tất cả lệnh
```

### Linux / macOS / Git Bash (có `make`)

```bash
cd demo/sharded-cluster/vagrant-lab
make demo
make failover
```

### Cả 2 path chạy cùng pipeline

1. **Sinh keyFile** — `.\demo.ps1 keyfile` hoặc `make keyfile`
2. **vagrant up** — boot 4 VMs Ubuntu, provisioner tự động:
   - **Mọi VM**: cài MongoDB 8.0, ghi keyFile (mode 400, owner mongodb), disable default `mongod.service`
   - **sc-node1/2/3** (data): cài 2 systemd units `mongod-cfg` (port 27019, configsvr) + `mongod-shard1rs` (port 27018, shardsvr)
   - **sc-node1** (initiator): `rs.initiate()` cho cfgrs + shard1rs, tạo admin users qua localhost exception
   - **sc-mgmt**: cài mongos, `sh.addShard('shard1rs/...')`, tạo cluster-wide users (clusteradmin/backupuser/appuser), `sh.enableSharding('appdb')`, `sh.shardCollection('appdb.events', {userId:'hashed'})`, insert 200 sample documents
3. **Smoke test** — verify từ host: `sh.status()`, chunks distribution, replication trong shard, balancer state

Total: **~12-15 phút** lần đầu (download box + cài MongoDB trên 4 VMs), **~5 phút** lần sau.

## Test failover

```powershell
.\demo.ps1 failover            # Windows
# hoặc
make failover                  # Linux/macOS/Git Bash
```

Pipeline tự động:

1. Tìm PRIMARY của shard1rs hiện tại
2. `vagrant halt` VM primary (giả lập crash thật)
3. Đợi 15s → kiểm tra PRIMARY mới
4. Insert document qua **mongos** (không đổi connection string) → mongos auto re-route
5. `vagrant up` VM cũ → verify rejoin làm SECONDARY + replication ngược

**Quan trọng:** App connect mongos (`sc-mgmt:27017`), KHÔNG đổi URI khi shard PRIMARY thay đổi.

## Topology

```text
  Host (Windows / Linux)
  │
  ├─ VirtualBox host-only network 192.168.40.0/24
  │
  ├─ VM sc-node1 (192.168.40.11)  cfgrs:27019 + shard1rs:27018 (priority=2)
  ├─ VM sc-node2 (192.168.40.12)  cfgrs:27019 + shard1rs:27018 (priority=1)
  ├─ VM sc-node3 (192.168.40.13)  cfgrs:27019 + shard1rs:27018 (priority=1)
  └─ VM sc-mgmt  (192.168.40.20)  mongos:27017 (App entry point)
```

- **cfgrs** (Config Server RS): 3 voting members, lưu metadata (chunk → shard mapping). MongoDB yêu cầu config server **phải là RS 3 nodes**.
- **shard1rs** (Shard RS): 3 voting members, lưu data (collection thật).
- **mongos**: stateless router. App connect mongos. Trong production deploy ≥2 mongos cho HA.

App URI:

```
mongodb://appuser:DemoApp#2026@192.168.40.20:27017/appdb
```

(`#` trong password URL-encode thành `%23` khi paste vào tool ngoài: `mongodb://appuser:DemoApp%232026@...`)

## Users tự động tạo

| User | DB | Roles | Tạo qua | Password env var |
|---|---|---|---|---|
| `admin` | admin | `root` | localhost exception trên cfgrs + shard1rs (riêng) | `DEMO_ADMIN_PWD` (default: `DemoAdmin#2026`) |
| `clusteradmin` | admin | `clusterAdmin + clusterManager + clusterMonitor` | mongos | `DEMO_CLUSTER_PWD` (default: `DemoCluster#2026`) |
| `backupuser` | admin | `backup + restore + clusterMonitor` | mongos | `DEMO_CLUSTER_PWD` |
| `appuser` | appdb | `readWrite@appdb` | mongos | `DEMO_APP_PWD` (default: `DemoApp#2026`) |

Đổi password:

```bash
DEMO_ADMIN_PWD='MyAdmin' DEMO_CLUSTER_PWD='MyCluster' DEMO_APP_PWD='MyApp' make demo
```

## Connect từ host

Sau khi `make demo` xong, từ host máy bạn:

```text
mongodb://appuser:DemoApp#2026@192.168.40.20:27017/appdb
```

Cần `mongosh` trên host:

```bash
mongosh "mongodb://admin:DemoAdmin#2026@192.168.40.20:27017/admin"
```

Hoặc query trong VM:

```bash
make ssh-mgmt              # vào mongos host
# Inside VM:
mongosh --port 27017 -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
```

## Khám phá sâu hơn

### Sharding metadata

```bash
make ssh-mgmt
mongosh --port 27017 -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
# Inside mongosh:
sh.status()                                         # tổng quan
db.getSiblingDB("config").shards.find()             # danh sách shards
db.getSiblingDB("config").chunks.aggregate([        # chunk distribution
  { $match: { ns: "appdb.events" } },
  { $group: { _id: "$shard", chunks: { $sum: 1 } } }
])
```

### Connect trực tiếp shard (bypass mongos — chỉ debug)

```bash
make ssh-node1
mongosh --port 27018 -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
# Hoặc connect config server:
mongosh --port 27019 -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
```

### Balancer ops

```bash
mongosh --port 27017 -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
# Inside:
sh.getBalancerState()
sh.stopBalancer()                                   # cho backup window
sh.startBalancer()
```

### Thêm shard thứ 2 (trên cùng 3 nodes, port khác)

Phức tạp hơn — cần thêm 2 systemd unit (mongod-shard2rs trên port 27028) và `sh.addShard('shard2rs/...')`. Xem [Runbook 03 §5.1](../../../runbooks/003-sharded-cluster.md#51-thêm-shard).

### Test config server quorum loss

```bash
vagrant halt sc-node1 sc-node2    # halt 2/3 config server members
# Đợi 30s
make ssh-mgmt
mongosh --port 27017 -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin
# Inside:
db.getSiblingDB("appdb").events.findOne()     # READ vẫn OK (mongos cache)
db.getSiblingDB("appdb").events.insertOne({}) # WRITE cũng có thể OK nếu shard primary còn
# Nhưng KHÔNG split chunk, KHÔNG add shard, KHÔNG move chunk
```

## Cleanup

```bash
make destroy       # vagrant destroy -f (xoá 4 VMs)
make clean         # destroy + xoá keyfile
.\demo.ps1 clean-all    # clean + xoá box image + kill stale VBox
```

VMs lưu tại đường dẫn cấu hình bởi VirtualBox machinefolder. Để lưu vào `D:\VM VirtualBox\mongo-sc-demo`:

```powershell
VBoxManage setproperty machinefolder "D:\VM VirtualBox\mongo-sc-demo"
# (chạy trước make demo)
```

## Cấu trúc folder

```text
vagrant-lab/
├── Vagrantfile               # 4 VMs Ubuntu 22.04 + inline provisioners (4 phases)
├── Makefile                  # make demo / failover / destroy
├── demo.ps1                  # PowerShell wrapper (full feature, incl. logs dump)
├── demo-smoke-test.sh        # verify từ host sau khi up
├── demo-failover.sh          # shard primary failover demo
├── provision/
│   ├── setup-keyfile.sh      # sinh keyfile shared (chạy 1 lần trên host)
│   └── keyfile               # GITIGNORED — sinh ra bởi setup-keyfile.sh
├── logs/                     # GITIGNORED — dump logs/<timestamp>/ từ `.\demo.ps1 logs`
└── README.md                 # file này
```

## Output của `.\demo.ps1 logs`

Mỗi lần chạy `logs` action tạo 1 thư mục `logs/<YYYY-MM-DD_HH-mm-ss>/`:

| File | Nội dung |
|---|---|
| `setup-recipe.md` | **Recipe verbatim** — toàn bộ lệnh đã chạy theo thứ tự (6 phases), kèm giải thích cho từng phase. **Đọc file này để hiểu setup từ A-Z.** |
| `setup-recipe.sh` | Bản runnable của recipe, copy theo SCOPE (`[ALL]`/`[DATA]`/`[NODE1]`/`[MGMT]`) vào shell VM tương ứng. |
| `sc-node1.txt` / `sc-node2.txt` / `sc-node3.txt` | Chi tiết per-data-node: hostname, network, systemd state cho `mongod-cfg` + `mongod-shard1rs`, listen ports, keyfile metadata, 2 config files, log tail, mtime của các config files (thứ tự ghi). |
| `sc-mgmt.txt` | Chi tiết mongos node: systemd `mongos.service`, listen port 27017, `/etc/mongos.conf`, log tail. |
| `cluster.txt` | `sh.status()`, `config.shards`, `config.databases`, `config.collections`, chunks per shard, balancer state, users (qua mongos), `rs.status()` cho cfgrs + shard1rs, oplog window của shard. |
| `mongod-cfg.conf` / `mongod-shard1rs.conf` / `mongos.conf` | 3 config files đại diện (identical pattern trên 3 data nodes). |
| `Vagrantfile.snapshot` | Vagrantfile tại thời điểm capture (nguồn cấu hình gốc). |
| `SUMMARY.md` | Tóm tắt high-level: topology, các bước HA đã làm, connection string. |

## Troubleshooting

| Triệu chứng | Nguyên nhân + Fix |
|---|---|
| `make demo` báo "machine folder not found" | Tạo thư mục đích trước: `New-Item -ItemType Directory "D:\VM VirtualBox\mongo-sc-demo"` |
| `vagrant up` báo IP `192.168.40.x` conflict | Đổi IP trong Vagrantfile `NODES` (vd. 192.168.50.x) |
| Provisioner báo "rs.initiate failed: NotYetInitialized" rồi succeed | Bình thường — script retry. Nếu fail hẳn: `.\demo.ps1 destroy && .\demo.ps1 demo` |
| `sh.addShard` báo "not master" / "no primary" | shard1rs election chưa xong — đợi 30s rồi `.\demo.ps1 up` lại |
| `mongos` start fail, log nói "BadValue: configdb specifies" | Format `configDB: cfgrs/host1:port,host2:port,host3:port` sai — verify `/etc/mongos.conf` |
| `mongosh --port 27017` từ host fail "connection refused" | Verify firewall: `vagrant ssh sc-mgmt -c "sudo ss -tlnp \| grep 27017"` |
| Chunks không phân bố đều sau insert | Hashed key cần ≥ vài chunks per shard — với 200 docs balancer có thể chưa split. Thử insert 10k+ documents. |
| `vagrant halt sc-node1` rồi tự nó power-on lại | VirtualBox auto-restart? Tắt trong GUI. Hoặc `vagrant suspend` thay |

## Tham khảo

- [Runbook 03 — Sharded Cluster](../../../runbooks/003-sharded-cluster.md) — runbook gốc của toolkit.
- [Scripts gốc](../../../scripts/sharded-cluster/) — `config-server-setup.sh`, `shard-setup.sh`, `mongos-setup.sh`, `add-shard.sh`, `balancer-ops.sh` (chạy thủ công trên lab main `vagrant/`).
- https://www.mongodb.com/docs/manual/sharding/
- https://www.mongodb.com/docs/manual/core/sharding-shard-key/


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/sharded-cluster/vagrant-lab/README.md`
