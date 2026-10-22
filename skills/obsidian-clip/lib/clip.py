#!/usr/bin/env python3
"""skills/obsidian-clip/lib/clip.py -- one URL / YouTube / local file -> one vault note.

Usage:
  clip.py <input>             write ~/para/project/obsidian-para/99-Inbox/<today> <title>.md
  clip.py --self-test         offline asserts on the pure helpers
  clip.py -h | --help | help

The vault is fixed (VAULT below): no --vault, no env, no setup-mode branch.
Flow: markitdown on PATH? -> vault exists? -> agent-reach on PATH? (no: a TIP
line) -> classify the input -> refuse a duplicate (normalized source anywhere
under 99-Inbox/) -> convert -> refuse an empty body -> title -> write with
mode "never overwrite".

  youtube   youtube.com/watch?v= | /shorts/ | youtu.be/   yt-dlp when agent-reach is installed,
                                                          else (or on failure) markitdown
  article   Discourse topic (<origin>/t/<id>.json post_stream)  first post /raw
  article   any other http(s) URL                         curl login-wall probe, then markitdown
  document  an existing local file                        markitdown

Output lines start with [OK] / [WARN] / [FAIL]; the last line of a success is
`/ingest <path>`. Exit 0 only when the note was written. Never touches git:
the vault's obsidian-git owns commits and sync. stdlib + curl + markitdown,
plus the yt-dlp CLI (optional, never imported, never installed).
"""

import datetime
import html
import json
import os
import re
import shlex
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
TIMEOUT = int(_t) if _t.isdigit() and int(_t) > 0 else 300  # bad value: default, never a traceback
VAULT = os.path.abspath(os.path.expanduser("~/para/project/obsidian-para"))
VAULT_SHOWN = "~/para/project/obsidian-para/99-Inbox"
# The light bulb is written as an escape: the repo's CI bans emoji characters in tracked text.
TIP = ("\U0001F4A1 [TIP] agent-reach 미설치 — 설치하면 YouTube 를 yt-dlp 로 클립합니다 "
       "(전체 설명·자막·채널·게시일)")
TIP_NEXT = ("Next: 설치 안내 https://github.com/Panniantong/Agent-Reach (docs/install.md) "
            "— 설치 후 agent-reach doctor 로 youtube: ok 확인")
SUB_LANGS = ("ko", "en")  # then <lang>-orig; manual before auto
BOM = chr(0xFEFF)  # not a literal: an invisible character in source is one editor away from deletion
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
    if r.returncode != 0:
        # curl's own text (and the -w trailer's effective URL) may carry session tokens
        raise FetchError(f"network error {url_host(url)}: curl exit {r.returncode}")
    err = r.stderr.decode(errors="replace").strip()
    effective, _, code = err.rsplit("\n", 1)[-1].rpartition(" ")
    if not code.startswith("2"):
        raise FetchError(f"HTTP {code} {url_host(url)}")
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


def url_host(url):
    """Only the host of `url`, or `?`: userinfo, path, query and fragment can carry tokens."""
    try:
        return urllib.parse.urlsplit(url).hostname or "?"
    except ValueError:
        return "?"


def wall(effective):
    return FetchError(f"로그인 필요 ({url_host(effective)}) -- 브라우저의 Obsidian Web Clipper 를 쓰라.")


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

def exc_class(r):
    """The last traceback's exception class name, else `markitdown exit <code>`.

    Never the exception message: downstream text can quote token-bearing URLs.
    """
    lines = r.stderr.splitlines()
    tb = [i for i, ln in enumerate(lines) if ln.startswith("Traceback (most recent call last):")]
    if tb:
        # the exception line is the first unindented one after the last traceback's frames
        line = next((ln for ln in lines[tb[-1] + 1:] if ln.strip() and not ln[:1].isspace()), "")
        m = re.match(r"([\w.]+)(?::|$)", line)
        if m:
            return m.group(1).rpartition(".")[2]
    return f"markitdown exit {r.returncode}"


