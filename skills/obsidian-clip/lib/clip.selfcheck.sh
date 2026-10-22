#!/usr/bin/env bash
# skills/obsidian-clip/lib/clip.selfcheck.sh
#
# Offline check for lib/clip.py with a stub `markitdown` (and a stub `curl`
# for the Discourse path and the login-wall probe, stub `agent-reach` /
# `yt-dlp` for the YouTube yt-dlp path) on PATH: input classification, source
# normalization, filename, duplicate refusal, the missing-markitdown stop,
# empty / failed conversion, login walls, the never-overwrite collision, the
# agent-reach TIP, the yt-dlp path and its markitdown fallback, and the fixed
# vault. PATH is rebuilt from the stubs plus a few coreutils, so a real
# agent-reach / yt-dlp on the machine is never reached. HOME points at mktemp,
# so the fixed vault (~/para/project/obsidian-para) is a throwaway one --
# never the real one.
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
notes() { find "$VAULT/99-Inbox" -name '*.md' 2>/dev/null | wc -l; }

# Stub markitdown: YouTube URLs give the real output shape, *empty* gives an
# empty file, *boom* fails with a TLS error, *tbfail* with a real-shaped
# traceback, anything else one H1 + a line.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/markitdown" <<SH
#!/bin/sh
echo "\$*" >>"$TMP/calls"
in=\$1; out=\$3
case "\$in" in
*empty*) : >"\$out" ;;
*boom*) echo "SSLError: certificate verify failed" >&2; echo more >&2; exit 1 ;;
*nodeps*) printf '%s\n' 'Traceback (most recent call last):' '  File "/x/markitdown/__main__.py", line 1, in main' 'markitdown._exceptions.FileConversionException: File conversion failed after 1 attempts:' ' - PdfConverter threw MissingDependencyException with message: install [pdf]' >&2; exit 1 ;;
*tbfail*) printf '%s\n' 'Traceback (most recent call last):' '  File "/x/markitdown/__main__.py", line 1, in main' "requests.exceptions.ConnectionError: HTTPConnectionPool(host='127.0.0.1', port=9): Max retries exceeded with url: /sso;jsessionid=TOKJ?SAMLRequest=TOKSAML&state=TOKSTATE#frag (Caused by NewConnectionError(...))" >&2; exit 1 ;;
*tokfail*) echo "HTTPError: 403 Forbidden for url: https://u:TOKPW@idp.example.net/saml;jsessionid=TOKJ?state=TOKSTATE&SAMLRequest=TOKSAML#frag" >&2; exit 1 ;;
*/auth/intro) printf '# Auth Intro\n\nbody\n' >"\$out" ;;
*netfail*) printf '# Probe Down\n\nbody\n' >"\$out" ;;
*/guide/auth) printf '# Guide Auth\n\nbody\n' >"\$out" ;;
*/c/general) printf '# Forum Category\n\nbody\n' >"\$out" ;;
*/private) printf '# Private Page\n\nbody\n' >"\$out" ;;
*/guide/sign-in) printf '# Sign-in Guide\n\nbody\n' >"\$out" ;;
*nGKKWne_O2s*)
    printf '# YouTube\n\n## Video: A/B "test"\n\n### Description\nfirst line ...\n\n### Transcript\nhello\n' >"\$out" ;;
*youtube.com*|*youtu.be*)
    printf '# YouTube\n\n## MD %s\n\n### Description\ncut ...\n' "\${in##*v=}" >"\$out" ;;
