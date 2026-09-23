#!/usr/bin/env python3
"""Generate llms.txt (plain-text edition) from index.html. Standard library only.

    python3 tools/build_llms.py            # writes llms.txt next to index.html
    python3 tools/build_llms.py --check    # exit 1 if llms.txt is out of date

Never hand-edit llms.txt: edit index.html and re-run this script.
SVG maps, <style> and <script> are dropped; tables become pipe tables; headings become
Markdown headings; "Team research · Name" tags become [Team research · Name: <source>].
"""
import html
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE_URL = "https://jonathanwong1990.github.io/nyc-restroom-gap/"
REPO = "https://github.com/JonathanWong1990/nyc-restroom-gap"
TABS = [("walk", "Walkthrough"), ("lim", "Limits"), ("data", "Data & code")]  # the archived "original" tab is excluded on purpose

HEADER = """# NYC Restroom Gap — plain-text edition for AI assistants

Generated from index.html of {url} (last updated {stamp}) by tools/build_llms.py.
Do not edit by hand. The web page embeds large SVG maps that are useless to a language
model; everything else from all three tabs is below. Read all three before answering
questions about reliability: the Walkthrough states findings, the Limits tab bounds them
and lists the open questions.

Hold onto three things. The ranking ORDERS neighbourhoods; it does not prove any single one
is underserved. No New York causal effect was measured (two designs failed, one on a
placebo set in advance), so there is no return-on-investment figure here. Items marked
[Team research · Name: ...] come from the named teammate's research, checked against the
primary source.

Authoritative sources, in order (the first outranks this file):
- {repo}/blob/main/analysis/outputs/headline_numbers.json  (every number, with its script)
- {repo}/blob/main/METHODS.md
- {repo}

---
"""


