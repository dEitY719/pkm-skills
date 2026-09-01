# Installing pkm for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- For the Obsidian skills: a local, git-backed Obsidian vault
- For the Karakeep skills: a reachable Karakeep instance and its API token, in a
  `.env` the skill can read (`NEXTAUTH_URL`, `KARAKEEP_API_KEY`)

## Installation

Add the plugin to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["pkm-skills@git+https://github.com/dEitY719/pkm-skills.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers all four skills.

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install this plugin separately for each one.

## Usage

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
use skill tool to load karakeep-classify
```

## Tool mapping

The authoritative OpenCode tool mapping for every `dEitY719/*-skills` repo lives
in the sibling repo `harness-skills`, at
[`references/opencode-tools.md`](https://github.com/dEitY719/harness-skills/blob/main/references/opencode-tools.md).
This repo owns no copy — one tool rename must stay one edit. Read it when a
skill names a tool you do not recognise. Short version:

- "Read a file" -> `read`
- "Create a file" / "edit a file" -> `apply_patch`
- "Run a shell command" -> `bash`
- "Search file contents" / "find files by name" -> `grep`, `glob`
- "Create a todo" -> `todowrite`
- "Dispatch a subagent" -> `task` with `subagent_type: "general"` (or
  `"explore"` for read-only exploration)
- "Invoke a skill" -> OpenCode's native `skill` tool

Two gaps matter here:

- The `lib/*.sh` helpers that `obsidian-session-clip` and
  `obsidian-resolve-conflict` call are plain bash. Run them with `bash` and pass
  their `[OK]` / `[FAIL]` lines through verbatim — do not reimplement them.
- `karakeep-classify` declares Claude Code's `WebFetch` for reading a page title
  and meta description. OpenCode has no equivalent tool: use `bash` with
  `curl -sL`, or skip the fetch. It is optional — host and path usually decide
  the List, and a full-body fetch is never wanted.

## Safety contracts

- `karakeep-classify` is dry-run by default and writes nothing; `--apply` hands
  the write to `karakeep-add`.
- `karakeep-add` writes to the live Karakeep instance. It is idempotent and
  refuses a public or personal URL under the `Company` subtree.
- `obsidian-resolve-conflict` runs destructive git operations on the vault.
  OpenCode has no structured question tool — ask in the conversation and wait
  for a real answer before resolving any note-body conflict. Never auto-merge a
  note body, never rewrite vault history, never force-push.
- `obsidian-session-clip` is explicit-invocation only. Never trigger it because
  a session looks finished.

## Troubleshooting

### Plugin not loading

1. Check logs: `opencode run --print-logs "hello" 2>&1 | grep -i pkm`
2. Verify the plugin line in your `opencode.json`
3. Make sure you are running a recent version of OpenCode

### Skills not found

1. Use the `skill` tool to list what was discovered
2. Check that the plugin is loading (see above)

### Karakeep skills fail immediately

`NEXTAUTH_URL` or `KARAKEEP_API_KEY` is unset. Both skills fail loudly rather
than guessing a base URL — they will never fall back to `localhost`.

## Getting Help

Report issues: https://github.com/dEitY719/pkm-skills/issues
