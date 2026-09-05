# pkm:obsidian-session-clip — 옵션 / 환경변수 상세

## 인자 파싱

```
/pkm:obsidian-session-clip [description] [--no-commit] [--dry-run] [--vault <path>]
```

`[description]` 은 위치 인자이며, 플래그가 아닌 첫 토큰들을 공백으로 이어
붙인 것이다. 없어도 되고, 있으면 제목·요약 생성의 힌트로 우선한다.

| Option | 타입 | 동작 |
|---|---|---|
| `[description]` | 위치 | 추가 컨텍스트. `title` 과 `## 요약` 작성 시 최우선 힌트 |
| `--no-commit` | 플래그 | 실행 흐름 8단계(커밋)를 건너뛴다. 노트는 정상 생성 |
| `--dry-run` | 플래그 | 경로와 본문 전체를 stdout 에 출력만 한다. 디렉토리 생성·파일 쓰기·커밋 전부 없음 |
| `--vault <path>` | 값 | vault 루트. `OBSIDIAN_VAULT_DIR` 보다 우선 |
| `-h` / `--help` / `help` | 플래그 | `references/help.md` verbatim 출력 후 정지. API 호출 없음 |

`--dry-run` 과 `--no-commit` 이 같이 오면 `--dry-run` 이 이긴다 (아무것도 쓰지 않음).

## 환경변수 / vault 해석 순서 (F-1, dEitY719/dotfiles#1351)

vault 해석은 `lib/resolve-vault.sh [explicit-vault-path]` 가 구현하며, 우선순위는:

1. `--vault <path>` — 명시적 override, 최우선
2. `$OBSIDIAN_VAULT_DIR` — vault 루트를 지정하는 명시적 env override
   (`notes:task-history` 의 `TASK_HISTORY_DIR` 선례와 같은 이유: PC 마다 vault
   경로가 다르다)
3. `~/.dotfiles-setup-mode` 를 읽어 PC 모드별 기본값 (신규):

   | 모드 파일 값 | 해석 결과 |
   |---|---|
   | `internal` / `2` (legacy 숫자값) | `$HOME/para/project/obsidian-para-company` |
   | `external` / `public` / 빈 값 / 파일 없음 / 미인식 | `$HOME/para/project/obsidian-para` |

`internal` PC 2대는 사내용 vault(`obsidian-para-company`)가 WSL 상의 개인
`obsidian-para` 클론과 별도로 존재한다 ([dotfiles `shell-common/functions/obsidian_claude.sh`](https://github.com/dEitY719/dotfiles/blob/main/shell-common/functions/obsidian_claude.sh)
가 쓰는 vault 와도 다르다). 이 3단계는 vault 후보 문자열만 넓힌다.

출력 디렉토리는 항상 `<vault>/99-Inbox/ai-session/` 이다. vault 루트 자체가
없으면 **만들지 않고 정지**한다 (오타난 경로에 유령 vault 를 만들면 안 된다) —
이 판단은 `resolve-vault.sh` 가 아니라 SKILL.md Step 1 의 몫이다.
`99-Inbox/ai-session/` 만 없으면 `mkdir -p` 한다.

## 파일명 규칙 (F-2 / NF-1)

```
YYYY-MM-DD-HHmm-<repo>-<slug>.md
```

| 조각 | 규칙 |
|---|---|
| `YYYY-MM-DD-HHmm` | `date '+%Y-%m-%d-%H%M'` (로컬 시간) |
| `<repo>` | `basename $(git rev-parse --show-toplevel)`. git 저장소가 아니면 `none` |
| `<slug>` | 세션 한 줄 요약을 소문자 ASCII 로 축약. 공백·`_` 는 `-`, 연속 `-` 는 1개로, 앞뒤 `-` 제거. 3~6단어 |

조립한 stem 은 반드시 `lib/safe-name.sh` 를 통과시킨다:

```bash
STEM="$(bash "${SKILL_DIR}/lib/safe-name.sh" sanitize "$RAW_STEM")"
NOTE="$(bash "${SKILL_DIR}/lib/safe-name.sh" resolve "$OUT_DIR" "$STEM")"
```

`sanitize` 는 `\ / : * ? " < > |` 와 제어문자를 제거하고 100자로 자른다.
남는 글자가 없으면 조용히 넘어가지 않고 non-zero 로 죽는다 (NF-1).
`resolve` 는 충돌 시 `-2` … `-10` 을 붙이고, 10개가 모두 차면 정지한다 (F-2).

## 커밋 (F-7 / NF-2)

```bash
bash "${SKILL_DIR}/lib/commit-note.sh" "$VAULT" "$NOTE" "$SUMMARY" "$REPO"
```

커밋 제목: `clip: <SUMMARY> (<REPO>)`.
`git add -- <파일>` / `git commit -- <파일>` 로 pathspec 을 한정한다.
`-a` / `-A` / `git add .` 는 금지다 — 병렬 세션의 노트를 삼킨다.
원격 동기화는 하지 않는다 (NF-3).

## 자체검증

```bash
bash "${SKILL_DIR}/lib/verify-clip.sh" "$NOTE"
```

`--dry-run` 이 아닐 때 매 실행 끝에 돌린다. FAIL 이 하나라도 나오면 사용자에게
그대로 보여준다 — 설계 제약이 조용히 깨지는 것을 막는 장치다.
