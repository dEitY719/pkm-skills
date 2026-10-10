#!/usr/bin/env bash
# skills/obsidian-clip/lib/clip.selfcheck.sh
#
# Offline check for lib/clip.py with a stub `markitdown` (and a stub `curl`
# for the Discourse path and the login-wall probe) on PATH: input
# classification, source normalization, filename, duplicate refusal, the
# missing-markitdown stop, empty / failed conversion, login walls, and the
# never-overwrite collision. Every run
# writes into a throwaway vault under mktemp -- never the real one.
#
# Usage:
#   bash skills/obsidian-clip/lib/clip.selfcheck.sh
# Exits 0 when every assertion passes, 1 otherwise.

# rc is read inside the eval strings below, which shellcheck cannot see.
# shellcheck disable=SC2034
set -uo pipefail

LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PY="$LIB/clip.py"
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
failures=0
TODAY="$(date +%F)"

ok() { printf '[OK]   %s\n' "$1"; }
bad() {
    printf '[FAIL] %s\n' "$1"
    sed 's/^/       /' "$TMP/out"
    failures=$((failures + 1))
}
check() { # <label> <test command...>
    local label="$1"
    shift
    if "$@"; then ok "$label"; else bad "$label"; fi
}
has() { grep -qF -- "$1" "$TMP/out"; }
notes() { find "$TMP/vault/99-Inbox" -name '*.md' 2>/dev/null | wc -l; }

# Stub markitdown: YouTube URLs give the real output shape, *empty* gives an
# empty file, *boom* fails with a TLS error, anything else one H1 + a line.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/markitdown" <<SH
#!/bin/sh
echo "\$*" >>"$TMP/calls"
in=\$1; out=\$3
case "\$in" in
*empty*) : >"\$out" ;;
*boom*) echo "SSLError: certificate verify failed" >&2; echo more >&2; exit 1 ;;
*/auth/intro) printf '# Auth Intro\n\nbody\n' >"\$out" ;;
*netfail*) printf '# Probe Down\n\nbody\n' >"\$out" ;;
*/guide/auth) printf '# Guide Auth\n\nbody\n' >"\$out" ;;
*/c/general) printf '# Forum Category\n\nbody\n' >"\$out" ;;
*youtube.com*|*youtu.be*)
    printf '# YouTube\n\n## Video: A/B "test"\n\n### Description\nfirst line ...\n\n### Transcript\nhello\n' >"\$out" ;;
*) printf 'nav\n\n# Page Title\n\nbody of %s\n' "\$in" >"\$out" ;;
esac
SH
chmod +x "$TMP/bin/markitdown"
# Stub curl: every URL answers 200 with an empty body unless it is the fake
# Discourse topic, which answers the topic JSON and its /raw markdown; topic
# 88 is a login-walled Discourse, 99 a non-Discourse site redirecting via /auth.
# private.* redirects to /login, sso.* hops via /session/sso to a third-party
# IdP, *netfail* is a network error, redir.* adds a trailing slash, and
# */c/general is a public Discourse page (generator meta + the preloaded
# login_required setting). Every URL is logged to $TMP/curlcalls.
cat >"$TMP/bin/curl" <<'SH'
#!/bin/sh
hdr=/dev/null
for a; do [ "${prev:-}" = -D ] && hdr=$a; prev=$a; url=$a; done
echo "$url" >>"$(dirname "$0")/../curlcalls"
eff=$url
case "$url" in
*netfail*) echo "curl: (6) Could not resolve host" >&2; exit 6 ;;
https://redir.example.com/guide/auth) printf 'HTTP/1.1 301 Moved\r\nLocation: /guide/auth/\r\n\r\n' >"$hdr"; printf '<html>guide</html>'; eff=https://redir.example.com/guide/auth/ ;;
*/c/general) printf '<meta name="generator" content="Discourse 3.2"><div data-preloaded="{&quot;login_required&quot;:false}">' ;;
https://private.example.com/*) printf 'HTTP/1.1 302 Found\r\nLocation: /login\r\n\r\n' >"$hdr"; printf '<form>sign in</form>'; eff=https://private.example.com/login ;;
https://sso.example.com/*) printf 'HTTP/1.1 302 Found\r\nLocation: /session/sso?return_path=/x\r\n\r\nHTTP/1.1 302 Found\r\nLocation: https://idp.example.net/oauth2/authorize?s=1\r\n\r\n' >"$hdr"; printf '<html>IdP</html>'; eff=https://idp.example.net/oauth2/authorize?s=1 ;;
*/t/88.json) printf '<meta name="generator" content="Discourse 3.2"><body class="login-required">'; eff=https://walled.example.com/login ;;
*/t/99.json) printf 'HTTP/1.1 302 Found\r\nLocation: /auth/sign-in\r\n\r\n' >"$hdr"; printf '<html>sign in</html>'; eff=https://plain.example.com/auth/sign-in ;;
*/t/77.json) printf '{"title":"Disc Topic","post_stream":{"posts":[{"username":"kim","created_at":"2026-01-02T00:00:00Z","cooked":"<img src=\\"https://cdn/x.png\\" data-base62-sha1=\\"AbC\\">"}]}}' ;;
*/raw/77/1) printf 'raw body ![i|10x20](upload://AbC.png)\n' ;;
*) : ;;
esac
printf '\n%s 200' "$eff" >&2
SH
chmod +x "$TMP/bin/curl"

