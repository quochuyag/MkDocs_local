---
title: Chuẩn hoá Vagrant lab cho HA đa-DB
course: 06-high-availability
source: HA/mongo/MULTI_DB_STANDARD.md
---

# Chuẩn hoá Vagrant lab cho HA đa-DB

Tài liệu thiết kế: cách tổ chức Vagrant lab thống nhất cho 5 database engine — MySQL, MongoDB, Redis, MSSQL, Oracle. Convention này cho phép Claude (và developer) tạo / mở rộng / chuyển đổi giữa các DB lab mà không phải nhớ context cụ thể từng cái.

Trạng thái: **PROPOSAL — chưa apply cross-repo**. Đã chứng minh được ở `mongo/demo/replica-set/vagrant-lab/`.

## Mục tiêu

1. **Một developer nắm 1 DB lab** → hiểu ngay cấu trúc của 4 DB còn lại
2. **Claude tạo lab mới** chỉ cần biết "DB X + topology Y" là spawn được, không phải hỏi lại convention
3. **Tài nguyên không xung đột**: subnet, port, VM name, box, credential — đều phân tách rõ
4. **DRY**: OS prep, firewall, ssh trust, helper Vagrantfile chia sẻ ở `_shared/`

## Cấu trúc thư mục đề xuất

```
d:\Dba_project\HA\
├── _shared\                          # CHƯA TỒN TẠI — tạo khi user xác nhận
│   ├── scripts\
│   │   ├── 00-prepare-os.sh          # THP, swap, sysctl, ulimit (universal)
│   │   ├── 02-firewall.sh            # nhận PORTS env array
│   │   └── ssh-trust.sh              # cluster-internal passwordless ssh
│   ├── vagrant\
│   │   └── lab_dsl.rb                # Ruby helpers: define_nodes, common_vb_config...
│   └── README.md
├── mysql\                            # đã có (sibling)
├── mongo\                            # đã có (REPO HIỆN TẠI)
├── redis\                            # tạo theo template khi cần
├── mssql\
└── oracle\
```

## Subnet plan (mỗi DB chiếm 1 subnet /24)

| DB | Subnet | Tự do dùng cho |
|---|---|---|
| MySQL | `192.168.10.0/24` | Group Replication / Async / MHA |
| MongoDB main lab | `192.168.20.0/24` | Replica Set / PSA / Sharded |
| MongoDB demo | `192.168.30.0/24` | Demo lab full automation |
| **Redis** (proposed) | `192.168.40.0/24` | Sentinel / Cluster |
| **MSSQL** (proposed) | `192.168.50.0/24` | Always On AG / FCI |
| **Oracle** (proposed) | `192.168.60.0/24` | Data Guard / RAC |

IP scheme trong subnet:

| Range | Vai trò |
|---|---|
| `.11 – .13` | Data nodes 1, 2, 3 |
| `.14 – .19` | Replica / witness / arbiter / hidden |
| `.20 – .29` | Mgmt: mongos / router / proxy / backup |
| `.30+` | Cross-region / DR / monitoring |

## Port plan (per engine)

| DB | Primary | HA / cluster components |
|---|---|---|
| MySQL | `3306` | router `6446/6447`, MGR `33061`, MTS `3307+` |
| MongoDB | `27017` mongod / mongos | `27018` shard, `27019` config, `27020` arbiter |
| Redis | `6379` redis-server | `26379` Sentinel, `16379` Cluster bus |
| MSSQL | `1433` sqlservr | `5022` AG endpoint, `1433` AG listener |
| Oracle | `1521` listener | `1521` SCAN, `+offset` DG broker |

## Cấu trúc bên trong mỗi `<db>/` repo

```
<db>/
├── CLAUDE.md            # repo-specific guidance, link tới tài liệu này
├── README.md            # matrix HA pattern + entry points
├── scripts\
│   ├── common\          # OS prep + install + firewall + security
│   │   ├── env.sh                   # SST cho IPs/ports/users/version
│   │   ├── 00-prepare-os.sh
│   │   ├── 01-install-<db>.sh
│   │   ├── 02-firewall.sh
│   │   └── 03-security.sh           # keyfile / TLS cert / pwd_file
│   └── <topology>\      # 1 thư mục mỗi HA pattern
│       ├── 01-init-<step>.sh
│       └── 0N-...
├── runbooks\
│   ├── 00-overview.md   # bảng matrix tất cả runbook
│   └── 0N-<topology>.md
├── vagrant\             # main lab production-like
│   ├── Vagrantfile
│   ├── Makefile
│   └── provision\
└── demo\                # demo subset: tự động hoá đầy đủ
    └── <topology>\
        └── vagrant-lab\
            ├── Vagrantfile          # cpu=2, mem=4GB chuẩn
            ├── demo.ps1             # 11 actions chuẩn
            ├── README.md
            ├── provision\
            └── app\                 # optional load test (CLI + GUI Flask)
                ├── load-data.py
                ├── requirements.txt
                └── ui\
```

## Chuẩn hoá `demo.ps1` — 11 actions

Mọi `demo/<topology>/vagrant-lab/demo.ps1` phải hỗ trợ:

