---
name: obsidian-web-clip
description: >-
  URL 1건을 PARA vault 99-Inbox/Web 에 Obsidian Web Clipper 형식 md 로 클립한다.
  Use for /pkm:obsidian-web-clip <url>, "이 URL 볼트 인박스에 클립", "clip this
  page to my vault". Do NOT use for AI 세션 클립 (pkm:obsidian-session-clip) or
  북마크 (pkm:karakeep-add).
allowed-tools: Bash, Read
license: MIT
compatibility:
  network: required
metadata:
  model_recommendation:
    tier: haiku
    reason: "fully deterministic: lib/web-clip.py fetches, converts and writes; the model only relays its lines"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-web-clip — URL → vault Inbox

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop. No network calls, no file writes.

**Stop-on-error policy** — any failure (missing `<url>`, missing vault, a
non-zero exit from `lib/web-clip.py`) stops the run at that step; there is no
retry and no fallback in prose — the script owns the Discourse → generic one.

## Step 1: Args + vault

`SKILL_DIR` = this file's directory. Positional `<url>` (required, exactly one);
flag `--vault <path>`. Missing `<url>` → print `Run /pkm:obsidian-web-clip -h
for usage.` and stop.

```bash
VAULT=$(bash "${SKILL_DIR}/lib/vendor/resolve-vault.sh" "$VAULT_ARG")
```

`$VAULT_ARG` = the `--vault` value, empty if absent. Priority is `--vault` >
`$OBSIDIAN_VAULT_DIR` > the `~/.dotfiles-setup-mode` default, same as
`pkm:obsidian-session-clip`. The script stops on a missing vault; never create one.

## Step 2: Clip

```bash
python3 "${SKILL_DIR}/lib/web-clip.py" "$URL" "$VAULT"
```

It picks the path itself — Discourse (`<origin>/t/<id>.json` answers with a
`post_stream`: first post's `/raw` markdown, `upload://` links mapped through
the cooked HTML, `|WxH` suffixes stripped) or the generic HTML → markdown
fallback — and writes `99-Inbox/Web/<today> <title>.md` with the Web Clipper
frontmatter and an empty `## 메모` skeleton. Details: `references/help.md`.

It refuses, writing nothing, when the same `source` URL already exists under
`99-Inbox/`, on any HTTP or network failure, and on a name collision.

## Step 3: Report

Show **every output line verbatim** (`[OK]` / `[WARN]` / `[FAIL]`). Never hide
a `[WARN]` — the generic-path accuracy note and each unmapped `upload://` link
are the user's cue to check the note. On success, end with the note path and,
as the last line, `/ingest <path>`.

## Constraints

- **Never commit, stage or sync the vault.** The file write is the whole job;
  obsidian-git picks the note up (`vault backup:`).
- Never overwrite an existing note, never download images (remote URLs stay),
  never fill the `## 메모` sections, never run `/ingest`.
- One URL per run; comments (posts after the first) are not collected.

## Related Skills

- [[pkm:obsidian-session-clip]] clips an AI session into `99-Inbox/ai-session/`;
  this skill clips a web page into `99-Inbox/Web/`.
- [[pkm:karakeep-add]] bookmarks a URL in Karakeep instead of the vault.
