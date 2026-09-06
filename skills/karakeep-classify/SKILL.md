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

Decide where `<url>` belongs in Karakeep. Compare the URL's topic against the
live List tree and recommend the best-fit existing List, or — when nothing
fits — propose a new (possibly nested) List path. **Default is dry-run**:
print the proposal and write nothing; `pkm:karakeep-add` owns the write.

## Step 1: Parse Args + Load Env

Positional `<url>` (required → else usage pointer `Run /pkm:karakeep-classify -h
for usage.`). Flag `--apply` switches from dry-run to execution.

`SKILL_DIR` = this file's directory. Step 2's script loads `NEXTAUTH_URL` +
`KARAKEEP_API_KEY` from `./.env` itself; unset → `[FAIL]`, no localhost fallback.

## Step 2: Read the Live List Tree

```bash
bash "${SKILL_DIR}/../karakeep-add/lib/list-tree.sh"
```

One `<id>\t<full/path>` line per List, `parentId` already resolved. Add
`--db <path>` to read a SQLite copy on an external host. Detail:
`references/classify-mechanics.md` → "Env + read the tree".

## Step 3: Analyze the URL

Determine the URL's topic from its host/path and, when useful, a WebFetch of
the page title + meta description. Host and path alone usually suffice.

## Step 4: Match or Propose

Pick the best-fit existing List path. If none is a good fit, propose a new
(possibly nested) path with a one-line rationale. Apply the Company
guardrail at proposal time: never suggest a public/personal URL into
`Company/*` — see `references/classify-mechanics.md` → "Company boundary".

## Step 5: Output (dry-run) or Apply

- **dry-run (default)** — print: the analyzed topic, the recommended path,
  whether it exists or would be created, `confidence=<high|medium|low>`, and
  the exact command `pkm:karakeep-add <url> --list <path>`. Write nothing.
- **`--apply`** — hand the chosen `<url>` + `<path>` to `pkm:karakeep-add`
  (Skill(pkm:karakeep-add, "<url> --list <path>")); it owns creation, dedup,
  attach, and verification.

## Step 6: Report

The last line is always exactly one of these three, so a caller tells success
from refusal by that line alone:

```
[DRY-RUN] <url> -> <path> (<exists|would-create>) confidence=<high|medium|low>
[APPLIED] <url> -> <path>
[FAIL] <reason>
```

`[FAIL]` covers every refusal — unset env (Step 1), an unreachable List tree
(Step 2), a Company-boundary refusal (Step 4). `[DRY-RUN]` adds a `Next:` line
with the `pkm:karakeep-add` command; `[APPLIED]` re-runs classify to show the
no-op.

## Constraints

The dry-run default, the `NEXTAUTH_URL` base URL and the Company boundary are
stated where they apply (Steps 1, 4 and 5). The one rule that lives nowhere
else: keep analysis lightweight — title/meta, not a full-body fetch, unless
the user asks for deeper inspection.

## Related Skills

- Sister skill [[pkm:karakeep-add]] owns the write path; this one only decides.
  Flags and usage: `references/help.md`.
