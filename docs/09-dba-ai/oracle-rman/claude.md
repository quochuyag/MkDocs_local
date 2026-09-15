---
title: CLAUDE.md
course: 09-dba-ai
source: dba_ai/oracle_rman/CLAUDE.md
---

# CLAUDE.md

## Dự án

Oracle RMAN Backup & Recovery — 17 modules (Ahmed Baraka, Packt). Scripts chạy trên Linux Oracle server 192.168.1.8.

---

## BẮT BUỘC: LF Line Endings

`.sh` / `.sql` / `.rman` phải dùng **LF** — không CRLF. File tạo trên Windows nhưng chạy trên Linux.
Gọi SQL*Plus từ bash: `tr -d '\r' < script | sqlplus -S / as sysdba`

---

## BẮT BUỘC: Đọc skill file trước khi viết code

| Viết loại file | Đọc trước khi viết |
| --- | --- |
| `.sh` | `.claude/skills/skill-bash.md` |
| `.rman` | `.claude/skills/skill-rman.md` |
| `.sql` | `.claude/skills/skill-sql.md` |
| Script chứa lệnh nguy hiểm | `.claude/skills/skill-safety.md` |

Lệnh invoke full review: `/rman-review`

---

## Kết nối Lab

```text
SSH  : oracle@192.168.1.8  (pass: oracle)
RMAN : rman target /
RMAN + catalog: rman TARGET sys/oracle@oradb CATALOG rcowner/oracle@catdb
```

---

## Cấu trúc

```text
oracle_rman/
├── modules/           # 17 guide .md + progress.md
├── scripts/           # module_02 → module_06
├── reviews_all/       # Fire Drills, Mock Exams
└── .claude/
    ├── skills/        # skill-bash / rman / sql / safety .md
    └── commands/      # rman-review.md (full reference)
```

---

## Lệnh nguy hiểm — đọc skill-safety.md trước khi dùng

`ALTER SYSTEM SET ... SCOPE=SPFILE` | `ALTER SYSTEM SET CONTROL_FILES` | `ALTER DATABASE DROP LOGFILE` | `ALTER DATABASE ARCHIVELOG/NOARCHIVELOG` | `SHUTDOWN ABORT` | `CONFIGURE ... TO` (RMAN)


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/CLAUDE.md`
