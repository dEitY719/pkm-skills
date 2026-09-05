# pkm:karakeep-add — REST mechanics

All calls are plain `curl` against the **live** Karakeep instance. The
karakeep-sync project's `KarakeepClient` is read/sync only — it has no
List-create or attach method, so REST is the correct (and verified) path.

## Env + base URL

`lib/karakeep-env.sh` is the single copy of this contract, and every script in
`lib/` sources it itself — you never source it by hand (`pkm:karakeep-classify`
reaches the same file). It loads the working directory's `.env` behind a
`[ -f ]` guard (sourcing a missing file aborts a POSIX shell), asserts both
variables, and exports `BASE="${NEXTAUTH_URL%/}"` plus the
`Authorization: Bearer` header.

- **Base URL is `NEXTAUTH_URL`** (e.g. `https://karakeep.<your-tailnet>.ts.net`),
  reachable from home/internal over tailscale. It is **not** the
  `config.yaml` `localhost:3001` value.
- If either var is unset, fail with the message above — never invent a URL.

## Resolve or create a List

Lists nest via `parentId`. `lib/karakeep-add.sh` owns the walk: it takes one
`GET /api/v1/lists` snapshot (`.lists[]?`, null-safe if the field is missing),
then resolves a slash path segment by segment, reusing a List whose `name` and
`parentId` both match and creating it otherwise. Run the script — `-h` prints
its flags and the `KEY='value'` lines it emits — rather than retyping the
calls.

To *look at* the tree instead — the shape `pkm:karakeep-classify` needs — use
the shared helper, which prints one `<id>\t<full/path>` line per List:

```bash
bash "${SKILL_DIR}/lib/list-tree.sh"                    # REST
bash "${SKILL_DIR}/lib/list-tree.sh" --db data/db.db    # SQLite copy
```

Why the walk is shaped the way it is:

- `icon` is **required** by the API and must be a single emoji. The default is
  a folder glyph; override it with `KARAKEEP_LIST_ICON`.
- Payloads are built with `jq -n --arg`, never string-interpolated — a raw
  `-d '{"name":"'"$SEGMENT"'"...}'` breaks or injects when a value contains a
  quote or a backslash.
- Parents are created first, because membership is preserved by full path.
- Idempotent: a second run finds every segment and creates nothing.

## Resolve or create a bookmark

The dedup key is `url.rstrip("/")`, applied to both sides of the comparison.
`lib/karakeep-add.sh` pages `GET /api/v1/bookmarks` looking for it, accepting
the link URL at either `.content.url` or `.url` (Karakeep has carried both),
and gives up loudly rather than risk a duplicate if the pages never run out.
No hit → `POST /api/v1/bookmarks` `{type:"link", url, title}`, `title`
defaulting to the URL itself when no better one is known; Karakeep backfills
the metadata asynchronously.

## Attach + verify

The attach is `PUT /api/v1/lists/$LIST_ID/bookmarks/$BOOKMARK_ID` — idempotent,
empty body on a 2xx — and the following `GET /api/v1/lists/$LIST_ID/bookmarks`
confirms membership before the script reports `VERIFIED`.

## Reading the live tree on an external host

`bash "${SKILL_DIR}/lib/list-tree.sh" --db <path>`. It reads the Karakeep
SQLite database with the Python stdlib (the `sqlite3` CLI is not installed)
and feeds the **same** path reconstruction the REST mode uses, so the two
cannot drift apart the way the hand-written copies did.

## Company boundary

`Company` and every descendant list form a confidentiality boundary (this
repo's `CLAUDE.md` -> "Safety contracts"). Refuse to attach a public or
personal URL anywhere under `Company/`. Only proceed if the URL is genuinely
company-internal **and** the user confirmed the target. When refusing, name
the rule and suggest a non-Company list instead.

## Error cases

| Situation | Behavior |
|---|---|
| List name already exists under parent | Skip create, reuse existing id (idempotent). |
| URL already bookmarked | Skip create, attach existing bookmark id only. |
| `NEXTAUTH_URL` / `KARAKEEP_API_KEY` unset | Fail clearly, no fallback guess. |
| Public URL → `Company` subtree | Block with a warning; do not write. |
| `curl` non-2xx | Print status + response body, stop; do not retry blindly. |
