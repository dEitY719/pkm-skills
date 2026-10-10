---
name: obsidian-clip
description: >-
  URL·YouTube·로컬 문서(pdf/docx/xlsx/pptx) 1건을 markitdown 으로 변환해 PARA vault
  99-Inbox 에 Web Clipper 형식 md 로 클립한다. Use for /pkm:obsidian-clip <input>,
  "이 URL/영상/문서 볼트 인박스에 클립", "clip this to my vault". Do NOT use for AI
  세션 클립 (pkm:obsidian-clip-session) or 북마크 (pkm:karakeep-add).
allowed-tools: Bash, Read
license: MIT
compatibility:
  network: required for URLs
metadata:
  model_recommendation:
    tier: haiku
    reason: "fully deterministic: lib/clip.py classifies, converts and writes; the model only relays its lines"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-clip — URL / YouTube / document → vault Inbox

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop. No network calls, no file writes.

**Stop-on-error policy** — any failure (missing `<input>`, missing vault, a
non-zero exit from `lib/clip.py`) stops the run at that step; there is no
retry and no fallback in prose — the script owns every path decision.

## Step 1: Args + vault

`SKILL_DIR` = this file's directory. Positional `<input>` (required, exactly
one: URL or local file path); flag `--vault <path>`; env
`OBSIDIAN_CLIP_NO_PROBE=1` skips the login-wall redirect probe (opt-out for a
public page it wrongly refuses). Missing `<input>` → print
`Run /pkm:obsidian-clip -h for usage.` and stop.

```bash
VAULT=$(bash "${SKILL_DIR}/lib/vendor/resolve-vault.sh" "$VAULT_ARG")
```

`$VAULT_ARG` = the `--vault` value, empty if absent. Priority is `--vault` >
`$OBSIDIAN_VAULT_DIR` > the `~/.dotfiles-setup-mode` default, same as
`pkm:obsidian-clip-session`. The script stops on a missing vault; never create one.

## Step 2: Clip

```bash
python3 "${SKILL_DIR}/lib/clip.py" "$INPUT" "$VAULT"
```

When the user asks to skip the login-wall probe, prefix the call with
`OBSIDIAN_CLIP_NO_PROBE=1`.

It checks `markitdown` is on PATH first (missing → `[FAIL]` + `Next:` install
hint, nothing written; never install it), classifies the input — YouTube,
Discourse topic (`/raw` markdown), other URL, local file — refuses a source
already clipped under `99-Inbox/` (normalized: tracking params dropped, every
YouTube URL shape → its video ID), converts, and writes
`99-Inbox/<today> <title>.md` with the Web Clipper frontmatter
(`tags: [clippings, youtube|article|document]`) and an empty `## 메모`
skeleton. Paths, title rules, messages: `references/help.md`.

It writes nothing on an empty conversion, any markitdown / network failure, a
duplicate source, or a name collision. Error lines name only the exception
class (or `curl exit <code>`) and host, never the downstream tool's text.

## Step 3: Report

Show **every output line verbatim** (`[OK]` / `[WARN]` / `[FAIL]` / `Next:`).
Never hide a `[WARN]` — a truncated YouTube description and each unmapped
`upload://` link are the user's cue to check the note. On success the script's
last line is `/ingest <path>`; keep it last.

## Constraints

- **Never commit, stage or sync the vault.** The file write is the whole job;
  obsidian-git picks the note up (`vault backup:`).
- Never overwrite an existing note, never copy the original file or download
  images, never fill the `## 메모` sections, never run `/ingest`.
- Never disable certificate verification; a TLS failure gets the
  `REQUESTS_CA_BUNDLE` hint instead.
- Never run the `Next: 원인 상세: markitdown ...` command yourself: its raw
  stderr can carry session tokens. Relay the line; the user runs it.
- One input per run; comments (posts after the first) are not collected.

## Related Skills

- [[pkm:obsidian-clip-session]] clips an AI session into `99-Inbox/ai-session/`;
  this skill clips a page, video or document into `99-Inbox/`.
- [[pkm:karakeep-add]] bookmarks a URL in Karakeep instead of the vault.