*) printf 'nav\n\n# Page Title\n\nbody of %s\n' "\$in" >"\$out" ;;
esac
SH
chmod +x "$TMP/bin/markitdown"
# Stub curl: every URL answers 200 with an empty body unless it is the fake
# Discourse topic, which answers the topic JSON and its /raw markdown; topic
# 88 is a login-walled Discourse, 99 a non-Discourse site redirecting via /auth,
# 66 a topic whose /raw times out after a redirect to a token-bearing IdP URL,
# 64 one whose /raw curl error line itself names a token-bearing URL
# (synthetic: real curl names host and port there; none of it may be printed),
# 65 the same as 66 with no curl error line (the -w trailer alone on stderr).
# private.* redirects to /login, sso.* hops via /session/sso to a third-party
# IdP, *netfail* is a network error, redir.* adds a trailing slash, and
# */c/general is a public Discourse page (generator meta + the preloaded
# login_required setting). Every URL is logged to $TMP/curlcalls.
cat >"$TMP/bin/curl" <<'SH'
#!/bin/sh
hdr=/dev/null
for a; do [ "${prev:-}" = -D ] && hdr=$a; prev=$a; url=$a; done
echo "$url" >>"$(dirname "$0")/../curlcalls"
echo "$*" >>"$(dirname "$0")/../curlargs"
eff=$url
case "$url" in
*netfail*) echo "curl: (6) Could not resolve host" >&2; exit 6 ;;
https://redir.example.com/guide/auth) printf 'HTTP/1.1 301 Moved\r\nLocation: /guide/auth/\r\n\r\n' >"$hdr"; printf '<html>guide</html>'; eff=https://redir.example.com/guide/auth/ ;;
*/c/general) printf '<meta name="generator" content="Discourse 3.2"><div data-preloaded="{&quot;login_required&quot;:false}">' ;;
https://private.example.com/*) printf 'HTTP/1.1 302 Found\r\nLocation: /login\r\n\r\n' >"$hdr"; printf '<form>sign in</form>'; eff=https://private.example.com/login ;;
https://sso.example.com/*) printf 'HTTP/1.1 302 Found\r\nLocation: /session/sso?return_path=/x\r\n\r\nHTTP/1.1 302 Found\r\nLocation: https://u:TOKPW@idp.example.net/oauth2/authorize;jsessionid=TOKJSID?state=TOKSTATE&SAMLRequest=TOKSAML#frag\r\n\r\n' >"$hdr"; printf '<html>IdP</html>'; eff='https://u:TOKPW@idp.example.net/oauth2/authorize;jsessionid=TOKJSID?state=TOKSTATE&SAMLRequest=TOKSAML#frag' ;;
*/raw/66/1) printf 'curl: (28) Operation timed out\n%s 000' 'https://idp.example.net/a?state=TOKRAW' >&2; exit 28 ;;
*/t/88.json) printf '<meta name="generator" content="Discourse 3.2"><body class="login-required">'; eff='https://walled.example.com/login?nonce=TOK88' ;;
*/t/99.json) printf 'HTTP/1.1 302 Found\r\nLocation: /auth/sign-in\r\n\r\n' >"$hdr"; printf '<html>sign in</html>'; eff=https://plain.example.com/auth/sign-in ;;
*/t/66.json) printf '{"title":"Raw Down","post_stream":{"posts":[{"username":"kim"}]}}' ;;
*/raw/64/1) printf 'curl: (7) Failed to connect to %s\n%s 000' 'https://idp.example.net/a?state=TOKCURL' 'https://idp.example.net/b?state=TOKTRL64' >&2; exit 7 ;;
*/t/64.json) printf '{"title":"Raw Tok","post_stream":{"posts":[{"username":"kim"}]}}' ;;
*/raw/65/1) printf '\n%s 000' 'https://idp.example.net/a?state=TOKTRL' >&2; exit 28 ;;
*/t/65.json) printf '{"title":"Raw Bare","post_stream":{"posts":[{"username":"kim"}]}}' ;;
*/t/77.json) printf '{"title":"Disc Topic","post_stream":{"posts":[{"username":"kim","created_at":"2026-01-02T00:00:00Z","cooked":"<img src=\\"https://cdn/x.png\\" data-base62-sha1=\\"AbC\\">"}]}}' ;;
*/raw/77/1) printf 'raw body ![i|10x20](upload://AbC.png)\n' ;;
*) : ;;
esac
printf '\n%s 200' "$eff" >&2
SH
chmod +x "$TMP/bin/curl"

# Hermetic PATH: stubs + the coreutils the stubs call. $AR / $YT are the
# optional agent-reach / yt-dlp stub dirs; RP=<path> overrides it per run.
pybin="$(python3 -c 'import sys; print(sys.executable)')"
mkdir -p "$TMP/sys" "$TMP/home/para/project/obsidian-para"
for t in dirname cat sleep; do ln -s "$(command -v "$t")" "$TMP/sys/$t"; done
BASE="$TMP/bin:$TMP/sys"
AR="$TMP/ar"
YT="$TMP/yt"
VAULT="$TMP/home/para/project/obsidian-para"
run() { # <args...>; output in $TMP/out, returns the exit code
    HOME="${H:-$TMP/home}" PATH="${RP:-$BASE}" "$pybin" "$PY" "$@" >"$TMP/out" 2>&1
}

check "pure helpers (--self-test)" run --self-test

