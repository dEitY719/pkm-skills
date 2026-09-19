# pkm:obsidian-cli — Help

Run the `obsidian` CLI against a running Obsidian desktop app: read, create,
search, and append notes, manage tasks and properties, and reload or debug
plugins and themes.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `[request]` | Free text or an `obsidian` subcommand to run | — |
| `vault=<name>` | Target a specific vault (first parameter) | most recently focused vault |
| `file=<name>` / `path=<path>` | Target a note by wikilink name or vault path | active file |
| `-h` / `--help` / `help` | Print this help and stop | — |

## Requirements

- The Obsidian desktop app is running.
- The `obsidian` CLI is on `PATH` (`obsidian help` lists every command).

## Usage

- `/pkm:obsidian-cli search my vault for "karakeep"`
- `/pkm:obsidian-cli reload plugin my-plugin and show errors`
- `/pkm:obsidian-cli -h`

## What the skill will NOT do

- Edit vault files by hand when the CLI or the app is unavailable.
- Commit, push, or sync the vault.

## Output example

```
[OK] obsidian plugin:reload id=my-plugin  reloaded
Next: obsidian dev:errors
```
