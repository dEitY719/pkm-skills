# pkm:obsidian-canvas — Help

Create or edit an Obsidian JSON Canvas (`.canvas`) file: text, file, link, and
group nodes, and the edges between them.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `[path]` | The `.canvas` file to create or edit | asked, or inferred from the request |
| `[request]` | Free text: what to draw or change | — |
| `-h` / `--help` / `help` | Print this help and stop | — |

## Usage

- `/pkm:obsidian-canvas Maps/project.canvas mind map of the Q3 roadmap`
- `/pkm:obsidian-canvas Maps/project.canvas connect "Design" to "Build"`
- `/pkm:obsidian-canvas -h`

## What the skill will NOT do

- Leave a duplicate ID or a dangling edge reference in the file.
- Commit, push, or sync the vault.
- Edit `.base` files (`/pkm:obsidian-bases`).

## Output example

```
[OK] Maps/project.canvas  nodes=7 edges=6
Next: open Maps/project.canvas in Obsidian to check the layout
```