# Stub agent-reach: logs every call (clip.py must never run it, doctor
# included). Stub yt-dlp: the video ID picks the behaviour -- yt*FAIL* exits 1
# with a token-bearing stderr, ytSLOW* hangs, ytBADJSON* / ytNOTITLE* return
# unusable metadata, ytNOSUBS* / ytSUBFAIL* land no subtitle file, ytAUTO* only
# a rolling auto-caption track; anything else full metadata, a manual ko track
# and an auto en track. Every call is logged to $TMP/ytcalls.
mkdir -p "$AR" "$YT"
printf '#!/bin/sh\necho "$*" >>"%s/arcalls"\n' "$TMP" >"$AR/agent-reach"
cat >"$YT/yt-dlp" <<'SH'
#!/bin/sh
echo "$*" >>"$(dirname "$0")/../ytcalls"
prev=; out=; dump=0
for a; do
    [ "$prev" = -o ] && out=$a
    [ "$a" = --dump-json ] && dump=1
    prev=$a
    url=$a
done
id=${url##*v=}
case "$id" in
ytFAIL*) echo "ERROR: [youtube] $id: Sign in to confirm you're not a bot https://x.example/?state=TOKSTDERR" >&2; exit 1 ;;
ytSLOW*) sleep 5; exit 0 ;;
esac
if [ $dump = 1 ]; then
    case "$id" in
    ytBADJSON*) echo 'not json'; exit 0 ;;
    ytNOTITLE*) echo '{"id":"x","title":"  "}'; exit 0 ;;
    esac
    printf '{"id":"%s","title":"YT Full %s","uploader":"Chan Name","upload_date":"20260315","duration":3725,"view_count":1234567,"description":"line one\\nends with dots ...\\nno truncation here","chapters":[{"start_time":0,"title":"Intro"},{"start_time":65,"title":"Main"}],"subtitles":{"ko":[{}]},"automatic_captions":{"en":[{}]}}\n' "$id" "$id"
    exit 0
fi
dir=$(dirname "$out")
case "$id" in
ytNOSUBS*) : ;;
ytSUBFAIL*) echo "ERROR: subtitles https://x.example/?state=TOKSUB" >&2; exit 1 ;;
ytAUTO*) printf 'WEBVTT\nKind: captions\n\n00:00:00.000 --> 00:00:01.000 align:start\nroll one<00:00:00.500><c> two</c>\n\n00:00:01.000 --> 00:00:01.010\nroll one two\n\n00:00:01.010 --> 00:00:02.000\nroll one two\nroll three\n' >"$dir/$id.en.vtt" ;;
*) printf 'WEBVTT\n\n1\n00:00:00.000 --> 00:00:01.000\n<v Kim>ko line one</v>\n\n2\n00:00:01.000 --> 00:00:02.000\nko line two\n' >"$dir/$id.ko.vtt"
   printf 'WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nenglish auto\n' >"$dir/$id.en.vtt" ;;
esac
SH
chmod +x "$AR/agent-reach" "$YT/yt-dlp"
BULB="$(printf '\360\237\222\241')"

# 1. markitdown missing -> exact lines, exit 1, vault untouched
mkdir -p "$TMP/emptybin"
RP="$TMP/emptybin" run https://example.com/x
rc=$?
check "markitdown missing -> [FAIL] + Next: install, exit 1, nothing written" \
    eval '[ $rc = 1 ] && has "[FAIL] markitdown 미설치" && has "Next: markitdown-help install" && has "uv tool install '"'"'markitdown[all]'"'"'" && [ -z "$(ls -A "$VAULT")" ]'

# 2. YouTube share URL -> 99-Inbox/<today> <## title>.md, tag youtube
: >"$TMP/calls"
: >"$TMP/curlcalls"
run "https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB"
yt="$VAULT/99-Inbox/$TODAY Video AB test.md"
check "YouTube shorts -> markitdown gets the canonical watch URL" \
    grep -qF "https://www.youtube.com/watch?v=nGKKWne_O2s -o " "$TMP/calls"
check "YouTube -> 99-Inbox/ root, title from ## heading, forbidden chars removed" \
    eval '[ -s "$yt" ] && has "[OK] $yt" && tail -n1 "$TMP/out" | grep -qxF "/ingest $yt"'
check "YouTube note: Web Clipper frontmatter, tag youtube, source verbatim, body kept" \
    eval 'grep -qxF "  - \"youtube\"" "$yt" && grep -qxF "status: \"unread\"" "$yt" && grep -qxF "source: \"https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB\"" "$yt" && grep -q "^### Transcript" "$yt" && grep -q "^## 메모" "$yt"'
