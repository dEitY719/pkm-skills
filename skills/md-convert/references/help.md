# pkm:md-convert — Help

## Arguments

| Token | Default | Description |
|-------|---------|-------------|
| `<input>...` | — | One or more local file paths or `http(s)://` URLs (required). |
| `--output-path <dir>` | see Output | Write every `.md` into this directory (created if missing). Must be a directory, never a file. |
| `--force` | off | Overwrite an existing `.md` instead of skipping it. |
| `-h` / `--help` / `help` | — | Print this help and stop. |

## Usage

- `/pkm:md-convert report.pdf`
- `/pkm:md-convert a.docx b.pptx c.xlsx --output-path out/`
- `/pkm:md-convert https://example.com/page`
- `/pkm:md-convert https://www.youtube.com/watch?v=ID --force`

## Output

| Input | Directory | File name |
|-------|-----------|-----------|
| local file | the input's directory | basename minus extension + `.md` (`report.pdf` -> `report.md`) |
| YouTube (`youtube.com/watch?v=ID`, `youtu.be/ID`) | `<cwd>/.md-convert/` | `youtube-<ID>.md` (query string ignored) |
| other URL | `<cwd>/.md-convert/` | `<host>-<path slug>.md`, slug lowercase `[a-z0-9-]`, max 80 chars |

`--output-path` overrides the directory for every input. `<cwd>` is where you
call it, not the git root; a non-git directory works the same.

The first time `.md-convert/` is used inside a git repo, `.md-convert/` is
added once to that repo's `.git/info/exclude` (local only; the shared
`.gitignore` is never touched). Not done for `--output-path`.

`.md-convert/` is a hidden directory, so `rg` / Grep skip it by default —
open results with `Read` or an explicit path. The skill never deletes it.

Supported first-class: pdf, docx, pptx, xlsx / xls, URL. Anything else
`markitdown` handles (html, csv, json, images, ...) is tried, not guaranteed.
YouTube gives the transcript only; no transcript means `[FAIL]`.

## Messages

| Line | Meaning |
|------|---------|
| `[OK] <input> -> <abs path> (<n> bytes)` | Written. |
| `[SKIP] <input> -> <abs path> ...` | Target exists (or an earlier input in this run took the name); `--force` overwrites. |
| `[WARN] <input>: empty output ...` | Scanned PDF or similar; no file left. Counted as fail. No OCR. |
| `[FAIL] <input>: not found` | No such file; the rest continue. |
| `[FAIL] <input>: <stderr first line>` | markitdown failed; partial output removed. URL failures add a `Next:` hint (check `REQUESTS_CA_BUNDLE` / proxy). Certificate checks are never disabled. |
| `[FAIL] --output-path is not a directory` | Nothing converted. |
| `[FAIL] markitdown 미설치` + `Next:` | Not on PATH. Install with `uv tool install 'markitdown[all]'` (`--native-tls` on a TLS certificate error); nothing processed, nothing written. |
| `ok=N skip=N fail=N` | Last line. Exit 1 when `fail` > 0. |

dotfiles users can also install markitdown via `./setup.sh`.

## What it will NOT do

- Install markitdown, OCR, recurse into directories, or post-process the text.
- Commit, stage, or move results into a vault (chain `pkm:obsidian-markdown`
  or `pkm:obsidian-web-clip` yourself).
