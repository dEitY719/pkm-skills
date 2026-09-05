#!/usr/bin/env bash
# tests/karakeep-lib-check.sh
#
# One runnable check for the deterministic half of the two Karakeep skills.
# Offline by design: it exercises the paths that decide whether a live REST
# write happens at all — argument validation, the Company confidentiality
# gate, the env contract, and List-path reconstruction — none of which need
# a Karakeep instance. The network paths (create / dedup / attach / verify)
# are deliberately out of scope; asserting them would mean shipping a stub
# HTTP server, and the guards below are what stand between a typo and a
# write to the user's real bookmark database.
#
# Usage:
#   bash tests/karakeep-lib-check.sh
# Exits 0 when every assertion passes, 1 on the first failure.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/skills/karakeep-add/lib"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# Run a lib script with no Karakeep credentials in the environment, so a test
# machine that happens to have a live .env cannot turn an assertion green.
run_lib() {
    (cd "$TMP" && env -u NEXTAUTH_URL -u KARAKEEP_API_KEY bash "$@" 2>&1)
}

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        printf '[OK]   %s\n' "$label"
    else
        printf '[FAIL] %s\n       expected: %s\n       actual:   %s\n' \
            "$label" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

check_contains() {
    local label="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) printf '[OK]   %s\n' "$label" ;;
        *)
            printf '[FAIL] %s\n       missing: %s\n       actual:  %s\n' \
                "$label" "$needle" "$haystack"
            failures=$((failures + 1))
            ;;
    esac
}

# --- argument validation: never guess, never write on a malformed call ------

out=$(run_lib "$LIB/karakeep-add.sh")
check_contains "no <url> is refused" "FAIL: missing <url>" "$out"

out=$(run_lib "$LIB/karakeep-add.sh" https://example.com)
check_contains "no --list is refused (never guesses a List)" \
    "FAIL: missing --list" "$out"

out=$(run_lib "$LIB/karakeep-add.sh" https://example.com --list AI --bogus)
check_contains "unknown flag is refused" "FAIL: unknown argument" "$out"

# --- Company confidentiality boundary: fails closed -------------------------

out=$(run_lib "$LIB/karakeep-add.sh" https://example.com --list Company)
check_contains "bare Company path is refused without --allow-company" \
    "inside the Company subtree" "$out"

out=$(run_lib "$LIB/karakeep-add.sh" https://example.com --list Company/Docs)
check_contains "nested Company path is refused without --allow-company" \
    "inside the Company subtree" "$out"

# With --allow-company the gate opens, so the run proceeds far enough to hit
# the env contract instead. That is the assertion: the guard is what stopped
# the two runs above, not a missing variable.
out=$(run_lib "$LIB/karakeep-add.sh" https://example.com --list Company/Docs --allow-company)
check_contains "--allow-company opens the gate (stops later, at the env check)" \
    "NEXTAUTH_URL" "$out"

# --- env contract: no guessed base URL, no localhost fallback ---------------

out=$(run_lib "$LIB/karakeep-env.sh")
check_contains "unset NEXTAUTH_URL is fatal" "NEXTAUTH_URL" "$out"
case "$out" in
    *localhost*)
        printf '[FAIL] env failure must not suggest a localhost fallback\n'
        failures=$((failures + 1))
        ;;
    *) printf '[OK]   env failure suggests no localhost fallback\n' ;;
esac

printf 'NEXTAUTH_URL=https://karakeep.example.test/\nKARAKEEP_API_KEY=s3cr3t-must-not-leak\n' >"$TMP/.env"
out=$(cd "$TMP" && env -u NEXTAUTH_URL -u KARAKEEP_API_KEY bash "$LIB/karakeep-env.sh" 2>&1)
check "base URL is NEXTAUTH_URL, trailing slash stripped" \
    "https://karakeep.example.test" "$out"
case "$out" in
    *s3cr3t-must-not-leak*)
        printf '[FAIL] karakeep-env.sh leaked the API key on stdout\n'
        failures=$((failures + 1))
        ;;
    *) printf '[OK]   API key is never printed\n' ;;
esac
rm -f "$TMP/.env"

# --- list-tree.sh: parentId reconstruction, one implementation, two sources -

python3 - "$TMP/kk.db" <<'PY'
import sqlite3, sys

db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE bookmarkLists (id TEXT, parentId TEXT, name TEXT)")
db.executemany("INSERT INTO bookmarkLists VALUES (?,?,?)", [
    ("a", None, "AI"),            # root
    ("b", "a", "Agent Tooling"),  # child -> full path
    ("c", "zz", "Orphan"),        # dangling parentId: visible, not dropped
    ("d", "e", "Loop1"),          # mutual cycle: must terminate
    ("e", "d", "Loop2"),
])
db.commit()
PY

out=$(run_lib "$LIB/list-tree.sh" --db "$TMP/kk.db")
check_contains "root List keeps its bare name" "$(printf 'a\tAI')" "$out"
check_contains "child List gets the full slash path" \
    "$(printf 'b\tAI/Agent Tooling')" "$out"
check_contains "dangling parentId stays visible" "$(printf 'c\tOrphan')" "$out"
check "cyclic parentId terminates rather than hanging or recursing forever" \
    "5" "$(printf '%s\n' "$out" | grep -c .)"

out=$(run_lib "$LIB/list-tree.sh" --db)
check_contains "--db without a path is refused" "FAIL: --db needs a path" "$out"

# REST mode must reach the shared env contract, not invent a base URL.
out=$(run_lib "$LIB/list-tree.sh")
check_contains "REST mode requires the env contract" "NEXTAUTH_URL" "$out"

# ---------------------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    printf '\n[OK] karakeep lib check passed\n'
    exit 0
fi
printf '\n[FAIL] %s assertion(s) failed\n' "$failures"
exit 1
