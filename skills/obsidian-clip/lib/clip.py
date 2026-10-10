#!/usr/bin/env python3
"""skills/obsidian-clip/lib/clip.py -- one URL / YouTube / local file -> one vault note.

Usage:
  clip.py <input> <vault>     write <vault>/99-Inbox/<today> <title>.md
  clip.py --self-test         offline asserts on the pure helpers
  clip.py -h | --help | help

Flow: markitdown on PATH? -> classify the input -> refuse a duplicate
(normalized source anywhere under 99-Inbox/) -> convert -> refuse an empty
body -> title -> write with mode "never overwrite".

  youtube   youtube.com/watch?v= | /shorts/ | youtu.be/   markitdown
  article   Discourse topic (<origin>/t/<id>.json post_stream)  first post /raw
  article   any other http(s) URL                         curl login-wall probe, then markitdown
  document  an existing local file                        markitdown

Output lines start with [OK] / [WARN] / [FAIL]; the last line of a success is
`/ingest <path>`. Exit 0 only when the note was written. Never touches git:
the vault's obsidian-git owns commits and sync. stdlib + curl + markitdown.
"""

import datetime
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

HELP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references", "help.md")
UA = "Mozilla/5.0 (pkm:obsidian-clip)"
FORBIDDEN = re.compile(r'[\\/:*?"<>|\x00-\x1f]')
TLS_HINT = re.compile(r"ssl|tls|certificate|cert|proxy|connection|resolve|timed? ?out", re.I)
YT_HOSTS = ("youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com")
_t = os.environ.get("OBSIDIAN_CLIP_TIMEOUT", "")
MARKITDOWN_TIMEOUT = int(_t) if _t.isdigit() and int(_t) > 0 else 300  # bad value: default, never a traceback
TRACKING = re.compile(r"^(si|feature|utm_.*)$", re.I)


class FetchError(Exception):
    pass


# --- classify / normalize ----------------------------------------------------

def is_url(s):
    return re.match(r"https?://", s, re.I) is not None


def youtube_id(url):
    u = urllib.parse.urlsplit(url)
    host = (u.hostname or "").lower()
    vid = None
    if host in YT_HOSTS:
        if u.path == "/watch":
            vid = urllib.parse.parse_qs(u.query).get("v", [None])[0]
        elif u.path.startswith("/shorts/"):
            vid = u.path.split("/")[2]
    elif host == "youtu.be":
        vid = u.path.strip("/").split("/")[0]
    vid = re.sub(r"[^A-Za-z0-9_-]", "", vid or "")  # IDs are case-sensitive: keep case
    return vid or None


def normalize(src):
    """The key duplicate detection compares: one per video / page / file."""
    if not is_url(src):
        return os.path.abspath(src)
    vid = youtube_id(src)
    if vid:
        return f"youtube:{vid}"
    u = urllib.parse.urlsplit(src)
    tid = discourse_topic_id(src)
    if tid:
        # shortcut: any /t/<slug>/<id>[/<post>] path is taken as Discourse (the clip is the
        # whole topic's first post, so post number and query never matter); probe the
        # site here instead if a non-Discourse /t/ path ever collides.
        u = u._replace(path=f"/t/{tid}", query="")
    host = (u.hostname or "").lower().removeprefix("www.")
    if u.port:
        host += f":{u.port}"
    query = urllib.parse.urlencode(
        [(k, v) for k, v in urllib.parse.parse_qsl(u.query, keep_blank_values=True) if not TRACKING.match(k)])
    return urllib.parse.urlunsplit((u.scheme.lower(), host, u.path.rstrip("/"), query, ""))


def classify(src):
    """Return 'youtube' | 'article' | 'document', or None for a missing file."""
    if is_url(src):
        return "youtube" if youtube_id(src) else "article"
    return "document" if os.path.isfile(src) else None


# --- fetch (Discourse + the login-wall probe; markitdown fetches the body) ---

