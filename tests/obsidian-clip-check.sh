#!/usr/bin/env bash
# tests/obsidian-clip-check.sh
#
# Offline check for pkm:obsidian-clip: runs its stub-markitdown selfcheck
# (classification, normalization, filename, duplicate, missing markitdown,
# Discourse via a fake curl -- no network, temp vault only) and asserts the
# vendored resolve-vault.sh stays byte-identical to its SSOT.
#
# Usage:
#   bash tests/obsidian-clip-check.sh
# Exits 0 when every assertion passes, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/obsidian-clip"
failures=0

bash "$SKILL/lib/clip.selfcheck.sh" || failures=$((failures + 1))

if cmp "$REPO_ROOT/skills/obsidian-clip-session/lib/resolve-vault.sh" \
    "$SKILL/lib/vendor/resolve-vault.sh"; then
    printf '[OK]   vendored resolve-vault.sh matches obsidian-clip-session/lib\n'
else
    printf '[FAIL] vendored resolve-vault.sh drifted from obsidian-clip-session/lib\n'
    failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || exit 1
