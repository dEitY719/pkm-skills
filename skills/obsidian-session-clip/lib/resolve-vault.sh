#!/usr/bin/env bash
# skills/obsidian-session-clip/lib/resolve-vault.sh
#
# F-1 vault default resolution for the pkm:obsidian-session-clip skill.
#
# The hardcoded single default ($HOME/para/project/obsidian-para) ignores
# the PC-mode SSOT (dEitY719/dotfiles docs/.ssot/pc-environment.md): internal
# PCs keep a separate company vault at obsidian-para-company, so with no
# --vault and no OBSIDIAN_VAULT_DIR, an internal-mode PC always stopped at vault-missing
# (dEitY719/dotfiles#1351). This script only widens the *default candidate* —
# existence checking stays SKILL.md Step 1's job.
#
# Usage:
#   resolve-vault.sh [explicit-vault-path]
#   resolve-vault.sh -h | --help | help

set -euo pipefail

usage() {
    cat <<'EOF'
resolve-vault.sh — PC-mode-aware vault default for pkm:obsidian-session-clip

Usage:
  resolve-vault.sh [explicit-vault-path]
      Print the resolved vault path on stdout, by priority:
        1. <explicit-vault-path>, if non-empty (e.g. --vault from the caller)
        2. $OBSIDIAN_VAULT_DIR, if non-empty
        3. $HOME/.dotfiles-setup-mode, read and trimmed:
             internal | 2  -> $HOME/para/project/obsidian-para-company
             (anything else, incl. missing/unreadable file) ->
                               $HOME/para/project/obsidian-para
      Always exits 0. Does not check whether the resolved path exists.

  resolve-vault.sh -h | --help | help
      Print this text.
EOF
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    # Both overrides mean the same thing — "a caller already decided" — so one
    # `:-` chain expresses the first-non-empty-wins precedence directly.
    vault="${1:-${OBSIDIAN_VAULT_DIR:-}}"

    if [ -z "$vault" ]; then
        # Same normalisation as setup_mode() in the sibling
        # obsidian-resolve-conflict lib and _dotfiles_setup_mode()
        # (dEitY719/dotfiles shell-common/tools/integrations/claude.sh): one
        # `tr`, and the legacy numeric mode values written by
        # pre-dEitY719/dotfiles#571 setup.sh treated as aliases
        # of their names. The `[ -f ]` guard is load-bearing — on a missing
        # file the *shell* reports the failed redirect before `tr` ever runs,
        # so an inner `2>/dev/null` would not suppress it.
        mode=""
        if [ -f "$HOME/.dotfiles-setup-mode" ]; then
            mode="$(tr -d ' \t\n\r' <"$HOME/.dotfiles-setup-mode" 2>/dev/null || true)"
        fi
        case "$mode" in
            2 | internal) vault="$HOME/para/project/obsidian-para-company" ;;
            *) vault="$HOME/para/project/obsidian-para" ;;
        esac
    fi

    printf '%s\n' "$vault"
}

main "$@"
