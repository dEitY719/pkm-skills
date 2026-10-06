---
name: md-convert
description: >-
  PDF / DOCX / PPTX / XLSX 파일이나 URL 을 markitdown 으로 .md 변환해 저장한다.
  Use for /pkm:md-convert <input>..., "이 PDF 마크다운으로 변환", "convert this
  docx to markdown". Do NOT use for vault 클립 (pkm:obsidian-web-clip) or 노트
  편집 (pkm:obsidian-markdown).
allowed-tools: Bash, Read
license: MIT
compatibility:
  network: "URL inputs only"
  tools: "markitdown CLI on PATH"
metadata:
  model_recommendation:
    tier: haiku
    reason: "fully deterministic: lib/md-convert.py computes paths, runs markitdown and writes; the model only relays its lines"
    claude: prefer
    non_claude: advisory-only
---

# pkm:md-convert — files / URLs → markdown

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop. No network calls, no file writes.

**Stop-on-error policy** — the script owns every decision. No retry, no
fallback in prose, never call `markitdown` yourself, never install it.

## Step 1: Args

`SKILL_DIR` = this file's directory. Positional `<input>...` (one or more local
paths or `http(s)://` URLs); flags `--output-path <dir>` (directory only) and
`--force`. No `<input>` → print `Run /pkm:md-convert -h for usage.` and stop.

Pass the tokens through unchanged, each as its own quoted argument — never
build one shell string out of user paths.

## Step 2: Convert

```bash
python3 "${SKILL_DIR}/lib/md-convert.py" "$@"
```

Run it from the user's current directory: URL output defaults to
`<cwd>/.md-convert/`. It handles, per input and in order:

- output dir: the input's directory for a file, `<cwd>/.md-convert/` for a URL
  (then `.md-convert/` is added once to `.git/info/exclude` when cwd is in a
  repo), or `--output-path` for everything
- name: `<stem>.md`, `youtube-<ID>.md`, or `<host>-<path slug>.md`
- existing target → `[SKIP]` unless `--force`; one failure never stops the rest
- empty output (scanned PDF) → `[WARN]`, no file; markitdown error → `[FAIL]`
  with its first stderr line, partial output removed

Rules and the message table: `references/help.md`.

## Step 3: Report

Show **every output line verbatim** (`[OK]` / `[SKIP]` / `[WARN]` / `[FAIL]` /
`Next:`) and the closing `ok=N skip=N fail=N` line. `[OK]` lines carry the
absolute output path — `Read` it when the user wants the content. A
`.md-convert/` file is hidden from `rg` / Grep by default; use `Read` or the
explicit path.

`[FAIL] markitdown 미설치` → relay its `Next:` install lines and stop; do not
run them.

## Constraints

- Never commit, stage, or push. Writing the `.md` files is the whole job.
- Never overwrite without `--force`, never delete `.md-convert/`, never touch
  `.gitignore`, never disable certificate verification for a TLS error.
- No OCR, no recursive directory conversion, no post-processing of the text.

## Related Skills

- [[pkm:obsidian-web-clip]] clips one URL into the vault Inbox as a Web Clipper
  note; this skill only converts, wherever the input lives.
- [[pkm:obsidian-markdown]] edits the resulting note once it is in a vault.
