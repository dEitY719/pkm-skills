# karakeep-add

## 한 줄 요약

URL 하나를 지정한 Karakeep List 에 REST 로 실제로 **등록**하고, 경로에서 빠진 부모 List 를
전부 만들어 준다. 산출물은 라이브 Karakeep 인스턴스에 붙은 북마크와 그 검증 결과다.

## 언제 쓰고, 언제 안 쓰나

| 상황 | 이 스킬 | 대신 쓸 것 |
|------|:------:|-----------|
| 넣을 List 를 이미 안다 | 예 | |
| 어디 넣을지 정해야 한다 | 아니오 | `pkm:karakeep-classify` |

`<url>` 은 줬는데 `--list` 를 빠뜨리면 **쓰지 않는다.** `pkm:karakeep-classify` 로 넘겨
제안을 받고 정지한다. 사용자가 명시적 `--list` 로 재실행할 때만 쓴다 — 추측을 자동 적용하지 않는다.

## 호출 형식

```
/pkm:karakeep-add <url> --list <path>
/pkm:karakeep-add -h
```

| 인자 | 뜻 |
|------|-----|
| `<url>` | 필수. 없으면 usage 포인터를 찍고 정지 |
| `--list <path>` | 슬래시로 중첩을 표현한다 (`AI/Agent Tooling`) |

환경 변수는 작업 디렉터리의 `.env` 에서 읽는다: `NEXTAUTH_URL`, `KARAKEEP_API_KEY`.

## 동작 단계

1. **인자 + env 로드** — `--list` 없으면 classify 로 위임하고 정지.
2. **Company 가드레일** — 경로가 `Company` 이거나 `Company/` 로 시작하면,
   URL 이 명시적으로 사내 것이고 사용자가 확인해 준 경우가 아닌 한 거부한다.
3. **List 경로 해석 또는 생성** — 루트에서 한 세그먼트씩 걸어 내려가며 `parentId` 를 들고 간다.
   세그먼트마다 `name` + 현재 `parentId` 로 매칭해 있으면 id 재사용, 없으면
   `POST /api/v1/lists` (emoji `icon` 필수). 전체 경로로 소속이 결정되므로 부모부터 만든다.
4. **북마크 해석 또는 생성** — `url.rstrip("/")` 로 dedup. 있으면 id 재사용,
   없으면 `POST /api/v1/bookmarks` `{type:"link", url, title}`.
5. **붙이기 + 검증** — `PUT /api/v1/lists/<list_id>/bookmarks/<bookmark_id>` (멱등, 성공 시 빈 본문)
   후 `GET /api/v1/lists/<list_id>/bookmarks` 로 실제 소속을 확인한다.
6. **보고** — `[OK]`/`[FAIL]` 한 줄에 List 경로, id 들, 그리고 각 List/북마크가
   **생성인지 재사용인지**를 밝힌다. 이것이 멱등성의 증거다.

## 주의사항

- base URL 은 항상 `NEXTAUTH_URL` 이다. `localhost:3001` 로 떨어지지 않는다.
- 끝에서 끝까지 멱등이다. 같은 name+parent 의 List 도, 같은 `url.rstrip("/")` 의 북마크도
  중복 생성하지 않는다. 두 번째 실행은 아무것도 만들지 않는다.
- 공개/개인 URL 을 `Company` 하위에 절대 쓰지 않는다.
- 라이브 인스턴스만 건드린다. karakeep-sync 저장소를 편집하거나 `karakeep-sync push` 를
  돌리지 않는다.
- JSON 페이로드는 `jq -n` 으로 만든다. 값에 따옴표나 백슬래시가 들어가도 깨지거나
  주입되지 않게 하기 위해서다.
