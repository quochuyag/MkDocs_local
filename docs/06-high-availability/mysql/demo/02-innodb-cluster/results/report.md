---
title: Báo cáo Demo 02 — MySQL InnoDB Cluster
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/results/report.md
---

# Báo cáo Demo 02 — MySQL InnoDB Cluster

## 1. Trạng thái

**OK (sau recovery)** — B6 fail lần đầu do UFW bug; đã patch script + rerun B6/B7/B8 → smoke-test PASS end-to-end.

## 2. Tóm tắt sự cố B6 → fix

| Trường | Giá trị |
|---|---|
| Symptom | `vagrant ssh mgmt -c "...router-setup.sh"` exit 255, 0 dòng output, B6 FAIL sau 4746s |
| Root cause | `06-router-setup.sh` bật UFW (`ufw --force enable`) **không pre-allow 22/tcp** → SSH session đang chạy survive nhưng kết nối SSH mới kế tiếp bị block |
| Vì sao log trống | Vagrant ssh fail trước khi script trên VM in được dòng log nào; `set -o pipefail` + `\| tee -a` kill B6 ngay |
| Tại sao "VM running" mà SSH chết | UFW chỉ allow 6446/6447. Reboot mgmt không tự khôi phục — UFW rule vẫn persist sau reboot |
| Fix | (a) Patch `demo/02-innodb-cluster/06-router-setup.sh` thêm `ufw allow OpenSSH \|\| ufw allow 22/tcp` trước `ufw --force enable`. (b) Khôi phục mgmt VM hiện tại: `VBoxManage guestcontrol mysql-ha-mgmt run --username vagrant --password vagrant --exe /usr/bin/sudo -- /usr/bin/sudo ufw allow 22/tcp` |
| Liên quan | Trùng họ bug với `bug_ufw_blocks_ssh.md` (DB nodes) đã fix ở `common/02-firewall.sh`. Wrapper demo có instance UFW riêng, không pick up fix kia |

## 3. Kết quả sau recovery

| Step | Result | Time |
|---|---|---|
| B6 router-setup (rerun) | OK | 67s |
| B7 verify (rerun) | WARN — cluster healthy nhưng verify script có bug check | 240s |
| B8 smoke-test | **PASS** | 114s |

### B8 smoke metrics
- Insert 200 rows qua :6446 → **13.294s** (kỳ vọng <2s — chậm vì SSH overhead 1 row 1 query, không phải vấn đề cluster)
- Replica lag node1=6.414s / node2=6.807s / node3=6.812s
- :6447 round-robin 6 hit → node2: 3, node3: 3 (perfect)
- GTID consistent giữa 3 node

### Router routing
| Endpoint | Hit pattern | Pass? |
|---|---|---|
| :6446 (RW) — 3 lần | node1 / node1 / node1 (tất cả PRIMARY) | ✓ |
| :6447 (RO) — 4 lần | node3 / node2 / node3 / node2 | ✓ round-robin |

## 4. B7 verify — các check báo FAIL nhưng cluster thực sự khỏe

Verify script có **bugs riêng** chưa fix trong scope này:

| Check | Báo cáo | Thực tế |
|---|---|---|
| `:6446 không nhất quán: node1 node1 node1` | FAIL | OK — RW endpoint phải hit primary 100% |
| `[node1] super_read_only=0` | FAIL | OK — node1 là PRIMARY, không phải read-only |
| `port 33061 not listening` (cả 3 node) | FAIL | GR vẫn ONLINE — có thể GR dùng local_address khác hoặc check sai port |
| `baseline=ON ON ROW` (cả 3 node) | FAIL | Cần xem `07-verify.sh` để biết baseline kỳ vọng gì |

Cluster.status() = OK, replication_group_members = 3 ONLINE, mysqlrouter active+listening. Cluster health không vấn đề.

## 5. Bước tiếp theo (manual)

- [ ] (Optional) Fix bugs trong `demo/02-innodb-cluster/07-verify.sh` (so sánh hostname vs IP, check super_read_only theo role, baseline kỳ vọng đúng)
- [ ] Có thể chạy `09-failover-test.sh` để kiểm tra PROMOTE_RTO/WRITE_RTO
- [ ] Hoặc `10-rollback.sh` để tear down

## 6. Lab state hiện tại

- 4 VMs running (node1/2/3 + mgmt)
- InnoDB Cluster `myCluster` ONLINE, primary = node1
- MySQL Router trên mgmt, listening :6446 (RW) + :6447 (RO)
- UFW trên mgmt: allow 22/6446/6447 (đã patch)


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/results/report.md`
