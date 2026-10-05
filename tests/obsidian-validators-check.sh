#!/usr/bin/env bash
# tests/obsidian-validators-check.sh
#
# Offline check for the three Obsidian knowledge-skill validators:
# obsidian-canvas/lib/validate-canvas.py, obsidian-bases/lib/validate-base.py
# and obsidian-markdown/lib/check-note.py. Fixtures are written to a temp dir;
# PyYAML is hidden for the no-YAML path so both branches run on any machine.
#
# Usage:
#   bash tests/obsidian-validators-check.sh
# Exits 0 when every assertion passes, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CANVAS="$REPO_ROOT/skills/obsidian-canvas/lib/validate-canvas.py"
BASE="$REPO_ROOT/skills/obsidian-bases/lib/validate-base.py"
NOTE="$REPO_ROOT/skills/obsidian-markdown/lib/check-note.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

check() { # <label> <command...>
    local label="$1"
    shift
    if "$@" >"$TMP/out" 2>&1; then
        printf '[OK]   %s\n' "$label"
    else
        printf '[FAIL] %s\n' "$label"
        sed 's/^/       /' "$TMP/out"
        failures=$((failures + 1))
    fi
}

# expect <want-exit> <want-grep> <command...>: exit code and one output line.
expect() {
    local want="$1" pattern="$2" got
    shift 2
    "$@" >"$TMP/run" 2>&1
    got=$?
    cat "$TMP/run"
    [ "$got" -eq "$want" ] && grep -qF -- "$pattern" "$TMP/run"
}

# A module named yaml that refuses to import: hides PyYAML if it is installed.
mkdir -p "$TMP/noyaml"
printf 'raise ImportError("hidden by test")\n' >"$TMP/noyaml/yaml.py"
noyaml() { PYTHONPATH="$TMP/noyaml" "$@"; }

# --- canvas -----------------------------------------------------------------
N1='{"id":"6f0ad84f44ce9c17","type":"text","text":"a","x":0,"y":0,"width":10,"height":10}'
N2='{"id":"a0b1c2d3e4f5a6b7","type":"link","url":"u","x":0,"y":0,"width":10,"height":10,"color":"#FF0000"}'
E1='{"id":"0123456789abcdef","fromNode":"6f0ad84f44ce9c17","toNode":"a0b1c2d3e4f5a6b7","fromSide":"right","toEnd":"arrow","color":"3"}'
printf '{"nodes":[%s,%s],"edges":[%s]}' "$N1" "$N2" "$E1" >"$TMP/ok.canvas"
printf '{"nodes":[%s,%s],"edges":[]}' "$N1" "$N1" >"$TMP/dup.canvas"
printf '{"nodes":[%s],"edges":[{"id":"e","fromNode":"6f0ad84f44ce9c17","toNode":"gone"}]}' "$N1" >"$TMP/dangling.canvas"
printf '{"nodes":[{"id":"x","type":"image","x":0,"y":0,"width":1,"height":1}]}' >"$TMP/type.canvas"
printf '{"nodes":[{"id":"x","type":"text","text":"a\n' >"$TMP/broken.canvas"
printf '{"nodes":[{"id":"x","type":"file","x":0,"y":0,"width":1,"height":1,"color":"7"}],"edges":[{"id":"e","fromNode":"x","toNode":"x","toSide":"middle","fromEnd":"dot"}]}' >"$TMP/fields.canvas"

check "canvas: valid file passes" expect 0 "[OK] $TMP/ok.canvas  nodes=2 edges=1" python3 "$CANVAS" "$TMP/ok.canvas"
check "canvas: duplicate id -> check 1" expect 1 "check 1: duplicate id" python3 "$CANVAS" "$TMP/dup.canvas"
check "canvas: dangling edge -> check 2" expect 1 "check 2: edge 'e' toNode='gone'" python3 "$CANVAS" "$TMP/dangling.canvas"
check "canvas: bad type -> check 4" expect 1 "check 4: node 'x' has type 'image'" python3 "$CANVAS" "$TMP/type.canvas"
check "canvas: broken JSON -> check 8" expect 1 "check 8:" python3 "$CANVAS" "$TMP/broken.canvas"
check "canvas: missing file field -> check 3" expect 1 "check 3: file node 'x' is missing \`file\`" python3 "$CANVAS" "$TMP/fields.canvas"
check "canvas: bad side -> check 5" expect 1 "check 5: edge 'e' toSide='middle'" python3 "$CANVAS" "$TMP/fields.canvas"
check "canvas: bad end -> check 6" expect 1 "check 6: edge 'e' fromEnd='dot'" python3 "$CANVAS" "$TMP/fields.canvas"
check "canvas: bad color -> check 7" expect 1 "check 7: node 'x' color='7'" python3 "$CANVAS" "$TMP/fields.canvas"
check "canvas: missing file -> exit 2" expect 2 "cannot read" python3 "$CANVAS" "$TMP/none.canvas"

