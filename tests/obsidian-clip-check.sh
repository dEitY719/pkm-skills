#!/usr/bin/env bash
# tests/obsidian-clip-check.sh
#
# Offline check for pkm:obsidian-clip: runs its stub selfcheck
# (classification, normalization, filename, duplicate, missing markitdown,
# Discourse via a fake curl, the yt-dlp path via fake agent-reach / yt-dlp,
# the fixed vault from another cwd -- no network, temp HOME only) and asserts
# the vault stays fixed: one ~-relative constant in clip.py, no vault
# resolver, no --vault / OBSIDIAN_VAULT_DIR left in the skill.
#
# Usage:
#   bash tests/obsidian-clip-check.sh
# Exits 0 when every assertion passes, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/obsidian-clip"
failures=0

check() { # <label> <test command...>
    local label="$1"
    shift
    if "$@"; then
        printf '[OK]   %s\n' "$label"
    else
        printf '[FAIL] %s\n' "$label"
        failures=$((failures + 1))
    fi
}

bash "$SKILL/lib/clip.selfcheck.sh" || failures=$((failures + 1))

check "clip.py fixes the vault to ~/para/project/obsidian-para via expanduser" \
    grep -qF 'os.path.expanduser("~/para/project/obsidian-para")' "$SKILL/lib/clip.py"
check "clip.py hardcodes no home directory" \
    eval '! grep -q "/home/\|/Users/" "$SKILL/lib/clip.py"'
check "no vault resolver left in obsidian-clip (lib/vendor/resolve-vault.sh removed)" \
    eval '[ ! -e "$SKILL/lib/vendor/resolve-vault.sh" ] && ! grep -rq "resolve-vault" "$SKILL/SKILL.md" "$SKILL/references" "$SKILL/lib/clip.py"'
check "clip.py reads no OBSIDIAN_VAULT_DIR / setup mode" \
    eval '! grep -rq "OBSIDIAN_VAULT_DIR\|dotfiles-setup-mode" "$SKILL/lib/clip.py"'

[ "$failures" -eq 0 ] || exit 1
