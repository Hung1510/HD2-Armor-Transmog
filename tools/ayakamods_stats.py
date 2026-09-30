#!/usr/bin/env python3
"""
Read the AyakaMods page and write shields.io endpoint badges:

    python tools/ayakamods_stats.py OUT_DIR [PAGE_URL]

Writes OUT_DIR/ayakamods-downloads.json, -views.json, -rating.json (only the ones it
could read). Used by tools/update_badges_local.ps1; if nothing was found the old
badges stay up.

AyakaMods sits behind a Cloudflare JavaScript challenge that plain HTTP clients can't pass
(403 + "cf-mitigated: challenge"). Set AYAKAMODS_BROWSER=msedge (or chrome) to read the
page through that installed browser instead, via Playwright (pip install playwright; no
browser download needed). tools/update_badges_local.ps1 does this on a home PC.
"""
import html
import json
import os
import re
import sys
import time
import urllib.request

# tried in order. The mod was renamed; the old slug is the one AyakaMods serves directly
# (the new slug stalls on the Cloudflare check through a browser), the id alone redirects.
PAGES = ["https://ayakamods.com/mods/passive-picker-v4.4359/",
         "https://ayakamods.com/mods/super-earth-armory-forge.4359/",
         "https://ayakamods.com/mods/4359/"]
PAGE = PAGES[0]
# AyakaMods sometimes answers CI runners with a 403 / bot-check page. If no
# address works, wait and go round again before keeping the old badges.
RETRY_WAITS = (20, 60, 120)
COLOR = "ffe710"


def fetch(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/126.0 Safari/537.36 (badge updater; +https://github.com/Hung1510/Super-Earth-Armory-Forge)",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def browser_stats(urls, channel):
    """Open the page in a real installed browser, wait out the Cloudflare check, read it.

    Uses a persistent profile so the Cloudflare clearance cookie survives between runs.
    The window is placed off-screen; it has to be a headed browser, headless ones get
    challenged again.
    """
    from playwright.sync_api import sync_playwright
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    profile = os.path.join(base, "ArmoryForgeBadges", "browser-profile")
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            profile, channel=channel, headless=False,
            args=["--window-position=-32000,-32000", "--window-size=1280,900",
                  "--disable-blink-features=AutomationControlled"])
        try:
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            for url in urls:
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=60000)
                except Exception as e:
                    print("%s: %s" % (url, e), file=sys.stderr)
                    continue
                for _ in range(45):                 # challenge usually clears in 5-15 s
                    try:
                        s = stats(page.content())
                    except Exception:               # mid-redirect after the challenge clears
                        s = {}
                        try:
                            page.wait_for_load_state("domcontentloaded", timeout=15000)
                        except Exception:
                            pass
                    if s:
                        print("%s (%s): %s" % (url, channel, json.dumps(s)))
                        return s
                    page.wait_for_timeout(1000)
                print("%s (%s): no stats after 45 s (challenge not cleared?)" % (url, channel),
                      file=sys.stderr)
        finally:
            ctx.close()
    return {}


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
    urls = [sys.argv[2]] if len(sys.argv) > 2 else PAGES
    s = {}
    local = all(u.startswith("file://") for u in urls)
    channel = os.environ.get("AYAKAMODS_BROWSER", "").strip()
    if channel and not local:
        try:
            s = browser_stats(urls, channel)
        except Exception as e:                      # playwright missing, browser won't start...
            print("browser (%s): %s" % (channel, e), file=sys.stderr)
        urls = [] if s else urls                    # got it: skip the plain HTTP rounds
    for wait in (0,) + (() if local or channel else RETRY_WAITS):
        if s:
            break
        if wait:
            print("no address worked; retrying in %ds" % wait, file=sys.stderr)
            time.sleep(wait)
        for url in urls:
            try:
                page = open(url[7:], encoding="utf-8").read() if url.startswith("file://") else fetch(url)
            except Exception as e:                  # blocked, moved, down: try the next address
                print("%s: %s" % (url, e), file=sys.stderr)
                continue
            s = stats(page)
            print("%s: %s" % (url, json.dumps(s)))
            if s:
                break
        if s:
            break
    if not s:
        # not an error worth an email: the badges just keep their last numbers
        print("::warning::could not read the AyakaMods page; keeping the old badges")
        return 0
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
