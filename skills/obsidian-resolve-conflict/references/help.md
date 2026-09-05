# pkm:obsidian-resolve-conflict — Help

Obsidian vault 클론의 `git pull` 충돌을 진단 → 분류 → 해결 → 커밋 → push →
peer 클론 동기화까지 한 번에 처리한다. 대상은 같은 원격을 보는 두 클론
(`windows` / `wsl`) 이고, `~/.dotfiles-setup-mode` 를 읽어 사내PC 와 개인PC 를
같은 명령으로 다룬다.

## Usage

```
/pkm:obsidian-resolve-conflict [windows|wsl] [--no-push] [--no-sync-peer] [--dry-run] [--vault <path>]
```

## Options

| Option | Description | Default |
|---|---|---|
| `[windows\|wsl]` | 해결할 클론 | `windows` |
| `--no-push` | 커밋까지만 하고 원격에 반영하지 않는다 | push 함 |
| `--no-sync-peer` | 반대편 클론을 건드리지 않는다 | 동기화 시도 |
| `--dry-run` | 분류와 계획만 출력. 인덱스/워킹트리 불변 | off |
| `--vault <path>` | vault 루트를 명시한다 (env 보다 우선) | 런타임 탐지 |
| `-h`, `--help`, `help` | 이 도움말을 출력하고 정지 | — |

## Environment

| Variable | Description |
|---|---|
| `OBSIDIAN_VAULT_WIN_DIR` | Windows 쪽 클론 경로 |
| `OBSIDIAN_VAULT_DIR` | WSL 쪽 클론 경로 |
| `OBSIDIAN_VAULT_WIN_ROOT` | Windows 사용자 홈 루트 (기본 `/mnt/c/Users`) |
| `OBSIDIAN_VAULT_WIN_NAME` | vault 폴더명 (기본 `ObsidianVault-PARA`) |
| `OBSIDIAN_VAULT_WSL_ROOT` | WSL 클론 부모 (기본 `$HOME/para/project`) |

경로는 **하드코딩하지 않는다** — Windows 사용자명과 WSL 사용자명이 PC마다 다르다
([dotfiles `docs/.ssot/pc-environment.md`](https://github.com/dEitY719/dotfiles/blob/main/docs/.ssot/pc-environment.md) §1). 해석 우선순위는 `references/options.md`.

## 충돌 3분류 (F-4)

| 분류 | 대상 | 처리 |
|---|---|---|
| **A. 로컬 상태** | `conflict-files-obsidian-git.md` | 자동 삭제 (플러그인 아티팩트) |
| | 지금 `.gitignore` 가 제외 중인 `.obsidian/**`·`.trash/**` | `git rm --cached` — 인덱스에서만 제거, **디스크 파일 유지** |
| **B. 노트 본문** | vault 의 `*.md` | **자동 병합 없음.** 파일별 요약 + 3택을 제시하고 사용자가 고른다 |
| **C. 나머지** | `.gitignore`, `docs/**`, 제외 대상이 아닌 `.obsidian/*.json` | B 와 동일 |

경계는 "`.obsidian/` 아래냐"가 아니라 "**지금 `.gitignore` 가 추적 제외로
선언했느냐**"다. 자세한 규칙과 명령은 `references/classify.md`.

## Safety

- **merge 전용.** vault 히스토리를 재작성하지 않고, 강제 push 도 하지 않는다 (NF-1).
- 노트 본문은 절대 자동 병합하지 않는다 (NF-3).
- vault 를 새로 만들지 않는다. 경로가 없으면 출력하고 정지한다 (NF-4).
- `--dry-run` 은 인덱스와 워킹트리를 바꾸지 않는다 (NF-5).
- `.git/index.lock` 은 지수 백오프로 재시도만 한다. **강제 삭제 금지** (NF-6).
- `internal` 모드 PC 에서 `github.com` 원격으로의 push 는 **거부**된다 (NF-7,
  SSOT [`docs/.ssot/pc-environment.md`](https://github.com/dEitY719/dotfiles/blob/main/docs/.ssot/pc-environment.md) §3). GHES 원격은 정상 push.
- 시작할 때 `BACKUP_SHA` 를 출력한다. 되돌리기는 커밋 전이면 `git merge --abort`,
  커밋 후면 `git revert -m 1 <merge-sha>` 다.

## Errors

| 상황 | 동작 |
|---|---|
| Windows glob 0개 매칭 | 시도한 후보 출력 + `--vault` 안내 후 정지 |
| Windows glob 2개 이상 매칭 | 매칭 목록 출력 후 정지 (임의 선택 금지) |
| WSL 후보 2개 + 모드 불명 | 두 경로 출력 후 정지 |
| `--vault` 경로 없음 | 해석된 경로 출력 후 정지. 디렉터리 생성 안 함 |
| git 저장소 아님 | 경로와 함께 정지 |
| 충돌 없음 | "해결할 충돌 없음" + ahead/behind 출력 후 정상 종료 (멱등) |
| `.git/index.lock` 재시도 실패 | obsidian-git 이 도는 중일 수 있다고 안내 후 정지 |
| 머지가 아닌 작업 진행 중 | 정지하고 사용자에게 정리를 요구 |
| B/C 결정 보류 | 커밋하지 않고 머지 진행 상태 유지 + 재개 방법 안내 |
| `internal` + `github.com` push | 거부 + "external/public PC 에서 push" 안내 |
| peer 가 dirty / ff 불가 / origin 불일치 | 건드리지 않고 경고 1줄. 대상 해결은 성공 |
| push 거부 (non-fast-forward) | 강제 재시도 없음. 스킬 재실행 안내 |

## Related

- `references/options.md` — 인자·env·경로 해석 우선순위
- `references/classify.md` — F-4 분류 규칙과 자동 처리 명령
- `references/merge-flow.md` — 진입 상태 3종 절차, 커밋 메시지, peer 동기화
- `references/pc-modes.md` — 모드 인지와 런타임 탐지 (SSOT 참조)
- 형제 스킬 `gh-resolve:conflict` — PR 브랜치 전용, 히스토리 재작성 방식
- 이웃 스킬 `pkm:obsidian-session-clip` — 같은 vault 를 다루지만 원격은 건드리지 않는다