check "truncated Description -> [WARN]" eval 'has "[WARN] YouTube Description"'
check "YouTube -> no login-wall probe (curl not called)" eval '[ ! -s "$TMP/curlcalls" ]'
check "no agent-reach -> light-bulb [TIP] + Next: install line, still exit 0" \
    eval 'has "$BULB [TIP] agent-reach 미설치 — 설치하면 YouTube 를 yt-dlp 로 클립합니다" && has "Next: 설치 안내 https://github.com/Panniantong/Agent-Reach (docs/install.md)" && [ -s "$yt" ]'

# 3. same video, other URL shapes -> duplicate refusal with the existing path
for u in "https://www.youtube.com/shorts/nGKKWne_O2s" "https://www.youtube.com/watch?v=nGKKWne_O2s&t=3s" "https://youtu.be/nGKKWne_O2s"; do
    : >"$TMP/calls"
    run "$u"
    rc=$?
    check "duplicate ($u) refused before conversion, existing path shown" \
        eval '[ $rc = 1 ] && has "이미 클립됨" && has "$yt" && [ "$(notes)" = 1 ] && [ ! -s "$TMP/calls" ]'
done

# 4. generic URL -> markitdown, tag article, title from the H1
run "https://example.com/post/?utm_source=x"
art="$VAULT/99-Inbox/$TODAY Page Title.md"
check "generic URL -> markitdown, tag article, title from # heading" \
    eval '[ -s "$art" ] && grep -qxF "  - \"article\"" "$art"'
check "no agent-reach -> [TIP] on a web URL too" has "[TIP] agent-reach 미설치"
run "https://www.example.com/post"
check "tracking params / www / trailing slash normalized -> duplicate" eval 'has "이미 클립됨" && has "$art"'

# 5. same title, different source -> filename collision, no overwrite
before="$(cat "$art")"
run "https://example.com/other"
rc=$?
check "same title + date, other source -> [FAIL], existing note untouched" \
    eval '[ $rc = 1 ] && has "같은 이름의 다른 노트" && [ "$(cat "$art")" = "$before" ] && [ -z "$(find "$VAULT" -name ".clip-*")" ]'

# 6. local documents -> stem title, tag document, absolute source
mkdir -p "$TMP/docs"
: >"$TMP/curlcalls"
for ext in pdf docx xlsx; do
    : >"$TMP/docs/report-$ext.$ext"
    (cd "$TMP/docs" && run "report-$ext.$ext")
    d="$VAULT/99-Inbox/$TODAY report-$ext.md"
    check "local .$ext -> document note, absolute source" \
        eval '[ -s "$d" ] && grep -qxF "  - \"document\"" "$d" && grep -qxF "source: \"$TMP/docs/report-$ext.$ext\"" "$d"'
done
check "local files -> no login-wall probe (curl not called)" eval '[ ! -s "$TMP/curlcalls" ]'
check "no agent-reach -> [TIP] on a local document too" has "[TIP] agent-reach 미설치"
run "$TMP/docs/report-pdf.pdf"
check "same local file again -> duplicate" eval 'has "이미 클립됨"'
# shellcheck disable=SC2088  # the literal tilde is the point: clip.py must expand it
run "~/../docs/report-pdf.pdf"
check "tilde input expanded -> same file, duplicate" eval 'has "이미 클립됨"'
OBSIDIAN_CLIP_TIMEOUT=abc run -h
check "non-numeric OBSIDIAN_CLIP_TIMEOUT -> no traceback" eval 'has "## Arguments" && ! has "Traceback"'

# 7. failures write nothing
n="$(notes)"
: >"$TMP/docs/scan-empty.pdf"
run "$TMP/docs/scan-empty.pdf"
check "empty conversion -> [WARN], nothing written" eval 'has "[WARN]" && [ "$(notes)" = "$n" ]'
run "https://boom.example.com/x"
check "markitdown failure, no traceback -> exit code + host, TLS and markitdown Next:, nothing written" \
    eval 'has "[FAIL] https://boom.example.com/x: markitdown exit 1 (boom.example.com) -- " && ! has "SSLError" && ! has "more" && has "REQUESTS_CA_BUNDLE" && has "Next: 원인 상세: markitdown https://boom.example.com/x 를 직접 실행" && [ "$(notes)" = "$n" ]'
run "https://boom.example.com/x?a=1&b=\$HOME"
check "markitdown Next: command shell-quotes the input" \
    has "Next: 원인 상세: markitdown 'https://boom.example.com/x?a=1&b=\$HOME' 를 직접 실행"