mkdir -p "$TMP/vault"
run() { # <args...>; output in $TMP/out, returns the exit code
    PATH="$TMP/bin:$PATH" python3 "$PY" "$@" >"$TMP/out" 2>&1
}

check "pure helpers (--self-test)" run --self-test

# 1. markitdown missing -> exact lines, exit 1, vault untouched
pybin="$(python3 -c 'import sys; print(sys.executable)')"
mkdir -p "$TMP/emptybin"
PATH="$TMP/emptybin" "$pybin" "$PY" https://example.com/x "$TMP/vault" >"$TMP/out" 2>&1
rc=$?
check "markitdown missing -> [FAIL] + Next: install, exit 1, nothing written" \
    eval '[ $rc = 1 ] && has "[FAIL] markitdown 미설치" && has "Next: markitdown-help install" && has "uv tool install '"'"'markitdown[all]'"'"'" && [ -z "$(ls -A "$TMP/vault")" ]'

# 2. YouTube share URL -> 99-Inbox/<today> <## title>.md, tag youtube
: >"$TMP/calls"
: >"$TMP/curlcalls"
run "https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB" "$TMP/vault"
yt="$TMP/vault/99-Inbox/$TODAY Video AB test.md"
check "YouTube shorts -> markitdown gets the canonical watch URL" \
    grep -qF "https://www.youtube.com/watch?v=nGKKWne_O2s -o " "$TMP/calls"
check "YouTube -> 99-Inbox/ root, title from ## heading, forbidden chars removed" \
    eval '[ -s "$yt" ] && has "[OK] $yt" && tail -n1 "$TMP/out" | grep -qxF "/ingest $yt"'
check "YouTube note: Web Clipper frontmatter, tag youtube, source verbatim, body kept" \
    eval 'grep -qxF "  - \"youtube\"" "$yt" && grep -qxF "status: \"unread\"" "$yt" && grep -qxF "source: \"https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB\"" "$yt" && grep -q "^### Transcript" "$yt" && grep -q "^## 메모" "$yt"'
check "truncated Description -> [WARN]" eval 'has "[WARN] YouTube Description"'
check "YouTube -> no login-wall probe (curl not called)" eval '[ ! -s "$TMP/curlcalls" ]'

# 3. same video, other URL shapes -> duplicate refusal with the existing path
for u in "https://www.youtube.com/shorts/nGKKWne_O2s" "https://www.youtube.com/watch?v=nGKKWne_O2s&t=3s" "https://youtu.be/nGKKWne_O2s"; do
    : >"$TMP/calls"
    run "$u" "$TMP/vault"
    rc=$?
    check "duplicate ($u) refused before conversion, existing path shown" \
        eval '[ $rc = 1 ] && has "이미 클립됨" && has "$yt" && [ "$(notes)" = 1 ] && [ ! -s "$TMP/calls" ]'
