#!/usr/bin/env bash
# tests/obsidian-web-clip-check.sh
#
# Offline check for pkm:obsidian-web-clip: the pure helpers in lib/web-clip.py
# (filename sanitising, upload:// mapping, |WxH stripping, Discourse topic-id
# parsing, HTML -> markdown, frontmatter), the refuse-to-overwrite guard, the
# login-wall stop (fake curl), and
# the vendored resolve-vault.sh staying byte-identical to its SSOT. The
# network paths are out of scope -- they need a live Discourse.
#
# Usage:
#   bash tests/obsidian-web-clip-check.sh
# Exits 0 when every assertion passes, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/obsidian-web-clip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

check() { # <label> <command...>
    local label="$1"
    shift
    if "$@" >"$TMP/out" 2>&1; then
        printf '[OK]   %s\n' "$label"
    else
        printf '[FAIL] %s\n' "$label"
        sed 's/^/       /' "$TMP/out"
        failures=$((failures + 1))
    fi
}

check "web-clip.py --self-test" python3 "$SKILL/lib/web-clip.py" --self-test

# An already-clipped source must stop before any fetch (no network needed).
mkdir -p "$TMP/vault/99-Inbox/Web"
# The padding pushes `source:` past 4 KB -- a prefix-only scan would miss it.
{
    printf -- '---\ntitle: "x"\ndescription: "%s"\n' "$(printf '%5000s' '' | tr ' ' a)"
    printf 'source: "https://example.invalid/t/x/1"\n---\n'
} >"$TMP/vault/99-Inbox/Web/old.md"
dup_refused() {
    # Match the refusal itself: a network failure also exits non-zero.
    { python3 "$SKILL/lib/web-clip.py" https://example.invalid/t/x/1 "$TMP/vault" || :; } |
        grep -q '이미 클립됨' &&
        [ "$(find "$TMP/vault" -name '*.md' | wc -l)" -eq 1 ]
}
check "duplicate source refused, nothing written" dup_refused

missing_vault_refused() {
    ! python3 "$SKILL/lib/web-clip.py" https://example.invalid/ "$TMP/no-such-vault" &&
        [ ! -e "$TMP/no-such-vault" ]
}
check "missing vault refused, never created" missing_vault_refused

# A login-walled Discourse redirects /t/<id>.json to its HTML login page; a
# fake curl stands in for it. The clip must stop with the auth message.
mkdir -p "$TMP/bin" "$TMP/vault2"
cat >"$TMP/bin/curl" <<'SH'
#!/bin/sh
printf '<html><meta name="generator" content="Discourse 3.2"><body class="login-required">Log in</body></html>'
printf '\nhttps://example.invalid/login 200' >&2
SH
chmod +x "$TMP/bin/curl"
login_wall_refused() { # <url>
    { PATH="$TMP/bin:$PATH" python3 "$SKILL/lib/web-clip.py" "$1" "$TMP/vault2" || :; } |
        grep -q '로그인 필요' &&
        [ -z "$(find "$TMP/vault2" -type f)" ]
}
check "Discourse login wall refused, nothing written" login_wall_refused https://example.invalid/t/x/1
check "login wall on a non-topic URL refused too" login_wall_refused https://example.invalid/private

# SSO: the chain hops through /session/sso and ends on a third-party IdP page
# with no Discourse marker -- only the -D header dump's Location:s reveal it.
cat >"$TMP/bin/curl" <<'SH'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = -D ] && hdr=$2; shift; done
printf '<html><title>Sign in</title><form>password</form></html>'
{
    printf 'HTTP/1.1 302 Found\r\nLocation: /session/sso?return_path=%%2Fprivate\r\n\r\n'
    printf 'HTTP/1.1 302 Found\r\nLocation: https://idp.invalid/oauth2/v1/authorize?c=1\r\n\r\n'
    printf 'HTTP/1.1 200 OK\r\n\r\n'
} >"$hdr"
printf '\nhttps://idp.invalid/oauth2/v1/authorize?c=1 200' >&2
SH
check "SSO hop to a third-party IdP refused, nothing written" login_wall_refused https://example.invalid/private

check "vendored resolve-vault.sh matches obsidian-session-clip/lib" \
    cmp "$REPO_ROOT/skills/obsidian-session-clip/lib/resolve-vault.sh" \
    "$SKILL/lib/vendor/resolve-vault.sh"

[ "$failures" -eq 0 ] || exit 1
