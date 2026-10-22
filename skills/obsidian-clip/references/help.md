# pkm:obsidian-clip — Help

## Arguments

| Token | Default | Description |
|-------|---------|-------------|
| `<input>` | — | One URL, YouTube URL, or local file (required, one per run). |
| `OBSIDIAN_CLIP_NO_PROBE=1` (env) | unset | Skip the login-wall redirect probe for a public page it wrongly refuses. Only the exact value `1` counts. A Discourse topic's own wall still stops. On a real wall markitdown clips the login page instead; delete that note before clipping the URL again, or the duplicate check stops the retry. |
| `OBSIDIAN_CLIP_TIMEOUT` (env) | `300` | Seconds each markitdown / yt-dlp call may run. |
| `-h` / `--help` / `help` | — | Print this help and stop. |

The vault is fixed: `~/para/project/obsidian-para` (`~` expanded), whatever the
current directory, `$OBSIDIAN_VAULT_DIR` or `~/.dotfiles-setup-mode` say; notes
land in its `99-Inbox/`. There is no `--vault`: passing it is a `[FAIL]` that
writes nothing, never a silent ignore.

## Usage

- `/pkm:obsidian-clip https://youtube.com/shorts/nGKKWne_O2s?si=0WCRD0677GIEY8KB`
- `/pkm:obsidian-clip https://discuss.pytorch.kr/t/graphify-ai-knowledge-graph/9652`
- `/pkm:obsidian-clip ~/Downloads/report.pdf`

## Requirement

`markitdown` on PATH (`uv tool install 'markitdown[all]'`; add `--native-tls`
on a TLS error; dotfiles users: `markitdown-help install`). It is checked
first: when missing, nothing is written. The skill never installs it.