done

# 4. generic URL -> markitdown, tag article, title from the H1
run "https://example.com/post/?utm_source=x" "$TMP/vault"
art="$TMP/vault/99-Inbox/$TODAY Page Title.md"
check "generic URL -> markitdown, tag article, title from # heading" \
    eval '[ -s "$art" ] && grep -qxF "  - \"article\"" "$art"'
run "https://www.example.com/post" "$TMP/vault"
check "tracking params / www / trailing slash normalized -> duplicate" eval 'has "이미 클립됨" && has "$art"'

# 5. same title, different source -> filename collision, no overwrite
before="$(cat "$art")"
run "https://example.com/other" "$TMP/vault"
rc=$?
check "same title + date, other source -> [FAIL], existing note untouched" \
    eval '[ $rc = 1 ] && has "같은 이름의 다른 노트" && [ "$(cat "$art")" = "$before" ] && [ -z "$(find "$TMP/vault" -name ".clip-*")" ]'

# 6. local documents -> stem title, tag document, absolute source
mkdir -p "$TMP/docs"
: >"$TMP/curlcalls"
for ext in pdf docx xlsx; do
    : >"$TMP/docs/report-$ext.$ext"
    (cd "$TMP/docs" && PATH="$TMP/bin:$PATH" python3 "$PY" "report-$ext.$ext" "$TMP/vault") >"$TMP/out" 2>&1
    d="$TMP/vault/99-Inbox/$TODAY report-$ext.md"
    check "local .$ext -> document note, absolute source" \
        eval '[ -s "$d" ] && grep -qxF "  - \"document\"" "$d" && grep -qxF "source: \"$TMP/docs/report-$ext.$ext\"" "$d"'
done
check "local files -> no login-wall probe (curl not called)" eval '[ ! -s "$TMP/curlcalls" ]'
run "$TMP/docs/report-pdf.pdf" "$TMP/vault"
check "same local file again -> duplicate" eval 'has "이미 클립됨"'
# shellcheck disable=SC2088  # the literal tilde is the point: clip.py must expand it
HOME="$TMP" run "~/docs/report-pdf.pdf" "$TMP/vault"
check "tilde input expanded -> same file, duplicate" eval 'has "이미 클립됨"'
OBSIDIAN_CLIP_TIMEOUT=abc run -h
check "non-numeric OBSIDIAN_CLIP_TIMEOUT -> no traceback" eval 'has "## Arguments" && ! has "Traceback"'

# 7. failures write nothing
n="$(notes)"
: >"$TMP/docs/scan-empty.pdf"
run "$TMP/docs/scan-empty.pdf" "$TMP/vault"
check "empty conversion -> [WARN], nothing written" eval 'has "[WARN]" && [ "$(notes)" = "$n" ]'
run "https://boom.example.com/x" "$TMP/vault"
check "markitdown failure -> first stderr line + TLS Next:, nothing written" \
    eval 'has "SSLError: certificate verify failed" && ! has "more" && has "REQUESTS_CA_BUNDLE" && [ "$(notes)" = "$n" ]'
run "$TMP/docs/missing.pdf" "$TMP/vault"
check "missing local file -> [FAIL]" eval 'has "[FAIL] 입력을 찾을 수 없다" && [ "$(notes)" = "$n" ]'
run "https://example.com/z" "$TMP/no-such-vault"
check "missing vault refused, never created" eval 'has "vault 없음" && [ ! -e "$TMP/no-such-vault" ]'

