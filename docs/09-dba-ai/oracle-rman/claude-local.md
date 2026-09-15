---
title: CLAUDE.local.md — Ghi chú cá nhân (không commit)
course: 09-dba-ai
source: dba_ai/oracle_rman/CLAUDE.local.md
---

# CLAUDE.local.md — Ghi chú cá nhân (không commit)

> File này bị .gitignore. Ghi mọi thứ cá nhân, tạm thời, hoặc nhạy cảm ở đây.

## Lab Connection

```text
SSH  : oracle@192.168.1.8  (pass: oracle)
RMAN : rman target /
RMAN + catalog: rman TARGET sys/oracle@oradb CATALOG rcowner/oracle@catdb
sqlplus: sqlplus / as sysdba
```

## Tình trạng lab hiện tại

- Oracle 12c R2 (12.2.0.1) — SID=ORADB
- FRA: /u01/app/oracle/fast_recovery_area — 10GB
- Backup dir: /backup/rman
- Archivelog: ARCHIVELOG mode ✅
- Recovery Catalog: catdb trên cùng server

## Ghi chú phiên làm việc

<!-- Thêm ghi chú tạm thời tại đây, xóa khi xong -->

## Passwords (không commit)

<!-- wallet_password=... -->
<!-- sys_password=oracle -->


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/CLAUDE.local.md`
