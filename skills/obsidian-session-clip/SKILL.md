---
name: obsidian-session-clip
description: >-
  AI 세션 작업을 PARA vault Inbox 에 md 노트 1개로 클립한다. 명시 호출에만
  실행: /pkm:obsidian-session-clip, "이번 세션 볼트에
  클립", "세션 옵시디언에 남겨", "clip this session to my vault". 자동 트리거
  금지. Do NOT use for 일자별 daily log — use notes:task-history instead.
allowed-tools: Bash, Read, Write, Grep
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "conversation synthesis into a structured note; the file/commit path is deterministic in lib/, but section content needs judgment"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-session-clip — 세션 → vault Inbox

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop. No API calls, no file writes.

## Step 1: Args + vault

`SKILL_DIR` = this file's directory. Parse per `references/options.md`: non-flag
tokens join into `[description]`; `--no-commit`, `--dry-run`, `--vault <path>`
(`--dry-run` wins). `VAULT` = `bash "${SKILL_DIR}/lib/resolve-vault.sh" "$VAULT_ARG"`
(`$VAULT_ARG` = the parsed `--vault` value, empty if absent) — priority and
PC-mode mapping in `references/options.md`. If `VAULT` does not exist, print
the resolved path plus the `--vault` usage line and **stop** (never create a
vault at a typo'd path). Otherwise `mkdir -p "$VAULT/99-Inbox/ai-session"`
(skip on `--dry-run`).

## Step 2: Git context + classify

From the **current working repo**, not the vault: `REPO` =
`basename $(git rev-parse --show-toplevel)`, `BRANCH` =
`git rev-parse --abbrev-ref HEAD`, `git log --oneline <base>..HEAD`,
`git diff <base>...HEAD --stat`, every `#N` named in the conversation. `<base>`
is the default branch; not a git repo → `REPO`/`BRANCH` = `none`, continue.
`session_type` = `code` if the session produced 1 or more commits or created a
PR, else `research` (`references/frontmatter.md`).

## Step 3: Compose

Frontmatter: all 9 keys per `references/frontmatter.md`, `status: unprocessed`,
`memo: ai-generated`. Body: `references/template-code.md` or
`references/template-research.md`, section titles and order verbatim. Fill all
3 `## 메모` subsections. No commits, no file changes and no substantive
discussion → print "클립할 내용이 없다" and stop; never write an empty note.

## Step 4: Filename

`RAW_STEM` = `$(date '+%Y-%m-%d-%H%M')-<repo>-<slug>` (slug rules in
`references/options.md`), then:

```
STEM=$(bash "${SKILL_DIR}/lib/safe-name.sh" sanitize "$RAW_STEM")
NOTE=$(bash "${SKILL_DIR}/lib/safe-name.sh" resolve "$VAULT/99-Inbox/ai-session" "$STEM")
```

Either failing is fatal — surface stderr, do not invent a fallback name.
`resolve` reserves `NOTE` atomically (empty file, closes a parallel-session race).

## Step 5: Write

`--dry-run` → print `NOTE` + body, `rm -f "$NOTE"` (undo the reservation —
write nothing), jump to Step 7. Otherwise write the body to `NOTE`. **This
is the objective**; everything after it is best-effort.

## Step 6: Commit

Skip on `--no-commit`. Otherwise run
`bash "${SKILL_DIR}/lib/commit-note.sh" "$VAULT" "$NOTE" "$SUMMARY" "$REPO"`.
It stages and commits **only** `NOTE` (pathspec on both `git add` and
`git commit`), retries `.git/index.lock` with exponential backoff, treats an
obsidian-git preemption as success, and never contacts a remote. Pass its
warnings through verbatim; never let them change the exit code.

## Step 7: Verify and report

Run `bash "${SKILL_DIR}/lib/verify-clip.sh" "$NOTE"` (skip on `--dry-run`), show **all output lines verbatim** (each line begins with `[OK]` or `[FAIL]`), then the note path, and as the **last line**: `/ingest <NOTE>`.

## Constraints

- Vault commits are pathspec-only — never `-a` / `-A` / `git add .`.
- Never synchronise the vault to its remote; obsidian-git owns that.
- Never dump the transcript, never merge several sessions into one note.
- Never modify code, never run `/ingest` — the vault's human gate is the point.

## Related Skills

- [[notes:task-history]] 는 일자별 daily log 에 append 하고, [[session:handoff]]
  는 *미완* 작업을 이슈 코멘트로 넘긴다 — 이 스킬은 *완료* 기록을 vault 노트
  1개로 남긴다 (Web Clipper 가 "웹페이지 → Inbox" 라면 이 스킬은 "세션 → Inbox").
- 옵션·env 상세는 `references/help.md` / `references/options.md`.
