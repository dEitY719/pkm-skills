#!/usr/bin/env python3
"""validate-base.py -- the deterministic half of pkm:obsidian-bases Step 4.

Usage: validate-base.py <file.base>

Checks: the file is valid YAML (only when PyYAML is importable -- otherwise
one `[WARN] yaml syntax check skipped (PyYAML not installed)` line), and every
`formula.X` reference names a key defined under `formulas:` (always, by regex).

stdout: `[FAIL] <path>  <line>: <error>` per problem, or
        `[OK] <path>  views=<n> formulas=<n>` when none.
exit:   0 pass | 1 problems | 2 usage error or file not found

Read-only, Python 3 stdlib only (PyYAML optional).
"""
import re
import sys

REF = re.compile(r"\bformula\.([A-Za-z_]\w*)")
TOP = re.compile(r"^([A-Za-z_]\w*)\s*:")
CHILD_KEY = re.compile(r"^(\s+)(?:([A-Za-z_]\w*)|\"([^\"]+)\"|'([^']+)')\s*:")
ITEM = re.compile(r"^(\s*)-\s")


def scan(lines):
    """Stdlib fallback: formula keys and view count from indentation alone."""
    formulas, views, section, indent = set(), 0, None, None
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        top = TOP.match(line)
        if top:
            section, indent = top.group(1), None
            continue
        if section == "formulas":
            m = CHILD_KEY.match(line)
            if m and (indent is None or len(m.group(1)) == indent):
                indent = len(m.group(1))
                formulas.add(m.group(2) or m.group(3) or m.group(4))
        elif section == "views":
            m = ITEM.match(line)
            if m and (indent is None or len(m.group(1)) == indent):
                indent = len(m.group(1))
                views += 1
    return formulas, views


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print("usage: validate-base.py <file.base>", file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as exc:
        print(f"[FAIL] {path}  cannot read: {exc.strerror}", file=sys.stderr)
        return 2
    lines = text.splitlines()
    errs = []
    formulas, views = scan(lines)

    try:
        import yaml
    except ImportError:
        print("[WARN] yaml syntax check skipped (PyYAML not installed)")
    else:
        try:
            data = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            mark = getattr(exc, "problem_mark", None)
            line = mark.line + 1 if mark else 0
            errs.append((line, f"yaml: {getattr(exc, 'problem', None) or exc}"))
        else:
            if not isinstance(data, dict):
                errs.append((1, "yaml: top level is not a mapping"))
            else:
                f_map, v_list = data.get("formulas") or {}, data.get("views") or []
                formulas = set(f_map) if isinstance(f_map, dict) else set()
                views = len(v_list) if isinstance(v_list, list) else 0

    for no, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        for name in REF.findall(line):
            if name not in formulas:
                errs.append((no, f"formula.{name} is referenced but not defined under formulas"))

    for no, msg in errs:
        print(f"[FAIL] {path}  {no}: {msg}")
    if errs:
        return 1
    print(f"[OK] {path}  views={views} formulas={len(formulas)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