# 8. Discourse topic -> /raw body, upload:// mapped, |WxH stripped, no markitdown
: >"$TMP/calls"
run "https://forum.example.com/t/some-topic/77" "$TMP/vault"
disc="$TMP/vault/99-Inbox/$TODAY Disc Topic.md"
check "Discourse -> /raw body, author/published, upload mapped, markitdown not called" \
    eval 'has "[OK] Discourse" && grep -qxF "raw body ![i](https://cdn/x.png)" "$disc" && grep -qxF "  - \"kim\"" "$disc" && grep -qxF "published: 2026-01-02" "$disc" && [ ! -s "$TMP/calls" ]'

run "https://forum.example.com/t/other-slug/77/5?u=kim" "$TMP/vault"
check "same Discourse topic, other post / referral -> duplicate" eval 'has "이미 클립됨" && has "$disc"'

# 9. login walls: Discourse's own is a stop; another site's walled /t/<id>.json
# is not (its page is probed instead, see 9b)
n="$(notes)"
run "https://walled.example.com/t/slug/88" "$TMP/vault"
check "login-walled Discourse -> [FAIL] 로그인 필요, nothing written" eval 'has "로그인 필요" && [ "$(notes)" = "$n" ]'
: >"$TMP/calls"
run "https://plain.example.com/t/slug/99" "$TMP/vault"
check "non-Discourse /t/ URL behind /auth -> falls back to markitdown" \
    eval '! has "로그인 필요" && grep -q "plain.example.com/t/slug/99" "$TMP/calls"'

# 9b. login walls on any article URL: the curl probe refuses before markitdown
n="$(notes)"
: >"$TMP/calls"
run "https://private.example.com/private" "$TMP/vault"
rc=$?
check "non-topic URL redirected to /login -> [FAIL] 로그인 필요, nothing written, no markitdown" \
    eval '[ $rc = 1 ] && has "[FAIL] 로그인 필요 (https://private.example.com/login)" && [ "$(notes)" = "$n" ] && [ ! -s "$TMP/calls" ]'
run "https://sso.example.com/page" "$TMP/vault"
rc=$?
check "SSO hop via /session/sso to a third-party IdP -> [FAIL] 로그인 필요, nothing written" \
    eval '[ $rc = 1 ] && has "로그인 필요 (https://idp.example.net/" && [ "$(notes)" = "$n" ] && [ ! -s "$TMP/calls" ]'
run "https://blog.example.com/auth/intro" "$TMP/vault"
check "user-requested /auth/intro (no redirect) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$TMP/vault/99-Inbox/$TODAY Auth Intro.md" ]'
run "https://netfail.example.com/a" "$TMP/vault"
check "probe network error -> falls through to markitdown, clipped" \
    eval '! has "로그인 필요" && [ -s "$TMP/vault/99-Inbox/$TODAY Probe Down.md" ]'
run "https://redir.example.com/guide/auth" "$TMP/vault"
check "redirect that keeps the asked /auth path (trailing slash) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$TMP/vault/99-Inbox/$TODAY Guide Auth.md" ]'
run "https://forum.example.com/c/general" "$TMP/vault"
check "public Discourse non-topic page (login_required preloaded) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$TMP/vault/99-Inbox/$TODAY Forum Category.md" ]'

# 10. markitdown that hangs -> timeout [FAIL], nothing written
n="$(notes)"
printf '#!/bin/sh\nsleep 5\n' >"$TMP/slowbin-markitdown"
mkdir -p "$TMP/slowbin" && mv "$TMP/slowbin-markitdown" "$TMP/slowbin/markitdown" && chmod +x "$TMP/slowbin/markitdown"
PATH="$TMP/slowbin:$PATH" OBSIDIAN_CLIP_TIMEOUT=1 python3 "$PY" https://slow.example.com/x "$TMP/vault" >"$TMP/out" 2>&1
check "markitdown timeout -> [FAIL], nothing written" eval 'has "markitdown timeout 1s" && [ "$(notes)" = "$n" ]'

# 11. help writes nothing, calls nothing
for h in -h --help help; do
    run "$h"
    check "$h prints help" eval 'has "## Arguments"'
done

[ "$failures" -eq 0 ] || exit 1
