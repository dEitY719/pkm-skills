#!/usr/bin/env bash
# skills/karakeep-add/lib/list-tree.sh
#
# The live Karakeep List tree, flattened to one "<id>\t<full/path>" line per
# List. Shared by pkm:karakeep-add (which walks the path it must create) and
# pkm:karakeep-classify (which matches a URL against the existing taxonomy).
#
# It used to be written twice — once per skill's references/*.md — and the
# two SQLite fallbacks had already drifted apart. Both sources now feed the
# same path reconstruction, so they cannot disagree again.
#
# Usage:
#   list-tree.sh              read the live tree over REST (needs ./.env)
#   list-tree.sh --db <path>  read it from a Karakeep SQLite DB instead
#   list-tree.sh -h | --help | help

set -euo pipefail

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./karakeep-env.sh
. "$LIB_DIR/karakeep-env.sh"

usage() {
    cat <<'EOF'
list-tree.sh — flatten the Karakeep List tree to "<id>\t<full/path>" lines

Usage:
  list-tree.sh
      Read GET /api/v1/lists over REST and print one line per List:
      the list id, a TAB, then its full slash-joined path ("부모/자식").
      Needs NEXTAUTH_URL + KARAKEEP_API_KEY (see karakeep-env.sh).

  list-tree.sh --db <path>
      Same output, read from a Karakeep SQLite database instead — for an
      external host where REST is awkward. The sqlite3 CLI is not assumed;
      this uses the Python stdlib.

  list-tree.sh -h | --help | help
      Print this text.

Output is sorted by path. A List whose parentId does not resolve is printed
under its own name rather than dropped, so a dangling row is visible.
EOF
}

# stdin: "<id>\t<parentId>\t<name>" rows. stdout: "<id>\t<full/path>" rows.
build_paths() {
    python3 -c '
import sys

rows = {}
order = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        continue
    i, parent, name = parts
    rows[i] = (parent, name)
    order.append(i)

def path(i, seen=None):
    seen = seen or set()
    if i not in rows or i in seen:   # dangling or cyclic parentId: stop
        return ""
    seen.add(i)
    parent, name = rows[i]
    prefix = path(parent, seen) if parent else ""
    return prefix + "/" + name if prefix else name

for i in sorted(order, key=lambda k: path(k)):
    print(i + "\t" + path(i))
'
}

rows_from_rest() {
    karakeep_env_load
    curl -fsS -H "$AUTH" "$BASE/api/v1/lists" \
        | jq -r '.lists[]? | [.id, (.parentId // ""), .name] | @tsv'
}

rows_from_sqlite() {
    python3 -c '
import sqlite3, sys

db = sqlite3.connect(sys.argv[1])
for row in db.execute("SELECT id, parentId, name FROM bookmarkLists"):
    print("\t".join("" if c is None else str(c) for c in row))
' "$1"
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
        --db)
            db="${2:-}"
            [ -n "$db" ] || {
                echo "FAIL: --db needs a path" >&2
                return 2
            }
            rows_from_sqlite "$db" | build_paths
            return 0
            ;;
        "")
            rows_from_rest | build_paths
            return 0
            ;;
        *)
            echo "FAIL: unknown argument '$1' — see list-tree.sh -h" >&2
            return 2
            ;;
    esac
}

main "$@"
