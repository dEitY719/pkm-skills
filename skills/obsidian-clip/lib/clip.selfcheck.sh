#!/usr/bin/env bash
# skills/obsidian-clip/lib/clip.selfcheck.sh
#
# Offline check for lib/clip.py with a stub `markitdown` (and a stub `curl`
# for the Discourse path) on PATH: input classification, source
# normalization, filename, duplicate refusal, the missing-markitdown stop,
# empty / failed conversion, and the never-overwrite collision. Every run
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
*youtube.com*|*youtu.be*)
    printf '# YouTube\n\n## Video: A/B "test"\n\n### Description\nfirst line ...\n\n### Transcript\nhello\n' >"\$out" ;;
*) printf 'nav\n\n# Page Title\n\nbody of %s\n' "\$in" >"\$out" ;;
esac
SH
chmod +x "$TMP/bin/markitdown"
# Stub curl: every URL answers 200 with an empty body unless it is the fake
# Discourse topic, which answers the topic JSON and its /raw markdown.
cat >"$TMP/bin/curl" <<'SH'
#!/bin/sh
for a; do url=$a; done
case "$url" in
*/t/77.json) printf '{"title":"Disc Topic","post_stream":{"posts":[{"username":"kim","created_at":"2026-01-02T00:00:00Z","cooked":"<img src=\\"https://cdn/x.png\\" data-base62-sha1=\\"AbC\\">"}]}}' ;;
*/raw/77/1) printf 'raw body ![i|10x20](upload://AbC.png)\n' ;;
*) : ;;
esac
printf '\n%s 200' "$url" >&2
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
run "https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB" "$TMP/vault"
yt="$TMP/vault/99-Inbox/$TODAY Video AB test.md"
check "YouTube shorts -> markitdown gets the canonical watch URL" \
    grep -qF "https://www.youtube.com/watch?v=nGKKWne_O2s -o " "$TMP/calls"
check "YouTube -> 99-Inbox/ root, title from ## heading, forbidden chars removed" \
    eval '[ -s "$yt" ] && has "[OK] $yt" && tail -n1 "$TMP/out" | grep -qxF "/ingest $yt"'
check "YouTube note: Web Clipper frontmatter, tag youtube, source verbatim, body kept" \
    eval 'grep -qxF "  - \"youtube\"" "$yt" && grep -qxF "status: \"unread\"" "$yt" && grep -qxF "source: \"https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB\"" "$yt" && grep -q "^### Transcript" "$yt" && grep -q "^## 메모" "$yt"'
check "truncated Description -> [WARN]" eval 'has "[WARN] YouTube Description"'

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
for ext in pdf docx xlsx; do
    : >"$TMP/docs/report-$ext.$ext"
    (cd "$TMP/docs" && PATH="$TMP/bin:$PATH" python3 "$PY" "report-$ext.$ext" "$TMP/vault") >"$TMP/out" 2>&1
    d="$TMP/vault/99-Inbox/$TODAY report-$ext.md"
    check "local .$ext -> document note, absolute source" \
        eval '[ -s "$d" ] && grep -qxF "  - \"document\"" "$d" && grep -qxF "source: \"$TMP/docs/report-$ext.$ext\"" "$d"'
done
run "$TMP/docs/report-pdf.pdf" "$TMP/vault"
check "same local file again -> duplicate" eval 'has "이미 클립됨"'

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

# 9. help writes nothing, calls nothing
for h in -h --help help; do
    run "$h"
    check "$h prints help" eval 'has "## Arguments"'
done

[ "$failures" -eq 0 ] || exit 1
