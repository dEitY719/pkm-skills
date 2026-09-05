# pkm:obsidian-resolve-conflict — PC 모드 인지

## SSOT

모드별 경로·원격·**push 권한**의 단일 진실 공급원은
[dotfiles `docs/.ssot/pc-environment.md`](https://github.com/dEitY719/dotfiles/blob/main/docs/.ssot/pc-environment.md) 다.

- §1 공통 전제 — "Windows 사용자명과 WSL 사용자명은 PC마다 다름 → 경로를
  하드코딩하지 말고 런타임에 탐지한다"
- §2 PC 인벤토리 (5대)
- §3 접근/동기화 규칙 (모드별) — NF-7 push 가드가 코드로 강제하는 규칙

이 문서는 그 표의 **값을 복사하지 않는다** (NF-9). 값이 궁금하면 SSOT 를 읽고,
모드별 동작이 바뀌면 SSOT 를 먼저 고친다. 여기 적는 것은 스킬이 그 규칙을
런타임에 **어떻게 알아내는가** 뿐이다.

## 모드 읽기

새 설정 파일을 만들지 않는다. 기존 `~/.dotfiles-setup-mode` 를 읽고
dotfiles 의 `_dotfiles_setup_mode()`
([`shell-common/tools/integrations/claude.sh`](https://github.com/dEitY719/dotfiles/blob/main/shell-common/tools/integrations/claude.sh)) 와 **동일하게** 정규화한다:

| 파일 내용 | 정규화 결과 |
|---|---|
| `1` / `public` | `public` |
| `2` / `internal` | `internal` |
| `3` / `external` | `external` |
| 파일 없음 | 빈 문자열 (모드 불명) |

숫자 값은 pre-#571 setup.sh 가 쓰던 레거시 표기이며 그대로 받아준다.
`lib/resolve-vault.sh` 의 `setup_mode()` 가 이 로직을 담고 있고,
`--mode <값>` 으로 덮어쓸 수 있다 (테스트·일회성 진단용).

`shell-common` 함수를 source 하지 않는 이유: lib 스크립트는 셸 초기화에 섞이지
않는 독립 실행 파일이고, 대화형 가드가 걸린 파일을 배치 컨텍스트에서 source 하면
조용히 빈 값이 돌아온다.

## 모드가 결정하는 것 (이 스킬 안에서)

| 항목 | 모드의 역할 |
|---|---|
| WSL 클론 선택 | 후보 두 개가 **모두 존재할 때만** 우선순위를 정한다 (`internal` → company clone, 그 외 → personal clone). 하나만 있으면 모드와 무관하게 그것 |
| Windows 클론 선택 | 관여하지 않는다. 폴더명이 같고 사용자명만 다르므로 glob 이 흡수한다 |
| push 허용 여부 | `internal` + origin 호스트 `github.com` → **거부** (NF-7). GHES origin 은 정상 push |
| peer 판정 | 관여하지 않는다. `git remote get-url origin` 일치 여부로만 판정한다 |

**모드는 후보 우선순위만 정한다.** 최종 판정은 항상 실제 존재 여부와 origin URL
이다. 모드 파일은 손으로 고칠 수 있고 PC 를 재설치하면 어긋나지만, 디스크에
있는 클론과 그 원격 URL 은 거짓말하지 않는다.

## 모드 불명일 때

| 상황 | 동작 |
|---|---|
| WSL 후보가 하나만 존재 | 그대로 진행 |
| WSL 후보가 둘 다 존재 | 두 경로를 출력하고 정지. `--vault` 또는 `--mode` 를 요구 |
| Windows 측 | 영향 없음 (glob 이 결정) |
| push 가드 | 모드가 `internal` 이 아니면 가드가 걸리지 않는다. 모드 불명 = `internal` 아님 |

마지막 줄은 의도된 선택이다: 모드 불명 상태에서 push 를 전부 막으면 개인 PC 가
멈춘다. 사내PC 는 `~/.dotfiles-setup-mode` 가 반드시 세팅된 환경이고, 만약
지워졌다면 GHES 원격이 아닌 `github.com` 원격을 쓰는 vault 자체가 사내PC 에
존재하지 않아야 한다.
