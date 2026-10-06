#!/usr/bin/env bash
# skills/md-convert/lib/md-convert.selfcheck.sh
#
# Offline check for lib/md-convert.py with a stub `markitdown` on PATH:
# output dir / filename rules, SKIP vs --force, partial failure, the
# .git/info/exclude append, and the refusals that must write nothing.
#
# Usage:
#   bash skills/md-convert/lib/md-convert.selfcheck.sh
# Exits 0 when every assertion passes, 1 otherwise.

# rc is read inside the eval strings below, which shellcheck cannot see.
# shellcheck disable=SC2034
set -uo pipefail

LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PY="$LIB/md-convert.py"
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
failures=0

ok() { printf '[OK]   %s\n' "$1"; }
bad() {
    printf '[FAIL] %s\n' "$1"
    sed 's/^/       /' "$TMP/out"
    failures=$((failures + 1))
}
check() { # <label> <test command...>
    local label="$1"
    shift
    if "$@"; then ok "$label"; else bad "$label"; fi
}
has() { grep -qF -- "$1" "$TMP/out"; }

# Stub: writes "# <input>" to -o; inputs named *empty* give empty output,
# *boom* write a partial file and fail. Every call is logged.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/markitdown" <<SH
#!/bin/sh
echo "\$*" >>"$TMP/calls"
in=\$1; out=\$3
case "\$in" in
*empty*) : >"\$out" ;;
*boom*) echo partial >"\$out"; echo "SSLError: certificate verify failed" >&2; echo more >&2; exit 1 ;;
*) printf '# %s\n' "\$in" >"\$out" ;;
esac
SH
chmod +x "$TMP/bin/markitdown"

run() { # <cwd> <args...>; output in $TMP/out, returns the exit code
    local dir="$1"
    shift
    (cd "$dir" && PATH="$TMP/bin:$PATH" python3 "$PY" "$@") >"$TMP/out" 2>&1
}

# 1. same-dir output
mkdir -p "$TMP/a" && : >"$TMP/a/report.pdf"
run "$TMP" "$TMP/a/report.pdf"
check "local file -> same dir, absolute path reported" \
    eval '[ -s "$TMP/a/report.md" ] && has "[OK] $TMP/a/report.pdf -> $TMP/a/report.md" && has "ok=1 skip=0 fail=0"'

# 2. --output-path creates the dir; relative input + relative output
mkdir -p "$TMP/b" && : >"$TMP/b/a.docx" && : >"$TMP/b/b.pptx" && : >"$TMP/b/c.xlsx"
run "$TMP/b" a.docx b.pptx c.xlsx --output-path out/
check "--output-path created and used for every input" \
    eval '[ -s "$TMP/b/out/a.md" ] && [ -s "$TMP/b/out/b.md" ] && [ -s "$TMP/b/out/c.md" ] && has "ok=3"'

# 3. URL default .md-convert/ in a git cwd + exclude file
mkdir -p "$TMP/repo" && git -C "$TMP/repo" init -q
run "$TMP/repo" https://example.com/page
check "URL -> ./.md-convert/<host>-<slug>.md with absolute path" \
    eval '[ -s "$TMP/repo/.md-convert/example.com-page.md" ] && has "-> $TMP/repo/.md-convert/example.com-page.md"'
check "exclude has exactly one .md-convert/ line" \
    eval '[ "$(grep -cx ".md-convert/" "$TMP/repo/.git/info/exclude")" = 1 ]'
check "git status does not show .md-convert/" \
    eval '[ -z "$(git -C "$TMP/repo" status --porcelain)" ]'
run "$TMP/repo" https://example.com/other/Path_2
check "exclude stays one line on rerun; slug lowercased" \
    eval '[ "$(grep -cx ".md-convert/" "$TMP/repo/.git/info/exclude")" = 1 ] && [ -s "$TMP/repo/.md-convert/example.com-other-path-2.md" ]'

# 4. YouTube: both URL shapes map to one name, second is SKIP
run "$TMP/repo" "https://www.youtube.com/watch?v=AbC_12-x&t=30s" "https://youtu.be/AbC_12-x?si=zz"
check "YouTube watch?v= and youtu.be -> youtube-<ID>.md, second SKIP" \
    eval '[ -s "$TMP/repo/.md-convert/youtube-AbC_12-x.md" ] && has "ok=1 skip=1 fail=0"'

# 5. no-git cwd works, nothing outside .md-convert/
mkdir -p "$TMP/nogit"
check "URL in a non-git cwd converts" \
    eval 'run "$TMP/nogit" https://example.com/x && [ -s "$TMP/nogit/.md-convert/example.com-x.md" ]'

# 6. --output-path never touches the exclude file
mkdir -p "$TMP/repo2" && git -C "$TMP/repo2" init -q
run "$TMP/repo2" https://example.com/y --output-path o
check "--output-path for a URL skips the exclude append" \
    eval '[ -s "$TMP/repo2/o/example.com-y.md" ] && ! grep -q md-convert "$TMP/repo2/.git/info/exclude" 2>/dev/null'