: >"$TMP/docs/nodeps.pdf"
run "$TMP/docs/nodeps.pdf"
check "local file missing a markitdown extra -> class + install Next:, nothing written" \
    eval 'has "[FAIL] $TMP/docs/nodeps.pdf: FileConversionException -- " && has "uv tool install '"'"'markitdown[all]'"'"'" && ! has "PdfConverter" && [ "$(notes)" = "$n" ]'
run "https://tokfail.example.com/x"
check "markitdown stderr naming a token-bearing URL -> none of it printed, input host only, nothing written" \
    eval 'has "markitdown exit 1 (tokfail.example.com) -- " && ! has "TOK" && ! has "idp.example.net" && ! has "/saml" && ! has "state=" && ! has "SAMLRequest=" && ! has "#frag" && [ "$(notes)" = "$n" ]'
run "https://tbfail.example.com/x"
check "markitdown traceback -> exception class + host only, message never printed" \
    eval 'has "[FAIL] https://tbfail.example.com/x: ConnectionError (tbfail.example.com) -- " && ! has "requests.exceptions" && ! has "HTTPConnectionPool" && ! has "/sso" && ! has "Traceback" && ! has "TOK" && ! has "state=" && ! has "SAMLRequest=" && ! has "#frag" && [ "$(notes)" = "$n" ]'
run "$TMP/docs/missing.pdf"
check "missing local file -> [FAIL]" eval 'has "[FAIL] 입력을 찾을 수 없다" && [ "$(notes)" = "$n" ]'
H="$TMP/nohome" run "https://example.com/z"
rc=$?
check "missing fixed vault refused, never created" \
    eval '[ $rc = 1 ] && has "[FAIL] vault 없음: $TMP/nohome/para/project/obsidian-para" && [ ! -e "$TMP/nohome" ]'

# 8. Discourse topic -> /raw body, upload:// mapped, |WxH stripped, no markitdown
: >"$TMP/calls"
run "https://forum.example.com/t/some-topic/77"
disc="$VAULT/99-Inbox/$TODAY Disc Topic.md"
check "Discourse -> /raw body, author/published, upload mapped, markitdown not called" \
    eval 'has "[OK] Discourse" && grep -qxF "raw body ![i](https://cdn/x.png)" "$disc" && grep -qxF "  - \"kim\"" "$disc" && grep -qxF "published: 2026-01-02" "$disc" && [ ! -s "$TMP/calls" ]'

run "https://forum.example.com/t/other-slug/77/5?u=kim"
check "same Discourse topic, other post / referral -> duplicate" eval 'has "이미 클립됨" && has "$disc"'
run "https://forum.example.com/t/raw-down/66"
check "/raw network error -> [WARN] with host + curl exit, no curl text, no -w trailer URL" \
    eval 'has "[WARN] Discourse /raw 실패 (network error forum.example.com: curl exit 28)" && ! has "Operation timed out" && ! has "TOKRAW" && ! has "idp.example.net"'
run "https://forum.example.com/t/raw-tok/64"
check "/raw curl error line carrying a token-bearing URL -> [WARN], curl text never printed" \
    eval 'has "[WARN] Discourse /raw 실패 (network error forum.example.com: curl exit 7)" && ! has "Failed to connect" && ! has "idp.example.net" && ! has "TOKCURL" && ! has "TOKTRL64"'
run "https://forum.example.com/t/raw-bare/65"
check "Discourse /raw failure with only the -w trailer on stderr -> [WARN], trailer URL never printed" \
    eval 'has "[WARN] Discourse /raw 실패" && has "curl exit 28" && ! has "TOKTRL"'

# 9. login walls: Discourse's own is a stop; another site's walled /t/<id>.json
# is not (its page is probed instead, see 9b)
n="$(notes)"
run "https://walled.example.com/t/slug/88"
check "login-walled Discourse -> [FAIL] 로그인 필요 (host only), nothing written" \
    eval 'has "로그인 필요 (walled.example.com)" && ! has "/login" && ! has "TOK88" && [ "$(notes)" = "$n" ]'
check "Discourse's own wall -> no OBSIDIAN_CLIP_NO_PROBE hint (the opt-out cannot bypass it)" \
    eval '! has "OBSIDIAN_CLIP_NO_PROBE"'
