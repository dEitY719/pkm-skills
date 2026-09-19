# pkm:obsidian-markdown — Help

Write or fix Obsidian Flavored Markdown in a vault note: wikilinks, embeds,
callouts, properties, tags, comments, highlight, math, Mermaid, footnotes.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `[path]` | The vault note to create or edit | asked, or inferred from the request |
| `[request]` | Free text: what to add or fix | — |
| `-h` / `--help` / `help` | Print this help and stop | — |

## Usage

- `/pkm:obsidian-markdown Projects/Alpha.md add a warning callout for the deadline`
- `/pkm:obsidian-markdown fix the broken wikilinks in this note`
- `/pkm:obsidian-markdown -h`

## What the skill will NOT do

- Apply Obsidian syntax to a plain `.md` outside a vault (README, docs).
- Clip or commit an AI session note — that is `/pkm:obsidian-session-clip`,
  explicit invocation only.
- Commit, push, or sync the vault.

## Output example

```
[OK] Projects/Alpha.md  links=4 embeds=1 callouts=1
Next: open the note in reading view; unresolved links are listed above
```