# --- bases ------------------------------------------------------------------
cat >"$TMP/ok.base" <<'YAML'
filters:
  and:
    - file.hasTag("task")
formulas:
  days_until_due: 'if(due, (date(due) - today()).days, "")'
  "is overdue": 'formula.days_until_due < 0'
views:
  - type: table
    name: "Active Tasks"
    order:
      - file.name
      - formula.days_until_due
  - type: cards
    name: Cards
YAML
sed 's/formula.days_until_due$/formula.missing_one/' "$TMP/ok.base" >"$TMP/undef.base"
printf 'views:\n  - type: table\n    name: "unclosed\n' >"$TMP/bad.base"

check "bases: valid file passes (no PyYAML)" expect 0 "[OK] $TMP/ok.base  views=2 formulas=2" noyaml python3 "$BASE" "$TMP/ok.base"
check "bases: no PyYAML -> exact WARN line" expect 0 "[WARN] yaml syntax check skipped (PyYAML not installed)" noyaml python3 "$BASE" "$TMP/ok.base"
check "bases: undefined formula.X -> [FAIL] (no PyYAML)" expect 1 "[FAIL] $TMP/undef.base  12: formula.missing_one" noyaml python3 "$BASE" "$TMP/undef.base"
check "bases: missing file -> exit 2" expect 2 "cannot read" python3 "$BASE" "$TMP/none.base"
if python3 -c 'import yaml' 2>/dev/null; then
    check "bases: valid file passes (PyYAML)" expect 0 "[OK] $TMP/ok.base  views=2 formulas=2" python3 "$BASE" "$TMP/ok.base"
    check "bases: YAML syntax error -> [FAIL] (PyYAML)" expect 1 "[FAIL] $TMP/bad.base" python3 "$BASE" "$TMP/bad.base"
else
    printf '[SKIP] bases: PyYAML branch (PyYAML not installed)\n'
fi

# --- markdown ---------------------------------------------------------------
V="$TMP/vault"
mkdir -p "$V/.obsidian" "$V/Notes/Sub" "$V/Assets"
: >"$V/Notes/Algorithm Notes.md"
: >"$V/Assets/diagram.png"
: >"$V/Notes/Sub/Deep.md"
cat >"$V/Notes/note.md" <<'MD'
---
tags:
  - project
---
See [[Algorithm Notes#Sorting|sorting]], [[Notes/Sub/Deep]] and [[#Local]].

> [!warning] Deadline
> ![[diagram.png|600]]

`[[ignored inline]]`

```
[[ignored fenced]]
```
MD
sed 's/\[\[#Local\]\]/[[Missing Note]] [[Missing Note]]/' "$V/Notes/note.md" >"$V/Notes/broken.md"

check "markdown: all targets resolve" expect 0 "[OK] $V/Notes/note.md  links=3 embeds=1 callouts=1" noyaml python3 "$NOTE" --vault "$V" "$V/Notes/note.md"
check "markdown: missing [[target]] -> UNRESOLVED + exit 1" expect 1 "UNRESOLVED Missing Note" noyaml python3 "$NOTE" --vault "$V" "$V/Notes/broken.md"
check "markdown: unresolved run starts with [FAIL]" expect 1 "[FAIL] $V/Notes/broken.md  links=4" noyaml python3 "$NOTE" --vault "$V" "$V/Notes/broken.md"
dedup() { [ "$(noyaml python3 "$NOTE" --vault "$V" "$V/Notes/broken.md" | grep -c '^UNRESOLVED')" -eq 1 ]; }
check "markdown: one UNRESOLVED line per target" dedup
check "markdown: --vault missing -> exit 2" expect 2 "usage" python3 "$NOTE" "$V/Notes/note.md"

[ "$failures" -eq 0 ] || exit 1