def markitdown(arg, url):
    """Return the converted markdown, or None after printing the [FAIL] lines."""
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "out.md")
        try:
            r = subprocess.run(["markitdown", arg, "-o", out], capture_output=True, text=True,
                               check=False, timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            print(f"[FAIL] {arg}: markitdown timeout {TIMEOUT}s -- 파일을 만들지 않았다")
            if url:
                print("Next: 네트워크가 느리거나 막혔으면 HTTP(S)_PROXY 설정을 확인하고 다시 실행")
            return None
        if r.returncode != 0:
            where = f" ({url_host(arg)})" if url else ""
            print(f"[FAIL] {arg}: {exc_class(r)}{where} -- 파일을 만들지 않았다")
            print(f"Next: 원인 상세: markitdown {shlex.quote(arg)} 를 직접 실행")
            if "MissingDependencyException" in r.stderr:  # the class alone hides which extra is missing
                print("Next: 이 형식의 markitdown extra 미설치: markitdown-help install (dotfiles 셸) "
                      "또는 uv tool install 'markitdown[all]'")
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


# --- yt-dlp (the agent-reach YouTube backend) --------------------------------

def run_ytdlp(*args):
    """Run the yt-dlp CLI; return stdout, or raise FetchError with a stderr-free reason.

    Never cookies, never --no-check-certificate: a bot check is a fallback, not a retry.
    """
    try:
        r = subprocess.run(["yt-dlp", "--no-warnings", *args], capture_output=True, text=True,
                           check=False, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as e:
        raise FetchError(f"timeout {TIMEOUT}s") from e
    except OSError as e:
        raise FetchError(type(e).__name__) from e
    if r.returncode != 0:  # stderr can quote URLs and account state: never printed
        raise FetchError(f"yt-dlp exit {r.returncode} (www.youtube.com)")
    return r.stdout


def ytdlp_meta(url):
    """The --dump-json metadata dict; FetchError when unusable."""
    try:
        meta = json.loads(run_ytdlp("--dump-json", "--skip-download", "--", url))
    except ValueError as e:
        raise FetchError(type(e).__name__) from e
    if not isinstance(meta, dict) or not str(meta.get("title") or "").strip():
        raise FetchError("title 없음")
    return meta


def sub_rank(lang, manual):
    """Sort key: manual before auto, then ko > en > <lang>-orig; None for any other track.

    A regional track (en-US) ranks as its base language, just after the bare code.
    """
    base = lang.split("-")[0]
    if lang.endswith("-orig"):
        order = len(SUB_LANGS)
    elif base in SUB_LANGS:
        order = SUB_LANGS.index(base)
    else:
        return None
    return (0 if manual else 1, order, lang != base)


def ytdlp_subs(url, meta, tmp):
    """Return (lang, 'manual'|'auto', text) for the best subtitle track, or None."""
    try:
        # --ignore-errors: one failed track (an HTTP 429 on an auto track is common) must not
        # abort the remaining ones; ko.* / en.* also catch regional manual tracks (en-US).
        run_ytdlp("--ignore-errors", "--write-sub", "--write-auto-sub",
                  "--sub-langs", "ko.*,en.*,.*-orig", "--sub-format", "vtt", "--skip-download",
                  "-o", os.path.join(tmp, "%(id)s"), "--", url)
    except FetchError:
        pass  # a subtitle failure is not a fallback: the files that did land still count
    manual = meta.get("subtitles") or {}
    best = None
    for f in os.listdir(tmp):
        parts = f.split(".")
        if len(parts) < 3 or parts[-1] != "vtt":
            continue
        lang = parts[-2]
        key = sub_rank(lang, lang in manual)
        if key is None:
            continue
        with open(os.path.join(tmp, f), encoding="utf-8", errors="replace") as fh:
            text = vtt_to_text(fh.read())
        if text and (best is None or key < best[0]):
            best = (key, lang, "manual" if key[0] == 0 else "auto", text)
    return best[1:] if best else None


def vtt_to_text(vtt):
    """WebVTT -> plain lines: no header, NOTE/STYLE/REGION blocks, cue ids, timings or tags.

    Auto captions roll: each cue repeats the previous line, so consecutive duplicates collapse.
    """
    out = []
    for block in re.split(r"\n[ \t]*\n", vtt.replace("\r\n", "\n").replace("\r", "\n")):
        lines = block.strip("\n").split("\n")
        if not lines or lines[0].lstrip(BOM).startswith(("WEBVTT", "NOTE", "STYLE", "REGION")):
            continue
        timing = next((i for i, ln in enumerate(lines) if "-->" in ln), None)
        if timing is None:
            continue
        for ln in lines[timing + 1:]:
            text = html.unescape(re.sub(r"<[^>]*>", "", ln)).strip()
            if text and (not out or out[-1] != text):
                out.append(text)
    return "\n".join(out)


def hms(seconds):
    try:
        s = int(float(seconds))
    except (TypeError, ValueError):
        return ""
    h, rem = divmod(s, 3600)
    return f"{h}:{rem // 60:02d}:{rem % 60:02d}" if h else f"{rem // 60}:{rem % 60:02d}"


def upload_day(d):
    d = str(d or "")
    return f"{d[:4]}-{d[4:6]}-{d[6:]}" if re.fullmatch(r"\d{8}", d) else ""


def ytdlp_body(meta, url, subs):
    channel = meta.get("uploader") or meta.get("channel") or ""
    views = meta.get("view_count")
    rows = [("Channel", channel), ("Uploaded", upload_day(meta.get("upload_date"))),
            ("Duration", hms(meta.get("duration")) or meta.get("duration_string") or ""),
            ("Views", f"{views:,}" if isinstance(views, int) else ""), ("URL", url)]
    parts = [f"# {meta['title'].strip()}", "## Video Metadata",
             "\n".join(f"- {k}: {v}" for k, v in rows if v),
             "## Description", (meta.get("description") or "").strip() or "(없음)"]
    chapters = [c for c in meta.get("chapters") or [] if isinstance(c, dict) and c.get("title")]
    if chapters:
        parts += ["## Chapters", "\n".join(f"- {hms(c.get('start_time', 0))} {c['title']}" for c in chapters)]
    if subs:
        lang, how, text = subs
        parts += [f"## Transcript ({lang}, {how})", text]
    return "\n\n".join(parts) + "\n"


def ytdlp(src):
    """Return (meta, body) via yt-dlp, or None after the fallback [WARN] line."""
    url = f"https://www.youtube.com/watch?v={youtube_id(src)}"
    try:
        info = ytdlp_meta(url)
    except FetchError as e:
        print(f"[WARN] yt-dlp 실패 ({e}) -- markitdown 경로로 폴백")
        return None
    with tempfile.TemporaryDirectory() as tmp:
        subs = ytdlp_subs(url, info, tmp)
    if not subs:
        print("[WARN] 자막 없음 -- Transcript 섹션 생략")
    print("[OK] yt-dlp 경로 (agent-reach)")
    author = info.get("uploader") or info.get("channel") or ""
    meta = {"title": info["title"].strip(), "author": [author],
            "published": upload_day(info.get("upload_date"))}
    return meta, ytdlp_body(info, url, subs)


# agent-reach routing: kind -> (the CLI it needs, converter). Other platforms land here.
ROUTES = {"youtube": ("yt-dlp", ytdlp)}


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

def clip(src, vault=VAULT):
    if shutil.which("markitdown") is None:
        # PATH only, before anything else; never auto-install. dotfiles'
        # `markitdown-help` is an interactive-shell alias a script cannot see,
        # so both pointers are always printed.
        print("[FAIL] markitdown 미설치 -- 파일을 만들지 않았다")
        print("Next: markitdown-help install (dotfiles 셸) 또는 uv tool install 'markitdown[all]'")
        print("      TLS 인증서 오류가 나면: uv tool install --native-tls 'markitdown[all]'")
        return 1
    if not os.path.isdir(vault):
        print(f"[FAIL] vault 없음: {vault} -- 저장 위치는 고정이다 ({VAULT_SHOWN}); 만들지 않는다")
        return 1
    agent_reach = shutil.which("agent-reach") is not None  # PATH only: `agent-reach doctor` costs seconds
    if not agent_reach:
        print(TIP)
        print(TIP_NEXT)
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
    found = None
    route = ROUTES.get(kind) if agent_reach else None
    if route:
        tool, convert = route
        if shutil.which(tool) is None:
            print(f"[WARN] agent-reach 는 있으나 {tool} 미설치 -- markitdown 경로")
            print("Next: agent-reach doctor")
        else:
            found = convert(src)
    try:
        if kind == "article":
            found = discourse(src)
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
    if kind == "youtube" and not found and description_truncated(body):
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
    assert url_host("https://u:PW@Idp.kr:8443/sso;j=J?state=S#f") == "idp.kr"
    assert url_host("http://[bad/b?state=S") == "?" and url_host("/no/scheme") == "?"
    def run(err, code=1):
        return subprocess.CompletedProcess([], code, "", err)
    assert exc_class(run("SSLError: x https://h/a?state=S\n")) == "markitdown exit 1"
    assert exc_class(run("\n", 2)) == "markitdown exit 2"
    tb = ("Traceback (most recent call last):\n  File \"m.py\", line 1\n    f()\n"
          "requests.exceptions.ConnectionError: HTTPConnectionPool(url: /a?state=S)\n")
    assert exc_class(run(tb)) == "ConnectionError"
    chained = ("Traceback (most recent call last):\n  File \"a\"\nKeyError: 'k'\n\n"
               "During handling of the above exception, another exception occurred:\n\n" + tb)
    assert exc_class(run(chained)) == "ConnectionError"
    assert exc_class(run("Traceback (most recent call last):\n  File \"a\"\nnot a class line\n", 3)) == \
        "markitdown exit 3"
    assert login_wall("https://d.kr/login", "<html></html>")
    assert login_wall("https://d.kr/session/sso?return_path=/t/1", "")
    idp = "https://idp.example/oauth2/v1/authorize?s=2"
    assert login_wall(idp, "<html></html>", ["https://d.kr/session/sso?x=1", idp])
    assert not login_wall("https://d.kr/t/slug/1", "<html></html>", ["https://d.kr/t/slug/1"])
    assert not login_wall("https://blog.kr/auth/intro", "<html></html>")
    assert login_wall("https://gitlab.kr/users/sign_in", "")
    assert login_wall("https://d.kr/t/1.json",
                      '<meta name="generator" content="Discourse 3.2"><body class="login-required">')
    vtt = ("WEBVTT\nKind: captions\nLanguage: en\n\nNOTE a note\nspanning lines\n\n"
           "1\n00:00:00.000 --> 00:00:02.000 align:start position:0%\n"
           "hello<00:00:00.500><c> world</c>\n\n"
           "00:00:02.000 --> 00:00:02.010\nhello world\n \n\n"
           "00:00:02.010 --> 00:00:04.000\nhello world\nthis is <b>next</b> &amp; more\n\n"
           "00:00:04.000 --> 00:00:05.000\nthis is next &amp; more\nlast\n")
    assert vtt_to_text(vtt) == "hello world\nthis is next & more\nlast", vtt_to_text(vtt)
    assert vtt_to_text("WEBVTT\n\n") == ""
    assert sub_rank("ko", True) < sub_rank("en", True) < sub_rank("ja-orig", True) < sub_rank("ko", False)
    assert sub_rank("ja", True) is None
    assert sub_rank("en", True) < sub_rank("en-US", True) < sub_rank("ja-orig", True)
    assert sub_rank("en-orig", False) == sub_rank("ja-orig", False)
    assert upload_day("20260102") == "2026-01-02" and upload_day("2026") == "" and upload_day(None) == ""
    assert hms(3725) == "1:02:05" and hms(65.4) == "1:05" and hms(None) == ""
    body = ytdlp_body({"title": " T ", "uploader": "ch", "upload_date": "20260102", "duration": 65,
                       "view_count": 1234, "description": "full\ndesc",
                       "chapters": [{"start_time": 0, "title": "Intro"}]}, "https://y/w", ("ko", "manual", "t"))
    assert body.startswith("# T\n\n## Video Metadata\n\n- Channel: ch\n- Uploaded: 2026-01-02\n"), body
    assert "- Views: 1,234\n" in body and "## Chapters\n\n- 0:00 Intro" in body
    assert body.endswith("## Transcript (ko, manual)\n\nt\n")
    assert "## Transcript" not in ytdlp_body({"title": "T"}, "u", None)
    assert VAULT == os.path.abspath(os.path.expanduser("~/para/project/obsidian-para"))
    print("[OK] self-test")
    return 0


def main(argv):
    if argv and argv[0] in ("-h", "--help", "help"):
        with open(HELP, encoding="utf-8") as fh:
            sys.stdout.write(fh.read())
        return 0
    if argv == ["--self-test"]:
        return self_test()
    if any(a == "--vault" or a.startswith("--vault=") for a in argv):
        # refused, not ignored: a silently dropped --vault reads as "saved over there"
        print(f"[FAIL] --vault 는 지원하지 않는다 (저장 위치 고정: {VAULT_SHOWN})")
        return 2
    if len(argv) != 1:
        print("[FAIL] usage: clip.py <input> -- Run /pkm:obsidian-clip -h for usage.")
        return 2
    return clip(argv[0])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
