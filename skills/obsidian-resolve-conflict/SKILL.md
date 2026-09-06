---
name: obsidian-resolve-conflict
description: >-
  Obsidian vault 의 `git pull` 충돌을 진단·분류·해결·커밋·push 한다. Use for
  /pkm:obsidian-resolve-conflict, "볼트 충돌 해결",
  "vault 머지 충돌 풀어줘", "resolve my obsidian vault conflict". Do NOT use
  for PR 브랜치 — use gh-resolve:conflict instead.
allowed-tools: Bash, Read, Edit, Write, Grep
license: MIT
metadata:
  model_recommendation:
    tier: opus
    reason: "note-body conflicts need user-intent inference and a wrong pick silently destroys the user's writing; the automatic half must stay strictly inside the local-state boundary while every destructive shortcut is refused"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-resolve-conflict — vault pull 충돌 해결

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop. No API calls, no git writes.

## Step 1: Args + vault/peer

`SKILL_DIR` = this file's directory. Parse per `references/options.md`:
`[windows|wsl]` (default `windows`), `--no-push`, `--no-sync-peer`, `--dry-run`,
`--vault <path>`. Then

```bash
eval "$(bash "${SKILL_DIR}/lib/resolve-vault.sh" "$SIDE" ${VAULT_OPT:+--vault "$VAULT_OPT"})"
```

It sets `MODE SIDE VAULT VAULT_ORIGIN REMOTE BRANCH UPSTREAM BACKUP_SHA
PEER PEER_ORIGIN PEER_MATCH PUSH_ALLOWED PUSH_BLOCK_REASON` (mode detection
per `references/pc-modes.md`). A non-zero exit is fatal — surface its stderr
verbatim and stop. **Never** create a directory to make a path resolve.

## Step 2-3: Preflight + entry state

Print `BACKUP_SHA` first so the user can undo without you, then run
`references/merge-flow.md` → "Step 2 preflight" (`.git/index.lock` is waited out,
never deleted; a non-merge operation in flight → stop) and "Step 3", which routes
the three entry states — mid-merge / pre-merge / dirty-tree. `git fetch`, then
surface the conflict with `git merge` only when the state calls for it. No conflicts
and nothing behind → "해결할 충돌 없음" + ahead/behind, stop (idempotent).

## Step 4: Classify, then resolve

```bash
bash "${SKILL_DIR}/lib/classify-conflicts.sh" "$VAULT" ${APPLY:+--apply}
```

`--dry-run` omits `--apply`, so nothing is written. Class A — obsidian-git
아티팩트와 지금 `.gitignore` 가 제외 중인 `.obsidian/**` 같은 **로컬 상태
파일뿐** — is resolved by the script; **class B (노트 본문 `*.md`) and C are the
user's decision** — present the per-file diff summary and the 3 options from
`references/classify.md`, never guess. Deferring is a valid outcome:
leave the merge in progress, say how to resume, stop.

## Step 5-6: Merge commit + push

Commit only once `git -C "$VAULT" ls-files -u` is empty; message template (per-file
rationale) in `references/merge-flow.md` → "Step 5". Never `-a` / `-A` / `git add .`.
Then push — except `PUSH_ALLOWED=no` beats the default and the absence of
`--no-push`: print `PUSH_BLOCK_REASON`, commit only, push from an `external`/`public`
PC instead. A non-fast-forward rejection stops the run; never escalate it.

## Step 7-8: Peer fast-forward + nested `90-personal/`

Skip Step 7 on `--no-sync-peer`. Otherwise all three gates in
`references/merge-flow.md` → "Step 7" (`PEER_MATCH=yes`, peer clean, `--ff-only`)
must hold; any failing is one warning line, not a failed run. Step 8 is report-only.

## Step 9: Verify + report

```bash
bash "${SKILL_DIR}/lib/verify-sync.sh" "$VAULT" ${PEER:+--peer "$PEER"} ${RESOLVED:+--resolved "$RESOLVED"}
```

Show every FAIL/SUGGEST line from `verify-sync.sh` verbatim; never edit `.gitignore`.
**Last line** = `[OK] 해결 완료`, `[FAIL] <reason>`, or one runnable pending
follow-up command (`/pkm:obsidian-resolve-conflict <side> --vault <vault>/90-personal`); never bare `해결 완료`.

## Constraints

merge 전용 — vault 히스토리 재작성도, 파괴적 reset 도, 디렉터리 트리 삭제도 없다.
사용자의 노트가 여기 산다. PC 표는 `references/pc-modes.md` 가 링크한 dotfiles SSOT
에서만 읽고, 이 파일로 복사하지 않는다. (index.lock · 노트 본문 자동 병합 · push
에스컬레이션 · vault 생성 금지는 각각 Step 2-3 / 4 / 5-6 / 1 에 인라인으로 있다.)

## Related Skills

형제 [[gh-resolve:conflict]] 는 PR 브랜치를 히스토리 재작성 + 강제 push 로 풀지만
이쪽은 vault 를 merge 로만 푼다. 이웃 [[pkm:obsidian-session-clip]] 은 원격을
건드리지 않지만 이 스킬은 원격 동기화가 목적이다. 옵션·env: `references/options.md`.