def fetch(url, *curl_args):
    """Return (body, redirect hop URLs, effective URL); curl_args go before the URL."""
    # curl, not urllib: it uses the system trust store, which a corporate TLS
    # proxy's CA lives in, and python 3.13's strict X509 checks reject some
    # chains curl accepts.
    with tempfile.TemporaryDirectory() as tmp:
        hdr = os.path.join(tmp, "headers")  # -D: every hop's headers, portable path
        try:
            r = subprocess.run(
                ["curl", "-sSL", "--proto", "=http,https", "--proto-redir", "=http,https",
                 "--max-time", "30", "-A", UA, "-D", hdr,
                 "-w", "%{stderr}\n%{url_effective} %{http_code}", *curl_args, "--", url],
                capture_output=True, check=False,
            )
        except FileNotFoundError as e:
            raise FetchError("curl 이 없다") from e
        try:
            with open(hdr, encoding="latin-1") as fh:
                headers = fh.read().splitlines()
        except FileNotFoundError:
            headers = []
    err = r.stderr.decode(errors="replace").strip()
    if r.returncode != 0:
        # drop the -w trailer: its effective URL may be an IdP URL carrying session tokens
        # (a stderr with no error line is the trailer alone: never fall back to it)
        reason = scrub(err.rpartition("\n")[0]) or f"curl exit {r.returncode}"
        raise FetchError(f"network error {url}: {reason}")
    effective, _, code = err.rsplit("\n", 1)[-1].rpartition(" ")
    if not code.startswith("2"):
        raise FetchError(f"HTTP {code} {url}")
    hops, base = [], url
    for line in headers:
        name, _, value = line.partition(":")
        if name.strip().lower() == "location" and value.strip():
            base = urllib.parse.urljoin(base, value.strip())
            hops.append(base)
    return r.stdout.decode("utf-8", "replace"), hops, effective


LOGIN_PATH = re.compile(r"/(login|sign[-_]?in|session/sso)/?$")
# Broader, but only for redirect targets: a server sending you to /auth/... is
# a login wall; a page the user asked for at /auth/intro is not.
HOP_PATH = re.compile(r"/(login|sign[-_]?in|session/sso|auth)(/|$)")
DISCOURSE_MARK = re.compile(r'data-discourse-setup|name="generator" content="Discourse', re.I)
LOGIN_MARK = re.compile(r"login-required|login_required|id=\"login-form\"|/session/sso", re.I)


def login_wall(effective, page, hops=()):
    # Any hop through a login/SSO path counts: an SSO redirect ends on a
    # third-party IdP page that carries no Discourse marker at all.
    if LOGIN_PATH.search(urllib.parse.urlsplit(effective).path):
        return True
    if any(HOP_PATH.search(urllib.parse.urlsplit(u).path) for u in hops):
        return True
    return bool(DISCOURSE_MARK.search(page) and LOGIN_MARK.search(page))


def bare_url(url):
    # Session tokens ride in the query/fragment (state, SAMLRequest), userinfo and
    # ;jsessionid path params; scheme, host and the bare path are enough.
    try:
        p = urllib.parse.urlsplit(url)
    except ValueError:  # e.g. a broken [ipv6] host: drop userinfo, keep what precedes any query
        return re.split(r"[?#;]", re.sub(r"^([^:/]*://)[^/?#]*@", r"\1", url), maxsplit=1)[0]
    path = re.sub(r";[^/]*", "", p.path)
    return f"{p.scheme}://{p.netloc.rpartition('@')[2]}{path}" if p.scheme else path


# Lazy up to trailing punctuation, so "(see https://h/a?x=1)." keeps its ")."
# urllib3's "Max retries exceeded with url: /path?query" carries no scheme.
URL_IN_TEXT = re.compile(r"""(?:https?://|(?<=\burl: )/)[^\s'"<>]*?(?=[).,;:]*(?:[\s'"<>]|$))""", re.I)


def scrub(text):
    """Shorten every http(s) URL, and every scheme-less `url: /path?query`, with bare_url()."""
    return URL_IN_TEXT.sub(lambda m: bare_url(m.group(0)), text)


