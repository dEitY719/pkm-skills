# obsidian-session-clip 사용 결과

> **한 줄 요약** — 끝난 AI 세션을 받아 vault Inbox 의 markdown 노트 1개를 생성합니다.

```
AI 세션  ──▶  /pkm:obsidian-session-clip  ──▶  99-Inbox/ai-session/<stem>.md
```

## 1. 실행한 명령

```
/pkm:obsidian-session-clip [description] [--no-commit] [--dry-run] [--vault <path>]
```

이번 예시 — 개인 vault 무변경을 위해 `--dry-run` 경로로 실행했습니다:

```
/pkm:obsidian-session-clip pkm-skills 스킬 문서화 및 HTML 시각화 --dry-run
```

## 2. 입력

- 세션: 이 대화 (pkm 4개 스킬의 guide/usage 문서화)
- vault: `lib/resolve-vault.sh` 해석 결과 `/home/bwyoon/para/project/obsidian-para`
  (`--vault` 없음, `$OBSIDIAN_VAULT_DIR` 없음, `~/.dotfiles-setup-mode` = `external`)
- git 컨텍스트: repo `pkm-skills-feat-1`, branch `wt/feat/1`, `main..HEAD` 커밋 0개

## 3. 결과

```
분류    session_type: research   (커밋 0개, PR 없음)
파일명  safe-name.sh sanitize -> 2026-09-01-1634-pkm-skills-feat-1-skill-docs-html-visualization
예약    safe-name.sh resolve -> 빈 파일로 원자적 예약 (reserved? yes)
NOTE    /home/bwyoon/para/project/obsidian-para/99-Inbox/ai-session/
        2026-09-01-1634-pkm-skills-feat-1-skill-docs-html-visualization.md

[DRY-RUN] 본문 출력 후 rm -f 로 예약 해제 -> 파일 미생성 (gone)
Step 6 커밋, Step 7 verify-clip.sh 는 --dry-run 이므로 미실행

/ingest <NOTE>
```

무변경 확인: 실행 후 vault `git status --short` 0줄.
