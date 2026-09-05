---
name: karakeep-classify
description: >-
  Analyze a URL and suggest the best-fit Karakeep List (dry-run by default).
  Use for /pkm:karakeep-classify, "이 URL 어느 list 가
  좋을지", "분류 제안해줘", "where should this bookmark go". Do NOT use to
  write — use pkm:karakeep-add instead.
allowed-tools: Bash, Read, WebFetch
license: MIT
compatibility:
  network: required
metadata:
  model_recommendation:
    tier: sonnet
    reason: "judgment task — fits URL content against a live taxonomy and reasons about the Company boundary"
    claude: prefer
    non_claude: advisory-only
---

# pkm:karakeep-classify — Suggest a List for a URL (default dry-run)

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Decide where `<url>` belongs in Karakeep. Compare the URL's topic against
the live List tree and recommend the best-fit existing List, or — when
nothing fits — propose a new (possibly nested) List path. **Default is
dry-run**: print the proposal and write nothing. This skill is the "judge";
the "write" is `pkm:karakeep-add`.

## Step 1: Parse Args + Load Env

Positional `<url>` (required → else usage pointer `Run /pkm:karakeep-classify -h
for usage.`). Flag `--apply` switches from dry-run to execution.

`SKILL_DIR` = this file's directory. `../karakeep-add/lib/karakeep-env.sh`
loads `NEXTAUTH_URL` + `KARAKEEP_API_KEY` from `./.env`; unset → fail
clearly, no localhost fallback.

## Step 2: Read the Live List Tree

```bash
bash "${SKILL_DIR}/../karakeep-add/lib/list-tree.sh"
```

One `<id>\t<full/path>` line per List, `parentId` already resolved. Add
`--db <path>` to read a SQLite copy on an external host. Detail:
`references/classify-mechanics.md` → "Env + read the tree".

## Step 3: Analyze the URL

Determine the URL's topic from its host/path and, when useful, a WebFetch of
the page title + meta description (do not deep-fetch bodies by default). Keep
it lightweight — title/host/path usually suffice.

## Step 4: Match or Propose

Pick the best-fit existing List path. If none is a good fit, propose a new
(possibly nested) path with a one-line rationale. Apply the Company
guardrail at proposal time: never suggest a public/personal URL into
`Company/*` — see `references/classify-mechanics.md` → "Company boundary".

## Step 5: Output (dry-run) or Apply

- **dry-run (default)** — print: the analyzed topic, the recommended path,
  whether it exists or would be created, a confidence note, and the exact
  follow-up command `pkm:karakeep-add <url> --list <path>`. Write nothing.
- **`--apply`** — hand the chosen `<url>` + `<path>` to `pkm:karakeep-add`
  (Skill(pkm:karakeep-add, "<url> --list <path>")); it owns creation, dedup,
  attach, and verification.

## Step 6: Report

End with a `[DRY-RUN]` or `[APPLIED]` verdict line and the `Next:` hint —
dry-run → the `pkm:karakeep-add` command to confirm; applied → re-run classify
to confirm the no-op.

## Constraints

- Default writes nothing — only `--apply` mutates, and only via
  `pkm:karakeep-add` (no duplicate REST write logic here).
- Base URL is always `NEXTAUTH_URL`, never `localhost:3001`.
- Never propose or apply a public/personal URL under the `Company` subtree.
- Lightweight analysis — title/meta over full-body fetch unless the user
  asks for deeper inspection.

## Related Skills

- Sister skill [[pkm:karakeep-add]] owns the write path; this one only decides.
  Flags and usage: `references/help.md`.
