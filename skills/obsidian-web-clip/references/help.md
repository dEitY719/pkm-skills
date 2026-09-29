# pkm:obsidian-web-clip — Help

## Arguments

| Token | Default | Description |
|-------|---------|-------------|
| `<url>` | — | The page to clip (required, one per run). Kept verbatim as `source`. |
| `--vault <path>` | see below | Vault root. Otherwise `$OBSIDIAN_VAULT_DIR`, otherwise `~/para/project/obsidian-para` (`-company` on an internal-mode PC). |
| `-h` / `--help` / `help` | — | Print this help and stop. |

## Usage

- `/pkm:obsidian-web-clip https://discuss.pytorch.kr/t/graphify-ai-knowledge-graph/9652`
- `/pkm:obsidian-web-clip https://example.com/post --vault ~/notes/vault`

## Output

`<vault>/99-Inbox/Web/YYYY-MM-DD <title>.md` — today's date, the page title
with `\ / : * ? " < > |` removed, cut to 100 characters. Content:

```
---
title: "<title>"
source: "<url as given>"
author:
  - "<author>"
published: YYYY-MM-DD
created: <today>
status: "unread"
tags:
  - "clippings"
  - "article"
---
## 메모

### 핵심 요약


### 왜 저장했나


### 액션 아이템


---

<article markdown>
```

The frontmatter keys match the Obsidian Web Clipper's, so the vault's
`/ingest` takes the note unchanged. A generic page with no author or date
meta leaves `author:` / `published:` empty.

## Paths

| Path | When | Body source |
|------|------|-------------|
| Discourse | URL has `/t/<id>` and `<origin>/t/<id>.json` returns a `post_stream` | First post's `<origin>/raw/<id>/1` markdown; `upload://` short links replaced by the cooked HTML's `<img src>`; `![alt\|WxH]` size suffix removed. Title from the topic, author = first poster, published = its `created_at`. |
| Generic | anything else, or Discourse `/raw` failed | stdlib HTML → markdown of `<article>` / `<main>` (else `<body>`); title from `og:title` / `<title>`, author from `author` meta, published from `article:published_time`. Lossy — headings, paragraphs, links, images, lists, code, emphasis only. |

Fetching goes through `curl` (system trust store, so a TLS-intercepting proxy
works); parsing is python3 stdlib. No other dependency.

## Messages

| Line | Meaning |
|------|---------|
| `[OK] Discourse 경로` | Discourse path used. |
| `[WARN] 범용 경로 ...` | Generic path — check the note against the page. |
| `[WARN] Discourse /raw 실패 ... 폴백` | Discourse detected but `/raw` failed; generic path used. |
| `[WARN] upload 매핑 누락 ...` | That `upload://` link had no cooked-HTML match and was left as is. |
| `[FAIL] 이미 클립됨 ...` | Same `source` already under `99-Inbox/`; nothing written, existing path shown. |
| `[FAIL] HTTP <code>` / `network error` | Fetch failed; nothing written. |
| `[FAIL] vault 없음 ...` | Vault path missing; pass `--vault` or set `OBSIDIAN_VAULT_DIR`. |

## What it will NOT do

- Commit, stage, push or pull the vault — obsidian-git owns that.
- Overwrite a note, download images, collect comments, or clip several URLs.
- Fill the `## 메모` sections or run `/ingest` — that is the human gate.
