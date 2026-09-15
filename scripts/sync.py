#!/usr/bin/env python3
"""
Gom toan bo bai hoc .md tu D:/Dba_project ve MkDocs_local/docs/

- Moi thu muc goc = 1 khoa hoc
- Chuan hoa ten file: chi a-z 0-9 -
- Giu thu tu tang dan bang prefix so
- Giu tieu de tieng Viet co dau trong front-matter

File goc KHONG bi thay doi. docs/ la ban sinh tu dong.
"""
import hashlib
import os
import re
import shutil
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote

import yaml

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "manifest" / "courses.yml"
DOCS = ROOT / "docs"

IMG_EXT = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".bmp"}

# Khop ca anh ![alt](path) lan link thuong [text](path "title").
# Bat tron phan trong ngoac de khong cat nham duong dan co khoang trang.
# Cho phep 1 cap ngoac long nhau: "Introduction to RMAN (RMAN).md"
LINK_RE = re.compile(r'(!?\[[^\]]*\]\()((?:[^()]|\([^()]*\))*)(\))')

# Tach phan duong dan khoi tieu de tuy chon: path "title" / path 'title'
TITLE_SUFFIX_RE = re.compile(r'^(.*?)(\s+["\'].*["\'])\s*$', re.S)

# Anh nhung bang HTML: <img src="path">
HTML_IMG_RE = re.compile(r'(<img[^>]*\ssrc\s*=\s*["\'])([^"\']+)(["\'])', re.I)

# File tai nguyen di kem bai hoc -> copy sang docs de link khong bi hong
ASSET_EXT = {
    ".sql", ".txt", ".js", ".py", ".sh", ".ps1", ".yml", ".yaml", ".json",
    ".conf", ".cfg", ".ini", ".cypher", ".rman", ".ora", ".log", ".csv",
    ".pdf", ".zip", ".html", ".htm", ".ics", ".mjs", ".psd1", ".expect",
    ".cksum", ".sql", ".xml", ".sqlplus",
}
SKIP_LINK_PREFIX = ("http://", "https://", "mailto:", "tel:", "data:", "#", "//")

# --- Nhan dien noi dung tieng Viet ---
# Ky tu chi xuat hien trong tieng Viet, khong co trong tieng Anh
VI_CHARS = (
    "ăâđêôơưĂÂĐÊÔƠƯ"
    "áàảãạấầẩẫậắằẳẵặ"
    "éèẻẽẹếềểễệ"
    "íìỉĩị"
    "óòỏõọốồổỗộớờởỡợ"
    "úùủũụứừửữự"
    "ýỳỷỹỵ"
    "ÁÀẢÃẠẤẦẨẪẬẮẰẲẴẶ"
    "ÉÈẺẼẸẾỀỂỄỆ"
    "ÍÌỈĨỊ"
    "ÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢ"
    "ÚÙỦŨỤỨỪỬỮỰ"
    "ÝỲỶỸỴ"
)
VI_RE = re.compile("[" + VI_CHARS + "]")

# Bo code block truoc khi dem -> tranh dem nham ten bien, output lenh
FENCE_RE = re.compile(r"```.*?```", re.S)
INLINE_CODE_RE = re.compile(r"`[^`]*`")


def slugify(text):
    """Bo dau tieng Viet, ve kebab-case ASCII."""
    text = text.replace("\u0110", "D").replace("\u0111", "d")
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    text = re.sub(r"-{2,}", "-", text).strip("-")
    return text or "untitled"


def num_prefix(name):
    """Lay so dau ten de sap xep: '055 - 058 - Managing' -> '055'."""
    m = re.match(r"^(\d{1,4})", name.strip())
    return m.group(1).zfill(3) if m else None


def strip_lead_num(name):
    """Bo cac cum so dan dau: '002 - 003 - Practice' -> 'Practice'."""
    return re.sub(r"^(\s*\d{1,4}\s*[-_.]\s*)+", "", name).strip()


def extract_title(path):
    """Lay H1 dau tien lam tieu de; khong co thi suy tu ten file."""
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            for _ in range(80):
                line = fh.readline()
                if not line:
                    break
                s = line.strip()
                if s.startswith("# "):
                    t = s[2:].strip().strip("#").strip()
                    if t:
                        return t
    except OSError:
        pass
    fallback = strip_lead_num(path.stem).replace("_", " ").replace("-", " ").strip()
    return fallback or path.stem


def vi_score(text):
    """Do luong tieng Viet trong bai: (so ky tu VI, ty le tren tong chu cai)."""
    body = FENCE_RE.sub(" ", text)
    body = INLINE_CODE_RE.sub(" ", body)
    n_vi = len(VI_RE.findall(body))
    n_alpha = sum(1 for c in body if c.isalpha())
    return n_vi, (n_vi / n_alpha if n_alpha else 0.0)


