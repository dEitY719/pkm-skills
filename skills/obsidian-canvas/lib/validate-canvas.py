#!/usr/bin/env python3
"""validate-canvas.py -- the eight canvas checks of pkm:obsidian-canvas Step 4.

Usage: validate-canvas.py <file.canvas>

stdout: one `[FAIL] <path>  check <n>: <detail>` line per violation, or
        `[OK] <path>  nodes=<n> edges=<n>` when none. Check numbers and their
        meaning: references/validation.md.
exit:   0 pass | 1 violations | 2 usage error or file not found

Read-only, Python 3 stdlib only.
"""
import json
import re
import sys

NODE_TYPES = {"text", "file", "link", "group"}
REQUIRED = {"text": "text", "file": "file", "link": "url"}
SIDES = {"top", "right", "bottom", "left"}
ENDS = {"none", "arrow"}
HEX = re.compile(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})")


def check(data):
    """Return [(check_number, detail)] for a parsed canvas document."""
    if not isinstance(data, dict):
        return [(8, "top level is not a JSON object")]
    nodes, edges = data.get("nodes", []), data.get("edges", [])
    errs = []
    for key, val in (("nodes", nodes), ("edges", edges)):
        if not isinstance(val, list):
            errs.append((8, f"`{key}` is not an array"))
    if errs:
        return errs
    for kind, items in (("node", nodes), ("edge", edges)):
        for i, item in enumerate(items):
            if not isinstance(item, dict):
                errs.append((8, f"{kind} #{i} is not an object"))
    if errs:
        return errs

    seen = {}
    for kind, items in (("node", nodes), ("edge", edges)):
        for i, item in enumerate(items):
            iid = item.get("id")
            if not isinstance(iid, str) or not iid:
                errs.append((1, f"{kind} #{i} has no id"))
            elif iid in seen:
                errs.append((1, f"duplicate id {iid!r} ({seen[iid]} and {kind} #{i})"))
            else:
                seen[iid] = f"{kind} #{i}"

    node_ids = {n.get("id") for n in nodes}
    for e in edges:
        for end in ("fromNode", "toNode"):
            if e.get(end) not in node_ids:
                errs.append((2, f"edge {e.get('id')!r} {end}={e.get(end)!r} is not a node id"))

    for n in nodes:
        t, nid = n.get("type"), n.get("id")
        if t in REQUIRED and not isinstance(n.get(REQUIRED[t]), str):
            errs.append((3, f"{t} node {nid!r} is missing `{REQUIRED[t]}`"))
        if t not in NODE_TYPES:
            errs.append((4, f"node {nid!r} has type {t!r}"))

    for e in edges:
        for key, allowed, n in (("fromSide", SIDES, 5), ("toSide", SIDES, 5),
                                ("fromEnd", ENDS, 6), ("toEnd", ENDS, 6)):
            if key in e and e[key] not in allowed:
                errs.append((n, f"edge {e.get('id')!r} {key}={e[key]!r}"))

    for kind, items in (("node", nodes), ("edge", edges)):
        for item in items:
            if "color" not in item:
                continue
            c = item["color"]
            if not (isinstance(c, str) and (c in {"1", "2", "3", "4", "5", "6"} or HEX.fullmatch(c))):
                errs.append((7, f"{kind} {item.get('id')!r} color={c!r}"))

    return sorted(errs, key=lambda e: e[0])


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print("usage: validate-canvas.py <file.canvas>", file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except OSError as exc:
        print(f"[FAIL] {path}  cannot read: {exc.strerror}", file=sys.stderr)
        return 2
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"[FAIL] {path}  check 8: {exc}")
        return 1
    errs = check(data)
    for n, detail in errs:
        print(f"[FAIL] {path}  check {n}: {detail}")
    if errs:
        return 1
    print(f"[OK] {path}  nodes={len(data.get('nodes', []))} edges={len(data.get('edges', []))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
