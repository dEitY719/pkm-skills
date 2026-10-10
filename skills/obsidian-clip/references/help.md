# pkm:obsidian-clip — Help

## Arguments

| Token | Default | Description |
|-------|---------|-------------|
| `<input>` | — | One URL, YouTube URL, or local file (required, one per run). |
| `--vault <path>` | see below | Vault root. Otherwise `$OBSIDIAN_VAULT_DIR`, otherwise `~/para/project/obsidian-para` (`-company` on an internal-mode PC). |
| `-h` / `--help` / `help` | — | Print this help and stop. |

## Usage

- `/pkm:obsidian-clip https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB`
- `/pkm:obsidian-clip https://discuss.pytorch.kr/t/graphify-ai-knowledge-graph/9652`
- `/pkm:obsidian-clip ~/Downloads/report.pdf --vault ~/notes/vault`

## Requirement

`markitdown` on PATH (`uv tool install 'markitdown[all]'`; add `--native-tls`
on a TLS error; dotfiles users: `markitdown-help install`). It is checked
first: when missing, nothing is written. The skill never installs it.

## Input types

| Input | Detected by | Body | `tags` |
|-------|-------------|------|--------|
| `youtube.com/watch?v=`, `youtube.com/shorts/`, `youtu.be/` | host + path | markitdown (title, metadata, description, transcript) | `youtube` |
| Discourse topic | `<origin>/t/<id>.json` answers with a `post_stream` | first post's `/raw` markdown; `upload://` links mapped through the cooked HTML, `![alt\|WxH]` suffix removed | `article` |
| any other `http(s)://` URL | — | markitdown, after a curl probe of the redirect chain refuses a login wall | `article` |
| existing local file (pdf, docx, xlsx, pptx, ...) | path exists | markitdown | `document` |

## Output

`<vault>/99-Inbox/YYYY-MM-DD <title>.md` — directly under `99-Inbox/`, no
per-type folder. The title is the first `## ` heading for YouTube (the video
title), the first `# ` heading for a web page, the topic title for Discourse,
and the file stem for a local file; `\ / : * ? " < > |` are removed and the
name is cut to 100 characters.

```
---
title: "<title>"
source: "<url as given | absolute file path>"
author:
  - "<author>"
published: YYYY-MM-DD
created: <today>
status: "unread"
tags:
  - "clippings"
  - "<youtube | article | document>"
---
## 메모

### 핵심 요약


### 왜 저장했나


### 액션 아이템


---

<converted markdown>
```

`author` / `published` are filled only on the Discourse path. A local file is
never copied into the vault; `source` keeps its absolute path.

## Duplicates

Before converting, every note under `99-Inbox/` is checked by its normalized
`source`: tracking parameters (`si`, `feature`, `utm_*`), `www.`, the fragment
and a trailing `/` are dropped, every YouTube URL shape collapses to its
video ID, and a `/t/<slug>/<id>[/<post>]` topic URL collapses to `/t/<id>`. A match is a stop that prints the existing note's path.

## Messages

| Line | Meaning |
|------|---------|
| `[OK] <path>` then `/ingest <path>` | Note written. |
| `[OK] Discourse 경로` | Discourse `/raw` path used. |
| `[WARN] YouTube Description 이 '...' 로 잘렸다` | markitdown cut the description; check the video page. |
| `[WARN] upload 매핑 누락 ...` | That `upload://` link had no cooked-HTML match and was left as is. |
| `[WARN] Discourse /raw 실패 ... 폴백` | Discourse detected but `/raw` failed; markitdown used. |
| `[WARN] ... 변환 결과가 비었다` | Empty conversion (scanned PDF, video without captions); nothing written. |
| `[FAIL] markitdown 미설치` + `Next:` | Install markitdown; nothing written. |
| `[FAIL] <input>: <error>` + `Next: ... REQUESTS_CA_BUNDLE` | markitdown failed (network / TLS / unsupported file); nothing written. |
| `[FAIL] 이미 클립됨 ...` | Same normalized source already under `99-Inbox/`; existing path shown. |
| `[FAIL] 같은 이름의 다른 노트 ...` | Same date + title, different source; nothing overwritten. |
| `[FAIL] <input>: markitdown timeout <N>s` | markitdown ran longer than `$OBSIDIAN_CLIP_TIMEOUT` seconds (default 300); nothing written. |
| `[FAIL] 로그인 필요 ...` | Login wall: a Discourse wall, or a web page redirected to `/login`, `/signin`, `/sign_in`, `/sign-in` or `/session/sso`, or through `/auth/...` on the way (SSO to an IdP included); nothing written. A page the user asked for at that path itself is clipped. Use the browser Web Clipper. A probe that fails (network error, non-2xx) is not a wall; markitdown still runs. |
| `[FAIL] vault 없음 ...` | Vault path missing; pass `--vault` or set `OBSIDIAN_VAULT_DIR`. |

## What it will NOT do

- Commit, stage, push or pull the vault — obsidian-git owns that.
- Overwrite a note, download images or the original file, collect comments, OCR.
- Fill the `## 메모` sections or run `/ingest` — that is the human gate.
- Clip an AI session — that is `/pkm:obsidian-clip-session`.
