# pkm:obsidian-resolve-conflict — 인자 / 환경변수 / 경로 해석

## 인자 파싱 (F-1)

```
/pkm:obsidian-resolve-conflict [windows|wsl] [--no-push] [--no-sync-peer] [--dry-run] [--vault <path>]
```

| Option | 타입 | 동작 |
|---|---|---|
| `[windows\|wsl]` | 위치 | 해결할 클론. 기본값 `windows` (obsidian-git 이 도는 쪽) |
| `--no-push` | 플래그 | Step 6 을 건너뛴다. 커밋까지만 |
| `--no-sync-peer` | 플래그 | Step 7 을 건너뛴다. peer 클론 무접촉 |
| `--dry-run` | 플래그 | 분류·계획만 출력. `classify-conflicts.sh` 를 `--apply` 없이 부르고, merge/commit/push/peer 를 전부 생략한다 (NF-5) |
| `--vault <path>` | 값 | vault 루트. 모든 탐지보다 우선 |
| `-h` / `--help` / `help` | 플래그 | `references/help.md` verbatim 출력 후 정지. API 호출·git 쓰기 없음 |

`--dry-run` 은 `--no-push` / `--no-sync-peer` 를 포함한다 (가장 강한 플래그).
위치 인자가 `windows`/`wsl` 둘 다 아니면 오류로 정지한다 — 오타를 경로로 오해하지 않는다.

## 경로 해석 우선순위 (F-2, NF-8)

전부 `lib/resolve-vault.sh` 가 수행한다. 스킬은 다음 한 줄로 결과를 받는다:

```bash
eval "$(bash "${SKILL_DIR}/lib/resolve-vault.sh" "$SIDE" ${VAULT_OPT:+--vault "$VAULT_OPT"})"
```

**windows**

1. `--vault <path>`
2. `$OBSIDIAN_VAULT_WIN_DIR`
3. glob `${OBSIDIAN_VAULT_WIN_ROOT:-/mnt/c/Users}/*/Documents/${OBSIDIAN_VAULT_WIN_NAME:-ObsidianVault-PARA}`
   — **정확히 1개** 매칭일 때만 채택
4. `cmd.exe /c echo %USERNAME%` 로 조합한 경로가 존재하면 채택
5. 실패 → 시도한 후보를 전부 출력하고 정지

**wsl**

1. `--vault <path>`
2. `$OBSIDIAN_VAULT_DIR`
3. `${OBSIDIAN_VAULT_WSL_ROOT:-$HOME/para/project}` 아래
   `obsidian-para-company` / `obsidian-para` 중 **존재하는** 것.
   둘 다 존재하면 모드가 정한다 (`internal` → company, `external`/`public` → personal).
   모드 불명 + 둘 다 존재 → 두 경로를 출력하고 정지
4. 실패 → 후보를 출력하고 정지

glob 이 사용자명 차이를 흡수한다 — Windows 사용자명 ≠ WSL 사용자명이므로
`/mnt/c/Users/$USER/...` 는 **어느 PC에서도 맞지 않는다** ([dotfiles `docs/.ssot/pc-environment.md`](https://github.com/dEitY719/dotfiles/blob/main/docs/.ssot/pc-environment.md) §1).

해석된 경로가 없거나 git 저장소가 아니면 **정지**한다. 디렉터리를 만들지 않는다 (NF-4).

## `resolve-vault.sh` 출력 (eval 가능)

| Key | 의미 |
|---|---|
| `MODE` | `public` / `internal` / `external` / 빈 문자열 |
| `SIDE` | `windows` / `wsl` |
| `VAULT` | 해석된 대상 절대경로 |
| `VAULT_ORIGIN` | `git remote get-url origin` |
| `REMOTE` | vault 의 git remote 이름 (항상 `origin`) — fetch/push 대상 |
| `BRANCH` / `UPSTREAM` | 현재 브랜치와 그 upstream (없으면 빈 문자열) |
| `BACKUP_SHA` | 시작 시점 HEAD — 되돌리기 기준점 |
| `PEER` / `PEER_ORIGIN` | 반대편 클론과 그 origin (없으면 빈 문자열) |
| `PEER_MATCH` | `yes` (origin 동일) / `no` (다름) / `none` (peer 없음) |
| `PUSH_ALLOWED` | `yes` / `no` — NF-7 하드 가드 결과 |
| `PUSH_BLOCK_REASON` | `no` 일 때의 사유 (사용자에게 그대로 보여준다) |

`PUSH_ALLOWED=no` 는 `--no-push` 를 주지 않았어도 **F-6 기본 push 를 이긴다**.

## 환경변수

| Variable | 기본값 | 비고 |
|---|---|---|
| `OBSIDIAN_VAULT_WIN_DIR` | — | Windows 클론 직접 지정 |
| `OBSIDIAN_VAULT_DIR` | — | WSL 클론 직접 지정. `pkm:obsidian-session-clip` 과 같은 변수 |
| `OBSIDIAN_VAULT_WIN_ROOT` | `/mnt/c/Users` | glob 루트 |
| `OBSIDIAN_VAULT_WIN_NAME` | `ObsidianVault-PARA` | vault 폴더명. 폴더명이 다른 PC 를 만나면 여기로 흡수한다 |
| `OBSIDIAN_VAULT_WSL_ROOT` | `$HOME/para/project` | WSL 클론 부모 |
| `DOTFILES_SETUP_MODE_FILE` | `$HOME/.dotfiles-setup-mode` | 모드 파일 위치 (테스트 격리용) |

## lib 스크립트 직접 호출

```bash
bash lib/resolve-vault.sh [windows|wsl] [--vault <path>] [--mode <mode>]
bash lib/classify-conflicts.sh <vault-dir> [--apply]
bash lib/verify-sync.sh <vault-dir> [--peer <path>] [--resolved <path>]...
```

셋 다 `-h` / `--help` / `help` 로 자체 usage 를 출력한다.
`classify-conflicts.sh` 는 `--apply` 없이는 **아무것도 쓰지 않는다** — 이것이
`--dry-run` 의 구현이다.
