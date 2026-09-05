#!/usr/bin/env bash
# skills/karakeep-add/lib/karakeep-add.sh
#
# Steps 3-5 of pkm:karakeep-add, deterministic half: walk-or-create the List
# path, dedup the bookmark on url.rstrip("/"), attach it idempotently, and
# verify the attach. The judgment half stays in SKILL.md — the Company
# decision, the title, and the report prose.
#
# Output is eval-able KEY='value' lines on stdout, the same contract the two
# Obsidian skills already use for their lib/resolve-vault.sh. Every failure
# is loud: a FAIL: line on stderr plus a non-zero exit. Never partial.
#
# Usage:
#   karakeep-add.sh <url> --list <path> [--title <title>] [--allow-company]
#   karakeep-add.sh -h | --help | help

set -euo pipefail

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./karakeep-env.sh
. "$LIB_DIR/karakeep-env.sh"

# Default List icon. The API requires a single emoji; this repo's CI bans
# emoji in tracked text, so it is built from its codepoint instead.
DEFAULT_ICON="$(printf '\U0001F4C1')"
# Bookmark pages scanned while deduping before giving up (100 per page).
MAX_PAGES=50

usage() {
    cat <<'EOF'
karakeep-add.sh — resolve/create a List path, dedup, attach, verify

Usage:
  karakeep-add.sh <url> --list <path> [--title <title>] [--allow-company]
      <path> is slash-nested, e.g. "AI/Agent Tooling". Every missing segment
      is created parents-first with a default folder icon (override with
      KARAKEEP_LIST_ICON). The bookmark is deduped on url.rstrip("/").

      Prints eval-able lines on stdout:
        LIST_ID           id of the leaf List
        LIST_CREATED      yes if any segment had to be created
        LIST_TRAIL        "name:id:created|reused" per segment, ";"-joined
        BOOKMARK_ID       id of the bookmark
        BOOKMARK_CREATED  yes if the bookmark was created, no on a dedup hit
        VERIFIED          yes if the GET confirmed membership

      --allow-company is required for a path at or under "Company". The
      confidentiality decision itself belongs to the caller; this flag only
      makes it impossible to reach that subtree by accident.

  karakeep-add.sh -h | --help | help
      Print this text.
EOF
}

emit() {
    printf "%s='%s'\n" "$1" "${2//\'/\'\\\'\'}"
}

die() {
    echo "FAIL: $1" >&2
    exit 1
}

# Print the id of the List named $1 under parent $2 ("" = root), or nothing.
find_list() {
    curl -fsS -H "$AUTH" "$BASE/api/v1/lists" \
        | jq -r --arg name "$1" --arg parent "$2" \
            '[.lists[]? | select(.name == $name and ((.parentId // "") == $parent))][0].id // empty'
}

create_list() {
    local payload
    payload=$(jq -n --arg name "$1" --arg icon "$ICON" --arg parentId "$2" \
        '{name: $name, icon: $icon, parentId: (if $parentId == "" then null else $parentId end)}')
    curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
        "$BASE/api/v1/lists" -d "$payload" | jq -r '.id // empty'
}

# Print the id of a bookmark whose url.rstrip("/") equals $1, or nothing.
find_bookmark() {
    local key="$1" cursor="" page=0 body hit
    while [ "$page" -lt "$MAX_PAGES" ]; do
        if [ -n "$cursor" ]; then
            body=$(curl -fsS -H "$AUTH" "$BASE/api/v1/bookmarks?limit=100&cursor=$cursor")
        else
            body=$(curl -fsS -H "$AUTH" "$BASE/api/v1/bookmarks?limit=100")
        fi
        # Karakeep has carried the link URL both at .url and at .content.url;
        # accept either rather than pinning one shape.
        hit=$(printf '%s' "$body" | jq -r --arg key "$key" \
            '[.bookmarks[]? | select((((.content.url // .url) // "") | sub("/+$"; "")) == $key)][0].id // empty')
        if [ -n "$hit" ]; then
            printf '%s\n' "$hit"
            return 0
        fi
        cursor=$(printf '%s' "$body" | jq -r '.nextCursor // empty')
        [ -n "$cursor" ] || return 0
        page=$((page + 1))
    done
    die "scanned $MAX_PAGES bookmark pages without exhausting the list — refusing to risk a duplicate"
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    local url="" path="" title="" allow_company="no"
    url="${1:-}"
    [ -n "$url" ] || die "missing <url> — see karakeep-add.sh -h"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --list)
                path="${2:-}"
                shift 2
                ;;
            --title)
                title="${2:-}"
                shift 2
                ;;
            --allow-company)
                allow_company="yes"
                shift
                ;;
            *) die "unknown argument '$1' — see karakeep-add.sh -h" ;;
        esac
    done
    [ -n "$path" ] || die "missing --list <path> — this script never guesses a List"

    # Fail-closed backstop for the Company confidentiality boundary. The
    # judgment ("is this URL genuinely company-internal?") is the caller's;
    # this only rules out reaching the subtree without having made it.
    case "$path" in
        Company | Company/*)
            [ "$allow_company" = "yes" ] ||
                die "'$path' is inside the Company subtree — pass --allow-company only after confirming the URL is company-internal"
            ;;
    esac

    karakeep_env_load
    ICON="${KARAKEEP_LIST_ICON:-$DEFAULT_ICON}"

    local parent="" list_created="no" trail="" segment id
    # A path never contains an empty segment; IFS splitting on "/" is enough.
    local -a segments=()
    IFS='/' read -r -a segments <<<"$path"
    for segment in "${segments[@]}"; do
        [ -n "$segment" ] || die "empty segment in --list '$path'"
        id=$(find_list "$segment" "$parent")
        if [ -n "$id" ]; then
            trail="${trail:+$trail;}${segment}:${id}:reused"
        else
            id=$(create_list "$segment" "$parent")
            [ -n "$id" ] || die "POST /api/v1/lists returned no id for segment '$segment'"
            list_created="yes"
            trail="${trail:+$trail;}${segment}:${id}:created"
        fi
        parent="$id"
    done
    [ -n "$parent" ] || die "--list '$path' resolved to no List"

    local key bookmark_id bookmark_created="no" payload
    key="$(printf '%s' "$url" | sed 's:/*$::')"
    bookmark_id=$(find_bookmark "$key")
    if [ -z "$bookmark_id" ]; then
        payload=$(jq -n --arg url "$url" --arg title "${title:-$url}" \
            '{type:"link", url:$url, title:$title}')
        bookmark_id=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
            "$BASE/api/v1/bookmarks" -d "$payload" | jq -r '.id // empty')
        [ -n "$bookmark_id" ] || die "POST /api/v1/bookmarks returned no id"
        bookmark_created="yes"
    fi

    # Idempotent: a second PUT of the same pair is still a 2xx empty body.
    curl -fsS -X PUT -H "$AUTH" \
        "$BASE/api/v1/lists/$parent/bookmarks/$bookmark_id" >/dev/null ||
        die "PUT attach failed for bookmark $bookmark_id -> list $parent"

    local verified="no"
    if curl -fsS -H "$AUTH" "$BASE/api/v1/lists/$parent/bookmarks" |
        jq -e --arg id "$bookmark_id" '.bookmarks[]? | select(.id == $id)' >/dev/null; then
        verified="yes"
    fi

    emit LIST_ID "$parent"
    emit LIST_CREATED "$list_created"
    emit LIST_TRAIL "$trail"
    emit BOOKMARK_ID "$bookmark_id"
    emit BOOKMARK_CREATED "$bookmark_created"
    emit VERIFIED "$verified"
}

main "$@"
