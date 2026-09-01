# karakeep-classify

## 한 줄 요약

URL 하나를 살아 있는 Karakeep List 트리에 맞춰 보고 **가장 잘 맞는 List 경로 제안**과
근거, 그리고 바로 붙여 쓸 수 있는 후속 명령을 출력한다. 기본값은 dry-run — 아무것도 쓰지 않는다.

## 언제 쓰고, 언제 안 쓰나

| 상황 | 이 스킬 | 대신 쓸 것 |
|------|:------:|-----------|
| 이 URL 을 어디에 넣을지 모르겠다 | 예 | |
| 넣을 곳을 이미 안다 | 아니오 | `pkm:karakeep-add <url> --list <path>` |
| 실제로 쓰기 | 아니오 | `pkm:karakeep-add` |

`karakeep-classify` 와 `karakeep-add` 는 propose-then-confirm 한 쌍이다.
이쪽은 **판단만** 하고, 쓰기 경로는 전부 `karakeep-add` 가 소유한다.
`--apply` 도 두 번째 쓰기 경로를 만들지 않고 `karakeep-add` 에 위임한다.

## 호출 형식

```
/pkm:karakeep-classify <url> [--apply]
/pkm:karakeep-classify -h
```

| 인자 | 뜻 |
|------|-----|
| `<url>` | 필수. 없으면 usage 포인터를 찍고 정지 |
| `--apply` | dry-run 대신 `pkm:karakeep-add` 로 넘겨 실제로 쓴다 |

환경 변수는 **작업 디렉터리의 `.env`** 에서 읽는다: `NEXTAUTH_URL`, `KARAKEEP_API_KEY`.
둘 중 하나라도 없으면 명확히 실패한다 — base URL 을 추측하지 않는다.

## 동작 단계

1. **인자 + env 로드** — `.env` 에서 두 변수를 읽는다. `BASE="${NEXTAUTH_URL%/}"`.
2. **살아 있는 List 트리 읽기** — `GET /api/v1/lists` 후 `parentId` 를 따라
   `부모/자식` 전체 경로를 복원한다.
3. **URL 분석** — 가장 싼 신호부터: host, path 세그먼트. 애매할 때만 페이지의
   `<title>` 과 meta description 을 가볍게 가져온다. 본문 전체는 기본적으로 안 읽는다.
4. **매칭 또는 제안** — 기존 경로 중 최적을 고른다. 크게 안 맞으면 새 경로를 제안하되,
   새 루트보다 기존 부모를 확장하는 쪽을 선호한다.
5. **출력** — dry-run 이면 주제, 추천 경로, 존재 여부, 신뢰도, 그리고 정확한 후속 명령
   `pkm:karakeep-add <url> --list <path>` 를 찍는다. `--apply` 면 `karakeep-add` 로 넘긴다.
6. **보고** — `[DRY-RUN]` 또는 `[APPLIED]` 판정 줄과 `Next:` 힌트로 끝난다.

## 주의사항

- 기본값이 무변경이다. `--apply` 만 변경을 일으키고, 그것도 `karakeep-add` 를 통해서만이다.
- base URL 은 항상 `NEXTAUTH_URL` 이다. `localhost:3001` 은 `config.yaml` 의 내부 값이라
  라이브 쓰기에는 틀린 값이다.
- `Company` 와 그 하위는 기밀 경계다. 주제가 아무리 맞아 보여도 공개/개인 URL 을
  `Company/*` 로 제안하지 않는다 — 경계의 기준은 주제가 아니라 출처다.
- 분석은 가볍게. title/meta 를 본문 전체 fetch 보다 우선한다.
- `WebFetch` 는 Claude Code 전용이다. 다른 하네스에서는 해당 하네스의 fetch 도구나
  `curl -sL` 로 대체하며, 이 fetch 자체가 선택적이다.
