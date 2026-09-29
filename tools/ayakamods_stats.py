#!/usr/bin/env python3
"""
Read the AyakaMods page and write shields.io endpoint badges:

    python tools/ayakamods_stats.py OUT_DIR [PAGE_URL]

Writes OUT_DIR/ayakamods-downloads.json, -views.json, -rating.json (only the ones it
could read). Used by .github/workflows/ayakamods-badges.yml; exits 1 if nothing was found
so the old badges stay up.
"""
import html
import json
import os
import re
import sys
import urllib.request

PAGE = "https://ayakamods.com/mods/super-earth-armory-forge.4359/"
COLOR = "ffe710"


def fetch(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (badge updater; +https://github.com/Hung1510/Super-Earth-Armory-Forge)",
        "Accept": "text/html"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def num(s):
    s = s.strip().replace(",", "").replace(" ", "")
    m = re.fullmatch(r"([\d.]+)\s*([KkMm]?)", s)
    if not m:
        return None
    v = float(m.group(1)) * {"": 1, "k": 1e3, "m": 1e6}[m.group(2).lower()]
    return int(round(v))


def meta(page, name):
    for tag in re.findall(r"<meta\b[^>]*>", page, re.I):
        if re.search(r'(?:name|property)\s*=\s*["\']%s["\']' % re.escape(name), tag, re.I):
            m = re.search(r'content\s*=\s*["\']([^"\']*)["\']', tag, re.I)
            if m:
                return html.unescape(m.group(1))
    return None


def labelled(page, label):
    """A number next to a label: <dt>Views</dt><dd>590</dd>, title="Views" ... 590, fa-eye ... 590."""
    pats = [
        r">\s*%s\s*</dt>\s*<dd[^>]*>\s*(?:<[^>]+>\s*)*([\d.,]+\s*[KkMm]?)" % label,
        r'title\s*=\s*["\']%s["\'][^>]*>(?:\s*<[^>]+>)*\s*([\d.,]+\s*[KkMm]?)' % label,
        r'aria-label\s*=\s*["\']%s["\'][^>]*>(?:\s*<[^>]+>)*\s*([\d.,]+\s*[KkMm]?)' % label,
    ]
    if label.lower() == "views":
        pats.append(r"fa-eye\b[^>]*>(?:\s*</?[^>]+>)*\s*([\d.,]+\s*[KkMm]?)")
    for p in pats:
        m = re.search(p, page, re.I | re.S)
        if m and num(m.group(1)) is not None:
            return num(m.group(1))
    # last resort: the page as plain text, "Views: 590" or "590 views"
    text = html.unescape(re.sub(r"<[^>]+>", " ", re.sub(r"(?is)<(script|style)\b.*?</\1>", " ", page)))
    text = re.sub(r"\s+", " ", text)
    for p in (r"\b%s\s*:?\s*([\d.,]+\s*[KkMm]?)\b" % label, r"\b([\d.,]+\s*[KkMm]?)\s+%s\b" % label):
        m = re.search(p, text, re.I)
        if m and num(m.group(1)) is not None:
            return num(m.group(1))
    return None


def short(n):
    if n >= 1_000_000:
        return ("%.1fM" % (n / 1e6)).replace(".0M", "M")
    if n >= 10_000:
        return "%dk" % (n // 1000)
    if n >= 1_000:
        return ("%.1fk" % (n / 1e3)).replace(".0k", "k")
    return str(n)


def stats(page):
    out = {}
    label1, data1 = meta(page, "twitter:label1"), meta(page, "twitter:data1")
    if data1 and (label1 or "downloads").lower().startswith("download"):
        out["downloads"] = num(data1)
    if out.get("downloads") is None:
        out["downloads"] = labelled(page, "Downloads")
    out["views"] = labelled(page, "Views")
    for k in ("label2", "label3"):
        lab, val = meta(page, "twitter:" + k), meta(page, "twitter:" + k.replace("label", "data"))
        if lab and val and lab.lower().startswith("rating"):
            m = re.match(r"\s*([\d.]+)\s*/\s*5", val)
            if m:
                out["rating"] = float(m.group(1))
    if "rating" not in out:
        val = meta(page, "twitter:data3")
        m = re.match(r"\s*([\d.]+)\s*/\s*5", val or "")
        if m:
            out["rating"] = float(m.group(1))
    return {k: v for k, v in out.items() if v is not None}


def badge(label, message):
    return {"schemaVersion": 1, "label": label, "message": message, "color": COLOR,
            "labelColor": "0b0c0d", "cacheSeconds": 3600}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    url = sys.argv[2] if len(sys.argv) > 2 else PAGE
    page = open(url[7:], encoding="utf-8").read() if url.startswith("file://") else fetch(url)
    s = stats(page)
    print(json.dumps(s))
    if not s:
        print("nothing found on the page; keeping the old badges", file=sys.stderr)
        return 1
    os.makedirs(out_dir, exist_ok=True)
    made = {"downloads": ("AyakaMods downloads", lambda v: short(v)),
            "views": ("AyakaMods views", lambda v: short(v)),
            "rating": ("rating", lambda v: ("%.1f" % v).rstrip("0").rstrip(".") + "/5")}
    for key, (label, fmt) in made.items():
        if key in s:
            with open(os.path.join(out_dir, "ayakamods-%s.json" % key), "w") as f:
                json.dump(badge(label, fmt(s[key])), f)
    with open(os.path.join(out_dir, "ayakamods.json"), "w") as f:
        json.dump(s, f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