OBSIDIAN_CLIP_NO_PROBE=1 run "https://walled.example.com/t/slug/88"
rc=$?
check "OBSIDIAN_CLIP_NO_PROBE=1 -> Discourse's own wall still stops, nothing written" \
    eval '[ $rc = 1 ] && has "로그인 필요" && [ "$(notes)" = "$n" ]'
: >"$TMP/calls"
run "https://plain.example.com/t/slug/99"
check "non-Discourse /t/ URL behind /auth -> falls back to markitdown" \
    eval '! has "로그인 필요" && grep -q "plain.example.com/t/slug/99" "$TMP/calls"'

# 9b. login walls on any article URL: the curl probe refuses before markitdown
n="$(notes)"
: >"$TMP/calls"
run "https://private.example.com/private"
rc=$?
check "non-topic URL redirected to /login -> [FAIL] 로그인 필요, nothing written, no markitdown" \
    eval '[ $rc = 1 ] && has "[FAIL] 로그인 필요 (private.example.com)" && ! has "/login" && [ "$(notes)" = "$n" ] && [ ! -s "$TMP/calls" ]'
check "probe wall -> Next: line names the OBSIDIAN_CLIP_NO_PROBE=1 opt-out" has "Next: 공개 페이지인데"
: >"$TMP/curlcalls"
OBSIDIAN_CLIP_NO_PROBE=1 run "https://private.example.com/private"
rc=$?
check "OBSIDIAN_CLIP_NO_PROBE=1 -> same /login redirect skips the probe (curl not called), clipped by markitdown" \
    eval '[ $rc = 0 ] && ! has "로그인 필요" && [ ! -s "$TMP/curlcalls" ] && grep -q "private.example.com/private" "$TMP/calls" && [ -s "$VAULT/99-Inbox/$TODAY Private Page.md" ]'
n="$(notes)"
: >"$TMP/calls"
run "https://sso.example.com/page"
rc=$?
check "SSO hop via /session/sso to a third-party IdP -> [FAIL] 로그인 필요, nothing written" \
    eval '[ $rc = 1 ] && has "로그인 필요 (idp.example.net)" && ! has "/oauth2" && [ "$(notes)" = "$n" ] && [ ! -s "$TMP/calls" ]'
check "SSO IdP path/query/fragment (state=, SAMLRequest=) never reach the output" \
    eval '! has "TOK" && ! has "authorize" && ! has "state=" && ! has "SAMLRequest=" && ! has "#frag" && ! has "jsessionid"'
run "https://blog.example.com/auth/intro"
check "user-requested /auth/intro (no redirect) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$VAULT/99-Inbox/$TODAY Auth Intro.md" ]'
run "https://netfail.example.com/a"
check "probe network error -> falls through to markitdown, clipped" \
    eval '! has "로그인 필요" && [ -s "$VAULT/99-Inbox/$TODAY Probe Down.md" ]'
run "https://redir.example.com/guide/auth"
check "redirect that keeps the asked /auth path (trailing slash) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$VAULT/99-Inbox/$TODAY Guide Auth.md" ]'
run "https://docs.example.com/guide/sign-in"
check "user-requested page on a sign-in path (no redirect) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$VAULT/99-Inbox/$TODAY Sign-in Guide.md" ]'
check "probe asks for a 1-byte range only" grep -qF -- "-r 0-0" "$TMP/curlargs"
run "https://forum.example.com/c/general"
check "public Discourse non-topic page (login_required preloaded) -> still clipped" \
    eval '! has "로그인 필요" && [ -s "$VAULT/99-Inbox/$TODAY Forum Category.md" ]'

# 10. markitdown that hangs -> timeout [FAIL], nothing written
n="$(notes)"
printf '#!/bin/sh\nsleep 5\n' >"$TMP/slowbin-markitdown"
mkdir -p "$TMP/slowbin" && mv "$TMP/slowbin-markitdown" "$TMP/slowbin/markitdown" && chmod +x "$TMP/slowbin/markitdown"
RP="$TMP/slowbin:$BASE" OBSIDIAN_CLIP_TIMEOUT=1 run https://slow.example.com/x
check "markitdown timeout -> [FAIL], nothing written" eval 'has "markitdown timeout 1s" && [ "$(notes)" = "$n" ]'

