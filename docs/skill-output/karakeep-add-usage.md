# karakeep-add 사용 결과

> **한 줄 요약** — URL 과 List 경로를 받아 라이브 Karakeep 에 붙은 북마크와 검증 결과를 생성합니다.

```
URL + --list 경로  ──▶  /pkm:karakeep-add  ──▶  List 에 붙은 북마크 (REST, 멱등)
```

## 1. 실행한 명령

```
/pkm:karakeep-add <url> --list <path>
```

이번 예시 — 이미 등록된 URL 로 **멱등 no-op 경로**를 검증했습니다:

```
/pkm:karakeep-add https://herdr.dev/plugins/ --list AI/Agent Tooling
```

## 2. 입력

- URL: `https://herdr.dev/plugins/` (dedup 키는 `url.rstrip("/")` -> `https://herdr.dev/plugins`)
- List 경로: `AI/Agent Tooling` (2단 중첩)
- base URL: `NEXTAUTH_URL` = `https://karakeep.tail7f8427.ts.net`
- Company 가드레일: N/A (경로가 `Company/*` 아님)

## 3. 결과

```
[OK] https://herdr.dev/plugins/  ->  AI/Agent Tooling

  list  AI             aow9udmua26h2lool5avu5k2   reused (not created)
  list  Agent Tooling  eisz99uyprtexueievao2fmr   reused (not created)
  bookmark             cz99n9c1xufte02h3qtt7ewy   reused (dedup hit)
  attach PUT           2xx / 빈 본문              idempotent
  verify GET           verified
```

멱등성 증거: List 수 36 -> 36, 해당 List 의 북마크 수 1 -> 1, 신규 생성 0건.