class Extract(HTMLParser):
    """Turn one tab's HTML into light Markdown."""

    SKIP = {"svg", "style", "script"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []          # finished blocks
        self.buf = []          # current inline text
        self.skip = 0
        self.list_stack = []   # 'ul' / 'ol' counters
        self.table = None      # list of rows
        self.row = None
        self.cell = None
        self.href = None
        self.tag_title = None
        self.in_pre = False

    # -- helpers --
    def flush(self, prefix=""):
        text = "".join(self.buf)
        if not self.in_pre:
            text = re.sub(r"\s+", " ", text).strip()
        self.buf = []
        if text:
            self.out.append(prefix + text)

    def emit(self, s):
        if self.cell is not None:
            self.cell.append(s)
        else:
            self.buf.append(s)

    # -- parser callbacks --
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in self.SKIP:
            self.skip += 1
            return
        if self.skip:
            return
        cls = a.get("class", "") or ""
        if "tag-team" in cls.split():
            t = a.get("title", "")
            self.tag_title = t.split(" — ", 1)[1] if " — " in t else t
            self.tag_label = []
            return
        if tag in ("h2", "h3", "p", "figure", "figcaption", "aside", "div", "pre"):
            self.flush()
        if tag == "pre":
            self.in_pre = True
        if tag in ("ul", "ol"):
            self.flush()
            self.list_stack.append([tag, 0])
        elif tag == "li":
            self.flush()
            if self.list_stack:
                self.list_stack[-1][1] += 1
        elif tag in ("strong", "b"):
            self.emit("**")
        elif tag == "em":
            self.emit("*")
        elif tag == "code" and not self.in_pre:
            self.emit("`")
        elif tag == "br":
            self.emit(" ")
        elif tag == "a":
            self.href = a.get("href")
        elif tag == "img":
            self.flush()
            self.out.append("[Chart: %s] (%s)" % (a.get("alt", ""), a.get("src", "")))
        elif tag == "table":
            self.flush()
            self.table = []
        elif tag == "tr":
            self.row = []
        elif tag in ("td", "th"):
            self.cell = []

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip -= 1
            return
        if self.skip:
            return
        if tag == "span" and self.tag_title is not None:
            label = re.sub(r"\s+", " ", "".join(self.tag_label)).strip() or "Team research"
            self.emit(" [%s: %s]" % (label, self.tag_title) if self.tag_title != "legend" else " [%s]" % label)
            self.tag_title = None
            return
        if tag == "h2":
            self.flush("## ")
        elif tag == "h3":
            self.flush("### ")
        elif tag == "li":
            depth = len(self.list_stack)
            kind, n = self.list_stack[-1] if self.list_stack else ("ul", 0)
            bullet = "%d. " % n if kind == "ol" else "- "
            self.flush("  " * (depth - 1) + bullet)
        elif tag in ("ul", "ol"):
            self.flush()
            if self.list_stack:
                self.list_stack.pop()
        elif tag in ("p", "figcaption", "aside", "div", "figure"):
            self.flush()
        elif tag == "pre":
            text = "".join(self.buf).strip("\n")
            self.buf = []
            self.in_pre = False
            self.out.append("```\n" + text + "\n```")
        elif tag in ("strong", "b"):
            self.emit("**")
        elif tag == "em":
            self.emit("*")
        elif tag == "code" and not self.in_pre:
            self.emit("`")
        elif tag == "a":
            if self.href and not self.href.startswith("#"):
                href = self.href
                if not re.match(r"^[a-z]+:", href):
                    href = SITE_URL + href
                self.emit(" <%s>" % href)
            self.href = None
        elif tag in ("td", "th"):
            txt = re.sub(r"\s+", " ", "".join(self.cell)).strip().replace("|", "/")
            self.row.append(txt)
            self.cell = None
        elif tag == "tr":
            self.table.append(self.row)
            self.row = None
        elif tag == "table":
            rows = self.table
            self.table = None
            if rows:
                w = max(len(r) for r in rows)
                rows = [r + [""] * (w - len(r)) for r in rows]
                lines = ["| " + " | ".join(rows[0]) + " |", "|" + "---|" * w]
                lines += ["| " + " | ".join(r) + " |" for r in rows[1:]]
                self.out.append("\n".join(lines))

    def handle_data(self, data):
        if self.skip:
            return
        if self.tag_title is not None:
            self.tag_label.append(data)
            return
        self.emit(data)


def tab_html(src, tab):
    m = re.search(r'<div id="%s"[^>]*>' % tab, src)
    if not m:
        sys.exit("tab #%s not found in index.html" % tab)
    # the tab ends where the next top-level tab div or the footer starts
    rest = src[m.end():]
    # the archived <section data-archive="true"> tab is a boundary too, and is never extracted
    end = re.search(r'\n<div id="(walk|lim|data)"|\n<section id="[^"]*" data-archive="true"|\n<footer', rest)
    return rest[: end.start()] if end else rest


def build():
    src = (ROOT / "index.html").read_text(encoding="utf-8")
    stamp = re.search(r'class="stamp">\s*Updated ([^<]+)<', src)
    stamp = stamp.group(1).strip() if stamp else "unknown"
    parts = [HEADER.format(url=SITE_URL, stamp=stamp, repo=REPO)]
    for tab, _ in TABS:
        p = Extract()
        chunk = re.sub(r'(?s)<div class="maplegend">.*?</div>', "", tab_html(src, tab))
        chunk = re.sub(r'(?s)<div class="(mapwrap|pair)[^"]*">', r'<p>[Map: see the web page]</p>\g<0>', chunk)
        p.feed(chunk)
        p.flush()
        parts.append("\n\n".join(b for b in p.out if b.strip()))
        parts.append("\n---\n")
    text = "\n".join(parts)
    text = html.unescape(text)
    text = re.sub(r"\*\*\s*\*\*", "", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    # keep list items together
    li = r"(?:[ ]*- |[ ]*\d+\. )"
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r"(\n%s[^\n]*)\n\n(?=%s)" % (li, li), r"\1\n", text)
    text = text.rstrip() + "\n"
    return text


def main():
    text = build()
    target = ROOT / "llms.txt"
    if "--check" in sys.argv:
        cur = target.read_text(encoding="utf-8") if target.exists() else ""
        if cur != text:
            print("llms.txt is out of date: run python3 tools/build_llms.py")
            sys.exit(1)
        print("llms.txt is current")
        return
    target.write_text(text, encoding="utf-8")
    print("wrote %s (%d words)" % (target.name, len(text.split())))


if __name__ == "__main__":
    main()
