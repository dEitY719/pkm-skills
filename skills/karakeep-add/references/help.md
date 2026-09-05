# pkm:karakeep-add — Help

## Arguments

| Token | Default | Description |
|-------|---------|-------------|
| `<url>` | — | The URL to bookmark (required). |
| `--list <path>` | — | Target List, slash-nested e.g. `github/repository`. Omit to get a `pkm:karakeep-classify` suggestion (propose-then-confirm; nothing is written). |
| `-h` / `--help` / `help` | — | Print this help and stop. |

`lib/karakeep-add.sh` takes two more, set by the skill rather than typed by
the user: `--title <title>` (defaults to the URL; Karakeep backfills real
metadata asynchronously) and `--allow-company`, which the skill passes only
after Step 2 has confirmed a `Company/*` target. Without it the script
refuses that subtree outright.

## Usage

- `/pkm:karakeep-add https://github.com/dEitY719/dotfiles --list github/repository`
  — create the `github` → `repository` path if missing, bookmark the URL,
  attach it, and verify membership.
- `/pkm:karakeep-add <url> --list reading/longform` — nested two levels deep.
- `/pkm:karakeep-add <url>` — no `--list`: delegates to `pkm:karakeep-classify` for a
  suggested path and stops (writes nothing). Re-run with the suggested
  `--list` to actually add.
- `/pkm:karakeep-add -h` — print this help.

## What the skill does

1. Loads `NEXTAUTH_URL` + `KARAKEEP_API_KEY` from `./.env` (no localhost
   fallback, no guessing).
2. Enforces the Company confidentiality boundary before any write.
3. Walks the `--list` path, reusing or creating each segment (emoji icon
   required by the API), parents first.
4. Dedups the bookmark by `url.rstrip("/")` — reuses an existing bookmark or
   creates a new one.
5. Attaches the bookmark to the List (`PUT`, idempotent) and verifies via
   `GET /api/v1/lists/<id>/bookmarks`.
6. Reports the path, ids, created-vs-reused for each, and a verified verdict.

## What the skill will NOT do

- Use `localhost:3001` — the live base URL is always `NEXTAUTH_URL`.
- Create a duplicate List or bookmark on re-run (idempotent).
- Put a public/personal URL into `Company` or its children.
- Run `karakeep-sync push` or edit the karakeep-sync repo (next push
  materializes the change to Obsidian on its own).
- Bulk-import — that is `import-chrome`'s job.

## Output example

A full worked run — command, inputs, and the report block Step 6 prints
(with the created-vs-reused column that proves idempotency) — is in
[`docs/skill-output/karakeep-add-usage.md`](../../../docs/skill-output/karakeep-add-usage.md).

## Related

- `pkm:karakeep-classify <url>` — analyze a URL and suggest the best List
  (default dry-run); `--apply` delegates to this skill.
