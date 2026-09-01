# pkm:obsidian-resolve-conflict — 충돌 3분류 (F-4)

자동과 수동의 경계가 이 스킬의 핵심이다. 전부 `lib/classify-conflicts.sh` 가
판정하고, 자동 처리도 그 스크립트의 `--apply` 가 수행한다. 스킬이 분류 규칙을
직접 다시 구현하지 않는다.

```bash
bash "${SKILL_DIR}/lib/classify-conflicts.sh" "$VAULT"           # 분류만 (--dry-run)
bash "${SKILL_DIR}/lib/classify-conflicts.sh" "$VAULT" --apply   # A 자동 해결
```

출력은 한 줄 1경로:

```
A	delete	conflict-files-obsidian-git.md
A	rm-cached	.obsidian/graph.json
B	manual	40-Areas/dev/note.md
C	manual	.obsidian/appearance.json
SUMMARY: A=2 B=1 C=1
```

## 규칙표

| 분류 | 대상 | action | 처리 |
|---|---|---|---|
| **A. 로컬 상태 (자동)** | `conflict-files-obsidian-git.md` | `delete` | 항상 삭제. obsidian-git 이 만드는 아티팩트이며 언제든 다시 생성된다 |
| | `.obsidian/**` · `.trash/**` 중 **지금 `.gitignore` 에 매칭되고 인덱스에 있는** 경로 | `rm-cached` | `git rm --cached` — 인덱스에서만 제거, 디스크 파일 유지 |
| **B. 노트 본문 (수동)** | 그 밖의 `*.md` | `manual` | 자동 병합 금지 (NF-3). 사용자가 결정 |
| **C. 나머지 (수동)** | `.gitignore`, `docs/**`, 제외 대상이 **아닌** `.obsidian/*.json` (`app.json`, `appearance.json`, `community-plugins.json`, `plugins/obsidian-git/data.json`) | `manual` | B 와 동일 |
| | `90-personal/` 및 그 하위 | `nested-repo` | 자동 해결 **제외**. 경고와 권장 명령만 (F-8) |

## 경계 기준

`.obsidian/` 아래냐가 아니라 **지금 `.gitignore` 가 추적 제외로 선언했느냐**다.

- gitignore 에 있다 = "이건 PC마다 다르니 추적하지 말자"는 결정이 **이미
  내려져 있다**는 뜻 → 자동 해결의 근거가 된다.
- `appearance.json` 처럼 **동기화가 목적인** `.obsidian` 파일은 제외 대상이
  아니므로 자동으로 건드리면 안 된다 → C.

판정은 `git check-ignore --no-index -q -- <path>` 다. `--no-index` 가 필수인
이유: 그것 없이는 git 이 **추적 중인** 경로를 "ignored 아님"으로 답한다. 그런데
class A 가 노리는 대상이 정확히 "추적 중이지만 제외 선언된" 경로다.

## `--apply` 가 실행하는 명령

```bash
git -C "$VAULT" rm -q -f -- conflict-files-obsidian-git.md   # 인덱스에 있을 때
rm -f -- "$VAULT/conflict-files-obsidian-git.md"             # 추적 안 될 때
git -C "$VAULT" rm -q --cached -- .obsidian/graph.json       # 디스크 파일 유지
```

`--cached` 뒤에는 디스크 파일 존재를 다시 확인하고, 사라졌으면 즉시 실패한다 —
"인덱스에서만 제거"가 깨지면 사용자 데이터 손실이기 때문이다.

인덱스를 만지는 모든 git 호출은 `.git/index.lock` 경합을 지수 백오프로 5회
재시도한다 (NF-6). 끝내 실패하면 **lock 을 지우지 않고** 정지한다 —
obsidian-git 이 커밋 중일 수 있고 lock 을 지우면 그 커밋이 깨진다.

## B / C 를 만났을 때 (NF-3)

파일마다 다음을 제시하고 **사용자가 고른다.** 절대 추측하지 않는다.

1. 요약 — `git diff --stat`, 그리고 양쪽 버전:
   `git show :2:<path>` (로컬) / `git show :3:<path>` (원격)
2. 3택
   - **로컬 유지**: `git restore --ours -- <path> && git add -- <path>`
   - **원격 채택**: `git restore --theirs -- <path> && git add -- <path>`
   - **직접 편집**: 사용자가 파일을 열어 충돌 마커를 정리한 뒤 `git add -- <path>`
3. modify/delete 충돌이면 3택 대신 "파일 유지 / 삭제 채택"으로 바꿔 묻는다
   (`git add -- <path>` vs `git rm -- <path>`).

사용자가 결정을 미루면 **커밋하지 않는다.** 머지 진행 상태를 그대로 두고 재개
방법(같은 명령 재실행)을 안내한다.

## 머지 전 상태에서의 분류

아직 머지를 시작하지 않았다면 (unmerged path 0개) `classify-conflicts.sh` 는
`git diff --name-only HEAD` 로 **추적 중인 dirty 경로**를 같은 규칙으로
분류한다. pull 을 막는 것이 그 경로들이기 때문이다 (F-3 상태 3). 추적되지 않는
파일은 pull 을 막지 않으므로 대상이 아니다 — 단 obsidian-git 아티팩트는 추적
여부와 무관하게 항상 A 다.
