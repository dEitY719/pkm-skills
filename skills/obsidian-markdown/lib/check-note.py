#!/usr/bin/env python3
"""check-note.py -- the deterministic half of pkm:obsidian-markdown Step 4.

Usage: check-note.py --vault <root> <note.md>

Counts wikilinks, embeds and callouts outside code, and resolves every
`[[target]]` / `![[target]]` the way Obsidian does: by vault-relative path or
by bare file name anywhere in the vault, `.md` optional. Frontmatter must
parse as YAML when PyYAML is importable; otherwise one
`[WARN] yaml syntax check skipped (PyYAML not installed)` line.

stdout: `[OK] <path>  links=<n> embeds=<n> callouts=<n>`, or the same counts
        behind `[FAIL]` followed by one `UNRESOLVED <target>` line per missing
        target (and/or a `frontmatter:` problem).
exit:   0 pass | 1 unresolved target or bad frontmatter | 2 usage error

Not checked: `#heading` / `^block` anchors (only the file is resolved) and
callout type names (custom CSS types are legal) -- references/CALLOUTS.md.

Read-only, Python 3 stdlib only (PyYAML optional).
"""
import os
import re
import sys

FENCE = re.compile(r"^(```|~~~).*?^\1[^\n]*$", re.M | re.S)
INLINE = re.compile(r"`[^`\n]*`")
LINK = re.compile(r"(!?)\[\[([^\]]*)\]\]")
CALLOUT = re.compile(r"^[ \t]*(?:>[ \t]*)+\[![^\]\n]+\]", re.M)
SKIP_DIRS = {".obsidian", ".git", ".trash"}


def vault_index(root):
    """Lower-cased names a link may use: rel path and basename, with/without .md."""
    names = set()
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/")
            for n in (rel, f):
                names.add(n.lower())
                if n.lower().endswith(".md"):
                    names.add(n[:-3].lower())
    return names


def frontmatter_error(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return "frontmatter: no closing ---"
    try:
        import yaml
    except ImportError:
        print("[WARN] yaml syntax check skipped (PyYAML not installed)")
        return None
    try:
        yaml.safe_load(text[4:end])
    except yaml.YAMLError as exc:
        return f"frontmatter: {getattr(exc, 'problem', None) or exc}"
    return None


def main(argv):
    args = argv[1:]
    if len(args) != 3 or args[0] != "--vault":
        print("usage: check-note.py --vault <root> <note.md>", file=sys.stderr)
        return 2
    root, path = args[1], args[2]
    if not os.path.isdir(root):
        print(f"[FAIL] vault not found: {root}", file=sys.stderr)
        return 2
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as exc:
        print(f"[FAIL] {path}  cannot read: {exc.strerror}", file=sys.stderr)
        return 2

    fm_err = frontmatter_error(text)
    body = INLINE.sub("", FENCE.sub("", text))
    index = vault_index(root)
    note_dir = os.path.relpath(os.path.dirname(os.path.abspath(path)), os.path.abspath(root))
    links = embeds = 0
    unresolved = []
    for bang, inner in LINK.findall(body):
        if bang:
            embeds += 1
        else:
            links += 1
        target = re.split(r"[|#^]", inner, maxsplit=1)[0].strip()
        if not target:  # [[#Heading]] points at this note
            continue
        rel = os.path.normpath(os.path.join(note_dir, target)).replace(os.sep, "/")
        if any(c.lower() in index or c.lower() + ".md" in index for c in (target, rel)):
            continue
        if target not in unresolved:
            unresolved.append(target)
    callouts = len(CALLOUT.findall(body))

    counts = f"links={links} embeds={embeds} callouts={callouts}"
    if unresolved or fm_err:
        print(f"[FAIL] {path}  {counts}")
        if fm_err:
            print(fm_err)
        for t in unresolved:
            print(f"UNRESOLVED {t}")
        return 1
    print(f"[OK] {path}  {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