# 12. agent-reach + yt-dlp -> the yt-dlp path; failures fall back to markitdown
ARYT="$AR:$YT:$BASE"
: >"$TMP/calls"
: >"$TMP/ytcalls"
: >"$TMP/arcalls"
RP="$ARYT" run "https://youtu.be/ytOKvid0001?si=x"
rc=$?
ok1="$VAULT/99-Inbox/$TODAY YT Full ytOKvid0001.md"
check "yt-dlp path -> [OK] yt-dlp 경로, note written, /ingest last, no TIP, markitdown not called" \
    eval '[ $rc = 0 ] && has "[OK] yt-dlp 경로 (agent-reach)" && has "[OK] $ok1" && tail -n1 "$TMP/out" | grep -qxF "/ingest $ok1" && ! has "[TIP]" && [ ! -s "$TMP/calls" ]'
check "yt-dlp path -> canonical watch URL, no cookies, no --no-check-certificate, agent-reach never run" \
    eval 'grep -qF -- "--dump-json --skip-download -- https://www.youtube.com/watch?v=ytOKvid0001" "$TMP/ytcalls" && ! grep -q "cookies\|no-check-certificate" "$TMP/ytcalls" && [ ! -s "$TMP/arcalls" ]'
check "yt-dlp note: author / published filled, tag youtube, source verbatim" \
    eval 'grep -qxF "  - \"Chan Name\"" "$ok1" && grep -qxF "published: 2026-03-15" "$ok1" && grep -qxF "  - \"youtube\"" "$ok1" && grep -qxF "source: \"https://youtu.be/ytOKvid0001?si=x\"" "$ok1"'
check "yt-dlp note: metadata, full description, chapters, manual ko transcript first" \
    eval 'grep -qxF "# YT Full ytOKvid0001" "$ok1" && grep -qxF -- "- Duration: 1:02:05" "$ok1" && grep -qxF -- "- Views: 1,234,567" "$ok1" && grep -qxF "no truncation here" "$ok1" && grep -qxF -- "- 1:05 Main" "$ok1" && grep -qxF "## Transcript (ko, manual)" "$ok1" && grep -qxF "ko line one" "$ok1" && grep -qxF "ko line two" "$ok1" && ! grep -q "english auto\|-->" "$ok1"'
check "yt-dlp path -> no truncated-description [WARN] (dots inside the full text)" eval '! has "[WARN]"'

: >"$TMP/ytcalls"
run "https://www.youtube.com/watch?v=ytOKvid0001"
check "clipped via yt-dlp, again via markitdown -> duplicate" eval 'has "이미 클립됨" && has "$ok1"'
RP="$ARYT" run "https://youtu.be/nGKKWne_O2s"
check "clipped via markitdown, again via yt-dlp -> duplicate before yt-dlp runs" \
    eval 'has "이미 클립됨" && has "$yt" && [ ! -s "$TMP/ytcalls" ]'

RP="$ARYT" run "https://www.youtube.com/watch?v=ytAUTOsub01"
auto="$VAULT/99-Inbox/$TODAY YT Full ytAUTOsub01.md"
check "auto captions only -> (en, auto), rolling duplicate lines collapsed, tags stripped" \
    eval 'grep -qxF "## Transcript (en, auto)" "$auto" && [ "$(grep -cxF "roll one two" "$auto")" = 1 ] && grep -qxF "roll three" "$auto" && ! grep -q "<c>" "$auto"'

for id in ytNOSUBS001 ytSUBFAIL01; do
    RP="$ARYT" run "https://www.youtube.com/watch?v=$id"
    rc=$?
    f="$VAULT/99-Inbox/$TODAY YT Full $id.md"
    check "no subtitles ($id) -> [WARN] 자막 없음, note without Transcript, no stderr" \
        eval '[ $rc = 0 ] && has "[WARN] 자막 없음 -- Transcript 섹션 생략" && has "[OK] yt-dlp 경로" && [ -s "$f" ] && ! grep -q "## Transcript" "$f" && ! has "TOKSUB"'
done

: >"$TMP/calls"
RP="$ARYT" run "https://www.youtube.com/watch?v=ytFAIL00001"
rc=$?
check "yt-dlp exit 1 -> [WARN] 폴백 (exit code + host), markitdown note, stderr never printed" \
    eval '[ $rc = 0 ] && has "[WARN] yt-dlp 실패 (yt-dlp exit 1 (www.youtube.com)) -- markitdown 경로로 폴백" && grep -qF "watch?v=ytFAIL00001 -o " "$TMP/calls" && [ -s "$VAULT/99-Inbox/$TODAY MD ytFAIL00001.md" ] && ! has "TOKSTDERR" && ! has "Sign in" && ! has "[OK] yt-dlp"'
