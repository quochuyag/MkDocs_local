#!/usr/bin/env python3
"""Khao sat: bao nhieu bai hoc co noi dung tieng Viet, theo tung khoa."""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from sync import collect  # noqa: E402

# Ky tu chi co trong tieng Viet (khong co trong tieng Anh)
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

# Bo code block va inline code truoc khi dem -> tranh dem nham
FENCE_RE = re.compile(r"```.*?```", re.S)
INLINE_RE = re.compile(r"`[^`]*`")


def vi_score(text):
    """Tra ve (so ky tu tieng Viet, ty le tren tong chu cai)."""
    body = FENCE_RE.sub(" ", text)
    body = INLINE_RE.sub(" ", body)
    n_vi = len(VI_RE.findall(body))
    n_alpha = sum(1 for c in body if c.isalpha())
    ratio = n_vi / n_alpha if n_alpha else 0.0
    return n_vi, ratio


def main():
    cfg = yaml.safe_load((ROOT / "manifest" / "courses.yml").read_text(encoding="utf-8"))
    src_root = Path(cfg["source_root"])
    exclude = set(cfg["exclude_dirs"])

    print("{:<30} {:>6} {:>6} {:>7}".format("KHOA", "TONG", "CO VI", "TY LE"))
    print("-" * 52)
    tot_all = tot_vi = 0
    for course in cfg["courses"]:
        cdir = src_root / course["path"]
        if not cdir.is_dir():
            continue
        files = collect(cdir, exclude)
        n_vi = 0
        for p in files:
            try:
                txt = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            cnt, ratio = vi_score(txt)
            # Nguong: it nhat 30 ky tu tieng Viet VA chiem >= 1% chu cai
            if cnt >= 30 and ratio >= 0.01:
                n_vi += 1
        tot_all += len(files)
        tot_vi += n_vi
        pct = (100.0 * n_vi / len(files)) if files else 0
        print("{:<30} {:>6} {:>6} {:>6.0f}%".format(course["id"], len(files), n_vi, pct))

    print("-" * 52)
    pct = (100.0 * tot_vi / tot_all) if tot_all else 0
    print("{:<30} {:>6} {:>6} {:>6.0f}%".format("TONG", tot_all, tot_vi, pct))


if __name__ == "__main__":
    main()
