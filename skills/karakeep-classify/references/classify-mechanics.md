# pkm:karakeep-classify — mechanics

This skill is read + judge only. The single write path lives in
`pkm:karakeep-add`; `--apply` delegates there rather than duplicating REST logic.

## Env + read the tree

Load from the working directory's `.env` (no hardcoded base URL):

```bash
set -a; [ -f ./.env ] && . ./.env; set +a   # guard: sourcing a missing file aborts a POSIX shell
: "${NEXTAUTH_URL:?NEXTAUTH_URL not set — refusing to guess base URL}"
: "${KARAKEEP_API_KEY:?KARAKEEP_API_KEY not set — cannot authenticate}"
BASE="${NEXTAUTH_URL%/}"
AUTH="Authorization: Bearer ${KARAKEEP_API_KEY}"
```

Base URL is `NEXTAUTH_URL` (tailscale-reachable), **not** the `config.yaml`
`localhost:3001` value. Read the List tree and rebuild nested paths:

```bash
curl -fsS -H "$AUTH" "$BASE/api/v1/lists" \
  | jq -r '.lists[]? | "\(.id)\t\(.parentId // "")\t\(.name)"'
# Then join child -> parent on id to print full "부모/자식" paths.
```

On an external host where REST is awkward, read SQLite directly (the
`sqlite3` CLI is absent — use Python stdlib):

```bash
python3 - <<'PY'
import sqlite3
db = sqlite3.connect("data/db.db")
rows = {r[0]: (r[1], r[2]) for r in
        db.execute("SELECT id, parentId, name FROM bookmarkLists")}
def path(i):
    if i not in rows:          # dangling parentId → stop, don't KeyError
        return ""
    parent, name = rows[i]     # row is (parentId, name)
    p = path(parent) if parent else ""
    return f"{p}/{name}" if p else name
for i in rows:
    print(path(i))
PY
```

## Analyzing the URL

Cheapest signal first: host + path segments. When ambiguous, WebFetch the
page for its `<title>` and `meta description` only — do not fetch full
article bodies by default. Map the topic to the closest existing path; if
the gap is large, propose a new path (prefer extending an existing parent
over a brand-new root).

## Company boundary

`Company` and its descendants are a confidentiality boundary (CLAUDE.md
§4.3). Never recommend a public or personal URL into `Company/*`, even when
the topic seems to match — the boundary is about provenance, not topic.
State the rule if the user pushes a public URL toward Company, and offer a
non-Company alternative.

## Delegating on --apply

```
Skill(pkm:karakeep-add, "<url> --list <chosen-path>")
```

`pkm:karakeep-add` owns List/parent creation, `url.rstrip("/")` dedup, the
idempotent attach, and post-attach verification. This skill never issues a
write `curl` itself.
