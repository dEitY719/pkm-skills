# Canvas validation checks

`lib/validate-canvas.py <file.canvas>` runs these eight checks. Each violation
prints `[FAIL] <path>  check <n>: <detail>`; a clean file prints
`[OK] <path>  nodes=<n> edges=<n>`. Exit 0 = pass, 1 = violations,
2 = usage error or unreadable file.

| # | Check |
|---|-------|
| 1 | Every `id` is present and unique across both nodes **and** edges |
| 2 | Every edge `fromNode` and `toNode` names an existing node `id` |
| 3 | Type-specific field present: `text` for text nodes, `file` for file nodes, `url` for link nodes |
| 4 | Node `type` is one of `text`, `file`, `link`, `group` |
| 5 | Edge `fromSide` / `toSide`, when set, is one of `top`, `right`, `bottom`, `left` |
| 6 | Edge `fromEnd` / `toEnd`, when set, is one of `none`, `arrow` |
| 7 | `color`, when set, is a preset `"1"` through `"6"` or a hex string (`"#FF0000"`) |
| 8 | The file is parseable JSON with `nodes` / `edges` arrays of objects |

Check 8 failing stops the run: the other seven are skipped, since nothing
reliable can be read from a file that does not parse.

## Fixing a failure

- **check 1** — regenerate the colliding id as a fresh 16-character lowercase
  hex string, not by incrementing it.
- **check 2** — the edge points at a deleted or mistyped node: fix the id, or
  drop the edge.
- **check 8** — usually an unescaped newline or quote inside a `text` value.
  Write line breaks as `\n`, never a raw newline and never the literal `\\n`.

Re-run the validator after every fix; report success only on exit 0. The
script checks structure, not layout: overlapping nodes and cramped groups are
still yours to judge (spacing rules: `references/SPEC.md`).
