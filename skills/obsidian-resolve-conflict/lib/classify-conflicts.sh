#!/usr/bin/env bash
# skills/obsidian-resolve-conflict/lib/classify-conflicts.sh
#
# F-4 three-way classification of a vault's conflicting / blocking paths, and
# — only with --apply — the automatic half of the resolution.
#
#   A  local state   obsidian-git's own artifact, plus paths the *current*
#                    .gitignore already declares untracked. Resolved
#                    automatically: the artifact is deleted, an ignored path
#                    is dropped from the index with `git rm --cached` so the
#                    on-disk file survives.
#   B  note body     any other *.md. Never touched (NF-3) — a vault note is
#                    the user's writing and a wrong automatic pick destroys
#                    it silently.
#   C  everything else, including a nested 90-personal/ clone (F-8).
#
# The A/B boundary is deliberately "does .gitignore already exclude it", not
# "does the path start with .obsidian/". An excluded path carries a decision
# the user already made ("this differs per PC, stop tracking it"), which is
# what licenses an automatic resolution. .obsidian/appearance.json is *not*
# excluded — it is synced on purpose — so it stays class C.
#
# Usage:
#   classify-conflicts.sh <vault-dir> [--apply]
# Without --apply nothing is written: classification only (NF-5).

set -uo pipefail

TAB=$'\t'
ARTIFACT="conflict-files-obsidian-git.md"
NESTED_DIR="90-personal"
LOCK_RETRIES=5

usage() {
    cat <<'EOF'
classify-conflicts.sh — F-4 A/B/C classification of vault conflicts

Usage:
  classify-conflicts.sh <vault-dir> [--apply]
  classify-conflicts.sh -h | --help | help

  <vault-dir>   vault root (must be a git repository)
  --apply       additionally resolve the class-A rows. Without it the
                script only reports and touches nothing (NF-5).

Output, one row per path:
  <A|B|C><TAB><action><TAB><path>
    A delete       obsidian-git artifact -> removed
    A rm-cached    .gitignore-excluded, tracked -> `git rm --cached`, file kept
    B manual       note body (*.md) -> the user decides (NF-3)
    C manual       anything else -> the user decides
    C nested-repo  90-personal/ appeared in the conflict list (F-8)
  SUMMARY: A=<n> B=<n> C=<n>

With --apply each resolved row is echoed as:
  APPLIED<TAB><action><TAB><path>
A delete row whose path had already vanished resolves to nothing and is
echoed instead as:
  SKIPPED<TAB>delete<TAB><path><TAB>already absent

Exits non-zero when the vault is not a git repository, when a non-merge
operation is in progress, or when an --apply step fails.
EOF
}

warn() { printf 'WARN: %s\n' "$1" >&2; }
err() { printf 'ERROR: %s\n' "$1" >&2; }

# run_git_index <args...> — a git call that takes .git/index, retried past
# obsidian-git's own contention (NF-6): 5 attempts, sleeping i*i seconds
# between them. The lock is never deleted — obsidian-git may be mid-commit
# and removing it corrupts that commit. Same shape as
# obsidian-session-clip/lib/commit-note.sh.
run_git_index() {
    local i=1 out=""
    while [ "$i" -le "$LOCK_RETRIES" ]; do
        if out=$(git -C "$VAULT" "$@" 2>&1); then
            [ -n "$out" ] && printf '%s\n' "$out" >&2
            return 0
        fi
        if [ "$i" -lt "$LOCK_RETRIES" ]; then
            sleep $((i * i))
        fi
        i=$((i + 1))
    done
    err "git ${1} 를 ${LOCK_RETRIES}회 재시도했지만 실패했다 — obsidian-git 이 .git/index.lock 을 잡고 있을 수 있다"
    [ -n "$out" ] && err "마지막 git 오류: ${out}"
    err "lock 파일을 강제로 지우지 마라. obsidian-git 이 멈춘 뒤 다시 실행하라."
    return 1
}

