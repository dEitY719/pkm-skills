# pkm:obsidian-session-clip — Help

이번 AI 세션에서 한 작업을 PARA vault 의 `99-Inbox/ai-session/` 에 md 노트
1개로 클립한다. Web Clipper 가 "웹페이지 → Inbox" 라면 이 스킬은
"세션 → Inbox" 다. 이후 처리는 vault 의 `/ingest` 가 맡는다.

## Usage

```
/pkm:obsidian-session-clip [description] [--no-commit] [--dry-run] [--vault <path>]
```

## Options

| Option | Description | Default |
|---|---|---|
| `[description]` | 노트에 얹을 추가 컨텍스트 한 줄 (제목·요약 힌트) | 대화에서 추론 |
| `--no-commit` | 노트 파일만 쓰고 vault 커밋을 생략한다 | 커밋함 |
| `--dry-run` | 생성될 경로와 본문만 출력하고 아무것도 쓰지 않는다 | off |
| `--vault <path>` | vault 루트를 명시한다 (env 보다 우선) | env / 기본 경로 |
| `-h`, `--help`, `help` | 이 도움말을 출력하고 정지 | — |

## Environment

| Variable | Description | Default |
|---|---|---|
| `OBSIDIAN_VAULT_DIR` | vault 루트 | 미설정 — 미설정이면 PC 모드 기반 기본 경로로 fallback (아래) |

우선순위: `--vault` > `OBSIDIAN_VAULT_DIR` > `~/.dotfiles-setup-mode` 기반 기본
경로. 모드별 경로 표는 `references/options.md`, 구현은
`lib/resolve-vault.sh -h` 가 SSOT 다.

## Output

```
<vault>/99-Inbox/ai-session/YYYY-MM-DD-HHmm-<repo>-<slug>.md
```

예) `2026-08-11-1530-dotfiles-agent-toolbox-order-refactor.md`

`HHmm` 과 `<repo>` 를 함께 넣는 이유는 병렬 세션 간 파일명 충돌 회피다.
그래도 겹치면 `-2`, `-3` … 으로 증가하고 10회를 넘기면 정지한다.

## Session type

| 조건 | `session_type` | 섹션 |
|---|---|---|
| 세션 중 커밋 1개 이상, 또는 PR 생성 | `code` | 요약 / 변경사항 / 설계 근거 / 검증 / 관련 / 다음 단계 / 메모 |
| 그 외 (조사·토론·의사결정만) | `research` | 질문 / 조사한 것 / 결론 / 근거 / 미해결 / 메모 |

## Safety

- 원격에 push 하지 않는다. vault 원격 동기화는 obsidian-git 소유다.
- 커밋은 **생성한 노트 1개만** 대상으로 한다 (`git add -- <파일>` +
  `git commit -- <파일>`). 다른 세션의 노트나 dirty 파일을 삼키지 않는다.
- `.git/index.lock` 이 잡혀 있으면 지수 백오프로 최대 5회 재시도한다.
  끝내 실패해도 노트는 디스크에 남고 종료 코드는 0 이다.
- 파일 쓰기 자체가 실패한 경우를 제외하면 항상 exit 0 이다.

## Errors

| 상황 | 동작 |
|---|---|
| vault 디렉토리 없음 | 경로를 출력하고 `--vault` 사용법을 안내한 뒤 정지 (임의 생성 금지) |
| vault 가 git 저장소가 아님 | 노트만 쓰고 커밋 생략 + 경고, exit 0 |
| `.git/index.lock` 5회 재시도 실패 | 노트 유지 + 경고, exit 0 |
| add~commit 사이에 obsidian-git 선점 | "이미 반영됨" 출력, exit 0 |
| 파일명 10회 충돌 | 정지 |
| 클립할 내용 없음 | 빈 노트를 만들지 않고 정지 |
| 현재 디렉토리가 git 저장소 아님 | `repo` / `branch` 를 `none` 으로 두고 계속 |

## Next

실행이 끝나면 마지막 줄에 다음 액션이 출력된다:

```
/ingest <생성된 경로>
```

## Related

- `references/options.md` — 옵션·env 상세
- `references/frontmatter.md` — F-3 frontmatter 스펙과 `/ingest` 계약
- `references/template-code.md` / `references/template-research.md` — 본문 골격
- `lib/verify-clip.sh <파일>` — 산출물 자체검증
- 인접 스킬: `notes:task-history` (일자별 daily log append),
  `session:handoff` (미완 작업의 세션 간 인수인계)
