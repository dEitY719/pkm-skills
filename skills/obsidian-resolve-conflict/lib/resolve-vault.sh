#!/usr/bin/env bash
# skills/obsidian-resolve-conflict/lib/resolve-vault.sh
#
# F-2 runtime resolution of an Obsidian vault clone (+ its peer clone) plus
# the NF-7 push guard, emitted as shell-quoted KEY=value lines.
#
# Why runtime detection instead of a path table (NF-8):
#   docs/.ssot/pc-environment.md §1 — every PC pairs a Windows account with a
#   WSL account and the two usernames differ per PC. `/mnt/c/Users/$USER/...`
#   is therefore wrong on every machine. The Windows side is found with a
#   glob over /mnt/c/Users/*/Documents/<vault folder>, the WSL side by testing
#   which of the two known clone directories actually exists.
#
# ~/.dotfiles-setup-mode only *orders* the candidates. The final decision is
# always made from what exists on disk and from `git remote get-url origin`
# — a mode table can go stale, the filesystem cannot.
#
# Every failure is loud: a message on stderr plus a non-zero exit. This script
# never creates a directory to make a path resolve (NF-4).
#
# Usage:
#   resolve-vault.sh [windows|wsl] [--vault <path>] [--mode <mode>]
#   eval "$(resolve-vault.sh windows)"

set -uo pipefail

WIN_ROOT="${OBSIDIAN_VAULT_WIN_ROOT:-/mnt/c/Users}"
WIN_NAME="${OBSIDIAN_VAULT_WIN_NAME:-ObsidianVault-PARA}"
WIN_SUBDIR="Documents"
WSL_ROOT="${OBSIDIAN_VAULT_WSL_ROOT:-${HOME}/para/project}"
WSL_COMPANY="obsidian-para-company"
WSL_PERSONAL="obsidian-para"
# The vault's git remote. A vault clone always has exactly one, named origin —
# emitted as REMOTE so merge-flow.md can name it instead of hardcoding it.
REMOTE_NAME="origin"
# NF-7: the one host `internal` PCs may never push to (SSOT: §3 of
# docs/.ssot/pc-environment.md — "GitHub (common) = pull only").
PUBLIC_HOST="github.com"

usage() {
    cat <<'EOF'
resolve-vault.sh — runtime vault/peer resolution + NF-7 push guard

Usage:
  resolve-vault.sh [windows|wsl] [--vault <path>] [--mode <mode>]
  resolve-vault.sh -h | --help | help

  [windows|wsl]     which clone to target (default: windows)
  --vault <path>    explicit vault root; wins over every other source
  --mode <mode>     override ~/.dotfiles-setup-mode (public|internal|external)

Emits shell-quoted KEY=value lines on stdout:
  MODE SIDE VAULT VAULT_ORIGIN REMOTE BRANCH UPSTREAM BACKUP_SHA
  PEER PEER_ORIGIN PEER_MATCH PUSH_ALLOWED PUSH_BLOCK_REASON

Environment:
  OBSIDIAN_VAULT_WIN_DIR    explicit Windows-side clone
  OBSIDIAN_VAULT_DIR        explicit WSL-side clone
  OBSIDIAN_VAULT_WIN_ROOT   glob root for the Windows side (/mnt/c/Users)
  OBSIDIAN_VAULT_WIN_NAME   vault folder name (ObsidianVault-PARA)
  OBSIDIAN_VAULT_WSL_ROOT   parent of the WSL clones ($HOME/para/project)

Exits non-zero when the path cannot be resolved unambiguously. Never
creates a directory.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    return 1
}

# emit KEY VALUE — one single-quoted shell assignment, so the caller can
# `eval` the whole block even when a Windows username contains a space.
emit() {
    local value="${2:-}"
    printf "%s='%s'\n" "$1" "${value//\'/\'\\\'\'}"
}

# setup_mode — same normalisation as _dotfiles_setup_mode()
# (shell-common/tools/integrations/claude.sh). Legacy numeric values written
# by pre-#571 setup.sh are translated; a missing file yields "".
setup_mode() {
    mode_file="${DOTFILES_SETUP_MODE_FILE:-${HOME}/.dotfiles-setup-mode}"
    [ -f "$mode_file" ] || {
        printf '%s' ""
        return 0
    }
    raw=$(tr -d ' \t\n\r' <"$mode_file" 2>/dev/null)
    case "$raw" in
        1 | public) printf '%s' "public" ;;
        2 | internal) printf '%s' "internal" ;;
        3 | external) printf '%s' "external" ;;
        *) printf '%s' "$raw" ;;
    esac
}

