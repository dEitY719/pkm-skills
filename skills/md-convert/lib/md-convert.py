#!/usr/bin/env python3
"""skills/md-convert/lib/md-convert.py -- files / URLs -> .md via markitdown.

Usage:
  md-convert.py <input>... [--output-path <dir>] [--force]
  md-convert.py -h | --help | help

Local file -> <its dir>/<stem>.md; URL -> <cwd>/.md-convert/<name>.md
(youtube-<ID>.md or <host>-<path slug>.md). --output-path overrides the dir.
An existing target is [SKIP]ped unless --force. Lines start with
[OK] / [SKIP] / [WARN] / [FAIL]; the last line is `ok=N skip=N fail=N`.
Exit 1 when anything failed. Never commits. stdlib only.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

HELP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references", "help.md")
URL_DIR = ".md-convert"
TLS_HINT = re.compile(r"ssl|tls|certificate|cert|proxy|connection|resolve|timed? ?out", re.I)


def is_url(s):
    return re.match(r"https?://", s, re.I) is not None


def slug(s, limit=80):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:limit].strip("-")


def url_name(url):
    u = urllib.parse.urlsplit(url)
    host = (u.hostname or "").lower()
    vid = None
    if host in ("youtube.com", "www.youtube.com", "m.youtube.com") and u.path == "/watch":
        vid = urllib.parse.parse_qs(u.query).get("v", [None])[0]
    elif host == "youtu.be":
        vid = u.path.strip("/").split("/")[0]
    if vid:
        vid = re.sub(r"[^A-Za-z0-9_-]", "", vid)  # IDs are case-sensitive: keep case
        if vid:
            return f"youtube-{vid}.md"
    host = re.sub(r"[^a-z0-9.-]", "", host) or "url"
    s = slug(u.path)
    return f"{host}-{s}.md" if s else f"{host}.md"


def ensure_excluded(cwd):
    """Append `.md-convert/` to the repo's info/exclude once; no-op outside git."""
    try:
        r = subprocess.run(["git", "rev-parse", "--git-path", "info/exclude"],
                           cwd=cwd, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return
    if r.returncode != 0:
        return
    path = os.path.join(cwd, r.stdout.strip())
    line = URL_DIR + "/"
    try:
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except FileNotFoundError:
            text = ""
        if line in text.splitlines():
            return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(("" if not text or text.endswith("\n") else "\n") + line + "\n")
    except OSError as e:
        print(f"[WARN] {path} 갱신 실패 ({e}) -- .md-convert/ 가 git status 에 보일 수 있음")


def convert(src, out_dir, force):
    """Return 'ok' / 'skip' / 'fail' after printing one report line."""
    url = is_url(src)
    if url:
        name, arg = url_name(src), src
    else:
        if not os.path.isfile(src):
            print(f"[FAIL] {src}: not found")
            return "fail"
        arg = os.path.abspath(src)
        name = os.path.splitext(os.path.basename(arg))[0] + ".md"
        out_dir = out_dir or os.path.dirname(arg)
    out = os.path.join(out_dir, name)
    if os.path.exists(out) and not force:
        print(f"[SKIP] {src} -> {out} (exists; --force to overwrite)")
        return "skip"
    # Convert into a temp file beside the target: a failed or empty run never
    # leaves a partial file and never clobbers the existing one under --force.
    fd, tmp = tempfile.mkstemp(prefix=".md-convert-", suffix=".md", dir=out_dir)
    os.close(fd)
    try:
        r = subprocess.run(["markitdown", arg, "-o", tmp],
                           capture_output=True, text=True, check=False)
        if r.returncode != 0:
            err = next((ln for ln in r.stderr.splitlines() if ln.strip()), f"exit {r.returncode}")
            print(f"[FAIL] {src}: {err.strip()}")
            if url or TLS_HINT.search(r.stderr):
                print("Next: 네트워크/TLS 오류면 REQUESTS_CA_BUNDLE (사내 CA 번들) 과 "
                      "HTTP(S)_PROXY 설정을 확인 -- 인증서 검증은 끄지 않는다")
            return "fail"
        with open(tmp, encoding="utf-8", errors="replace") as fh:
            empty = not fh.read().strip()
        if empty:
            print(f"[WARN] {src}: empty output (scanned PDF? OCR not supported) -- no file written")
            return "fail"
        os.replace(tmp, out)
        print(f"[OK] {src} -> {out} ({os.path.getsize(out)} bytes)")
        return "ok"
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def main(argv):
    if argv[:1] == ["help"] or "-h" in argv or "--help" in argv:
        with open(HELP, encoding="utf-8") as fh:
            sys.stdout.write(fh.read())
        return 0
    inputs, out_opt, force = [], None, False
    it = iter(argv)
    for a in it:
        if a == "--force":
            force = True
        elif a == "--output-path":
            out_opt = next(it, None)
            if not out_opt:
                print("[FAIL] --output-path needs a directory")
                return 1
        elif a.startswith("--output-path="):
            out_opt = a.split("=", 1)[1]
        elif a.startswith("--"):
            print(f"[FAIL] unknown option {a}")
            print("Run /pkm:md-convert -h for usage.")
            return 1
        else:
            inputs.append(a)
    if not inputs:
        print("Run /pkm:md-convert -h for usage.")
        return 1
    if shutil.which("markitdown") is None:
        # PATH only, before any mkdir / exclude write; never auto-install.
        print("[FAIL] markitdown 미설치")
        print("Next: uv tool install 'markitdown[all]'")
        print("      TLS 인증서 오류가 나면: uv tool install --native-tls 'markitdown[all]'")
        return 1
    if out_opt is not None:
        out_opt = os.path.abspath(out_opt)
        if os.path.exists(out_opt) and not os.path.isdir(out_opt):
            print("[FAIL] --output-path is not a directory")
            return 1

    cwd = os.getcwd()
    counts = {"ok": 0, "skip": 0, "fail": 0}
    for src in inputs:
        out_dir = out_opt
        if out_dir is None and is_url(src):
            out_dir = os.path.join(cwd, URL_DIR)
            os.makedirs(out_dir, exist_ok=True)
            ensure_excluded(cwd)
        elif out_dir is not None:
            os.makedirs(out_dir, exist_ok=True)
        try:
            counts[convert(src, out_dir, force)] += 1
        except OSError as e:
            print(f"[FAIL] {src}: {e}")
            counts["fail"] += 1
    print(f"ok={counts['ok']} skip={counts['skip']} fail={counts['fail']}")
    return 1 if counts["fail"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
