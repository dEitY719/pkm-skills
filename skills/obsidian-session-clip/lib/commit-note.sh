#!/usr/bin/env bash
# skills/obsidian-session-clip/lib/commit-note.sh
#
# NF-2 parallel-session-safe commit of exactly ONE note file into the vault.
#
# The vault is shared by N concurrent sessions and by obsidian-git's own
# auto-backup loop, so this script must never widen its blast radius:
#   * pathspec-limited `git add -- <one file>` and `git commit -- <that file>`.
#     `-a`, `-A` and `git add .` are forbidden — they would swallow another
#     session's half-written note or the user's dirty files.
#   * `.git/index.lock` contention is retried with exponential backoff
#     (5 attempts, sleep i*i). If the lock never clears, the note stays on
#     disk and obsidian-git picks it up on its next cycle.
#   * If obsidian-git commits the note between our add and our commit, the
#     staged diff is empty — that is success ("이미 반영됨"), not an error.
#   * Remote synchronisation belongs to obsidian-git alone (NF-3), so this
#     script never contacts a remote.
#
# NF-4: once the note exists on disk the objective is met. Every commit-side
# failure degrades to a warning plus exit 0.
#
# Usage:
#   commit-note.sh <vault-dir> <note-path> <summary> [repo]

set -uo pipefail

LOCK_RETRIES=5

usage() {
    cat <<'EOF'
commit-note.sh — pathspec-limited single-note commit (NF-2)

Usage:
  commit-note.sh <vault-dir> <note-path> <summary> [repo]

  <vault-dir>   vault root (a git repository; if not, the commit is skipped)
  <note-path>   the one note to commit, absolute or vault-relative
  <summary>     one-line session summary for the commit subject
  [repo]        source repo name, appended as "(repo)" to the subject

Commit subject: "clip: <summary> (<repo>)"
Exit code is 0 unless the note file itself is missing.
EOF
}

warn() { printf 'WARN: %s\n' "$1" >&2; }
info() { printf '%s\n' "$1"; }

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    if [ "$#" -lt 3 ]; then
        usage >&2
        return 1
    fi

    vault="${1%/}"
    note="$2"
    summary="$3"
    repo="${4:-}"

    # Absolute note path (for the on-disk existence check) and vault-relative
    # pathspec (for `git add`/`git commit`), computed together so a relative
    # $note isn't round-tripped relative -> absolute -> relative.
    case "$note" in
        /*)
            note_abs="$note"
            rel="${note_abs#"${vault}/"}"
            ;;
        *)
            note_abs="${vault}/${note}"
            rel="$note"
            ;;
    esac

    if [ ! -f "$note_abs" ]; then
        printf 'ERROR: 노트 파일이 없다: %s\n' "$note_abs" >&2
        return 1
    fi

    if ! git -C "$vault" rev-parse --git-dir >/dev/null 2>&1; then
        warn "vault 가 git 저장소가 아니다 — 노트만 남기고 커밋을 건너뛴다: ${vault}"
        return 0
    fi

    # --- stage, retrying past .git/index.lock contention -------------------
    staged=0
    last_add_err=""
    i=1
    while [ "$i" -le "$LOCK_RETRIES" ]; do
        if last_add_err=$(git -C "$vault" add -- "$rel" 2>&1); then
            staged=1
            break
        fi
        if [ "$i" -lt "$LOCK_RETRIES" ]; then
            sleep $((i * i))
        fi
        i=$((i + 1))
    done

    if [ "$staged" -ne 1 ]; then
        # index.lock is the common cause, but `git add` can also fail on
        # permission errors, a full disk, or a corrupt repo — those look
        # identical from the exit code alone, so surface the real stderr
        # instead of always blaming the lock (PR #1322 review).
        warn "git index 가 ${LOCK_RETRIES}회 재시도 후에도 잠겨 있다 (.git/index.lock) — 노트는 디스크에 남았고 obsidian-git 이 다음 주기에 회수한다"
        [ -n "$last_add_err" ] && warn "마지막 git add 오류: ${last_add_err}"
        return 0
    fi

    # --- obsidian-git may have committed it in the meantime ----------------
    if git -C "$vault" diff --cached --quiet -- "$rel"; then
        info "이미 반영됨 (obsidian-git 이 선점) — ${rel}"
        return 0
    fi

    # --- commit, pathspec-limited -----------------------------------------
    if [ -n "$repo" ]; then
        subject="clip: ${summary} (${repo})"
    else
        subject="clip: ${summary}"
    fi

    commit_err=""
    if commit_err=$(git -C "$vault" commit -q -m "$subject" -- "$rel" 2>&1); then
        info "커밋 완료: ${subject}"
        return 0
    fi

    warn "커밋에 실패했지만 노트는 디스크에 남아 있다 — obsidian-git 이 회수한다: ${rel}"
    [ -n "$commit_err" ] && warn "git commit 오류: ${commit_err}"
    return 0
}

main "$@"
