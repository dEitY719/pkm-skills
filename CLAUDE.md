# pkm-skills — Contributor Guidelines

This file is the AI context document for this repo. `AGENTS.md` is a symlink to
it, so Claude Code, Codex, Gemini CLI, and every other harness read the same
text. Edit `CLAUDE.md`; never replace the symlink with a second copy.

## What this repo is

A single-plugin skill marketplace. The plugin is named `pkm` and it bundles four
personal-knowledge-management skills spanning two external services:

| Skill | Service | Role |
|-------|---------|------|
| `obsidian-session-clip` | Obsidian vault | Writes one markdown note per finished AI session into `99-Inbox/ai-session/` and commits just that file. |
| `obsidian-resolve-conflict` | Obsidian vault | Resolves a vault `git pull` conflict: classify, resolve, commit, push, fast-forward the peer clone. |
| `karakeep-classify` | Karakeep | Reads the live List tree and proposes where a URL belongs. Dry-run by default. |
| `karakeep-add` | Karakeep | Writes the URL into that List over REST, creating missing parents. Idempotent. |

They write to the user's real personal data — a vault of notes they wrote by
hand, and a bookmark database. That is the reason this domain is its own repo,
and the reason every safety contract below is a hard rule rather than a
preference.

The skills were extracted from `dEitY719/dotfiles`
(`claude/skills/{obsidian-session-clip,obsidian-resolve-conflict,karakeep-add,karakeep-classify}`)
as a content snapshot at source commit
`e2e231fcc8bbe69eba69e078cbe087ba44d856bb` — no history rewriting. The dotfiles
copies remain in place; they are removed in Phase 4 of that repo's migration
plan. This is Phase 1 of dEitY719/dotfiles#1410; `packaging-skills` was Phase 0 and
`harness-skills` is the sibling that owns the shared assets.

## Layout: root manifests, one flat `skills/`

This repo deliberately does **not** use the nested `plugins/<name>/skills/`
"mono" layout. Every harness manifest sits at the repo root and points at a
single flat `./skills/` directory:

```
.claude-plugin/{marketplace,plugin}.json   Claude Code
.codex-plugin/plugin.json                  Codex
.kimi-plugin/plugin.json                   Kimi CLI
.hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
.opencode/plugins/pkm.js                   OpenCode
.agents/plugins/marketplace.json           Antigravity
gemini-extension.json + GEMINI.md          Gemini CLI
skills/<name>/SKILL.md                     the skills themselves
```

Only Claude Code understands the nested mono layout. The other five harnesses
resolve manifests at the repo root and a skills tree at `./skills/`, so nesting
would silently cut this plugin down to Claude-Code-only. **Do not move the
manifests under a `plugins/` directory.**

## Shared assets live elsewhere — link, never copy

This repo owns none. Both belong to `dEitY719/harness-skills`:

**1. Per-harness tool mappings** (`references/*-tools.md` there,
dEitY719/dotfiles#1410
F-5). Do not create a `references/` directory at this repo's root. If a doc here
needs a mapping, link to
`https://github.com/dEitY719/harness-skills/blob/main/references/<harness>-tools.md`.
One tool rename must stay one edit, not fifteen (NF-2). The single sanctioned
mirror is the condensed summary inside `.kimi-plugin/plugin.json`'s
`skillInstructions`, because Kimi CLI cannot read a reference file at load time;
keep it short and keep it pointing upstream.

**2. The reusable CI workflow** (`.github/workflows/skill-check.yml` there,
D-10). This repo's `validate.yml` calls it with `plugin-name: pkm` and nothing
else. Do not fork it into a standalone workflow — a check added upstream should
apply here on the next run, which is the whole point.

## Rules for changing skills

- **Skill directory name is the identity.** `skills/<name>/` must match the
  `name:` field in that skill's `SKILL.md` frontmatter, and that field is the
  **bare** name (`karakeep-add`), never namespaced (`pkm:karakeep-add`). CI
  fails on a `:` in the name. The harness supplies the `pkm:` prefix at
  invocation time.
- **Service prefixes stay.** `obsidian-` and `karakeep-` are not redundant here:
  they separate two different external services inside one plugin, and
  `/pkm:karakeep-add` reads cleanly. Do not shorten them to `add` / `classify`.
