#!/usr/bin/env python3
"""skills/obsidian-web-clip/lib/web-clip.py -- one URL -> one Web Clipper note.

Usage:
  web-clip.py <url> <vault>     write <vault>/99-Inbox/Web/<today> <title>.md
  web-clip.py --self-test       offline asserts on the pure helpers
  web-clip.py -h | --help | help

Discourse topics (<origin>/t/<id>.json answers with a post_stream) are
clipped from the first post's /raw markdown, with upload:// short links
mapped through the cooked HTML and the |WxH size suffix stripped. Every
other page takes a best-effort stdlib HTML -> markdown pass.

Output lines start with [OK] / [WARN] / [FAIL]. Exit 0 only when the note was
written. Never touches git: the vault's obsidian-git owns commits and sync.
curl + python3 stdlib only -- no new dependency.
"""

import datetime
import html
import json
import os
import re
import subprocess
import sys
import urllib.parse
from html.parser import HTMLParser

UA = "Mozilla/5.0 (pkm:obsidian-web-clip)"
FORBIDDEN = re.compile(r'[\\/:*?"<>|\x00-\x1f]')


class FetchError(Exception):
    pass


def fetch_ex(url):
    """Return (body, effective URL after redirects)."""
    # curl, not urllib: it uses the system trust store, which a corporate TLS
    # proxy's CA lives in, and python 3.13's strict X509 checks reject some
    # chains curl accepts.
    try:
        r = subprocess.run(
            ["curl", "-sSL", "--proto", "=http,https", "--proto-redir", "=http,https",
             "--max-time", "30", "-A", UA, "-w", "%{stderr}\n%{url_effective} %{http_code}",
             "--", url],
            capture_output=True, check=False,
        )
    except FileNotFoundError as e:
        raise FetchError("curl 이 없다") from e
    err = r.stderr.decode(errors="replace").strip()
    if r.returncode != 0:
        raise FetchError(f"network error {url}: {err}")
    effective, _, code = err.rsplit("\n", 1)[-1].rpartition(" ")
    if not code.startswith("2"):
        raise FetchError(f"HTTP {code} {url}")
    return r.stdout.decode("utf-8", "replace"), effective


def fetch(url):
    return fetch_ex(url)[0]


LOGIN_PATH = re.compile(r"/(login|session/sso)/?$")
DISCOURSE_MARK = re.compile(r'data-discourse-setup|name="generator" content="Discourse', re.I)
LOGIN_MARK = re.compile(r"login-required|login_required|id=\"login-form\"|/session/sso", re.I)


def login_wall(effective, page):
    # ponytail: marker heuristic -- an SSO redirect that lands on a third-party
    # IdP page slips through to the generic path; add IdP hosts if that bites.
    if LOGIN_PATH.search(urllib.parse.urlsplit(effective).path):
        return True
    return bool(DISCOURSE_MARK.search(page) and LOGIN_MARK.search(page))


def safe_filename(title, max_len=100):
    name = FORBIDDEN.sub("", title).strip()[:max_len].rstrip(" .")
    return name or "untitled"


def yaml_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def frontmatter(title, source, author, published, created):
    authors = "".join(f"\n  - {yaml_str(a)}" for a in author if a)
    return (
        "---\n"
        f"title: {yaml_str(title)}\n"
        f"source: {yaml_str(source)}\n"
        f"author:{authors}\n"
        f"published:{' ' + published if published else ''}\n"
        f"created: {created}\n"
        'status: "unread"\n'
        "tags:\n"
        '  - "clippings"\n'
        '  - "article"\n'
        "---\n"
        "## 메모\n\n### 핵심 요약\n\n\n### 왜 저장했나\n\n\n### 액션 아이템\n\n\n---\n\n"
    )


# --- Discourse ---------------------------------------------------------------

def discourse_topic_id(url):
    # /t/<slug>/<id>[/<post>] or /t/<id>[/<post>]; a slug is never all digits
    m = re.match(r"/t/(?:[^/]*[^/\d][^/]*/)?(\d+)", urllib.parse.urlsplit(url).path)
    return m.group(1) if m else None


def map_uploads(raw, cooked):
    """Replace upload://<base62>.<ext> with the cooked <img src>; return (md, missing)."""
    table = {}
    for tag in re.findall(r"<img\b[^>]*>", cooked):
        b62 = re.search(r'data-base62-sha1="([^"]+)"', tag)
        src = re.search(r'\bsrc="([^"]+)"', tag)
        if b62 and src:
            table[b62.group(1)] = html.unescape(src.group(1))
    missing = []

    def sub(m):
        if m.group(1) in table:
            return table[m.group(1)]
        missing.append(m.group(0))
        return m.group(0)

    return re.sub(r"upload://([A-Za-z0-9]+)(?:\.[A-Za-z0-9]+)?", sub, raw), missing