def wall(effective):
    return FetchError(f"로그인 필요 ({bare_url(effective)}) -- 브라우저의 Obsidian Web Clipper 를 쓰라.")


def probe_login_wall(url):
    """Raise FetchError when `url` lands behind a login wall.

    markitdown follows redirects out of sight, so the chain is read here first.
    A failed probe is not a wall: markitdown still gets the URL, as before.
    Page markers are not checked: every public Discourse page preloads the
    `login_required` site setting. A hop that keeps the requested path
    (http->https, trailing slash) is the page the user asked for, not a wall,
    and so is a final URL on that same path (a page at /guide/sign-in).
    """
    try:
        # -r 0-0: only the redirect chain matters; a server that honours ranges
        # sends 1 byte instead of the whole page markitdown downloads again.
        _, hops, effective = fetch(url, "-r", "0-0")
    except FetchError:
        return
    asked = urllib.parse.urlsplit(url).path.rstrip("/")

    def other(u):
        return urllib.parse.urlsplit(u).path.rstrip("/") != asked

    if login_wall(effective if other(effective) else "", "", [h for h in hops if other(h)]):
        raise wall(effective)


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


def discourse(url):
    """Return (meta, body) for a Discourse topic, or None when the URL is not one."""
    tid = discourse_topic_id(url)
    if not tid:
        return None
    parts = urllib.parse.urlsplit(url)
    origin = f"{parts.scheme}://{parts.netloc}"
    try:
        page, hops, effective = fetch(f"{origin}/t/{tid}.json")
    except FetchError:
        return None
    # Only a wall that is Discourse's own is a stop here: another site's /t/<id>.json may be
    # a walled API while its page is public, so that page is probed on the markitdown path.
    ours = DISCOURSE_MARK.search(page) or any(
        "/session/sso" in urllib.parse.urlsplit(u).path for u in [*hops, effective])
    if ours and login_wall(effective, page, hops):
        raise wall(effective)
    try:
        topic = json.loads(page)
        post = topic["post_stream"]["posts"][0]
    except (ValueError, TypeError, KeyError, IndexError):
        return None
    try:
        raw = fetch(f"{origin}/raw/{tid}/1")[0]
    except FetchError as e:
        print(f"[WARN] Discourse /raw 실패 ({e}) -- markitdown 경로로 폴백")
        return None
    body, missing = map_uploads(raw, post.get("cooked", ""))
    for link in missing:
        print(f"[WARN] upload 매핑 누락 -- 원문 유지: {link}")
    print("[OK] Discourse 경로 (/raw 원문 markdown)")
    meta = {
        "title": topic.get("title") or url,
        "author": [post.get("username", "")],
        "published": (post.get("created_at") or topic.get("created_at") or "")[:10],
    }
    return meta, strip_size_suffix(body)


# --- markitdown --------------------------------------------------------------

def stderr_reason(r):
    """One line of `r.stderr` that says why the run failed."""
    lines = [ln for ln in r.stderr.splitlines() if ln.strip()] or [f"exit {r.returncode}"]
    tb = [i for i, ln in enumerate(lines) if ln.startswith("Traceback (most recent call last):")]
    if not tb:
        return lines[0].strip()
    # The exception follows the last traceback's indented frames and may span lines
    # (markitdown's FileConversionException ends with "* etc."), so join all of it.
    rest = lines[tb[-1] + 1:]
    start = next((i for i, ln in enumerate(rest) if not ln[:1].isspace()), len(rest))
    return " ".join(ln.strip() for ln in rest[start:]) or lines[-1].strip()