# 7. SKIP vs --force
echo edited >"$TMP/a/report.md"
run "$TMP" "$TMP/a/report.pdf"
check "existing .md -> SKIP, untouched" \
    eval 'has "[SKIP]" && [ "$(cat "$TMP/a/report.md")" = edited ]'
run "$TMP" "$TMP/a/report.pdf" --force
check "--force overwrites" \
    eval 'has "[OK]" && [ "$(cat "$TMP/a/report.md")" != edited ]'

# 8. 1 of 3 missing
mkdir -p "$TMP/c" && : >"$TMP/c/one.pdf" && : >"$TMP/c/two.pdf"
run "$TMP/c" one.pdf missing.pdf two.pdf
rc=$?
check "missing input fails alone, others converted, fail=1, exit 1" \
    eval '[ $rc = 1 ] && [ -s "$TMP/c/one.md" ] && [ -s "$TMP/c/two.md" ] && has "missing.pdf: not found" && has "ok=2 skip=0 fail=1"'

# 9. markitdown not on PATH -> exact 3 lines, exit 1, nothing created
mkdir -p "$TMP/d" "$TMP/emptybin"
# The real interpreter, not a version-manager shim that needs bash on PATH.
pybin="$(python3 -c 'import sys; print(sys.executable)')"
nomd() { (cd "$TMP/d" && PATH="$TMP/emptybin" "$pybin" "$PY" "$@") >"$TMP/out" 2>&1; }
nomd x.pdf https://example.com/z
rc=$?
printf '%s\n' "[FAIL] markitdown 미설치" "Next: uv tool install 'markitdown[all]'" \
    "      TLS 인증서 오류가 나면: uv tool install --native-tls 'markitdown[all]'" >"$TMP/want"
check "markitdown missing -> exact 3 lines, exit 1, empty cwd stays empty" \
    eval '[ $rc = 1 ] && cmp -s "$TMP/want" "$TMP/out" && [ -z "$(ls -A "$TMP/d")" ]'
nomd https://example.com/z --output-path new
check "markitdown missing + --output-path -> no dir created" \
    eval 'cmp -s "$TMP/want" "$TMP/out" && [ -z "$(ls -A "$TMP/d")" ]'
nomd -h
check "-h prints help even with markitdown absent" \
    eval 'has "## Arguments" && [ -z "$(ls -A "$TMP/d")" ]'

# 10. -h writes nothing, calls nothing
mkdir -p "$TMP/e"
: >"$TMP/calls"
for h in -h --help help; do
    run "$TMP/e" "$h" https://example.com/q
    check "$h prints help, writes nothing" \
        eval 'has "## Arguments" && [ -z "$(ls -A "$TMP/e")" ] && [ ! -s "$TMP/calls" ]'
done

# 11. empty output -> WARN, no file
mkdir -p "$TMP/f" && : >"$TMP/f/scan-empty.pdf"
run "$TMP/f" scan-empty.pdf
check "empty output -> WARN, no file left" \
    eval 'has "[WARN]" && [ "$(ls -A "$TMP/f")" = scan-empty.pdf ]'

# 12. markitdown failure -> stderr first line, partial removed, TLS hint
: >"$TMP/f/boom.pdf"
run "$TMP/f" boom.pdf
check "markitdown failure -> first stderr line, partial removed" \
    eval 'has "boom.pdf: SSLError: certificate verify failed" && ! has "more" && [ ! -e "$TMP/f/boom.md" ] && [ "$(ls -A "$TMP/f" | wc -l)" = 2 ]'
check "TLS failure -> Next: REQUESTS_CA_BUNDLE hint" eval 'has "Next:" && has "REQUESTS_CA_BUNDLE"'

# 13. name collision a/x.pdf + a/x.docx
mkdir -p "$TMP/g" && : >"$TMP/g/x.pdf" && : >"$TMP/g/x.docx"
run "$TMP/g" x.pdf x.docx
check "x.pdf + x.docx -> second SKIP" eval 'has "ok=1 skip=1 fail=0" && grep -q x.pdf "$TMP/g/x.md"'

# 14. refusals: --output-path is a file, no inputs
: >"$TMP/g/afile"
run "$TMP/g" x.pdf --output-path afile --force
rc=$?
check "--output-path on a regular file -> FAIL, nothing converted" \
    eval '[ $rc = 1 ] && has "--output-path is not a directory" && grep -q x.pdf "$TMP/g/x.md" && [ ! -s "$TMP/g/afile" ]'
run "$TMP/g"
rc=$?
check "no inputs -> usage pointer" eval '[ $rc = 1 ] && has "Run /pkm:md-convert -h for usage."'

[ "$failures" -eq 0 ] || exit 1
