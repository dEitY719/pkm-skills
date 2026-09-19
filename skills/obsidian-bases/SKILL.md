---
name: obsidian-bases
description: >-
  Create and edit Obsidian Bases (.base) views, filters, and formulas. Use for
  /pkm:obsidian-bases, "옵시디언 베이스로 할 일 테이블 만들어줘", "add a
  formula to this .base". Do NOT use for .md note syntax — use
  pkm:obsidian-markdown.
allowed-tools: Read, Write, Edit
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "YAML + formula-expression authoring; Duration and quoting pitfalls need judgment, but the edit is one file"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-bases — Obsidian Bases (.base) files

A `.base` file is YAML defining database-like views over vault notes. This
skill edits one `.base` file in the user's vault; it never commits, syncs, or
touches a remote.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No file writes.

## Step 1: Locate the target

Use the `.base` path the user named. Editing → read and parse it first. New
file → confirm the vault folder exists; a missing folder is a stop, never a
`mkdir` of a guessed path.

## Step 2: Load only the reference you need

| Need | Read |
|------|------|
| Top-level keys, note / file / formula properties, `this` | `references/SCHEMA.md` |
| `and` / `or` / `not` filters and operators | `references/FILTERS.md` |
| Formula syntax, key functions, Duration, date arithmetic | `references/FORMULAS.md` |
| Every function by type (Date, String, Number, List, File, Link, Object, RegExp) | `references/FUNCTIONS_REFERENCE.md` |
| View types, default summary formulas, embedding a base in a note | `references/VIEWS.md` |
| Full task tracker, reading list, and daily-notes bases | `references/EXAMPLES.md` |
| YAML quoting rules, common YAML and formula errors | `references/TROUBLESHOOTING.md` |

## Step 3: Write the base

1. **Create the file**: a `.base` file in the vault with valid YAML content.
2. **Define scope**: `filters` select notes by tag, folder, property, or date.
3. **Add formulas** (optional): computed properties in `formulas`.
4. **Configure views**: one or more `table` / `cards` / `list` / `map` views,
   with `order` listing the properties to display.

Minimal example:

```yaml
filters:
  and:
    - file.hasTag("task")
formulas:
  days_until_due: 'if(due, (date(due) - today()).days, "")'
views:
  - type: table
    name: "Active Tasks"
    order:
      - file.name
      - status
      - formula.days_until_due
```

## Step 4: Validate

Verify the file is valid YAML with no syntax errors, and that every referenced
property and formula exists. Common issues: unquoted strings containing
special YAML characters, mismatched quotes in formula expressions, referencing
`formula.X` without defining `X` in `formulas`, and calling `.round()` on a
Duration instead of on `.days`. On any failure, fix it and re-validate
(`references/TROUBLESHOOTING.md`); do not report success until it passes.
Then have the user open it in Obsidian; a YAML error there means the quoting rules.

## Step 5: Report

```
[OK] <path>.base  views=<n> formulas=<n>
[FAIL] <path>.base  <YAML or reference error>
Next: open <path>.base in Obsidian, or embed it with ![[<name>.base]]
```

## Related Skills

- `/pkm:obsidian-markdown` — note syntax, including embedding a base in a note.
- `/pkm:obsidian-canvas` — `.canvas` files; `/pkm:obsidian-cli` — drive the
  running app. Obsidian doc links: end of `references/SCHEMA.md`.
