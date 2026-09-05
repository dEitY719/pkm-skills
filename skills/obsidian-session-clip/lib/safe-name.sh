#!/usr/bin/env bash
# skills/obsidian-session-clip/lib/safe-name.sh
#
# NF-1 Windows-safe filename normalisation + F-2 collision resolution for the
# pkm:obsidian-session-clip skill.
#
# The vault original lives on a Windows filesystem, so a note whose filename
# carries any of  \ / : * ? " < > |  (or a control character) is unusable
# there. dEitY719/obsidian-para#5 shipped that bug once already, and the way
# it hurt was that it failed *silently*. Every failure mode here is therefore
# loud: a message on stderr plus a non-zero exit. Never an empty name.
#
# Usage:
#   safe-name.sh sanitize <raw-name>
#   safe-name.sh resolve <dir> <stem> [ext]
#   safe-name.sh -h | --help | help

set -euo pipefail

# `${var:0:N}` below counts *characters*, not bytes, only when the process
# locale has a UTF-8 LC_CTYPE. A caller running under LC_ALL=C (cron, a
# minimal container, an unset LANG) makes bash count bytes instead, slicing
# a multibyte Korean slug mid-character and emitting invalid UTF-8 — the
# exact silent-corruption failure mode NF-1 exists to rule out. Force a
# UTF-8 locale here so the behaviour is deterministic regardless of caller
# environment (dEitY719/dotfiles#1322 review).
for _candidate_locale in C.utf8 C.UTF-8 en_US.UTF-8; do
    if locale -a 2>/dev/null | grep -qx "$_candidate_locale"; then
        export LC_ALL="$_candidate_locale"
        break
    fi
done
unset _candidate_locale

# The 9 characters Windows forbids in a path component.
FORBIDDEN_SET='\\/:*?"<>|'
MAX_LEN=100
# Base candidate plus -2 .. -10 == 10 candidates. An 11th is refused (F-2).
MAX_CANDIDATES=10

usage() {
    cat <<'EOF'
safe-name.sh — Windows-safe filenames for pkm:obsidian-session-clip

Usage:
  safe-name.sh sanitize <raw-name>
      Print <raw-name> with the 9 Windows-forbidden characters
      (\ / : * ? " < > |) and all control characters removed, trimmed,
      and truncated to 100 characters. Exits 1 if nothing survives.

  safe-name.sh resolve <dir> <stem> [ext]
      Print the first free path of <dir>/<stem><ext>, <dir>/<stem>-2<ext>,
      ... <dir>/<stem>-10<ext>. <ext> defaults to ".md". Exits 1 when all
      10 candidates are taken.

  safe-name.sh -h | --help | help
      Print this text.
EOF
}

# sanitize_name <raw> -> safe name on stdout
sanitize_name() {
    raw="$1"
    if [ -z "$raw" ]; then
        echo "safe-name: 빈 이름은 정규화할 수 없다 (NF-1)" >&2
        return 1
    fi

    cleaned="$(printf '%s' "$raw" | tr -d "$FORBIDDEN_SET" | tr -d '[:cntrl:]')"

    # Trim leading whitespace before truncating, so truncation counts real
    # content instead of padding.
    cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"

    # Truncate to MAX_LEN characters (bash substring expansion is
    # multibyte-aware, so a Korean slug is cut at 100 characters, not bytes).
    cleaned="${cleaned:0:$MAX_LEN}"

    # Trim trailing whitespace/dots. Windows also rejects names that end in a
    # dot or a space — this single pass covers both the case where truncation
    # exposed one and the case where the raw name already ended in one.
    cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
    while [ -n "$cleaned" ] && [ "${cleaned%.}" != "$cleaned" ]; do
        cleaned="${cleaned%.}"
    done

    if [ -z "$cleaned" ]; then
        echo "safe-name: '$raw' 는 금지문자만으로 이뤄져 남는 이름이 없다 (NF-1)" >&2
        return 1
    fi

    printf '%s\n' "$cleaned"
}

# resolve_path <dir> <stem> [ext] -> first free path on stdout
resolve_path() {
    dir="$1"
    stem="$2"
    ext="${3:-.md}"

    if [ -z "$dir" ] || [ -z "$stem" ]; then
        echo "safe-name: resolve 는 <dir> 와 <stem> 이 모두 필요하다" >&2
        return 1
    fi

    n=1
    while [ "$n" -le "$MAX_CANDIDATES" ]; do
        if [ "$n" -eq 1 ]; then
            candidate="${dir%/}/${stem}${ext}"
        else
            candidate="${dir%/}/${stem}-${n}${ext}"
        fi
        # Reserve the candidate atomically: `set -C` (noclobber) makes `>`
        # fail with EEXIST instead of truncating when the file already
        # exists. A plain `[ ! -e "$candidate" ]` check followed later by a
        # separate write leaves a TOCTOU window — two sessions racing on the
        # same minute + stem could both see "free" and one note would
        # silently overwrite the other, defeating the NF-2 parallel-session
        # guarantee (dEitY719/dotfiles#1322 review). The caller (SKILL.md Step 5) writes
        # the real content into this now-reserved, empty file.
        if (
            set -C
            : >"$candidate"
        ) 2>/dev/null; then
            printf '%s\n' "$candidate"
            return 0
        fi
        n=$((n + 1))
    done

    echo "safe-name: '${stem}${ext}' 충돌 회피 시도 ${MAX_CANDIDATES}회를 모두 소진해 정지한다 (F-2)" >&2
    return 1
}

main() {
    if [ "$#" -eq 0 ]; then
        usage >&2
        return 1
    fi

    mode="$1"
    shift

    case "$mode" in
        -h | --help | help)
            usage
            ;;
        sanitize)
            if [ "$#" -lt 1 ]; then
                echo "safe-name: sanitize 는 <raw-name> 이 필요하다" >&2
                return 1
            fi
            sanitize_name "$1"
            ;;
        resolve)
            if [ "$#" -lt 2 ]; then
                echo "safe-name: resolve 는 <dir> <stem> 이 필요하다" >&2
                return 1
            fi
            resolve_path "$1" "$2" "${3:-.md}"
            ;;
        *)
            echo "safe-name: 알 수 없는 모드 '$mode'" >&2
            usage >&2
            return 1
            ;;
    esac
}

main "$@"
