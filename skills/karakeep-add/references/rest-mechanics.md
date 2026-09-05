# pkm:karakeep-add — REST mechanics

All calls are plain `curl` against the **live** Karakeep instance. The
karakeep-sync project's `KarakeepClient` is read/sync only — it has no
List-create or attach method, so REST is the correct (and verified) path.

## Env + base URL

`lib/karakeep-env.sh` is the single copy of this contract — source it, never
retype it (`pkm:karakeep-classify` sources the same file):

```bash
. "${SKILL_DIR}/lib/karakeep-env.sh"   # exports BASE and AUTH, or exits
karakeep_env_load
```

It loads the working directory's `.env` behind a `[ -f ]` guard (sourcing a
missing file aborts a POSIX shell), asserts both variables, and sets
`BASE="${NEXTAUTH_URL%/}"` plus the `Authorization: Bearer` header.

- **Base URL is `NEXTAUTH_URL`** (e.g. `https://karakeep.<your-tailnet>.ts.net`),
  reachable from home/internal over tailscale. It is **not** the
  `config.yaml` `localhost:3001` value.
- If either var is unset, fail with the message above — never invent a URL.

## Resolve or create a List

Lists nest via `parentId`. To resolve a slash path like `github/repository`,
start at the root and walk one segment at a time, carrying `parentId`.

`lib/karakeep-add.sh` implements this walk against `GET /api/v1/lists`
(`.lists[]?`, null-safe if the field is missing). To *look at* the tree
instead — the shape `pkm:karakeep-classify` needs — use the shared helper,
which prints one `<id>\t<full/path>` line per List:

```bash
bash "${SKILL_DIR}/lib/list-tree.sh"                    # REST
bash "${SKILL_DIR}/lib/list-tree.sh" --db data/db.db    # SQLite copy
```

For each segment (bound to shell vars `SEGMENT`, `EMOJI`, `PARENT_ID` — not
`<...>` placeholders, which a shell would read as redirection):
- Match an existing list where `name == $SEGMENT` and `parentId` equals the
  running parent (`null` at the root). Found → reuse `.id`.
- Not found → create it. Build the JSON with `jq -n` so values are always
  escaped (a raw `-d '{"name":"'"$SEGMENT"'"...}'` breaks or injects when a
  value contains `"` or `\`):

```bash
payload=$(jq -n --arg name "$SEGMENT" --arg icon "$EMOJI" --arg parentId "$PARENT_ID" \
  '{name: $name, icon: $icon, parentId: (if $parentId == "" then null else $parentId end)}')
curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  "$BASE/api/v1/lists" -d "$payload" | jq -r '.id'
```

`icon` is **required** by the API and must be a single emoji — set `EMOJI` to
a sensible one (a folder glyph as default, or a topic-fitting one). Leave
`PARENT_ID` empty for a root list (the `jq` expression emits `null`).
Creating parents first preserves full-path membership. Idempotent: a second
run finds every segment and creates nothing.

## Resolve or create a bookmark

Dedup on the trailing-slash-stripped URL:

```bash
KEY="$(printf '%s' "$URL" | sed 's:/*$::')"   # url.rstrip("/")
```

Search existing bookmarks for one whose URL (also stripped) equals `KEY`;
reuse its id. None → create:

```bash
payload=$(jq -n --arg url "$URL" --arg title "$TITLE" \
  '{type:"link", url:$url, title:$title}')
curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  "$BASE/api/v1/bookmarks" -d "$payload" | jq -r '.id'
```

`TITLE` may be the URL itself when no better title is known; Karakeep
backfills metadata asynchronously. As above, `jq -n` keeps the payload valid
even when the URL or title contains quotes or backslashes.

## Attach + verify

```bash
# Idempotent; success returns an empty body / 2xx. (LIST_ID / BOOKMARK_ID are
# shell vars, not `<...>` placeholders.)
curl -fsS -X PUT -H "$AUTH" \
  "$BASE/api/v1/lists/$LIST_ID/bookmarks/$BOOKMARK_ID"

# Verify membership. `.bookmarks[]?` is null-safe.
curl -fsS -H "$AUTH" "$BASE/api/v1/lists/$LIST_ID/bookmarks" \
  | jq -e --arg id "$BOOKMARK_ID" '.bookmarks[]? | select(.id==$id)' >/dev/null \
  && echo verified || echo NOT-verified
```

## Reading the live tree on an external host

`bash "${SKILL_DIR}/lib/list-tree.sh" --db <path>`. It reads the Karakeep
SQLite database with the Python stdlib (the `sqlite3` CLI is not installed)
and feeds the **same** path reconstruction the REST mode uses, so the two
cannot drift apart the way the hand-written copies did.

## Company boundary

`Company` and every descendant list form a confidentiality boundary
(CLAUDE.md §4.3). Refuse to attach a public or personal URL anywhere under
`Company/`. Only proceed if the URL is genuinely company-internal **and** the
user confirmed the target. When refusing, name the rule and suggest a
non-Company list instead.

## Error cases

| Situation | Behavior |
|---|---|
| List name already exists under parent | Skip create, reuse existing id (idempotent). |
| URL already bookmarked | Skip create, attach existing bookmark id only. |
| `NEXTAUTH_URL` / `KARAKEEP_API_KEY` unset | Fail clearly, no fallback guess. |
| Public URL → `Company` subtree | Block with a warning; do not write. |
| `curl` non-2xx | Print status + response body, stop; do not retry blindly. |
