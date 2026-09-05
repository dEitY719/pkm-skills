# pkm:karakeep-classify — Help

## Arguments

| Token | Default | Description |
|-------|---------|-------------|
| `<url>` | — | The URL to classify (required). |
| `--apply` | off (dry-run) | Execute the proposal by delegating to `pkm:karakeep-add`. |
| `-h` / `--help` / `help` | — | Print this help and stop. |

## Usage

- `/pkm:karakeep-classify https://github.com/dEitY719/dotfiles` — analyze and
  print the suggested List path; write nothing (dry-run).
- `/pkm:karakeep-classify <url> --apply` — analyze, then immediately add the URL
  to the chosen List via `pkm:karakeep-add`.
- `/pkm:karakeep-classify -h` — print this help.

## What the skill does

1. Loads `NEXTAUTH_URL` + `KARAKEEP_API_KEY` from `./.env` (no localhost
   fallback).
2. Reads the live List tree (REST `GET /api/v1/lists`, or SQLite on an
   external host) and rebuilds nested paths.
3. Analyzes the URL — host/path first, lightweight WebFetch of title/meta
   only when ambiguous.
4. Recommends the best-fit existing List, or proposes a new (possibly
   nested) path when nothing fits, with a short rationale and confidence.
5. **Dry-run by default**: prints the proposal + the exact `pkm:karakeep-add`
   follow-up command. With `--apply`, delegates to `pkm:karakeep-add` to write.

## What the skill will NOT do

- Write anything in the default dry-run mode.
- Duplicate `pkm:karakeep-add`'s write logic — `--apply` always delegates.
- Use `localhost:3001` — base URL is always `NEXTAUTH_URL`.
- Suggest or apply a public/personal URL into `Company` or its children.
- Deep-fetch full page bodies unless explicitly asked.

## Output example

A full worked run — command, inputs, and the `[DRY-RUN]` report block Step 6
prints — is in
[`docs/skill-output/karakeep-classify-usage.md`](../../../docs/skill-output/karakeep-classify-usage.md).

## Related

- `pkm:karakeep-add <url> --list <path>` — the write path this skill delegates
  to under `--apply`, and the command printed for manual confirmation.
