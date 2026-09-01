# obsidian-resolve-conflict

## 한 줄 요약

Obsidian vault 의 `git pull` 충돌을 분류·해결한 뒤 **merge 커밋 1개**를 만들고 push 하고,
가능하면 짝(peer) 클론까지 fast-forward 한다. 산출물은 동기화된 vault 상태다.

## 언제 쓰고, 언제 안 쓰나

| 상황 | 이 스킬 | 대신 쓸 것 |
|------|:------:|-----------|
| vault 클론 두 개가 갈라져 pull 이 충돌 | 예 | |
| PR 브랜치 충돌 | 아니오 | `gh:pr-resolve-conflict` |
| 세션 기록을 vault 에 남기기 | 아니오 | `pkm:obsidian-session-clip` |

형제 `gh:pr-resolve-conflict` 는 히스토리 재작성과 강제 push 로 푼다. 이 스킬은
**merge 로만** 푼다 — vault 에는 사람이 직접 쓴 노트가 들어 있기 때문이다.

## 호출 형식

```
/pkm:obsidian-resolve-conflict [windows|wsl] [--no-push] [--no-sync-peer] [--dry-run] [--vault <path>]
/pkm:obsidian-resolve-conflict -h
```

| 인자 | 뜻 |
|------|-----|
| `windows` \| `wsl` | 어느 쪽 클론에서 푸는지 (기본 `windows`) |
| `--no-push` | 커밋까지만 하고 push 하지 않는다 |
| `--no-sync-peer` | 짝 클론 fast-forward(Step 7)를 건너뛴다 |
| `--dry-run` | `classify-conflicts.sh` 를 `--apply` 없이 돌려 아무것도 쓰지 않는다 |
| `--vault <path>` | vault 경로 직접 지정 |

## 동작 단계

1. **인자 + vault/peer 해석** — `lib/resolve-vault.sh` 가 `MODE SIDE VAULT REMOTE BRANCH
   UPSTREAM BACKUP_SHA PEER PEER_MATCH PUSH_ALLOWED` 를 한 번에 내보낸다. 0 이 아닌 종료는 치명적이다.
2. **preflight + 진입 상태 판별** — `BACKUP_SHA` 를 **가장 먼저** 출력한다.
   진입 상태는 셋 중 하나로 갈린다: merge 진행 중 / merge 이전 / 더티 트리.
   충돌도 없고 뒤처지지도 않았으면 "해결할 충돌 없음"을 찍고 멱등 정지한다.
3. **분류 후 해결** — `lib/classify-conflicts.sh`.
   - **class A** (obsidian-git 아티팩트, `.gitignore` 가 이미 제외 중인 `.obsidian/**` 같은
     로컬 상태 파일) 만 스크립트가 자동 해결한다.
   - **class B (노트 본문 `*.md`) 와 class C 는 사용자 결정이다.** 파일별 요약과 3개 선택지를
     제시하고 기다린다. 보류도 정당한 결과다.
4. **merge 커밋** — `ls-files -u` 가 빌 때까지 커밋하지 않는다. 파일별 근거를 메시지에 넣는다.
5. **push** — `PUSH_ALLOWED=no` 는 기본값과 `--no-push` 부재를 모두 이긴다.
   non-fast-forward 로 거절되면 그대로 드러내고 정지한다.
6. **peer fast-forward** — `PEER_MATCH=yes`, peer clean, `--ff-only` 세 관문이 모두 서야 한다.
   하나라도 실패하면 경고 한 줄이지 실패한 실행이 아니다.
7. **검증 + 보고** — `lib/verify-sync.sh` 의 FAIL/SUGGEST 줄을 그대로 출력한다.
   마지막 줄은 `[OK] 해결 완료`, `[FAIL] <reason>`, 또는 실행 가능한 후속 명령 하나다.

## 주의사항

이 스킬은 파괴적이며, 아래는 권고가 아니라 하드 룰이다.

- merge 전용. vault 히스토리를 재작성하지 않고, 거절된 push 를 절대 강행하지 않는다.
- worktree/index 를 파괴적으로 reset 하지 않고, 디렉터리 트리를 지우지 않는다.
- **노트 본문은 절대 자동 병합하지 않는다.** 파일별 요약을 제시하고 사용자가 고른다.
- vault 를 만들지 않는다. 해석 실패한 경로는 정지이지 `mkdir` 이 아니다.
- `.git/index.lock` 을 삭제하지 않는다. 백오프하며 기다린다.
- 승인받지 않은 해결을 실행하기 전에 `AskUserQuestion` 으로 확인한다.
