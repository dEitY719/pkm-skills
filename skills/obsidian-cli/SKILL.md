---
name: obsidian-cli
description: >-
  Drive a running Obsidian app with the `obsidian` CLI: read, search, append
  notes; reload and debug plugins. Use for /pkm:obsidian-cli, "옵시디언 CLI로
  노트 검색해줘", "reload my obsidian plugin". Do NOT use to hand-edit
  .md/.base/.canvas files.
allowed-tools: Bash, Read
license: MIT
compatibility:
  tools: "obsidian CLI on PATH, Obsidian desktop running"
metadata:
  model_recommendation:
    tier: haiku
    reason: "structured CLI wrapping against a local app; low reasoning, bounded output"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-cli — drive a running Obsidian

Use the `obsidian` CLI to interact with a running Obsidian instance: read,
create, search, and manage notes, tasks, and properties, and develop or debug
plugins and themes. Requires the Obsidian desktop app to be open. Commands act
on the local vault through the app; nothing here contacts a remote.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. Run no `obsidian` command.

## Step 1: Preflight

`command -v obsidian` must succeed and Obsidian must be open. Either missing is
a stop: print `[FAIL] obsidian CLI unavailable (<reason>)` and do not fall back
to editing vault files by hand.

## Step 2: Load only the reference you need

| Need | Read |
|------|------|
| Parameter and flag syntax, file / vault targeting, common note commands | `references/COMMANDS.md` |
| Plugin / theme develop-test cycle, `eval`, CSS, mobile emulation | `references/PLUGIN_DEV.md` |

`obsidian help` lists every command and is always up to date; full docs at
https://help.obsidian.md/cli.

## Step 3: Run the command

Parameters take a value with `=` (quote values with spaces); flags are bare
switches. Without `file=` or `path=` the active file is used; without
`vault=` the most recently focused vault is used.

```bash
obsidian read file="My Note"
obsidian search query="search term" limit=10
obsidian vault="My Vault" daily:append content="- [ ] New task"
```

Use `silent` to keep files from opening. A writing command (`create`,
`append`, `property:set`, `eval`) changes the user's vault: confirm the target
file and vault first.

## Step 4: Check the result

A non-zero exit or an error line is a stop: show it verbatim and do not retry
with different guesses. For plugin work, follow the reload, `dev:errors`,
screenshot / DOM, `dev:console` loop in `references/PLUGIN_DEV.md` until
`dev:errors` is clean.

## Step 5: Report

```
[OK] obsidian <command>  <one-line result>
[FAIL] obsidian <command>  <error line>
Next: <follow-up command, e.g. obsidian dev:errors after a plugin:reload>
```

## Related Skills

- `/pkm:obsidian-markdown`, `/pkm:obsidian-bases`, `/pkm:obsidian-canvas` —
  edit note, base, and canvas files directly when the app is not running.
