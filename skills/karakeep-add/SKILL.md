---
name: karakeep-add
description: >-
  Add a URL to a Karakeep List via REST, creating the List path on demand.
  Use when the user runs /pkm:karakeep-add, or asks "이 URL
  Karakeep <list>에 넣어줘", "add <url> to list <path>". Do NOT use to pick a
  List — use pkm:karakeep-classify.
allowed-tools: Bash, Read
license: MIT
compatibility:
  network: required
metadata:
  model_recommendation:
    tier: sonnet
    reason: "deterministic REST writes, but needs judgment for the Company guardrail and nested-path creation"
    claude: prefer
    non_claude: advisory-only
---

# pkm:karakeep-add — URL → List (write path via REST)

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Add `<url>` to the Karakeep List at `<path>`, creating the List (and every
missing parent in a nested `부모/자식` path) first. The write path is pure
REST — `KarakeepClient` in the karakeep-sync project is read/sync only and
has no create/attach methods. Idempotent end to end.

## Step 1: Parse Args + Load Env

Positional `<url>`; flag `--list <path>` (slash-delimited nesting).

- Missing `<url>` → print the usage pointer (`Run /pkm:karakeep-add -h for
  usage.`) and stop.
- `<url>` present but `--list` omitted → **do not write.** Delegate to
  `pkm:karakeep-classify` for a suggestion and stop:
  `Skill(pkm:karakeep-classify, "<url>")`. That runs dry-run: it proposes a
  best-fit List path and ends with the exact `pkm:karakeep-add <url> --list
  <path>` command for the user to confirm. This skill only writes when the
  user re-runs with an explicit `--list` (propose-then-confirm — never
  auto-apply the guess).

`SKILL_DIR` = this file's directory. `lib/karakeep-env.sh` loads
`NEXTAUTH_URL` + `KARAKEEP_API_KEY` from the working directory's `.env` and
fails loudly when either is unset — never guess a base URL or use `localhost`.

## Step 2: Company Guardrail

If `<path>` is `Company` or starts with `Company/`, refuse unless the URL is
explicitly company-internal and the user confirmed. Public/personal URLs
into the Company subtree are blocked — see `references/rest-mechanics.md`
→ "Company boundary". This is acceptance-criterion-critical, not advisory.

## Steps 3-5: Resolve the path, attach, verify

```bash
eval "$(bash "${SKILL_DIR}/lib/karakeep-add.sh" "$URL" --list "$LIST_PATH" \
  ${TITLE:+--title "$TITLE"} ${COMPANY_OK:+--allow-company})"
```

It walks `<path>` parents-first (reuse or `POST /api/v1/lists`), dedups the
bookmark on `url.rstrip("/")`, `PUT`s the idempotent attach and `GET`s the
verify, then sets `LIST_ID LIST_CREATED LIST_TRAIL BOOKMARK_ID
BOOKMARK_CREATED VERIFIED`. A non-zero exit is fatal — surface its `FAIL:`
line verbatim and stop. Pass `--allow-company` only once Step 2 approved it.
Mechanics: `references/rest-mechanics.md`.

## Step 6: Report

Print a `[OK]` / `[FAIL]` line with the List path, ids, and whether each
List/bookmark was created or reused (proves idempotency). End with the
`Next:` hint: `pkm:karakeep-classify <url>` for the suggest flow, or re-run to
confirm the no-op. Error templates: `references/rest-mechanics.md`
→ "Error cases".

## Constraints

- Base URL is always `NEXTAUTH_URL` — never `localhost:3001` (that is the
  `config.yaml` internal value, wrong for live writes).
- Idempotent: never create a duplicate List (same name+parent) or bookmark
  (same `url.rstrip("/")`).
- Never write a public/personal URL into the `Company` subtree.
- This skill only touches the live Karakeep instance — it does not edit the
  karakeep-sync repo or run `karakeep-sync push` (next push materializes).

## Related Skills

- Sister skill [[pkm:karakeep-classify]] suggests a List (default dry-run); this
  one performs the write. Flags and usage: `references/help.md`.