```
demo        # full pipeline: credential → up → smoke
keyfile     # sinh credential (mongo: keyFile · mysql/mssql: cert · redis: requirepass)
up          # vagrant up + provision
smoke       # verify cluster health (cmd per-DB)
failover    # halt primary → election → rejoin
ssh <node>  # ssh vào node
status      # vagrant status
destroy     # vagrant destroy -f
clean       # destroy + xoá credential + .vagrant/
clean-all   # clean + xoá box image + kill stale VBox processes
help
```

Khi tạo demo lab mới: copy `mongo/demo/replica-set/vagrant-lab/demo.ps1`, thay phần verify (`rs.status()`) bằng command tương ứng từng DB:

| DB | Smoke verify | Failover detection |
|---|---|---|
| MongoDB | `rs.status()` · `db.hello()` | `myState == 1` (PRIMARY) |
| MySQL MGR | `SELECT * FROM performance_schema.replication_group_members` | `MEMBER_ROLE = 'PRIMARY'` |
| Redis Sentinel | `SENTINEL master mymaster` | `role:master` from `INFO replication` |
| MSSQL AG | `SELECT * FROM sys.dm_hadr_database_replica_states` | `role_desc = 'PRIMARY'` |
| Oracle DG | `SELECT database_role FROM v$database` | `database_role = 'PRIMARY'` |

## Chuẩn hoá tài nguyên VM

| Item | Value |
|---|---|
| Box | `bento/ubuntu-22.04` (Linux engines) · `gusztavvargadr/sql-server` (MSSQL) · Oracle preinstall RPM box (Oracle) |
| vCPU | 2 |
| RAM | 4 GB (MSSQL/Oracle có thể cần 6–8 GB) |
| Disk | 60 GB (default) |
| Box check update | off (deterministic) |
| Linked clone | on |
| ioapic | on |
| natdnshostresolver1 | on |
| Boot timeout | 600 |
| Synced folder | disabled — credential nhúng inline |

## Tiền đề host (Windows)

Đã debug nặng ở session 2026-05-15 (xem memory `mongo-demo-vagrant-quirks`):

1. **Hyper-V/VBS phải TẮT** — `bcdedit /set hypervisorlaunchtype off` + reboot
   - Lý do: VBox dưới WHP không expose AVX → MongoDB 5.0+, MSSQL Linux, Oracle 19c+ all crash
2. **VirtualBox 7.0+**
3. **Vagrant 2.3+**
4. **Host RAM ≥ 16 GB** (3 VMs × 4 GB = 12 GB, cần buffer)

## Convention thêm topology mới

1. Tạo thư mục `scripts/<topology>/` với các step script
2. Tạo `runbooks/0N-<topology>.md` theo template (Khi nào dùng / Kiến trúc / Tiền đề / Các bước / Verify / Vận hành / Rollback / Tham khảo)
3. Update `runbooks/00-overview.md` matrix
4. (Optional) Tạo `demo/<topology>/vagrant-lab/` từ template

## Convention load test app

Reuse pattern `mongo/demo/replica-set/vagrant-lab/app/`:

```
app/
├── load-data.py          # CLI multi-thread bulk insert
├── requirements.txt
├── README.md
└── ui/
    ├── server.py         # Flask + SSE
    ├── templates/index.html
    └── static/{style.css, app.js}
```

Adapt driver theo DB:

| DB | Python driver | Connection scheme |
|---|---|---|
| MongoDB | `pymongo` | `mongodb://user:pwd@h1,h2,h3/db?replicaSet=rs0` |
| MySQL | `pymysql` / `mysql-connector-python` | `mysql://user:pwd@host:3306/db` |
| Redis | `redis-py` | `redis://:pwd@host:6379/0` (Sentinel: `Sentinel([(h,26379),...])`) |
| MSSQL | `pyodbc` | `mssql+pyodbc://user:pwd@host:1433/db?driver=ODBC+Driver+18+for+SQL+Server` |
| Oracle | `oracledb` | `user/pwd@host:1521/service` |

Scenarios giữ nguyên (ecommerce / iot / logs / users) — schema mở rộng theo phù hợp engine.

## Quy tắc bảo trì

1. **Version DB**: luôn default LTS mới nhất tại thời điểm. Không downgrade ngầm để workaround. (Xem memory `always-latest-mongo-version` — quy tắc chung cho mọi DB.)
2. **Cleanup**: mọi lab đều phải có `clean-all` action. (Xem memory `vagrant-resource-cleanup`.)
3. **Memory**: mỗi lần làm xong deliverable lớn → update memory `project-status` để session sau biết.

## Bước implementation (theo thứ tự ưu tiên)

| # | Bước | Status |
|---|---|---|
| 1 | Proposal này (`MULTI_DB_STANDARD.md`) | ✅ |
| 2 | Memory `multi-db-vagrant-standard` cho Claude future session | ✅ |
| 3 | Tạo `d:\Dba_project\HA\_shared\` với 3 script chung + 1 ruby helper | ⏳ chờ user approve |
| 4 | Refactor `mongo/demo/replica-set/vagrant-lab/Vagrantfile` dùng `_shared/lab_dsl.rb` | ⏳ |
| 5 | Tạo skeleton `redis/`, `mssql/`, `oracle/` repos theo template | ⏳ |
| 6 | Port load test app sang từng DB | ⏳ |

Khi user nói "OK chuẩn hoá đi" → bắt đầu từ bước 3.


---

!!! info "Nguồn gốc"
    `HA/mongo/MULTI_DB_STANDARD.md`
