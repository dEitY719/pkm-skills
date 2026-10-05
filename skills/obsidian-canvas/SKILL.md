---
name: obsidian-canvas
description: >-
  Create and edit Obsidian JSON Canvas (.canvas) nodes, edges, and groups. Use
  for /pkm:obsidian-canvas, "캔버스로 마인드맵 그려줘", "add a node to this
  .canvas". Do NOT use for .base views — use pkm:obsidian-bases.
allowed-tools: Read, Write, Edit, Bash
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "JSON edits with ID and edge-reference integrity plus layout judgment; one file, no external writes"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-canvas — JSON Canvas (.canvas) files

A `.canvas` file is JSON following the
[JSON Canvas Spec 1.0](https://jsoncanvas.org/spec/1.0/): two optional
top-level arrays, `nodes` and `edges`. This skill edits one canvas file in the
user's vault. It never commits, never syncs, and never touches a remote.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No file writes.

## Step 1: Pick the workflow

Read `references/WORKFLOWS.md` and follow the one that matches: create a new
canvas, add a node, connect two nodes, or edit an existing canvas. Editing →
read and parse the existing file first.

## Step 2: Load only the reference you need

| Need | Read |
|------|------|
| Node attributes (text, file, link, group), edges, colors, ID format, layout sizes | `references/SPEC.md` |
| Full mind map, project board, research canvas, and flowchart | `references/EXAMPLES.md` |

## Step 3: Write the canvas

- Every node needs `id`, `type`, `x`, `y`, `width`, `height`; array order is
  z-index (first = bottom layer).
- IDs are 16-character lowercase hex (e.g. `"6f0ad84f44ce9c17"`), unique
  across nodes **and** edges.
- Space nodes 50-100px apart and leave 20-50px padding inside groups.
- Use `\n` for line breaks in JSON strings. Do **not** use the literal `\\n` —
  Obsidian renders that as the characters `\` and `n`.

## Step 4: Validate

Run the validator after every create or edit:

```bash
_s=""
if [ -n "${HERMES_SKILL_DIR}" ]; then _s="${HERMES_SKILL_DIR}/lib/validate-canvas.py"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then _s="$CLAUDE_PLUGIN_ROOT/skills/obsidian-canvas/lib/validate-canvas.py"
fi
[ -n "$_s" ] && [ -f "$_s" ] || { printf '[FAIL] plugin root unresolved (tried: %s). Export HERMES_SKILL_DIR=<this skill dir> or CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' "${_s:-nothing}" >&2; return 1 2>/dev/null || exit 1; }
python3 "$_s" <file.canvas>
```

Relay its `[OK]` / `[FAIL] ... check <n>: ...` lines verbatim. On exit 1, fix
each named check and re-run; report success only on exit 0. Exit 2 is a bad
path. The eight checks and their fixes: `references/validation.md`.

## Step 5: Report

```
[OK] <path>.canvas  nodes=<n> edges=<n>
[FAIL] <path>.canvas  check <n>: <detail>
Next: open <path>.canvas in Obsidian to check the layout
```

## Related Skills

- `/pkm:obsidian-markdown` — the Markdown inside text nodes and linked notes.
- `/pkm:obsidian-bases` for `.base` files, `/pkm:obsidian-cli` to drive the
  running app.