check "markitdown fallback keeps the truncated-description [WARN]" has "[WARN] YouTube Description"
RP="$ARYT" OBSIDIAN_CLIP_TIMEOUT=1 run "https://www.youtube.com/watch?v=ytSLOW00001"
check "yt-dlp timeout -> [WARN] 폴백 (timeout 1s), markitdown note" \
    eval 'has "[WARN] yt-dlp 실패 (timeout 1s) -- markitdown 경로로 폴백" && [ -s "$VAULT/99-Inbox/$TODAY MD ytSLOW00001.md" ]'
RP="$ARYT" run "https://www.youtube.com/watch?v=ytBADJSON01"
check "yt-dlp bad JSON -> [WARN] 폴백 (JSONDecodeError)" \
    eval 'has "[WARN] yt-dlp 실패 (JSONDecodeError) -- markitdown 경로로 폴백" && [ -s "$VAULT/99-Inbox/$TODAY MD ytBADJSON01.md" ]'
RP="$ARYT" run "https://www.youtube.com/watch?v=ytNOTITLE01"
check "yt-dlp metadata without a title -> [WARN] 폴백 (title 없음)" \
    eval 'has "[WARN] yt-dlp 실패 (title 없음) -- markitdown 경로로 폴백" && [ -s "$VAULT/99-Inbox/$TODAY MD ytNOTITLE01.md" ]'

: >"$TMP/calls"
RP="$AR:$BASE" run "https://www.youtube.com/watch?v=ytNOYTDLP01"
check "agent-reach without yt-dlp -> [WARN] + Next: agent-reach doctor, markitdown note, no TIP" \
    eval 'has "[WARN] agent-reach 는 있으나 yt-dlp 미설치 -- markitdown 경로" && has "Next: agent-reach doctor" && ! has "[TIP]" && [ -s "$VAULT/99-Inbox/$TODAY MD ytNOYTDLP01.md" ]'
: >"$TMP/ytcalls"
mkdir -p "$TMP/docs2"
: >"$TMP/docs2/ar-doc.pdf"
RP="$ARYT" run "$TMP/docs2/ar-doc.pdf"
check "agent-reach + non-YouTube input -> no TIP, markitdown, yt-dlp not called" \
    eval '! has "[TIP]" && [ -s "$VAULT/99-Inbox/$TODAY ar-doc.md" ] && [ ! -s "$TMP/ytcalls" ]'

# 13. the vault is fixed: cwd, OBSIDIAN_VAULT_DIR and internal setup mode never move it
mkdir -p "$TMP/elsewhere"
: >"$TMP/elsewhere/cwd-doc.pdf"
printf 'internal\n' >"$TMP/home/.dotfiles-setup-mode"
mkdir -p "$TMP/home/para/project/obsidian-para-company"
(cd "$TMP/elsewhere" && OBSIDIAN_VAULT_DIR="$TMP/elsewhere" run "cwd-doc.pdf")
rc=$?
check "other cwd + OBSIDIAN_VAULT_DIR + internal mode -> fixed vault 99-Inbox, absolute [OK] path" \
    eval '[ $rc = 0 ] && has "[OK] $VAULT/99-Inbox/$TODAY cwd-doc.md" && [ ! -e "$TMP/elsewhere/99-Inbox" ] && [ -z "$(ls -A "$TMP/home/para/project/obsidian-para-company")" ]'

# 14. --vault is refused, not ignored; the old two-argument form is a usage error
n="$(notes)"
for a in "--vault $TMP/other" "--vault=$TMP/other"; do
    # shellcheck disable=SC2086  # word-splitting $a into flag + value is the point
    run "https://example.com/vault-flag" $a
    rc=$?
    check "$a -> [FAIL] 지원하지 않는다 (fixed path named), exit 2, nothing written" \
        eval '[ $rc = 2 ] && has "[FAIL] --vault 는 지원하지 않는다 (저장 위치 고정: ~/para/project/obsidian-para/99-Inbox)" && [ "$(notes)" = "$n" ] && [ ! -e "$TMP/other" ]'
done
run "https://example.com/two-args" "$VAULT"
rc=$?
check "old <input> <vault> form -> usage [FAIL], exit 2, nothing written" \
    eval '[ $rc = 2 ] && has "[FAIL] usage: clip.py <input>" && [ "$(notes)" = "$n" ]'

# 15. help writes nothing, calls nothing
for h in -h --help help; do
    run "$h"
    check "$h prints help" eval 'has "## Arguments"'
done

[ "$failures" -eq 0 ] || exit 1
