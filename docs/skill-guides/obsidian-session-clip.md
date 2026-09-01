# obsidian-session-clip

## 한 줄 요약

끝난 AI 세션 하나를 PARA vault 의 `99-Inbox/ai-session/` 아래 **markdown 노트 1개**로
남기고, 그 파일 하나만 커밋한다. 산출물은 항상 파일 1개다.

## 언제 쓰고, 언제 안 쓰나

| 상황 | 이 스킬 | 대신 쓸 것 |
|------|:------:|-----------|
| 완료된 세션을 vault 에 보관 | 예 | |
| 일자별 daily log 에 누적 기록 | 아니오 | `write:task-history` |
| 미완 작업을 다음 세션에 인계 | 아니오 | `devx:session-handoff` |
| vault 를 원격과 동기화 | 아니오 | `pkm:obsidian-resolve-conflict` |

이웃 스킬 `pkm:obsidian-resolve-conflict` 와 vault 는 공유하지만 remote 는 공유하지
않는다. 이 스킬은 원격을 **절대** 건드리지 않는다 — vault 동기화는 obsidian-git 소관이다.

**명시 호출 전용이다.** "세션이 끝난 것 같다"는 호출 근거가 아니다.

## 호출 형식

```
/pkm:obsidian-session-clip [description] [--no-commit] [--dry-run] [--vault <path>]
/pkm:obsidian-session-clip -h
```

| 인자 | 뜻 |
|------|-----|
| `description` | 플래그가 아닌 토큰들이 합쳐져 파일명 slug 와 제목의 재료가 된다 |
| `--no-commit` | 노트는 쓰되 커밋은 건너뛴다 |
| `--dry-run` | 경로와 본문만 출력하고 아무것도 쓰지 않는다 (`--no-commit` 보다 우선) |
| `--vault <path>` | vault 경로 직접 지정 |

vault 해석 우선순위: `--vault` > `$OBSIDIAN_VAULT_DIR` > `~/.dotfiles-setup-mode` 기반 기본값
(`internal` 이면 `obsidian-para-company`, 그 외 `obsidian-para`).

## 동작 단계

1. **인자 + vault 해석** — `lib/resolve-vault.sh`. vault 가 없으면 경로를 찍고 정지한다.
2. **git 컨텍스트 + 분류** — vault 가 아니라 **현재 작업 repo** 에서 repo/branch/커밋을 읽는다.
   커밋 1개 이상 또는 PR 생성이 있었으면 `session_type: code`, 아니면 `research`.
3. **본문 작성** — frontmatter 9개 키 고정 순서, 본문은 code/research 템플릿의 섹션 제목과
   순서를 그대로 따른다. `## 메모` 3개 하위 섹션을 모두 채운다.
4. **파일명 확정** — `safe-name.sh sanitize` 로 Windows 안전 이름을 만들고,
   `safe-name.sh resolve` 가 빈 파일을 만들어 이름을 **원자적으로 예약**한다
   (병렬 세션 경합 차단).
5. **쓰기** — 이 단계가 목표다. 이후는 전부 best-effort.
6. **커밋** — `commit-note.sh` 가 **pathspec 으로 그 파일 하나만** stage/commit 한다.
7. **검증 + 보고** — `verify-clip.sh` 의 `[OK]`/`[FAIL]` 줄을 그대로 출력하고,
   마지막 줄은 `/ingest <NOTE>`.

## 주의사항

- 커밋은 pathspec 전용이다. `-a`, `-A`, `git add .` 는 금지 — 병렬 세션의 노트를 삼킨다.
- 원격에 절대 접속하지 않는다.
- vault 경로가 없으면 만들지 않고 정지한다. 오타난 경로에 vault 를 생성하지 않는다.
- transcript 를 덤프하지 않고, 여러 세션을 노트 하나로 합치지 않는다.
- `/ingest` 는 사람이 실행한다. 이 스킬이 대신 돌리지 않는다 — vault 의 사람 게이트가 요점이다.
- `memo: ai-generated` 는 "승인 대상이 아니라 교정 대상"이라는 뜻이다.
