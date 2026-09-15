---
title: Báo cáo Demo 08 — Vagrant Lab
course: 06-high-availability
source: HA/Mysql/demo/08-vagrant-lab/results/report.md
---

# Báo cáo Demo 08 — Vagrant Lab

## 1. Thông tin

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-20 (B4 verify ~21:14–21:20 host time) |
| Host OS | Windows 11 Pro 10.0.26200 |
| Hypervisor | Oracle VirtualBox (VBoxManage.exe ở `C:\Program Files\Oracle\VirtualBox\`) |
| Box | ubuntu/jammy64 (Ubuntu 22.04 LTS) |

## 2. VMs đã spin up

| Host  | IP             | RAM    | State (lúc verify) |
|-------|----------------|--------|--------------------|
| node1 | 192.168.10.11  | 2 GB   | running |
| node2 | 192.168.10.12  | 2 GB   | running |
| node3 | 192.168.10.13  | 2 GB   | running |
| mgmt  | 192.168.10.20  | 1.5 GB | running |

VBox VM IDs (current):
- `mysql-ha-node1` `{626ed48a-ed7a-43bc-8930-d605ffc51f99}`
- `mysql-ha-node2` `{710280a2-4ddf-4fd9-a56c-4353adc909a1}`
- `mysql-ha-node3` `{512202ec-8ba0-404a-b4b9-58f1a357f934}`
- `mysql-ha-mgmt`  `{b5a0694c-d8ab-46d4-a61f-a19641c66ad1}`

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 vagrant-up   | PASS | ~600s lần đầu (download box ~600MB), idempotent sau đó | [01-vagrant-up.log](01-vagrant-up.log) |
| B2 prepare-os   | PASS | <120s | [02-prepare-os.log](02-prepare-os.log) |
| B3 ssh-trust    | PASS | <60s | [03-ssh-trust.log](03-ssh-trust.log) |
| B4 verify       | PASS | ~358s | [04-verify.log](04-verify.log) |
| B5 snapshot     | PASS (chạy thủ công) | — | [05-snapshot-clean.log](05-snapshot-clean.log) |

## 4. Checkpoint (từ B4 verify)

| # | Kiểm tra | Pass? |
|---|----------|-------|
| 1 | 4 VMs `running` | ✓ (node1/2/3/mgmt) |
| 2 | Ping nội bộ giữa mọi cặp (12 hướng) | ✓ (12/12 OK) |
| 3 | `/etc/hosts` đủ ≥4 entries (mọi VM) | ✓ (9 entries mỗi host) |
| 4 | Swap OFF | ✓ (cả 4 VM) |
| 5 | NTP synchronized | ✓ (cả 4 VM) |
| 6 | `vm.swappiness=1` + `fs.file-max=2097152` | ✓ |
| 7 | SSH trust 12 hướng (4×3) hoạt động | ✓ (12/12 SSH OK) |

## 5. Quan sát & nhận xét

### Điểm tốt
- Lab idempotent: `vagrant up` chạy lại không phá state. Có thể chạy nhiều demo lần lượt mà không cần destroy.
- 12 hướng SSH trust nhờ provisioner `ssh-trust` đảm bảo các demo cần copy file/exec lệnh chéo (MHA, Orchestrator, Galera SST) hoạt động trơn tru.
- `provision/cluster_id_rsa` sinh local + gitignored — không leak key ra repo.

### Bugs đã encountered & fix (qua memory)
- `bug_vbox_hostonly_ndis_filter.md`: `VERR_INTNET_FLT_IF_NOT_FOUND` adapter #7 — fix bằng `fix-vbox-hostonly.ps1` Method A.
- `bug_vboxmanage_not_in_path_gitbash.md`: Git Bash trên Windows không tự thêm `C:\Program Files\Oracle\VirtualBox\` vào PATH → auto-detect pattern thêm vào `01-vagrant-up.sh`.
- `bug_ufw_blocks_ssh.md`: `02-firewall.sh` enable UFW không allow 22 → khoá SSH. Đã fix.
- `bug_ssh_trust_vagrant_user_missing.md`: provisioner cũ chỉ set `/root/.ssh`; demo dùng `vagrant ssh` (user vagrant) bị treo. Đã fix set cả 2 user.

### Hạn chế
- 4 VMs × ~7GB RAM khi tất cả running — host cần ≥16GB RAM tổng. (Hiện tại host có đủ.)
- VirtualBox snapshot 4 VMs tốn ~3GB disk; mỗi rollback ~30s.
- Mỗi demo HA chỉ chọn 1 stack data-plane → cần `bash demo/<X>/09-rollback.sh` trước khi chuyển stack khác (đặc biệt: Galera ↔ MySQL community).

## 6. Bằng chứng (từ B4 verify, rút gọn)

```
[ OK ] [node1/node2/node3/mgmt] running
[ OK ] ping 12/12 OK (4 hosts × 3 peers)
[ OK ] [node1/2/3/mgmt] /etc/hosts có ≥4 entries (9)
[ OK ] [node1/2/3/mgmt] swap OFF
[ OK ] [node1/2/3/mgmt] NTP synchronized
[ OK ] [node1/2/3/mgmt] vm.swappiness=1 fs.file-max=2097152
[ OK ] ssh 12/12 OK (4 hosts × 3 peers)
VERIFY_PASS=true — lab sẵn sàng cho bất kỳ demo HA nào
```

## 7. Bước tiếp theo

- [ ] Snapshot tất cả VM ở state "clean OS + MySQL chưa cài" để có rollback point trước khi chạy demo HA mới (`05-snapshot-clean.sh`).
- [ ] Nếu workshop kết thúc: `bash 09-cleanup.sh --all --yes` để release ~30GB disk + free RAM.
- [ ] Cân nhắc dùng `vagrant cloud` hoặc base image custom (đã có sẵn MySQL + tooling) → giảm B1+B2+B3 từ ~15 phút xuống ~3 phút.
- [ ] Nếu chuyển sang ARM Mac: cần box `bento/ubuntu-22.04-arm64` thay `ubuntu/jammy64`.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/08-vagrant-lab/results/report.md`
