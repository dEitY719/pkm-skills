# pkm:obsidian-session-clip — frontmatter 스펙 (F-3) 과 `/ingest` 계약

노트 최상단에 아래 9개 키를 **이 순서 그대로** 넣는다. 하나라도 빠지면
`lib/verify-clip.sh` 가 FAIL 한다. Web Clipper 템플릿
([obsidian-para `docs/webclipper/article.json`](https://github.com/dEitY719/obsidian-para/blob/main/docs/webclipper/article.json)) 과 같은 계열이라 `/ingest` 가 추가 가공 없이
소비한다.

```yaml
---
title: <세션 한 줄 요약>
source: <PR URL | issue URL | repo URL>
repo: <repo 이름>
branch: <브랜치 이름>
session_type: code
created: 2026-08-11
status: unprocessed
memo: ai-generated
tags: [ai-session, dotfiles]
---
```

## 키별 규칙

| Key | 값 | 비고 |
|---|---|---|
| `title` | 세션 한 줄 요약 | 명사구. 콜론(`:`)을 쓰려면 값 전체를 큰따옴표로 감싼다 (YAML 파싱) |
| `source` | URL 1개 | 우선순위: 이번 세션에서 만든 PR URL > 구현한 이슈 URL > repo URL. 셋 다 없으면 빈 값 대신 `none`. `/ingest` 가 이 값을 `source_url` 로 승격한다 |
| `repo` | repo 이름 | `basename $(git rev-parse --show-toplevel)`. git 저장소가 아니면 `none` |
| `branch` | 브랜치 이름 | `git rev-parse --abbrev-ref HEAD`. git 저장소가 아니면 `none` |
| `session_type` | `code` \| `research` | F-4 판별 결과. 값 2개 외에는 쓰지 않는다 |
| `created` | `YYYY-MM-DD` | 파일명의 날짜와 같아야 한다 |
| `status` | `unprocessed` | **항상 고정**. `/ingest` 가 미처리 큐를 이 값으로 찾는다 |
| `memo` | `ai-generated` | **항상 고정**. 아래 참조 |
| `tags` | `[ai-session, <repo>]` | 인라인 리스트. `ai-session` 이 항상 첫 원소. `repo` 가 `none` 이면 `[ai-session]` |

## `session_type` 판별 (F-4)

| 조건 | 값 |
|---|---|
| 세션 중 커밋이 1개 이상 생성됨, 또는 PR 이 생성됨 | `code` |
| 그 외 (조사·토론·의사결정만) | `research` |

판별 근거는 `git log --oneline <base>..HEAD` 의 줄 수와 세션 중
`gh pr create` 수행 여부다. 커밋이 문서만 건드렸더라도 커밋이 있으면 `code` 다
(오탐 여지는 이슈 dEitY719/dotfiles#1321 Open Questions 에 기록되어 있다).

## `memo: ai-generated` 가 뜻하는 것 (F-5 트레이드오프)

`## 메모` 아래 3개 하위 섹션(`### 핵심 요약` / `### 왜 저장했나` /
`### 액션 아이템`)은 **AI 가 모두 채운다**. 사람이 백지에서 시작하지 않게
하려는 것이다.

동시에 `memo: ai-generated` 플래그를 남긴다. vault 설계의 핵심은 `/ingest`
2단계의 사람 개입 게이트이고, AI 가 메모를 채워 버리면 그 게이트가 약해진다.
플래그의 계약은 이렇다:

> 이 메모는 **승인 대상이 아니라 교정 대상**이다. `/ingest` 는 이 값을 보면
> "AI 초안이니 확인해 달라"고 사람에게 되물어야 하며, 채워져 있다는 이유로
> 사람 확인 단계를 건너뛰면 안 된다.

사람이 메모를 손보고 나면 `memo:` 값을 `human` 으로 바꾸는 것이 규약이다
(이 스킬은 그 전환을 하지 않는다).

`/ingest` 쪽에서 이 플래그를 실제로 다루려면 vault 저장소
(`dEitY719/obsidian-para`) 의 `.claude/commands/ingest.md` 개정이 필요하다 —
이슈 dEitY719/dotfiles#1321 의 Dependencies 항목이며 **별도 저장소의 별도 이슈**다. 개정 전에도
노트는 정상 소비되며, 플래그가 무시될 뿐이다.

## `/ingest` 가 기대하는 나머지

- 경로: `99-Inbox/ai-session/` 아래 (Inbox 하위 카테고리 디렉토리)
- 파일명: Windows 안전 (NF-1) — vault 원본이 Windows 파일시스템에 있다
- 본문: `references/template-code.md` / `references/template-research.md` 의
  섹션 제목·순서를 그대로 유지 (제목을 바꾸면 `/ingest` 가 골격을 못 읽는다)
- 커밋 프리픽스: `clip:` — vault `AGENTS.md` §6 에 추가되어야 한다
  (Dependencies, 별도 저장소 이슈). 추가 전에도 커밋 자체는 성공한다.
