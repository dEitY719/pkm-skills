#!/usr/bin/env bash
# skills/obsidian-resolve-conflict/lib/verify-sync.sh
#
# F-9 verification report for the target vault and its peer clone, in the
# self-check spirit of obsidian-session-clip/lib/verify-clip.sh: the design
# constraints of a conflict resolution are exactly the kind of thing that
# breaks silently, so they get an executable check shipped with the skill.
#
# Read-only. It never stages, commits, fetches or pushes anything — the peer
# fast-forward (F-7) is the caller's decision and the caller's command.
#
# Checks
#   1. the target is a git repository and no unmerged path is left
#   2. obsidian-git's artifact is gone
#   3. ahead/behind against the upstream is reported for target and peer
#   4. every --resolved path is actually excluded now, or a .gitignore line
#      is *suggested* (F-9 suggests; it never edits .gitignore)
#   5. a nested 90-personal/ clone is reported, never resolved (F-8)
#
# Usage:
#   verify-sync.sh <vault-dir> [--peer <path>] [--resolved <path>]...

set -uo pipefail

ARTIFACT="conflict-files-obsidian-git.md"
NESTED_DIR="90-personal"
FAILURES=0

usage() {
    cat <<'EOF'
verify-sync.sh — F-9 post-resolution report for a vault and its peer

Usage:
  verify-sync.sh <vault-dir> [--peer <path>] [--resolved <path>]...
  verify-sync.sh -h | --help | help

  <vault-dir>        the vault that was resolved
  --peer <path>      peer clone to report on (read-only)
  --resolved <path>  a path class A resolved; repeatable. Each one that is
                     not excluded by .gitignore yet produces a SUGGEST line.

Prints PASS/FAIL lines, `git status --short --branch` and ahead/behind for
both clones, then VERDICT. Exits 0 only when every check passes.
EOF
}

pass() { printf 'PASS: %s\n' "$1"; }
fail() {
    printf 'FAIL: %s\n' "$1"
    FAILURES=$((FAILURES + 1))
}

is_git_repo() {
    [ -n "$1" ] && [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# unmerged_count <dir> — number of distinct still-conflicting paths.
# `git ls-files -u` prints one line per *stage*, so counting its lines would
# report 2-3 per path; the paths are de-duplicated here instead.
unmerged_count() {
    git -C "$1" ls-files -u 2>/dev/null | cut -f2- | sort -u | grep -c . || true
}

# report_clone <label> <path> — status + ahead/behind, read-only
report_clone() {
    local label="$1" dir="$2" upstream counts
    printf '\n[%s] %s\n' "$label" "$dir"
    git -C "$dir" status --short --branch
    upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || printf '%s' "")"
    if [ -z "$upstream" ]; then
        printf 'AHEAD/BEHIND: upstream 없음\n'
        return 0
    fi
    counts="$(git -C "$dir" rev-list --left-right --count "HEAD...${upstream}" 2>/dev/null || printf '%s' "")"
    if [ -z "$counts" ]; then
        printf 'AHEAD/BEHIND: 계산 불가 (원격 ref 없음: %s)\n' "$upstream"
        return 0
    fi
    printf 'AHEAD/BEHIND vs %s: ahead=%s behind=%s\n' \
        "$upstream" "$(printf '%s' "$counts" | cut -f1)" "$(printf '%s' "$counts" | cut -f2)"
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    if [ "$#" -lt 1 ]; then
        usage >&2
        return 1
    fi

    local vault peer resolved=()
    vault="${1%/}"
    shift
    peer=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --peer)
                [ "$#" -ge 2 ] || {
                    printf 'ERROR: --peer 는 경로가 필요하다\n' >&2
                    return 1
                }
                peer="${2%/}"
                shift
                ;;
            --resolved)
                [ "$#" -ge 2 ] || {
                    printf 'ERROR: --resolved 는 경로가 필요하다\n' >&2
                    return 1
                }
                resolved+=("$2")
                shift
                ;;
            *)
                printf "ERROR: 알 수 없는 인자 '%s'\n" "$1" >&2
                usage >&2
                return 1
                ;;
        esac
        shift
    done

    if ! is_git_repo "$vault"; then
        fail "대상이 git 저장소가 아니다: ${vault}"
        printf '\nVERDICT: FAIL (%d)\n' "$FAILURES"
        return 1
    fi

    # --- 1. no unmerged path left -----------------------------------------
    local left
    left="$(unmerged_count "$vault")"
    if [ "$left" = "0" ]; then
        pass "미해결 충돌 경로 없음"
    else
        fail "아직 충돌 중인 경로가 있다 (${left}개)"
    fi

    # --- 2. obsidian-git artifact gone ------------------------------------
    if [ -e "${vault}/${ARTIFACT}" ]; then
        fail "obsidian-git 아티팩트가 남아 있다: ${ARTIFACT}"
    else
        pass "obsidian-git 아티팩트 없음: ${ARTIFACT}"
    fi

    # --- 3. status + ahead/behind -----------------------------------------
    report_clone "TARGET" "$vault"
    if [ -n "$peer" ]; then
        if is_git_repo "$peer"; then
            report_clone "PEER" "$peer"
        else
            printf '\n[PEER] %s — git 저장소가 아니다, 건너뛴다\n' "$peer"
        fi
    else
        printf '\n[PEER] 없음 — peer 동기화 대상 없음\n'
    fi

    # --- 4. .gitignore suggestions (suggest only, never edit) -------------
    local path
    printf '\n'
    for path in ${resolved[@]+"${resolved[@]}"}; do
        [ "$path" = "$ARTIFACT" ] && continue
        if git -C "$vault" check-ignore --no-index -q -- "$path"; then
            pass ".gitignore 가 이미 제외 중: ${path}"
        else
            printf 'SUGGEST: .gitignore 에 다음 줄 추가를 권장한다 (직접 수정하지 않았다): %s\n' "$path"
        fi
    done

    # --- 5. nested clone report (F-8) -------------------------------------
    if [ -e "${vault}/${NESTED_DIR}/.git" ]; then
        printf '\n[NESTED] %s/%s (별도 clone — obsidian-git 이 보지 못한다)\n' "$vault" "$NESTED_DIR"
        git -C "${vault}/${NESTED_DIR}" status --short --branch
        if [ "$(unmerged_count "${vault}/${NESTED_DIR}")" != "0" ]; then
            printf 'NESTED-ACTION: --vault %s/%s 로 이 스킬을 다시 실행하라 (F-8)\n' "$vault" "$NESTED_DIR"
        fi
    fi

    printf '\n'
    if [ "$FAILURES" -eq 0 ]; then
        printf 'VERDICT: PASS\n'
        return 0
    fi
    printf 'VERDICT: FAIL (%d)\n' "$FAILURES"
    return 1
}

main "$@"