Optional: [agent-reach](https://github.com/Panniantong/Agent-Reach) (>= 1.5)
and the `yt-dlp` CLI. Detection is `agent-reach` on PATH only -- `agent-reach
doctor` is never run. With both, YouTube goes through yt-dlp; without
agent-reach every run prints a light-bulb `[TIP]` line and works as before.
yt-dlp is called as a CLI only (never the Python module), without cookies and
without disabling certificate checks. Neither is ever installed by the skill.

## Input types

| Input | Detected by | Body | `tags` |
|-------|-------------|------|--------|
| `youtube.com/watch?v=`, `youtube.com/shorts/`, `youtu.be/` + agent-reach + yt-dlp | host + path, PATH | yt-dlp: `--dump-json` metadata, then VTT subtitles (manual before auto, `ko` > `en` > `<lang>-orig`) cleaned to text. Body: `# <title>`, `## Video Metadata` (Channel / Uploaded / Duration / Views / URL), `## Description` (full), `## Chapters` (when present), `## Transcript (<lang>, manual\|auto)` | `youtube` |
| same, without agent-reach or yt-dlp, or after a yt-dlp failure | host + path | markitdown (title, metadata, description, transcript) | `youtube` |
| Discourse topic | `<origin>/t/<id>.json` answers with a `post_stream` | first post's `/raw` markdown; `upload://` links mapped through the cooked HTML, `![alt\|WxH]` suffix removed | `article` |
| any other `http(s)://` URL | — | markitdown, after a curl probe of the redirect chain refuses a login wall | `article` |
| existing local file (pdf, docx, xlsx, pptx, ...) | path exists | markitdown | `document` |

## Output

`<vault>/99-Inbox/YYYY-MM-DD <title>.md` — directly under `99-Inbox/`, no
per-type folder. The title is the video title for YouTube (yt-dlp metadata, or
markitdown's first `## ` heading), the first `# ` heading for a web page, the topic title for Discourse,
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

`author` / `published` are filled on the Discourse path (username, post date)
and the yt-dlp YouTube path (uploader or channel, upload date). A local file is
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
| `[OK] yt-dlp 경로 (agent-reach)` | YouTube clipped through yt-dlp. |
| light bulb + `[TIP] agent-reach 미설치 ...` + `Next: 설치 안내 ...` | agent-reach is not on PATH: install it for the yt-dlp YouTube path. Printed on every run, before converting; not a failure. Relay it, never hide it. |
| `[WARN] agent-reach 는 있으나 yt-dlp 미설치 -- markitdown 경로` + `Next: agent-reach doctor` | agent-reach found, yt-dlp not; markitdown used. |
| `[WARN] yt-dlp 실패 (<reason>) -- markitdown 경로로 폴백` | yt-dlp metadata failed; markitdown used. `<reason>` is `yt-dlp exit <code> (www.youtube.com)`, `timeout <N>s`, `JSONDecodeError` or `title 없음` (a bot check is the exit-code case: no cookies are injected). yt-dlp's stderr is never printed. |
| `[WARN] 자막 없음 -- Transcript 섹션 생략` | No usable subtitle track; the note is written without `## Transcript`. |
| `[WARN] YouTube Description 이 '...' 로 잘렸다` | markitdown cut the description (markitdown path only); check the video page. |
| `[WARN] upload 매핑 누락 ...` | That `upload://` link had no cooked-HTML match and was left as is. |
| `[WARN] Discourse /raw 실패 ... 폴백` | Discourse detected but `/raw` failed; markitdown used. The reason is `network error <host>: curl exit <code>` or `HTTP <code> <host>`; curl's own error text is never printed. |
| `[WARN] ... 변환 결과가 비었다` | Empty conversion (scanned PDF, video without captions); nothing written. |
| `[FAIL] markitdown 미설치` + `Next:` | Install markitdown; nothing written. |
| `[FAIL] <input>: <Class> (<host>)` + `Next:` | markitdown failed (network / TLS / unsupported file); nothing written. `<Class>` is the exception class of its last traceback (`ConnectionError`), or `markitdown exit <code>` when there is none; `(<host>)` only for a URL input. The exception message is never printed: it can quote token-bearing URLs. `Next: 원인 상세: markitdown <input> 를 직접 실행` (input shell-quoted) shows the full error; a missing markitdown extra adds the same install hint as `markitdown 미설치`; the agent relays that line and never runs it (its stderr can carry tokens); a URL input also gets the `REQUESTS_CA_BUNDLE` / proxy hint. |
| `[FAIL] 이미 클립됨 ...` | Same normalized source already under `99-Inbox/`; existing path shown. |
| `[FAIL] 같은 이름의 다른 노트 ...` | Same date + title, different source; nothing overwritten. |
| `[FAIL] --vault 는 지원하지 않는다 (저장 위치 고정: ...)` | `--vault` given; nothing written. The vault is fixed. |
| `[FAIL] <input>: markitdown timeout <N>s` | markitdown ran longer than `$OBSIDIAN_CLIP_TIMEOUT` seconds (default 300); nothing written. |
| `[FAIL] 로그인 필요 ...` | Login wall: a Discourse wall, or a web page redirected to `/login`, `/signin`, `/sign_in`, `/sign-in` or `/session/sso`, or through `/auth/...` on the way (SSO to an IdP included); nothing written. Only the host of the login page is shown: path, query, fragment and userinfo can carry session tokens. A page the user asked for at that path itself is clipped. Use the browser Web Clipper; if the page is public and the redirect probe refused it, rerun with `OBSIDIAN_CLIP_NO_PROBE=1`. A probe that fails (network error, non-2xx) is not a wall; markitdown still runs. |
| `[FAIL] vault 없음 ...` | `~/para/project/obsidian-para` does not exist; it is never created. |

## What it will NOT do

- Commit, stage, push or pull the vault — obsidian-git owns that.
- Overwrite a note, download images, video or the original file, collect comments, OCR.
- Install markitdown, agent-reach or yt-dlp, or pass yt-dlp browser cookies.
- Fill the `## 메모` sections or run `/ingest` — that is the human gate.
- Clip an AI session — that is `/pkm:obsidian-clip-session`.
