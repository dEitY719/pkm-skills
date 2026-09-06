# karakeep-classify 사용 결과

> **한 줄 요약** — URL 하나를 받아 살아 있는 List 트리와 대조한 List 경로 제안을 생성합니다.

```
URL  ──▶  /pkm:karakeep-classify  ──▶  추천 List 경로 + 후속 명령 (쓰기 없음)
```

## 1. 실행한 명령

```
/pkm:karakeep-classify <url> [--apply]
```

이번 예시:

```
/pkm:karakeep-classify https://modelcontextprotocol.io/
```

작업 디렉터리는 `.env` 가 있는 `~/para/project/karakeep`.

## 2. 입력

- URL: `https://modelcontextprotocol.io/`
- 라이브 트리: `GET https://karakeep.tail7f8427.ts.net/api/v1/lists` -> HTTP 200, List 36개
- 페이지 title: `What is the Model Context Protocol (MCP)? - Model Context Protocol`

## 3. 결과

```
추천 경로   AI/Agent Tooling   (id eisz99uyprtexueievao2fmr — 이미 존재, 생성 불필요)
근거        MCP 는 에이전트 툴링 계층의 인터페이스 규격. 같은 List 에 이미
            herdr.dev/plugins (에이전트 플러그인 마켓) 가 들어 있어 성격이 일치
경쟁 후보   AI (상위, 너무 넓음) / 개발·SW엔지니어링 (에이전트 특화 아님)
신뢰도      high
Company     N/A — 공개 URL 이라 Company/* 는 제안 대상에서 제외

Next: pkm:karakeep-add https://modelcontextprotocol.io/ --list AI/Agent Tooling
[DRY-RUN] https://modelcontextprotocol.io/ -> AI/Agent Tooling (exists) confidence=high
```

무변경 확인: List 수 36 -> 36, 신규 북마크 0건.
