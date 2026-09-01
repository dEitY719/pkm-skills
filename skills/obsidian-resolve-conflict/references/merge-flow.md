# pkm:obsidian-resolve-conflict — 진입 상태 / 머지 / 커밋 / 동기화

vault 는 obsidian-git 이 여러 PC에서 자동 백업 커밋을 찍는 저장소다. 그래서
통합 방식은 **merge 하나뿐**이고, 히스토리 재작성은 하지 않는다 (NF-1):
자동 백업 커밋 덩어리를 재작성하면 커밋마다 같은 충돌이 반복되고 강제 push 가
불가피해진다. obsidian-git 플러그인 설정도 `syncMethod: merge` 다.

## Step 2 preflight

```bash
git -C "$VAULT" status --short --branch
```

- `BACKUP_SHA` (resolve-vault.sh 출력) 를 사용자에게 먼저 보여준다. 되돌리기는
  커밋 전이면 `git merge --abort`, 커밋 후면 `git revert -m 1 <merge-sha>` 다.
- `.git/index.lock` 이 잡혀 있으면 기다린다. **지우지 않는다** (NF-6).
  인덱스를 만지는 작업은 `classify-conflicts.sh --apply` 안에서 백오프 재시도된다.
- 머지가 아닌 작업(cherry-pick / revert / 히스토리 편집)이 진행 중이면
  `classify-conflicts.sh` 가 정지시킨다. 사용자에게 정리를 요구하고 끝낸다.

## Step 3 진입 상태 3종 (F-3)

사용자는 아무 상태에서나 이 스킬을 부른다. 먼저 판정한다:

```bash
git -C "$VAULT" ls-files -u            # 비어 있지 않다 = 머지 진행 중
git -C "$VAULT" rev-parse -q --verify MERGE_HEAD
git -C "$VAULT" fetch "$REMOTE" "$BRANCH"
```

| 상태 | 판정 | 절차 |
|---|---|---|
| 1. 머지 진행 중 | unmerged path 있음 + `MERGE_HEAD` 있음 | 그대로 Step 4 로 (이어서 해결) |
| 2. 머지 전 | unmerged 없음, dirty 아님 | `fetch` 후 behind 면 `git merge "$UPSTREAM"` 로 충돌을 표면화 |
| 3. dirty | unmerged 없음, 추적 파일이 dirty | **머지 시작 전에** Step 4 분류를 먼저 적용해 A 를 걷어내고, 남은 dirty 는 사용자에게 묻는다. 그 다음 상태 2 로 |

`UPSTREAM` 이 없으면 `"$REMOTE/$BRANCH"` 를 쓴다. 현재 브랜치와 그 upstream 을
그대로 따르며, 브랜치를 바꾸지 않는다.

fetch 후 behind 가 0 이고 unmerged 도 없으면 **"해결할 충돌 없음"** 을 출력하고
ahead/behind 만 보여준 뒤 정상 종료한다 (멱등).

## Step 5 머지 커밋 (F-5)

해결 근거를 본문에 남긴다. 무엇을 왜 그렇게 처리했는지가 다음 재발 때의 근거다.

```
merge: vault pull 충돌 해결 (<N>건)

- .obsidian/graph.json: 원격의 추적 제외를 채택 (git rm --cached). 디스크 파일 유지
- conflict-files-obsidian-git.md: obsidian-git 아티팩트 삭제
- 40-Areas/dev/note.md: 사용자 결정 — 로컬 유지

분류: A=2 (자동) B=1 (사용자) C=0
```

커밋 전 확인: `git -C "$VAULT" ls-files -u` 가 비어 있어야 한다. B/C 가 하나라도
남아 있으면 커밋하지 않고 정지한다.

```bash
git -C "$VAULT" commit --no-edit -m "$SUBJECT" -m "$BODY"
```

`-a` / `-A` / `git add .` 는 쓰지 않는다 — 다른 세션의 노트나 사용자의 dirty
파일을 삼킨다. 머지 해결로 스테이지된 것만 커밋한다.

## Step 6 push (F-6 / NF-7)

```bash
[ "$PUSH_ALLOWED" = "yes" ] || { echo "$PUSH_BLOCK_REASON"; }   # NF-7 이 F-6 을 이긴다
git -C "$VAULT" push "$REMOTE" "$BRANCH"
```

- `--no-push` 또는 `PUSH_ALLOWED=no` 면 **커밋까지만** 하고 사유를 출력한다.
  `internal` 모드 PC 의 `github.com` 원격은 pull only 이므로
  "external/public PC 에서 push 하라"고 안내한다.
- non-fast-forward 로 거부되면 **강제 재시도하지 않는다.** 그 사이 원격이
  움직였다는 뜻이므로 스킬 재실행을 안내하고 끝낸다.

## Step 7 peer 클론 fast-forward (F-7)

세 조건을 **전부** 만족할 때만 당긴다. 하나라도 어긋나면 건드리지 않고 경고 1줄:

```bash
[ "$PEER_MATCH" = "yes" ]                                   # 1. origin 이 대상과 동일
[ -z "$(git -C "$PEER" status --porcelain)" ]               # 2. working tree clean
git -C "$PEER" fetch "$REMOTE" "$BRANCH" \
  && git -C "$PEER" merge --ff-only "$REMOTE/$BRANCH"       # 3. fast-forward 만
```

`--ff-only` 가 조건 3 을 git 에게 강제시킨다 — 실패하면 peer 에 로컬 커밋이
있다는 뜻이고, 그건 peer 를 대상으로 스킬을 다시 실행할 일이다. 대상 vault 의
해결은 그대로 **성공**으로 처리한다.

origin 이 다르면(`PEER_MATCH=no`) 절대 당기지 않는다 — 사내PC에서 windows(GHES
company) 와 wsl 후보(github.com personal)가 엇갈리는 사고를 구조적으로 막는다.

## Step 8 중첩 `90-personal/` (F-8)

사내 vault 루트의 `90-personal/` 은 그 `.gitignore` 에 등재된 **별도 clone** 이라
obsidian-git 이 보지 못한다. `verify-sync.sh` 가 status 만 읽어 리포트하고,
충돌이 있으면 `--vault <vault>/90-personal` 재실행을 안내한다. 자동으로 해결하지
않는다.

## Step 9 검증 (F-9)

```bash
bash "${SKILL_DIR}/lib/verify-sync.sh" "$VAULT" \
  ${PEER:+--peer "$PEER"} --resolved .obsidian/graph.json
```

FAIL 줄이 하나라도 나오면 그대로 사용자에게 보여준다. 자동 해결된 로컬 상태
파일이 아직 `.gitignore` 에 없으면 `SUGGEST:` 줄이 나온다 — **제안만** 하고
`.gitignore` 를 직접 고치지 않는다.