def markitdown(arg, url):
    """Return the converted markdown, or None after printing the [FAIL] lines."""
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "out.md")
        try:
            r = subprocess.run(["markitdown", arg, "-o", out], capture_output=True, text=True,
                               check=False, timeout=MARKITDOWN_TIMEOUT)
        except subprocess.TimeoutExpired:
            print(f"[FAIL] {arg}: markitdown timeout {MARKITDOWN_TIMEOUT}s -- 파일을 만들지 않았다")
            if url:
                print("Next: 네트워크가 느리거나 막혔으면 HTTP(S)_PROXY 설정을 확인하고 다시 실행")
            return None
        if r.returncode != 0:
            print(f"[FAIL] {arg}: {scrub(stderr_reason(r))} -- 파일을 만들지 않았다")
            if url or TLS_HINT.search(r.stderr):
                print("Next: 네트워크/TLS 오류면 REQUESTS_CA_BUNDLE (사내 CA 번들) 과 "
                      "HTTP(S)_PROXY 설정을 확인 -- 인증서 검증은 끄지 않는다")
            return None
        try:
            with open(out, encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except FileNotFoundError:
            return ""


def first_heading(md, levels):
    m = re.search(rf"^#{{{levels}}} +(.+?)\s*#*\s*$", md, re.M)
    return m.group(1).strip() if m else ""


def title_for(kind, src, md):
    if kind == "document":
        return os.path.splitext(os.path.basename(src))[0]
    if kind == "youtube":  # markitdown: "# YouTube" then "## <video title>"; that H1 is no title
        return first_heading(md, "2") or src
    return first_heading(md, "1") or first_heading(md, "1,6") or src


def description_truncated(md):
    m = re.search(r"^### Description\s*\n(.*?)(?=^#{1,3} |\Z)", md, re.M | re.S)
    return bool(m) and m.group(1).rstrip().endswith(("...", "…"))


# --- note --------------------------------------------------------------------

def safe_filename(title, max_len=100):
    name = FORBIDDEN.sub("", title).strip()[:max_len].rstrip(" .")
    return name or "untitled"


def yaml_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def yaml_unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return v


def frontmatter(title, source, author, published, created, tag):
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
        f'  - "{tag}"\n'
        "---\n"
        "## 메모\n\n### 핵심 요약\n\n\n### 왜 저장했나\n\n\n### 액션 아이템\n\n\n---\n\n"
    )