def strip_size_suffix(md):
    # ![alt|876x451](...) -> ![alt](...); also |876x451, 50%
    return re.sub(r"(!\[[^\]]*?)\|\d+x\d+(?:,\s*\d+%)?\]", r"\1]", md)


def clip_discourse(url, origin, tid, topic):
    post = topic["post_stream"]["posts"][0]
    raw = fetch(f"{origin}/raw/{tid}/1")
    body, missing = map_uploads(raw, post.get("cooked", ""))
    for link in missing:
        print(f"[WARN] upload 매핑 누락 -- 원문 유지: {link}")
    meta = {
        "title": topic.get("title") or url,
        "author": [post.get("username", "")],
        "published": (post.get("created_at") or topic.get("created_at") or "")[:10],
    }
    return meta, strip_size_suffix(body)


# --- generic HTML -> markdown ------------------------------------------------

SKIP = {"title", "script", "style", "noscript", "nav", "header", "footer", "aside", "form", "svg", "template"}
BLOCK = {"p", "div", "section", "article", "main", "ul", "ol", "table", "tr", "figure"}
INLINE = {"strong": "**", "b": "**", "em": "*", "i": "*"}


class ToMarkdown(HTMLParser):
    # ponytail: no tables/nested-list indent; swap in a real converter if the
    # generic path becomes the common one.
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.skip, self.pre, self.href = [], 0, 0, []
        self.meta, self.title, self.in_title = {}, "", False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta":
            key = a.get("property") or a.get("name")
            if key and a.get("content"):
                self.meta.setdefault(key.lower(), a["content"])
            return
        if tag == "title":
            self.in_title = True
        if tag in SKIP:
            self.skip += 1
        if self.skip:
            return
        if re.fullmatch(r"h[1-6]", tag):
            self.out.append("\n\n" + "#" * int(tag[1]) + " ")
        elif tag in BLOCK:
            self.out.append("\n\n")
        elif tag == "br":
            self.out.append("\n")
        elif tag == "li":
            self.out.append("\n- ")
        elif tag == "blockquote":
            self.out.append("\n\n> ")
        elif tag == "pre":
            self.pre += 1
            self.out.append("\n\n```\n")
        elif tag == "code" and not self.pre:
            self.out.append("`")
        elif tag in INLINE:
            self.out.append(INLINE[tag])
        elif tag == "a":
            self.href.append(a.get("href"))
            self.out.append("[" if a.get("href") else "")
        elif tag == "img" and a.get("src"):
            self.out.append(f"![{a.get('alt', '')}]({a['src']})")

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        if tag in SKIP:
            self.skip = max(0, self.skip - 1)
            return
        if self.skip:
            return
        if re.fullmatch(r"h[1-6]", tag) or tag in BLOCK:
            self.out.append("\n\n")
        elif tag == "pre":
            self.pre = max(0, self.pre - 1)
            self.out.append("\n```\n\n")
        elif tag == "code" and not self.pre:
            self.out.append("`")
        elif tag in INLINE:
            self.out.append(INLINE[tag])
        elif tag == "a" and self.href:
            href = self.href.pop()
            if href:
                self.out.append(f"]({href})")

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self.skip:
            return
        self.out.append(data if self.pre else re.sub(r"\s+", " ", data))

    def markdown(self):
        text = "".join(self.out)
        text = re.sub(r"[ \t]+\n", "\n", text)
        return re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"


def html_to_markdown(page):
    """Return (meta, markdown) for an HTML page; body scoped to <article>/<main> when present."""
    head = ToMarkdown()
    head.feed(page)
    m = re.search(r"<(article|main)\b.*?</\1>", page, re.S | re.I)
    body = head
    if m:  # re-parse only the scoped fragment; the full-page parse already has the rest
        body = ToMarkdown()
        body.feed(m.group(0))
    md = head.meta
    meta = {
        "title": (md.get("og:title") or head.title).strip(),
        "author": [md.get("author") or md.get("article:author") or ""],
        "published": (md.get("article:published_time") or "")[:10],
    }
    return meta, body.markdown()


# --- main --------------------------------------------------------------------

def existing_clip(inbox, url):
    needle = f"source: {yaml_str(url)}\n"
    for root, _, files in os.walk(inbox):
        for f in files:
            if f.endswith(".md"):
                p = os.path.join(root, f)
                try:
                    # whole file: a long frontmatter can push `source:` past any fixed prefix
                    with open(p, encoding="utf-8", errors="replace") as fh:
                        if needle in fh.read():
                            return p
                except OSError:
                    pass
    return None