- **Invocation form in prose is namespaced.** Body text referring to a skill as
  a command writes `/pkm:karakeep-add`. The old dash-form aliases
  (`/karakeep-add`, `/obsidian-session-clip`) were dropped in the migration —
  do not reintroduce them.
- **Cross-repo references keep their own namespace.** `notes:task-history`,
  `session:handoff`, and `gh-resolve:conflict` live in other repos of
  this family. Leave them exactly as written; only siblings inside `skills/`
  take the `pkm:` prefix.
- **Progressive disclosure.** `SKILL.md` stays under 100 lines (CI enforces it)
  and names which `references/` file to read and when. Detail lives in
  `references/`; executable steps live in `lib/`. Do not inline either back into
  `SKILL.md` — all four are already within a dozen lines of the limit.
- **Description budget.** CI sums every skill description and fails past 5,440
  characters — Codex's context budget. Keep new descriptions tight.
- **`lib/*.sh` is the contract, not a suggestion.** `resolve-vault.sh`,
  `safe-name.sh`, `commit-note.sh`, `verify-clip.sh`, `classify-conflicts.sh`,
  and `verify-sync.sh` hold the deterministic half of the two Obsidian skills;
  `karakeep-env.sh`, `list-tree.sh`, and `karakeep-add.sh` under
  `skills/karakeep-add/lib/` do the same for the two Karakeep skills, which
  share them rather than keeping a copy each.
  Call them and surface their `[OK]` / `[FAIL]` lines verbatim. Never
  reimplement their logic in prose, and never swallow a warning to keep an exit
  code clean. CI shellchecks them at `--severity=warning`, and
  `bash tests/karakeep-lib-check.sh` asserts the Karakeep guards offline —
  run it after touching that `lib/`.

## Safety contracts

These are acceptance criteria carried over from dotfiles, not advice:

The `(F-n)` / `(NF-n)` tags still sprinkled through `references/` and `lib/`
are those dotfiles-era criterion ids. Nothing in this repo defines them, and
nothing needs to: in every case the rule is spelled out in the sentence that
carries the tag. Treat a tag as provenance, not as a pointer to look up — and
do not add new ones.

- **`obsidian-session-clip` is never auto-triggered.** "The session looks
  finished" is not an invocation. It runs on an explicit request only. It
  commits the one note it created, by pathspec — never `-a`, `-A`, or
  `git add .`, which would swallow a parallel session's note — and never
  contacts a remote; obsidian-git owns vault sync.
- **`obsidian-resolve-conflict` is destructive and merge-only.** Never rewrite
  vault history, never force-push, never reset the worktree destructively, never
  delete a directory tree, never delete `.git/index.lock` (back off and retry),
  never create a vault to make a path resolve. Note bodies are **never**
  auto-merged: present the per-file summary and let the user choose. Confirm
  through `AskUserQuestion` before any resolution the user has not approved, and
  print `BACKUP_SHA` first so they can undo without you.
- **`karakeep-classify` is dry-run by default** and read-only. `--apply` does not
  add a second write path; it delegates to `karakeep-add`.
- **`karakeep-add` performs live REST writes.** It must stay idempotent (no
  duplicate List for the same name+parent, no duplicate bookmark for the same
  `url.rstrip("/")`), must read its base URL from `NEXTAUTH_URL` rather than
  guessing or falling back to `localhost:3001`, and must refuse a public or
  personal URL under the `Company` subtree.

## Harness gaps are documented, not worked around silently

These skills are mostly shell, REST, and file writes, so they port well. Two
things do not: `WebFetch` (declared by `karakeep-classify` for a page title and
meta description — substitute the harness's own fetch tool or `curl -sL`, and
remember the fetch is optional) and `Skill()` (the Karakeep handoff — read the
sibling `SKILL.md` and follow it inline). When you add a step that depends on a
Claude-Code-only capability, say so in `README.md`'s harness-support matrix and
open an issue against `harness-skills` so its `references/*-tools.md` gain the
fallback.

## Version bumps

The version appears in seven manifests: `.claude-plugin/marketplace.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.kimi-plugin/plugin.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. CI checks that they agree — bump
all of them together. Versioning is independent per repo (dEitY719/dotfiles#1410 D-9); this repo
does not move in lockstep with its siblings.

## No emojis

Anywhere in this repo. Token efficiency, and CI rejects them.
