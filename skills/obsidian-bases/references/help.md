# pkm:obsidian-bases — Help

Create or edit an Obsidian Bases (`.base`) file: filters, formulas, property
display names, summaries, and table / cards / list / map views.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `[path]` | The `.base` file to create or edit | asked, or inferred from the request |
| `[request]` | Free text: what the base should show | — |
| `-h` / `--help` / `help` | Print this help and stop | — |

## Usage

- `/pkm:obsidian-bases Projects/tasks.base table of open tasks grouped by status`
- `/pkm:obsidian-bases Reading.base add a reading_time formula`
- `/pkm:obsidian-bases -h`

## What the skill will NOT do

- Create a vault folder that does not exist.
- Commit, push, or sync the vault.
- Edit `.md` note syntax (`/pkm:obsidian-markdown`) or `.canvas` files
  (`/pkm:obsidian-canvas`).

## Output example

```
[OK] Projects/tasks.base  views=2 formulas=3
Next: open Projects/tasks.base in Obsidian, or embed it with ![[tasks.base]]
```