def clip(url, vault):
    inbox = os.path.join(vault, "99-Inbox")
    if not os.path.isdir(vault):
        print(f"[FAIL] vault 없음: {vault} -- --vault <path> 또는 OBSIDIAN_VAULT_DIR 로 지정")
        return 1
    dup = existing_clip(inbox, url)
    if dup:
        print(f"[FAIL] 이미 클립됨 -- 덮어쓰지 않고 중단: {dup}")
        return 1

    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.netloc:
        print(f"[FAIL] http(s) URL 이 아니다: {url}")
        return 1
    origin = f"{parts.scheme}://{parts.netloc}"
    meta = body = None
    tid = discourse_topic_id(url)
    try:
        if tid:
            try:
                topic = json.loads(fetch(f"{origin}/t/{tid}.json"))
                if not isinstance(topic, dict) or not topic.get("post_stream", {}).get("posts"):
                    topic = None
            except (FetchError, ValueError):
                topic = None
            if topic:
                try:
                    meta, body = clip_discourse(url, origin, tid, topic)
                    print("[OK] Discourse 경로 (/raw 원문 markdown)")
                except FetchError as e:
                    print(f"[WARN] Discourse /raw 실패 ({e}) -- 범용 경로로 폴백")
        if body is None:
            page, effective = fetch_ex(url)
            # Every non-Discourse-JSON outcome lands here, so one check covers a
            # login-walled .json and a login-walled page alike.
            if login_wall(effective, page):
                raise FetchError(f"로그인 필요 ({effective}) -- 브라우저의 Obsidian Web Clipper 를 쓰라.")
            meta, body = html_to_markdown(page)
            print("[WARN] 범용 경로 (HTML -> markdown, 정확도 낮음 -- 원문과 대조 권장)")
    except FetchError as e:
        print(f"[FAIL] {e} -- 파일을 만들지 않았다")
        return 1

    today = datetime.date.today().isoformat()
    title = meta["title"] or url
    os.makedirs(os.path.join(inbox, "Web"), exist_ok=True)
    path = os.path.join(inbox, "Web", f"{today} {safe_filename(title)}.md")
    try:
        if not body.endswith("\n"):
            body += "\n"
        with open(path, "x", encoding="utf-8") as fh:  # "x": never overwrite
            fh.write(frontmatter(title, url, meta["author"], meta["published"], today) + body)
    except FileExistsError:
        print(f"[FAIL] 같은 이름의 다른 노트가 이미 있다 -- 중단: {path}")
        return 1
    if "upload://" in body:
        print("[WARN] 본문에 upload:// 링크가 남아 있다")
    print(f"[OK] {path}")
    return 0


def self_test():
    assert safe_filename('Graphify: a/b "c" <d>|?*') == "Graphify ab c d"
    assert safe_filename(":::") == "untitled"
    assert strip_size_suffix("![alt|876x451](x) ![b|10x2, 50%](y)") == "![alt](x) ![b](y)"
    cooked = '<img src="https://h/o/a.png" data-base62-sha1="AbC" width="1">'
    md, miss = map_uploads("![x](upload://AbC.png) ![y](upload://Zz.jpg)", cooked)
    assert md == "![x](https://h/o/a.png) ![y](upload://Zz.jpg)" and miss == ["upload://Zz.jpg"]
    assert discourse_topic_id("https://d.kr/t/some-slug/9652") == "9652"
    assert discourse_topic_id("https://d.kr/t/9652/3") == "9652"
    assert discourse_topic_id("https://d.kr/about") is None
    meta, body = html_to_markdown(
        '<html><head><title>T</title><meta name="author" content="A">'
        '<meta property="article:published_time" content="2026-01-02T03:04"></head>'
        '<body><nav>menu</nav><article><h1>H</h1><h2>Hi</h2><p>a <a href="/u">link</a> '
        '<strong>b</strong></p><script>x</script></article></body></html>'
    )
    assert meta == {"title": "T", "author": ["A"], "published": "2026-01-02"}, meta
    assert body == "# H\n\n## Hi\n\na [link](/u) **b**\n", repr(body)
    fm = frontmatter('a "q"', "u", ["x"], "2026-01-01", "2026-01-02")
    assert 'title: "a \\"q\\""\n' in fm and fm.endswith("---\n\n")
    assert "\npublished:\n" in frontmatter("t", "u", [""], "", "2026-01-02")
    assert login_wall("https://d.kr/login", "<html></html>")
    assert login_wall("https://d.kr/session/sso?return_path=/t/1", "")
    assert login_wall("https://d.kr/t/1.json",
                      '<meta name="generator" content="Discourse 3.2"><body class="login-required">')
    assert not login_wall("https://d.kr/t/1.json", '<meta name="generator" content="Discourse 3.2">')
    assert not login_wall("https://blog.kr/t/1.json", "<html><a href='/login'>login</a></html>")
    print("[OK] self-test")
    return 0


def main(argv):
    if argv and argv[0] in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 2:
        print("[FAIL] usage: web-clip.py <url> <vault>", file=sys.stderr)
        return 2
    return clip(argv[0], argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
