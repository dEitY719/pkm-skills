#!/usr/bin/env bash
# tests/obsidian-web-clip-check.sh
#
# Offline check for pkm:obsidian-web-clip: the pure helpers in lib/web-clip.py
# (filename sanitising, upload:// mapping, |WxH stripping, Discourse topic-id
# parsing, HTML -> markdown, frontmatter), the refuse-to-overwrite guard, and
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

check "vendored resolve-vault.sh matches obsidian-session-clip/lib" \
    cmp "$REPO_ROOT/skills/obsidian-session-clip/lib/resolve-vault.sh" \
    "$SKILL/lib/vendor/resolve-vault.sh"

[ "$failures" -eq 0 ] || exit 1