def is_vietnamese(text, min_chars, min_ratio):
    n_vi, ratio = vi_score(text)
    return n_vi >= min_chars and ratio >= min_ratio


def file_hash(path):
    h = hashlib.md5()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


NUM_CHUNK_RE = re.compile(r"(\d+)")

# Trang duoc dua len dau trong moi thu muc (neu co).
INDEX_FIRST = ("index.md", "readme.md")


def nat_key(name):
    """Khoa sap xep tu nhien: section-2 dung truoc section-10.

    Tach ten thanh cac doan chu / so; doan so so sanh bang gia tri,
    nen khong con canh section-2 nam sau section-19 nhu sap xep chuoi.
    Doan so xep truoc doan chu, giu bai danh so (001-, 002-...) len dau
    giong hanh vi cu.
    """
    return [
        (0, int(chunk), "") if chunk.isdigit() else (1, 0, chunk.lower())
        for chunk in NUM_CHUNK_RE.split(name)
        if chunk
    ]


def has_pages(d):
    """Thu muc co bai hoc .md nao khong (ke ca trong thu muc con)."""
    return any(True for _ in d.rglob("*.md"))


def write_pages_tree(out_dir, title=None):
    """Sinh .pages cho ca cay khoa hoc, nav liet ke tuong minh.

    Khong dung "order: asc" vi awesome-pages sap xep theo chuoi.
    """
    dirs = [out_dir] + sorted(x for x in out_dir.rglob("*") if x.is_dir())
    for d in dirs:
        children = []
        for c in d.iterdir():
            if c.name == ".pages":
                continue
            if c.is_dir():
                if has_pages(c):
                    children.append(c.name)
            elif c.suffix.lower() == ".md":
                children.append(c.name)

        first = [n for n in INDEX_FIRST if n in children]
        rest = sorted((n for n in children if n not in first), key=nat_key)

        out = []
        if title is not None and d == out_dir:
            out.append("title: {}".format(title))
        out.append("nav:")
        out += ["  - {}".format(n) for n in first + rest]
        out.append("  - ...")  # phong khi con sot muc nao do
        (d / ".pages").write_text("\n".join(out) + "\n", encoding="utf-8")


def collect(course_dir, exclude):
    """Liet ke .md hop le trong 1 khoa."""
    out = []
    for p in course_dir.rglob("*.md"):
        if not p.is_file():
            continue
        rel_parts = p.relative_to(course_dir).parts[:-1]
        if any(part in exclude for part in rel_parts):
            continue
        out.append(p)
    return sorted(out)


def dedupe_in_course(files):
    """Bo file trung byte-for-byte TRONG cung 1 khoa.

    Giu ban nam sau hon trong cay thu muc (vd ban trong modules/module_01/
    thay vi ban phang modules/).
    """
    seen = {}
    kept = []
    dropped = []
    for p in sorted(files, key=lambda x: (-len(x.parts), str(x))):
        h = file_hash(p)
        if h in seen:
            dropped.append(p)
        else:
            seen[h] = p
            kept.append(p)
    return sorted(kept), dropped


def build_target(rel, siblings_md):
    """Dung duong dan dich da chuan hoa, giu prefix so de sap xep."""
    parts = list(rel.parts)
    stem = Path(parts[-1]).stem
    dirs = parts[:-1]

    # Thu muc chi chua dung 1 file .md va co prefix so -> gop thanh 1 trang
    if dirs and siblings_md == 1:
        last = dirs[-1]
        n = num_prefix(last)
        if n:
            core = slugify(strip_lead_num(stem)) or slugify(strip_lead_num(last))
            parent = Path(*[slugify(d) for d in dirs[:-1]]) if dirs[:-1] else Path(".")
            return parent / "{}-{}.md".format(n, core)

    n = num_prefix(stem)
    core = slugify(strip_lead_num(stem))
    fname = "{}-{}.md".format(n, core) if n else "{}.md".format(core)
    parent = Path(*[slugify(d) for d in dirs]) if dirs else Path(".")
    return parent / fname


def yaml_str(value):
    """Dong goi tieu de an toan cho YAML front-matter."""
    dumped = yaml.safe_dump(value, allow_unicode=True, default_flow_style=True)
    return dumped.strip().rstrip("...").strip()


def asset_target(resolved, cdir, out_dir):
    """Vi tri dich da chuan hoa cho 1 file tai nguyen (anh, script...)."""
    try:
        rel = resolved.relative_to(cdir)
    except ValueError:
        # File nam ngoai thu muc khoa -> dua vao _assets/
        return out_dir / "_assets" / (slugify(resolved.stem) + resolved.suffix.lower())
    dirs = [slugify(d) for d in rel.parts[:-1]]
    name = slugify(Path(rel.parts[-1]).stem) + resolved.suffix.lower()
    parent = Path(*dirs) if dirs else Path(".")
    return out_dir / parent / name


