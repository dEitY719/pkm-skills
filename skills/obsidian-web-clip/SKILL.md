---
name: obsidian-web-clip
description: >-
  Deprecated stub: /pkm:obsidian-web-clip 는 pkm:obsidian-clip 으로 흡수됐다. 안내만 하고
  아무것도 쓰지 않는다. Use only when /pkm:obsidian-web-clip is invoked by name.
allowed-tools: Bash
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "prints a fixed notice; no logic"
    claude: prefer
    non_claude: advisory-only
---

# pkm:obsidian-web-clip — deprecated

This skill is a one-release deprecation stub. It is removed in the next
release.

## Step 1: Notice

Whatever the arguments (including `-h`), print exactly these lines and stop:

```
[WARN] /pkm:obsidian-web-clip 는 폐기됐다 -- /pkm:obsidian-clip 으로 흡수
Next: /pkm:obsidian-clip <url> [--vault <path>]
```

## Constraints

- Write nothing, fetch nothing, never run `/pkm:obsidian-clip` on the user's
  behalf — the user re-runs it with the new name.
- Notes go to `99-Inbox/` now, not `99-Inbox/Web/`; existing notes stay where
  they are.

## Related Skills

- [[pkm:obsidian-clip]] replaces this skill for URLs, YouTube and local documents.
