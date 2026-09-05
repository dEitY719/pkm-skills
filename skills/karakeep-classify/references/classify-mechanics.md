# pkm:karakeep-classify — mechanics

This skill is read + judge only. The single write path lives in
`pkm:karakeep-add`; `--apply` delegates there rather than duplicating REST logic.

## Env + read the tree

Both halves live in `pkm:karakeep-add`'s `lib/`, shared rather than copied —
the copies this file used to carry had already drifted from their originals:

```bash
LIB="${SKILL_DIR}/../karakeep-add/lib"
. "$LIB/karakeep-env.sh" && karakeep_env_load   # exports BASE and AUTH
bash "$LIB/list-tree.sh"                        # <id>\t<full/path> per List
bash "$LIB/list-tree.sh" --db data/db.db        # same output from SQLite
```

Base URL is `NEXTAUTH_URL` (tailscale-reachable), **not** the `config.yaml`
`localhost:3001` value; an unset variable is fatal, never guessed.
`list-tree.sh` resolves `parentId` into full `부모/자식` paths, keeps a
dangling or cyclic parent visible instead of dropping the row, and uses the
Python stdlib for the SQLite mode because the `sqlite3` CLI is absent.

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