def rewrite_links(body, src_md, tgt_md, mapping, cdir, out_dir, copied):
    """Viet lai moi link theo ten da chuan hoa, copy tai nguyen di kem.

    - Link toi bai hoc khac  -> tro sang ten file moi
    - Link toi anh / script  -> copy sang docs voi ten sach, sua link
    - Link ngoai (http...)   -> giu nguyen
    """
    def resolve_one(link):
        """Tra ve duong dan moi cho link, hoac None neu giu nguyen."""
        if not link or link.startswith(SKIP_LINK_PREFIX):
            return None

        anchor = ""
        if "#" in link:
            link, anchor = link.split("#", 1)
            anchor = "#" + anchor
        if not link:
            return None

        # Tai lieu goc co ca duong dan kieu Windows: module_01\Ten bai.md
        raw = unquote(link).replace("\\", "/").strip()
        if not raw:
            return None
        try:
            resolved = (src_md.parent / raw).resolve()
        except (OSError, ValueError):
            return None

        # 1. Link toi bai hoc khac
        if resolved in mapping:
            try:
                new = Path(os.path.relpath(mapping[resolved], tgt_md.parent)).as_posix()
                return new + anchor
            except ValueError:
                return None

        # 2. Link toi anh / file tai nguyen -> copy + chuan hoa ten
        if not resolved.is_file():
            return None
        ext = resolved.suffix.lower()
        if ext not in IMG_EXT and ext not in ASSET_EXT:
            return None

        dst = asset_target(resolved, cdir, out_dir)
        if dst not in copied:
            try:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(resolved, dst)
                copied[dst] = resolved
            except (OSError, ValueError):
                return None
        try:
            return Path(os.path.relpath(dst, tgt_md.parent)).as_posix() + anchor
        except ValueError:
            return None

    def repl_md(m):
        inner = m.group(2).strip()
        if not inner:
            return m.group(0)

        # Tach tieu de tuy chon:  path "Tieu de"
        suffix = ""
        mt = TITLE_SUFFIX_RE.match(inner)
        if mt:
            inner, suffix = mt.group(1).strip(), mt.group(2)

        # Duong dan boc trong <...>
        wrapped = inner.startswith("<") and inner.endswith(">")
        if wrapped:
            inner = inner[1:-1].strip()

        new = resolve_one(inner)
        if new is None:
            return m.group(0)
        # Duong dan moi luon sach (khong khoang trang) nen bo <> di
        return m.group(1) + new + suffix + m.group(3)

    def repl_html(m):
        new = resolve_one(m.group(2))
        return m.group(0) if new is None else m.group(1) + new + m.group(3)

    body = LINK_RE.sub(repl_md, body)
    return HTML_IMG_RE.sub(repl_html, body)


