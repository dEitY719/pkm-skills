---
name: obsidian-markdown
description: >-
  Write Obsidian vault notes: wikilinks, embeds, callouts, properties. Use for
  /pkm:obsidian-markdown, "옵시디언 노트에 콜아웃 넣어줘", "fix this
  wikilink". Not for plain .md outside a vault. Do NOT use to clip a session —
  use pkm:obsidian-session-clip.
allowed-tools: Read, Write, Edit, Bash
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "note authoring in the user's own vault; syntax is fixed, but content and link targets need judgment"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-markdown — Obsidian Flavored Markdown

Obsidian extends CommonMark and GFM with wikilinks, embeds, callouts,
properties, comments, and other syntax. This skill covers only those
Obsidian-specific extensions — standard Markdown (headings, bold, italic,
lists, quotes, code blocks, tables) is assumed knowledge. Vault notes only,
never a README or other plain `.md`; it edits files, never commits or syncs.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No file writes.

## Step 1: Confirm it is a vault note

Proceed only when the file lives in an Obsidian vault (a `.obsidian/` directory
at its root) or the user asked for Obsidian syntax. A plain `.md` outside a
vault is a stop: say so and use standard Markdown instead.

## Step 2: Load only the reference you need

| Need | Read |
|------|------|
| Wikilinks, block IDs, tags, comments, highlight, math, Mermaid, footnotes; a tour of all syntax | `references/SYNTAX.md` |
| Property types, default properties, tag rules | `references/PROPERTIES.md` |
| Note, image, audio, PDF, base, list, and search embeds | `references/EMBEDS.md` |
| Callout types and aliases, folding, nesting, custom CSS | `references/CALLOUTS.md` |
| A full note that uses all of it, plus Obsidian doc links | `references/EXAMPLE.md` |

## Step 3: Write the note

1. **Add frontmatter** with properties (title, tags, aliases) at the top.
2. **Write content** in standard Markdown plus Obsidian-specific syntax.
3. **Link related notes** using wikilinks (`[[Note]]`) for internal vault
   connections (Obsidian tracks renames), and `[text](url)` for external URLs
   only.
4. **Embed content** from other notes, images, or PDFs using `![[embed]]`.
5. **Add callouts** for highlighted information using `> [!type]`.

Minimal example:

```markdown
---
tags:
  - project
---
See [[Algorithm Notes#Sorting|sorting]] for details.

> [!warning] Deadline
> Due ==January 30th==. ![[Architecture Diagram.png|600]]
```

## Step 4: Validate

```bash
_s=""
if [ -n "${HERMES_SKILL_DIR}" ]; then _s="${HERMES_SKILL_DIR}/lib/check-note.py"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then _s="$CLAUDE_PLUGIN_ROOT/skills/obsidian-markdown/lib/check-note.py"
fi
[ -n "$_s" ] && [ -f "$_s" ] || { printf '[FAIL] plugin root unresolved (tried: %s). Export HERMES_SKILL_DIR=<this skill dir> or CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' "${_s:-nothing}" >&2; return 1 2>/dev/null || exit 1; }
python3 "$_s" --vault <vault> <note.md>
```

`<vault>` = the root holding `.obsidian/`. Relay its lines verbatim; each
`UNRESOLVED` is a typo to fix or an intended new note (say which). Anchors and
callout types (`references/CALLOUTS.md`) are left to Obsidian's reading view.

## Step 5: Report

```
[OK] <note path>  links=<n> embeds=<n> callouts=<n>
[FAIL] <note path>  links=<n> embeds=<n> callouts=<n>
UNRESOLVED <target>
Next: open the note in reading view; unresolved links are listed above
```

## Related Skills

- `/pkm:obsidian-session-clip` writes and commits a session note on explicit
  request; this skill only edits note syntax.
- `/pkm:obsidian-bases` for `.base` files, `/pkm:obsidian-canvas` for
  `.canvas` files, `/pkm:obsidian-cli` to drive the running app.