# origin_host <url> -> hostname of a git remote URL (scp-like or scheme form)
origin_host() {
    local url rest
    url="$1"
    case "$url" in
        '') printf '%s' "" ;;
        *://*)
            rest="${url#*://}"
            rest="${rest#*@}"
            rest="${rest%%/*}"
            printf '%s' "${rest%%:*}"
            ;;
        *@*:*)
            rest="${url#*@}"
            printf '%s' "${rest%%:*}"
            ;;
        *) printf '%s' "" ;;
    esac
}

origin_of() {
    git -C "$1" remote get-url "$REMOTE_NAME" 2>/dev/null || printf '%s' ""
}

is_git_repo() {
    [ -n "$1" ] && [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# resolve_windows [strict] -> path on stdout
# strict=1 (the target side) reports every failure loudly; strict=0 (the peer
# side) stays silent so a missing peer never fails the run (F-7).
resolve_windows() {
    strict="$1"
    if [ -n "${OBSIDIAN_VAULT_WIN_DIR:-}" ]; then
        printf '%s' "$OBSIDIAN_VAULT_WIN_DIR"
        return 0
    fi

    matches=()
    for candidate in "${WIN_ROOT}"/*/"${WIN_SUBDIR}"/"${WIN_NAME}"; do
        [ -d "$candidate" ] || continue
        matches+=("$candidate")
    done

    if [ "${#matches[@]}" -eq 1 ]; then
        printf '%s' "${matches[0]}"
        return 0
    fi

    if [ "${#matches[@]}" -gt 1 ]; then
        [ "$strict" -eq 1 ] && {
            printf 'ERROR: Windows vault 후보가 %d개다 — 임의로 고르지 않는다. --vault 로 지정하라:\n' "${#matches[@]}" >&2
            printf '  %s\n' "${matches[@]}" >&2
        }
        return 1
    fi

    # 0 matches: ask Windows for its own account name (WSL username differs).
    if command -v cmd.exe >/dev/null 2>&1; then
        win_user="$(cd / && cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d ' \t\r\n')"
        if [ -n "$win_user" ]; then
            candidate="${WIN_ROOT}/${win_user}/${WIN_SUBDIR}/${WIN_NAME}"
            if [ -d "$candidate" ]; then
                printf '%s' "$candidate"
                return 0
            fi
        fi
    fi

    [ "$strict" -eq 1 ] && {
        printf 'ERROR: Windows vault 을 찾지 못했다. 시도한 후보:\n' >&2
        printf '  glob : %s/*/%s/%s\n' "$WIN_ROOT" "$WIN_SUBDIR" "$WIN_NAME" >&2
        printf '  env  : OBSIDIAN_VAULT_WIN_DIR\n' >&2
        printf '  cmd  : cmd.exe /c echo %%USERNAME%%%s\n' "${win_user:+ -> ${win_user}}" >&2
        printf '해결: --vault <path> 로 직접 지정하라 (디렉터리를 새로 만들지 않는다).\n' >&2
    }
    return 1
}

# resolve_wsl <strict> <mode> -> path on stdout
resolve_wsl() {
    strict="$1"
    mode="$2"
    if [ -n "${OBSIDIAN_VAULT_DIR:-}" ]; then
        printf '%s' "$OBSIDIAN_VAULT_DIR"
        return 0
    fi

    company="${WSL_ROOT}/${WSL_COMPANY}"
    personal="${WSL_ROOT}/${WSL_PERSONAL}"
    has_company=0
    has_personal=0
    [ -d "$company" ] && has_company=1
    [ -d "$personal" ] && has_personal=1

    if [ "$has_company" -eq 1 ] && [ "$has_personal" -eq 1 ]; then
        case "$mode" in
            internal)
                printf '%s' "$company"
                return 0
                ;;
            external | public)
                printf '%s' "$personal"
                return 0
                ;;
            *)
                [ "$strict" -eq 1 ] && {
                    printf 'ERROR: WSL 클론이 둘 다 존재하는데 모드를 알 수 없다 (~/.dotfiles-setup-mode 없음/불명):\n' >&2
                    printf '  %s\n  %s\n' "$company" "$personal" >&2
                    printf '해결: --vault <path> 또는 --mode <internal|external|public> 로 지정하라.\n' >&2
                }
                return 1
                ;;
        esac
    fi

    [ "$has_company" -eq 1 ] && {
        printf '%s' "$company"
        return 0
    }
    [ "$has_personal" -eq 1 ] && {
        printf '%s' "$personal"
        return 0
    }

    [ "$strict" -eq 1 ] && {
        printf 'ERROR: WSL vault 을 찾지 못했다. 시도한 후보:\n' >&2
        printf '  %s\n  %s\n' "$company" "$personal" >&2
        printf '  env  : OBSIDIAN_VAULT_DIR\n' >&2
        printf '해결: --vault <path> 로 직접 지정하라 (디렉터리를 새로 만들지 않는다).\n' >&2
    }
    return 1
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    side="windows"
    vault_opt=""
    mode_opt=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            windows | wsl)
                side="$1"
                ;;
            --vault)
                [ "$#" -ge 2 ] || {
                    die "--vault 는 경로 인자가 필요하다"
                    return 1
                }
                vault_opt="$2"
                shift
                ;;
            --mode)
                [ "$#" -ge 2 ] || {
                    die "--mode 는 값이 필요하다"
                    return 1
                }
                mode_opt="$2"
                shift
                ;;
            *)
                die "알 수 없는 인자 '$1'"
                usage >&2
                return 1
                ;;
        esac
        shift
    done

    mode="$mode_opt"
    [ -n "$mode" ] || mode="$(setup_mode)"

    if [ -n "$vault_opt" ]; then
        vault="$vault_opt"
    elif [ "$side" = "windows" ]; then
        vault="$(resolve_windows 1)" || return 1
    else
        vault="$(resolve_wsl 1 "$mode")" || return 1
    fi
    vault="${vault%/}"

    if [ ! -d "$vault" ]; then
        printf 'ERROR: vault 경로가 없다: %s\n' "$vault" >&2
        printf '디렉터리를 새로 만들지 않는다 (NF-4). 경로를 확인하고 --vault <path> 로 다시 실행하라.\n' >&2
        return 1
    fi
    if ! is_git_repo "$vault"; then
        printf 'ERROR: git 저장소가 아니다: %s\n' "$vault" >&2
        return 1
    fi

    origin="$(origin_of "$vault")"
    branch="$(git -C "$vault" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s' "")"
    upstream="$(git -C "$vault" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || printf '%s' "")"
    backup_sha="$(git -C "$vault" rev-parse HEAD 2>/dev/null || printf '%s' "")"

    # --- peer clone (soft: never fatal) -----------------------------------
    peer=""
    if [ "$side" = "windows" ]; then
        peer="$(resolve_wsl 0 "$mode")" || peer=""
    else
        peer="$(resolve_windows 0)" || peer=""
    fi
    peer="${peer%/}"
    peer_origin=""
    peer_match="none"
    if [ -n "$peer" ] && [ "$peer" != "$vault" ] && is_git_repo "$peer"; then
        peer_origin="$(origin_of "$peer")"
        if [ -n "$peer_origin" ] && [ "$peer_origin" = "$origin" ]; then
            peer_match="yes"
        else
            peer_match="no"
        fi
    else
        peer=""
    fi

    # --- NF-7 push guard ---------------------------------------------------
    push_allowed="yes"
    push_reason=""
    host="$(origin_host "$origin")"
    # Hostnames are case-insensitive: git@GitHub.com:... must not slip past the
    # guard. Only the comparison is normalised — VAULT_ORIGIN keeps its casing.
    host_lc="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$origin" ]; then
        push_allowed="no"
        push_reason="origin 원격이 없다 — push 할 대상이 없다"
    elif [ "$mode" = "internal" ] && [ "$host_lc" = "$PUBLIC_HOST" ]; then
        push_allowed="no"
        push_reason="internal 모드 PC 에서 ${PUBLIC_HOST} 원격은 pull only 다 (docs/.ssot/pc-environment.md §3). 커밋까지만 하고 external/public PC 에서 push 하라"
    fi

    emit MODE "$mode"
    emit SIDE "$side"
    emit VAULT "$vault"
    emit VAULT_ORIGIN "$origin"
    emit REMOTE "$REMOTE_NAME"
    emit BRANCH "$branch"
    emit UPSTREAM "$upstream"
    emit BACKUP_SHA "$backup_sha"
    emit PEER "$peer"
    emit PEER_ORIGIN "$peer_origin"
    emit PEER_MATCH "$peer_match"
    emit PUSH_ALLOWED "$push_allowed"
    emit PUSH_BLOCK_REASON "$push_reason"
}

main "$@"