def note_source(path):
    """The frontmatter `source:` value of a note, or None."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            if fh.readline().strip() != "---":
                return None
            for line in fh:  # whole frontmatter: a long one can push `source:` far down
                if line.strip() == "---":
                    return None
                if line.startswith("source:"):
                    return yaml_unquote(line[len("source:"):])
    except OSError:
        pass
    return None


def existing_clip(inbox, key):
    for root, _, files in os.walk(inbox):
        for f in sorted(files):
            if f.endswith(".md"):
                p = os.path.join(root, f)
                s = note_source(p)
                if s and normalize(s) == key:
                    return p
    return None


def write_new(path, text):
    """Write `text` to `path` only if it does not exist; no partial file on error."""
    # "x", not a temp file + os.link: hard links fail on FAT/exFAT and some
    # network mounts, and a killed run would strand a .clip-*.md for obsidian-git.
    with open(path, "x", encoding="utf-8") as fh:  # FileExistsError: never overwrite
        try:
            fh.write(text)
        except BaseException:
            os.remove(path)
            raise


# --- main --------------------------------------------------------------------

def clip(src, vault):
    if shutil.which("markitdown") is None:
        # PATH only, before anything else; never auto-install. dotfiles'
        # `markitdown-help` is an interactive-shell alias a script cannot see,
        # so both pointers are always printed.
        print("[FAIL] markitdown 미설치 -- 파일을 만들지 않았다")
        print("Next: markitdown-help install (dotfiles 셸) 또는 uv tool install 'markitdown[all]'")
        print("      TLS 인증서 오류가 나면: uv tool install --native-tls 'markitdown[all]'")
        return 1
    if not os.path.isdir(vault):
        print(f"[FAIL] vault 없음: {vault} -- --vault <path> 또는 OBSIDIAN_VAULT_DIR 로 지정")
        return 1
    if not is_url(src):
        src = os.path.expanduser(src)  # "$INPUT" is quoted, so the shell never expanded ~
    kind = classify(src)
    if kind is None:
        print(f"[FAIL] 입력을 찾을 수 없다 (URL 도 파일도 아님): {src}")
        return 1
    source = os.path.abspath(src) if kind == "document" else src
    inbox = os.path.join(vault, "99-Inbox")
    dup = existing_clip(inbox, normalize(source))
    if dup:
        print(f"[FAIL] 이미 클립됨 -- 덮어쓰지 않고 중단: {dup}")
        return 1

    meta = {"title": "", "author": [], "published": ""}
    probed = False
    try:
        found = discourse(src) if kind == "article" else None
        probed = kind == "article" and not found and os.environ.get("OBSIDIAN_CLIP_NO_PROBE") != "1"
        if probed:
            probe_login_wall(src)
    except FetchError as e:
        print(f"[FAIL] {e} -- 파일을 만들지 않았다")
        if probed:  # the opt-out only skips the probe; a Discourse topic's own wall stays a stop
            print("Next: 공개 페이지인데 리다이렉트 프로브가 막았으면 OBSIDIAN_CLIP_NO_PROBE=1 로 다시 실행")
        return 1
    if found:
        meta, body = found
    else:
        # markitdown's YouTube converter only accepts https://www.youtube.com/watch?
        # URLs; shorts / youtu.be / m. shapes would get the generic HTML pass.
        arg = f"https://www.youtube.com/watch?v={youtube_id(src)}" if kind == "youtube" else source
        body = markitdown(arg, kind != "document")
        if body is None:
            return 1
        meta["title"] = title_for(kind, src, body)
    if not body.strip():
        print(f"[WARN] {src}: 변환 결과가 비었다 (스캔 PDF? 자막·설명 없는 영상?) -- 파일을 만들지 않았다")
        return 1
    if kind == "youtube" and description_truncated(body):
        print("[WARN] YouTube Description 이 '...' 로 잘렸다 -- 원문 확인 권장")

    today = datetime.date.today().isoformat()
    title = meta["title"] or src
    os.makedirs(inbox, exist_ok=True)
    path = os.path.join(inbox, f"{today} {safe_filename(title)}.md")
    if not body.endswith("\n"):
        body += "\n"
    try:
        write_new(path, frontmatter(title, source, meta["author"], meta["published"], today, kind) + body)
    except FileExistsError:
        print(f"[FAIL] 같은 이름의 다른 노트가 이미 있다 -- 중단: {path}")
        return 1
    if "upload://" in body:
        print("[WARN] 본문에 upload:// 링크가 남아 있다")
    print(f"[OK] {path}")
    print(f"/ingest {path}")
    return 0


def self_test():
    assert safe_filename('Graphify: a/b "c" <d>|?*') == "Graphify ab c d"
    assert safe_filename(":::") == "untitled"
    assert len(safe_filename("x" * 300)) == 100
    assert strip_size_suffix("![alt|876x451](x) ![b|10x2, 50%](y)") == "![alt](x) ![b](y)"
    cooked = '<img src="https://h/o/a.png" data-base62-sha1="AbC" width="1">'
    md, miss = map_uploads("![x](upload://AbC.png) ![y](upload://Zz.jpg)", cooked)
    assert md == "![x](https://h/o/a.png) ![y](upload://Zz.jpg)" and miss == ["upload://Zz.jpg"]
    assert discourse_topic_id("https://d.kr/t/some-slug/9652") == "9652"
    assert discourse_topic_id("https://d.kr/t/9652/3") == "9652"
    assert discourse_topic_id("https://d.kr/about") is None
    for u in ("https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB",
              "https://www.youtube.com/shorts/nGKKWne_O2s",
              "https://www.youtube.com/watch?v=nGKKWne_O2s&t=30s",
              "https://m.youtube.com/watch?feature=share&v=nGKKWne_O2s",
              "https://youtu.be/nGKKWne_O2s?si=zz"):
        assert normalize(u) == "youtube:nGKKWne_O2s", u
        assert classify(u) == "youtube", u
    assert youtube_id("https://www.youtube.com/channel/x") is None
    assert classify("https://www.youtube.com/channel/x") == "article"
    assert normalize("https://www.Example.com/a/?utm_source=x&id=2&si=q#frag") == "https://example.com/a?id=2"
    assert normalize("https://example.com/a") == normalize("https://example.com/a/")
    assert normalize("https://d.kr/t/slug/9652/3?u=kim") == normalize("https://d.kr/t/9652") == "https://d.kr/t/9652"
    assert normalize("https://example.com/a?id=2") != normalize("https://example.com/a?id=3")
    assert classify("/no/such/file.pdf") is None
    assert title_for("youtube", "u", "# YouTube\n\n## Video T\n### Video Metadata\n") == "Video T"
    assert title_for("youtube", "u", "# YouTube\n\nno metadata\n") == "u"
    assert title_for("article", "u", "intro\n## Sub\n# Main\n") == "Main"
    assert title_for("article", "u", "intro\n### Only\n") == "Only"
    assert title_for("article", "u", "no heading\n") == "u"
    assert title_for("document", "/a/b/report.v2.pdf", "# X\n") == "report.v2"
    assert description_truncated("### Description\nabc ...\n### Transcript\nt\n")
    assert not description_truncated("### Description\nabc ... def\n### Transcript\nt\n")
    assert not description_truncated("# no description\n")
    fm = frontmatter('a "q"', "u", ["x"], "2026-01-01", "2026-01-02", "youtube")
    assert 'title: "a \\"q\\""\n' in fm and '  - "youtube"\n' in fm and fm.endswith("---\n\n")
    assert "\npublished:\n" in frontmatter("t", "u", [""], "", "2026-01-02", "article")
    assert yaml_unquote(' "a \\"q\\" \\\\"') == 'a "q" \\'
    tok = "https://u:PW@idp.kr/sso;jsessionid=J?state=S&SAMLRequest=R#f"
    assert bare_url(tok) == "https://idp.kr/sso"
    assert scrub(f"403 for url: {tok}. (see {tok}) '{tok}'") == \
        "403 for url: https://idp.kr/sso. (see https://idp.kr/sso) 'https://idp.kr/sso'"
    assert scrub("HTTP://H.kr/a?x=1 and http://[bad/b?state=S") == "http://H.kr/a and http://[bad/b"
    assert scrub("no url here: /path?state=S") == "no url here: /path?state=S"
    assert scrub("with url: /a;j=J?state=S#f (Caused by X)") == "with url: /a (Caused by X)"
    assert bare_url("http://u:PW@[bad/b;j=J?state=S") == "http://[bad/b"
    def run(err, code=1):
        return subprocess.CompletedProcess([], code, "", err)
    assert stderr_reason(run("SSLError: x\nmore\n")) == "SSLError: x"
    assert stderr_reason(run("\n", 2)) == "exit 2"
    tb = ("Traceback (most recent call last):\n  File \"m.py\", line 1\n    f()\n"
          "E: failed after 1 attempts:\n - P threw M with message: need [pdf]:\n\n* etc.\n")
    assert stderr_reason(run(tb)) == \
        "E: failed after 1 attempts: - P threw M with message: need [pdf]: * etc."
    assert login_wall("https://d.kr/login", "<html></html>")
    assert login_wall("https://d.kr/session/sso?return_path=/t/1", "")
    idp = "https://idp.example/oauth2/v1/authorize?s=2"
    assert login_wall(idp, "<html></html>", ["https://d.kr/session/sso?x=1", idp])
    assert not login_wall("https://d.kr/t/slug/1", "<html></html>", ["https://d.kr/t/slug/1"])
    assert not login_wall("https://blog.kr/auth/intro", "<html></html>")
    assert login_wall("https://gitlab.kr/users/sign_in", "")
    assert login_wall("https://d.kr/t/1.json",
                      '<meta name="generator" content="Discourse 3.2"><body class="login-required">')
    print("[OK] self-test")
    return 0


def main(argv):
    if argv and argv[0] in ("-h", "--help", "help"):
        with open(HELP, encoding="utf-8") as fh:
            sys.stdout.write(fh.read())
        return 0
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 2:
        print("[FAIL] usage: clip.py <input> <vault> -- Run /pkm:obsidian-clip -h for usage.")
        return 2
    return clip(argv[0], argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