def sync_course(course, src_root, exclude, vi_filter=None):
    """Dong bo 1 khoa hoc. Tra ve (so bai, so ban trung, so tai nguyen, so bai bo vi khong phai TV)."""
    cdir = src_root / course["path"]
    files = collect(cdir, exclude)
    dropped = []
    if course.get("drop_duplicates"):
        files, dropped = dedupe_in_course(files)

    # Chi giu bai co noi dung tieng Viet
    skipped_lang = 0
    if vi_filter:
        min_chars, min_ratio = vi_filter
        keep = []
        for p in files:
            try:
                txt = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if is_vietnamese(txt, min_chars, min_ratio):
                keep.append(p)
            else:
                skipped_lang += 1
        files = keep

    # Khoa khong con bai nao sau khi loc -> dung luon, khong tao thu muc
    if not files:
        return 0, len(dropped), 0, skipped_lang

    md_count = {}
    for p in files:
        md_count[p.parent] = md_count.get(p.parent, 0) + 1

    out_dir = DOCS / course["id"]

    # --- Luot 1: tinh duong dan dich cho moi file, dung ban do link ---
    used = set()
    plan = []
    mapping = {}
    for p in files:
        rel = p.relative_to(cdir)
        tgt_rel = build_target(rel, md_count[p.parent])

        # chong dung ten sau khi chuan hoa
        if out_dir / tgt_rel in used:
            i = 2
            while out_dir / tgt_rel.with_name("{}-{}.md".format(tgt_rel.stem, i)) in used:
                i += 1
            tgt_rel = tgt_rel.with_name("{}-{}.md".format(tgt_rel.stem, i))
        tgt = out_dir / tgt_rel
        used.add(tgt)
        plan.append((p, rel, tgt))
        try:
            mapping[p.resolve()] = tgt
        except (OSError, ValueError):
            pass

    # --- Luot 2: ghi file, viet lai link, copy anh va tai nguyen ---
    written = 0
    copied = {}
    for p, rel, tgt in plan:
        tgt.parent.mkdir(parents=True, exist_ok=True)
        title = extract_title(p)
        body = p.read_text(encoding="utf-8", errors="replace")
        body = rewrite_links(body, p, tgt, mapping, cdir, out_dir, copied)
        src_disp = "{}/{}".format(course["path"], rel.as_posix())

        front = (
            "---\n"
            "title: {}\n".format(yaml_str(title))
            + "course: {}\n".format(course["id"])
            + "source: {}\n".format(yaml_str(src_disp))
            + "---\n\n"
        )
        footer = '\n\n---\n\n!!! info "Nguồn gốc"\n    `{}`\n'.format(src_disp)
        tgt.write_text(front + body + footer, encoding="utf-8")
        written += 1

    (out_dir / "index.md").write_text(
        "---\ntitle: {}\n---\n\n".format(yaml_str(course["title"]))
        + "# {}\n\n{}\n\n".format(course["title"], course.get("desc", ""))
        + "- **Số bài học:** {}\n".format(written)
        + "- **Thư mục gốc:** `{}`\n\n".format(course["path"])
        + "Chọn bài học ở thanh điều hướng bên trái.\n",
        encoding="utf-8",
    )
    # .pages cho ca cay -> sap xep theo so tang dan
    write_pages_tree(out_dir, title=course["title"])
    return written, len(dropped), len(copied), skipped_lang


def main():
    cfg = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    src_root = Path(cfg["source_root"])
    exclude = set(cfg["exclude_dirs"])

    if DOCS.exists():
        shutil.rmtree(DOCS)
    DOCS.mkdir(parents=True)

    # Bo loc tieng Viet (bat/tat trong manifest)
    vi_cfg = cfg.get("vietnamese_only") or {}
    vi_filter = None
    if vi_cfg.get("enabled"):
        vi_filter = (int(vi_cfg.get("min_chars", 30)), float(vi_cfg.get("min_ratio", 0.01)))
        print("  [Loc tieng Viet: BAT  -  toi thieu {} ky tu VI, ty le >= {:.0%}]\n".format(*vi_filter))

    rows = []
    empty = []
    total_skip = 0
    for course in cfg["courses"]:
        if not (src_root / course["path"]).is_dir():
            print("  !! bo qua (khong ton tai): {}".format(course["path"]))
            continue
        written, ndrop, nasset, nskip = sync_course(course, src_root, exclude, vi_filter)
        total_skip += nskip

        # Khoa khong con bai nao -> khong dua vao site
        if written == 0:
            shutil.rmtree(DOCS / course["id"], ignore_errors=True)
            empty.append(course["id"])
            print("  {:<28} {:>4} bai  -> BO KHOI SITE (khong co bai tieng Viet)".format(
                course["id"], 0))
            continue

        rows.append((course["id"], course["title"], written))
        line = "  {:<28} {:>4} bai  {:>5} tai nguyen".format(course["id"], written, nasset)
        if ndrop:
            line += "  (bo {} trung)".format(ndrop)
        if nskip:
            line += "  (bo {} bai khong co TV)".format(nskip)
        print(line)

    total = sum(r[2] for r in rows)
    table = "\n".join(
        "| [{}]({}/) | {} |".format(title, cid, n) for cid, title, n in rows
    )
    (DOCS / "index.md").write_text(
        "---\ntitle: Trang chủ\n---\n\n"
        "# Thư viện khóa học DBA\n\n"
        "Quản lý tập trung **{} bài học** từ **{} khóa học**.\n\n".format(total, len(rows))
        + "| Khóa học | Số bài |\n|---|---:|\n"
        + table
        + "\n",
        encoding="utf-8",
    )
    # Nav goc: index truoc, roi cac khoa theo so tang dan
    course_dirs = sorted(
        (d.name for d in DOCS.iterdir() if d.is_dir() and has_pages(d)),
        key=nat_key,
    )
    (DOCS / ".pages").write_text(
        "nav:\n  - index.md\n"
        + "".join("  - {}\n".format(n) for n in course_dirs)
        + "  - ...\n",
        encoding="utf-8",
    )

    print("\n  TONG: {} bai / {} khoa".format(total, len(rows)))
    if total_skip:
        print("  Da bo {} bai khong co noi dung tieng Viet".format(total_skip))
    if empty:
        print("  Khoa bi loai het: {}".format(", ".join(empty)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
