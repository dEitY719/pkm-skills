# pkm-skills

Four skills for personal knowledge management across two services — clip a
finished AI session into an Obsidian vault, resolve that vault's sync conflicts,
file a URL into Karakeep, and decide where a URL belongs before filing it.
Packaged as a single plugin named `pkm`, installable on six coding-agent
harnesses.

Unlike its sibling [`harness-skills`](https://github.com/dEitY719/harness-skills),
this repo owns no shared assets — it links out for the
[per-harness tool mappings and the CI workflow](#shared-assets).

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| `obsidian-session-clip` | `/pkm:obsidian-session-clip [description] [--no-commit] [--dry-run] [--vault <path>]` | Writes the current AI session to the vault as one markdown note under `99-Inbox/ai-session/`, classified `code` or `research`, then commits that single file. **Explicit invocation only** — never auto-triggered. |
| `obsidian-resolve-conflict` | `/pkm:obsidian-resolve-conflict [windows\|wsl] [--no-push] [--no-sync-peer] [--dry-run] [--vault <path>]` | Diagnoses a vault `git pull` conflict, sorts it into local-state / note-body / other, auto-resolves only the local-state class, asks about the rest, commits, pushes, and fast-forwards the peer clone. |
| `karakeep-classify` | `/pkm:karakeep-classify <url> [--apply]` | Reads the live Karakeep List tree and proposes the best-fit List path for a URL, with a rationale and the exact follow-up command. Dry-run by default; writes nothing. |
| `karakeep-add` | `/pkm:karakeep-add <url> --list <path>` | Adds the URL to that List over REST, creating every missing parent in a nested `parent/child` path. Idempotent on both the List and the bookmark. |

The two Karakeep skills are a propose-then-confirm pair: `karakeep-classify`
judges, `karakeep-add` writes. Running `karakeep-add` without `--list` delegates
to `karakeep-classify` rather than guessing.

The two Obsidian skills share a vault but not a remote: `obsidian-session-clip`
never contacts one, `obsidian-resolve-conflict` exists to synchronise with one.

## Requirements

| Skill | Needs |
|-------|-------|
| `obsidian-session-clip` | A local git-backed PARA vault. Resolution order: `--vault` > `$OBSIDIAN_VAULT_DIR` > a default derived from `~/.dotfiles-setup-mode`. A missing vault is a stop, never a `mkdir`. |
| `obsidian-resolve-conflict` | Two clones of the same vault remote (`windows` / `wsl`). Overrides: `$OBSIDIAN_VAULT_WIN_DIR`, `$OBSIDIAN_VAULT_DIR`, `$OBSIDIAN_VAULT_WIN_ROOT` (default `/mnt/c/Users`), `$OBSIDIAN_VAULT_WIN_NAME` (default `ObsidianVault-PARA`), `$OBSIDIAN_VAULT_WSL_ROOT` (default `$HOME/para/project`). |
| `karakeep-add`, `karakeep-classify` | A reachable Karakeep instance and its API token, read from the working directory's `.env`: `NEXTAUTH_URL` (the live base URL — never `localhost:3001`) and `KARAKEEP_API_KEY`. Either unset is a hard failure, not a fallback. |

## Install

### Claude Code

```
/plugin marketplace add dEitY719/pkm-skills
/plugin install pkm@pkm-skills
```

### Codex

```
codex plugin install dEitY719/pkm-skills
```

### Kimi CLI

```
kimi plugin install dEitY719/pkm-skills
```

### Hermes Agent

```
hermes plugins install dEitY719/pkm-skills
```

### OpenCode

See [`.opencode/INSTALL.md`](.opencode/INSTALL.md).

### Gemini CLI / Antigravity

```
gemini extensions install https://github.com/dEitY719/pkm-skills
```

Antigravity (`agy`) shares `~/.gemini`, so it inherits the install.

## Harness support

These skills are shell, REST, and file writes — they port better than most. The
only Claude-Code-specific tools they reach for are `WebFetch` (in
`karakeep-classify`) and `Skill()` (used by each Karakeep skill to hand off to
the other). Both have straightforward substitutes. Every gap and its workaround
is documented per harness in
[`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `obsidian-session-clip` | full | full | full | full | full | full |
| `obsidian-resolve-conflict` | full | full, confirm in chat | full | full | full, confirm in chat | full, confirm in chat |
| `karakeep-classify` | full | needs `curl` | needs `curl` | full | full | needs `curl` |
| `karakeep-add` | full | full | full | full | full | full |

*confirm in chat* — the skill must stop and ask before resolving a note-body
conflict. Kimi (`AskUserQuestion`) and Gemini (`ask_user`) have a structured
question tool; Codex, Hermes, Antigravity, and OpenCode do not, so ask in the
conversation and wait for a real reply. An auto-approve session setting is not
the user's answer.

*needs `curl`* — `karakeep-classify` fetches a page title and meta description.
Gemini maps this to `web_fetch` and Hermes to `web_extract`; elsewhere use the
shell tool with `curl -sL`. The fetch is optional in the first place — host and
path usually decide the List, and a full-body fetch is never wanted.

`Skill(pkm:karakeep-add, ...)` has no equivalent outside Claude Code. Read the
sibling skill's `SKILL.md` and follow it inline; the handoff contract (a URL and
a List path) is unchanged.

The `lib/*.sh` helpers under `obsidian-session-clip` and
`obsidian-resolve-conflict` are plain POSIX-friendly bash and run identically on
every harness. Call them; do not reimplement them.

## Shared assets

This repo owns none — deliberately.

- **Per-harness tool mappings** live in
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`{codex,kimi,gemini,antigravity,hermes,opencode}-tools.md`). That repo is
  their sole owner; the other fourteen `*-skills` repos link there rather than
  carrying copies, so one tool rename is one edit, not fifteen
  (dotfiles #1410 F-5 / NF-2). The only condensed mirror here is
  `.kimi-plugin/plugin.json`'s `skillInstructions`, because Kimi CLI cannot read
  a reference file at load time — it points back to the canonical file.
- **The reusable CI workflow** is
  [`harness-skills/.github/workflows/skill-check.yml`](https://github.com/dEitY719/harness-skills/blob/main/.github/workflows/skill-check.yml)
  (#1410 D-10). See [CI](#ci).

## Layout

Manifests live at the repo root and all point at one flat `skills/` directory:

```
.
├── skills/{obsidian-session-clip,obsidian-resolve-conflict,karakeep-add,karakeep-classify}/
│   ├── SKILL.md
│   ├── references/
│   └── lib/                                  (obsidian skills only)
├── .claude-plugin/{marketplace,plugin}.json  Claude Code
├── .codex-plugin/plugin.json                 Codex
├── .kimi-plugin/plugin.json                  Kimi CLI
├── .hermes-plugin/{plugin.yaml,__init__.py}  Hermes Agent
├── .opencode/plugins/pkm.js + INSTALL.md     OpenCode
├── .agents/plugins/marketplace.json          Antigravity
├── gemini-extension.json + GEMINI.md         Gemini CLI
├── package.json
├── CLAUDE.md · AGENTS.md -> CLAUDE.md
└── LICENSE
```

Only Claude Code understands a nested `plugins/<name>/skills/` layout. The other
five harnesses resolve manifests at the repo root and a skills tree at
`./skills/`, so this repo keeps everything flat. See [`CLAUDE.md`](CLAUDE.md) for
the full rationale and contribution rules.

Skill directory names keep their service prefix (`obsidian-`, `karakeep-`).
Unlike the `devx-` prefix that `harness-skills` dropped, these name two
different external services inside one plugin, and the invocation form reads
`/pkm:karakeep-add` — no stutter to avoid.

The `.kimi-plugin/` manifest is pre-provisioned: Kimi CLI is not installed on the
maintainer's machines yet, and shipping the manifest now costs nothing and saves
a migration later.

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) calls the
reusable workflow owned by `harness-skills`:

```yaml
jobs:
  validate:
    uses: dEitY719/harness-skills/.github/workflows/skill-check.yml@main
    with:
      plugin-name: pkm
```

It validates manifests, skill frontmatter (the `name:` must be bare and match
the directory), progressive-disclosure line limits, the Codex description
budget, version agreement across all seven manifests, shell scripts, and the
no-emoji rule. There is no local copy to keep in sync; a check added upstream
applies here on the next run.

## Provenance

These skills were extracted from
[`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/{obsidian-session-clip,obsidian-resolve-conflict,karakeep-add,karakeep-classify}`)
as a content snapshot at source commit `e2e231fcc8bbe69eba69e078cbe087ba44d856bb`
— no history rewriting. The dotfiles copies remain in place; they are removed in
Phase 4 of that repo's migration. Behaviour is unchanged from the snapshot; only
the namespace moved, from `obsidian:` / `karakeep:` to `pkm:`.

This is Phase 1 of the dotfiles #1410 migration. `packaging-skills` was Phase 0,
and `harness-skills` is the sibling that owns the shared assets this repo links
to.

## License

MIT. See [LICENSE](LICENSE).