in_list() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# is_tracked <path> — in the index (a tracked or unmerged path)
is_tracked() {
    git -C "$VAULT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

# is_ignored <path> — matched by the *current* .gitignore. --no-index is
# mandatory: without it git reports a tracked path as "not ignored", and a
# tracked-but-excluded path is exactly the case class A is about.
is_ignored() {
    git -C "$VAULT" check-ignore --no-index -q -- "$1"
}

# preflight — the skill resolves merges only, so any other in-flight
# operation must stop the run rather than be half-finished by it.
preflight() {
    if ! git -C "$VAULT" rev-parse --git-dir >/dev/null 2>&1; then
        err "git 저장소가 아니다: ${VAULT}"
        return 1
    fi
    if git -C "$VAULT" rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
        err "cherry-pick 이 진행 중이다 — 먼저 정리한 뒤 다시 실행하라 (git status)"
        return 1
    fi
    if git -C "$VAULT" rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1; then
        err "revert 가 진행 중이다 — 먼저 정리한 뒤 다시 실행하라 (git status)"
        return 1
    fi
    return 0
}

# collect_paths — conflicting paths, or (when the merge has not started yet)
# the tracked dirty paths that make git refuse the pull (F-3 state 3).
collect_paths() {
    local entry path
    PATHS=()

    while IFS= read -r -d '' entry; do
        path="${entry#*$'\t'}"
        in_list "$path" ${PATHS[@]+"${PATHS[@]}"} || PATHS+=("$path")
    done < <(git -C "$VAULT" ls-files -u -z 2>/dev/null)

    UNMERGED_COUNT="${#PATHS[@]}"

    if [ "$UNMERGED_COUNT" -gt 0 ]; then
        if ! git -C "$VAULT" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
            err "충돌 중인 경로가 있는데 MERGE_HEAD 가 없다 — 머지가 아닌 다른 작업이 진행 중이다"
            err "git status 로 확인하고 그 작업을 먼저 끝내거나 취소한 뒤 다시 실행하라"
            return 1
        fi
        return 0
    fi

    # No merge in flight: tracked changes against HEAD are what would block
    # the pull. Untracked files never block one, so they are skipped here —
    # the obsidian-git artifact is picked up separately below.
    if git -C "$VAULT" rev-parse -q --verify HEAD >/dev/null 2>&1; then
        while IFS= read -r -d '' path; do
            [ -n "$path" ] || continue
            in_list "$path" ${PATHS[@]+"${PATHS[@]}"} || PATHS+=("$path")
        done < <(git -C "$VAULT" diff --name-only -z HEAD 2>/dev/null)
    fi
    return 0
}

classify() {
    local path
    A_ROWS=()
    B_ROWS=()
    C_ROWS=()

    # The artifact is usually untracked, so it never shows up in either list
    # above. It is always class A — obsidian-git regenerates it at will.
    if [ -f "${VAULT}/${ARTIFACT}" ]; then
        A_ROWS+=("delete${TAB}${ARTIFACT}")
    fi

    for path in ${PATHS[@]+"${PATHS[@]}"}; do
        case "$path" in
            "${NESTED_DIR}" | "${NESTED_DIR}"/*)
                C_ROWS+=("nested-repo${TAB}${path}")
                continue
                ;;
        esac
        # Vault root only. obsidian-git writes its artifact there and nowhere
        # else, so a basename match would delete a same-named user note living
        # deeper in the tree (e.g. 40-Areas/conflict-files-obsidian-git.md).
        if [ "$path" = "$ARTIFACT" ]; then
            in_list "delete${TAB}${path}" ${A_ROWS[@]+"${A_ROWS[@]}"} || A_ROWS+=("delete${TAB}${path}")
            continue
        fi
        case "$path" in
            .obsidian/* | .trash/*)
                if is_ignored "$path" && is_tracked "$path"; then
                    A_ROWS+=("rm-cached${TAB}${path}")
                    continue
                fi
                ;;
        esac
        case "$path" in
            *.md) B_ROWS+=("manual${TAB}${path}") ;;
            *) C_ROWS+=("manual${TAB}${path}") ;;
        esac
    done
}

apply_row() {
    local action="$1" path="$2"
    case "$action" in
        delete)
            # Neither in the index nor on disk: something else removed it
            # between classify() and here. Nothing was applied, so say so
            # rather than claiming a deletion that never happened.
            if is_tracked "$path"; then
                run_git_index rm -q -f -- "$path" || return 1
            elif [ -e "${VAULT}/${path}" ]; then
                rm -f -- "${VAULT}/${path}" || {
                    err "아티팩트 삭제 실패: ${path}"
                    return 1
                }
            else
                printf 'SKIPPED\t%s\t%s\talready absent\n' "$action" "$path"
                return 0
            fi
            ;;
        rm-cached)
            run_git_index rm -q --cached -- "$path" || return 1
            # The whole point of --cached: the working copy must survive.
            if [ ! -e "${VAULT}/${path}" ]; then
                err "인덱스에서만 제거해야 하는데 디스크 파일이 사라졌다: ${path}"
                return 1
            fi
            ;;
        *)
            err "자동 처리할 수 없는 action: ${action}"
            return 1
            ;;
    esac
    printf 'APPLIED\t%s\t%s\n' "$action" "$path"
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

    VAULT="${1%/}"
    shift
    APPLY=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --apply) APPLY=1 ;;
            *)
                err "알 수 없는 인자 '$1'"
                usage >&2
                return 1
                ;;
        esac
        shift
    done

    if [ ! -d "$VAULT" ]; then
        err "vault 경로가 없다: ${VAULT}"
        return 1
    fi

    preflight || return 1
    collect_paths || return 1
    classify

    local row action path
    for row in ${A_ROWS[@]+"${A_ROWS[@]}"}; do
        printf 'A\t%s\n' "$row"
    done
    for row in ${B_ROWS[@]+"${B_ROWS[@]}"}; do
        printf 'B\t%s\n' "$row"
    done
    for row in ${C_ROWS[@]+"${C_ROWS[@]}"}; do
        printf 'C\t%s\n' "$row"
    done
    printf 'SUMMARY: A=%d B=%d C=%d\n' \
        "${#A_ROWS[@]}" "${#B_ROWS[@]}" "${#C_ROWS[@]}"

    for row in ${C_ROWS[@]+"${C_ROWS[@]}"}; do
        case "$row" in
            "nested-repo${TAB}"*)
                warn "${NESTED_DIR}/ 는 별도 clone 이다 — 충돌 목록에 뜬 것은 embedded repo 오염 신호다. 자동 해결하지 않는다."
                warn "권장: git -C ${VAULT}/${NESTED_DIR} status  후  --vault ${VAULT}/${NESTED_DIR} 로 재실행 (F-8)"
                break
                ;;
        esac
    done

    [ "$APPLY" -eq 1 ] || return 0

    for row in ${A_ROWS[@]+"${A_ROWS[@]}"}; do
        action="${row%%"${TAB}"*}"
        path="${row#*"${TAB}"}"
        apply_row "$action" "$path" || return 1
    done
    return 0
}

main "$@"
