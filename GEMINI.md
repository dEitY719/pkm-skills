# pkm — skill index

Four personal-knowledge-management skills across two services. Each lives in
this extension's `skills/` directory. They are explicitly invoked, never
ambient: load the one that matches the request by reading its `SKILL.md`, then
follow it. Do not load all four.

| Skill | Read | Use when |
|-------|------|----------|
| `obsidian-session-clip` | `@./skills/obsidian-session-clip/SKILL.md` | The user explicitly asks to clip this session to their vault. Writes one note to `99-Inbox/ai-session/`. **Never load this on your own initiative** — see the safety rules. |
| `obsidian-resolve-conflict` | `@./skills/obsidian-resolve-conflict/SKILL.md` | An Obsidian vault clone has a `git pull` conflict to diagnose, resolve, commit, and push. Not for PR branches — that is `gh-resolve:conflict`, in another repo. |
| `karakeep-classify` | `@./skills/karakeep-classify/SKILL.md` | Deciding which Karakeep List a URL belongs in. Dry-run by default; writes nothing. |
| `karakeep-add` | `@./skills/karakeep-add/SKILL.md` | Adding a URL to a known Karakeep List path. Only with an explicit `--list`; without one, classify first. |

Each skill's `references/` directory holds the detail it loads on demand, and
the deterministic steps live in `lib/*.sh` (`karakeep-classify` calls its
sibling `karakeep-add`'s).
`SKILL.md` says which file to read and which script to run, and when. Do not
read `references/` up front, and do not reimplement `lib/` in prose.

## What each skill needs

- **Obsidian skills** — a local git-backed vault. Resolution order for
  `obsidian-session-clip`: `--vault` > `$OBSIDIAN_VAULT_DIR` > a default derived
  from `~/.dotfiles-setup-mode`. `obsidian-resolve-conflict` additionally reads
  `$OBSIDIAN_VAULT_WIN_DIR`, `$OBSIDIAN_VAULT_WIN_ROOT`,
  `$OBSIDIAN_VAULT_WIN_NAME`, and `$OBSIDIAN_VAULT_WSL_ROOT`. A path that does
  not resolve is a stop, never a `mkdir`.
- **Karakeep skills** — a reachable Karakeep instance and its API token, read
  from the working directory's `.env`: `NEXTAUTH_URL` and `KARAKEEP_API_KEY`.
  Either unset is a hard failure. Never guess a base URL, never fall back to
  `localhost:3001`.

## Tool mapping for Gemini CLI

The skills speak in actions. On Gemini CLI these resolve to:

- "Read a file" -> `read_file` / `read_many_files`
- "Create a file" / "edit a file" -> `write_file`, `replace`
- "Run a shell command" -> `run_shell_command` (this is how every `lib/*.sh`
  helper and every `curl` call is made)
- "Search file contents" -> `grep_search`
- "Find files by name" -> `glob`
- "Create a todo" -> `write_todos`
- "Ask the user" -> `ask_user`
- "Fetch a URL" -> `web_fetch`
- "Dispatch a subagent" -> `invoke_agent` with `agent_name: "generalist"`

The full mapping, including every capability gap and its workaround, lives in
the sibling repo: `https://github.com/dEitY719/harness-skills/blob/main/references/gemini-tools.md`.
This repo owns no copy. Read it when a skill names a tool you do not recognise.
On Antigravity read `antigravity-tools.md` in that same directory instead —
`agy` shares `~/.gemini` but not Gemini CLI's tool names.

## Capability gaps on Gemini CLI

- `karakeep-classify` declares Claude Code's `WebFetch` for reading a page title
  and meta description. Use `web_fetch`. The fetch is optional in the first
  place — host and path usually decide the List, and a full-body fetch is never
  wanted.
- Both Karakeep skills hand off to each other with Claude Code's
  `Skill(pkm:karakeep-add, ...)`. Gemini has no skill-invocation tool: read the
  sibling `SKILL.md` and follow it inline. The handoff contract is just a URL
  and a List path.
- Nothing else is Claude-Code-specific. The `lib/*.sh` helpers are plain bash
  and run unchanged under `run_shell_command` (the Karakeep pair also needs
  `curl`, `jq`, and `python3` on PATH); pass their `[OK]` / `[FAIL]` lines
  through verbatim rather than summarising them.
- On Antigravity, `ask_user` does not exist — ask in the conversation and wait
  for a real reply before any confirmation step below.

## Safety rules

- `obsidian-session-clip` must **never** be auto-triggered. A finished-looking
  session is not a request. When it does run, it commits only the note it
  created, by pathspec, and never contacts a remote.
- `obsidian-resolve-conflict` performs destructive git operations on the user's
  own notes. Merge only: never rewrite vault history, never force-push, never
  delete `.git/index.lock`, never create a vault to make a path resolve. Note
  bodies are never auto-merged — present the per-file summary and use `ask_user`
  to let the user choose. Print `BACKUP_SHA` before touching anything. An
  auto-approve session setting is not the user's answer.
- `karakeep-classify` is read-only and dry-run by default. Only `--apply`
  mutates, and only by delegating to `karakeep-add`.
- `karakeep-add` writes to the live instance. Keep it idempotent — no duplicate
  List, no duplicate bookmark — and never place a public or personal URL under
  the `Company` subtree.
