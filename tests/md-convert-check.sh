#!/usr/bin/env bash
# tests/md-convert-check.sh
#
# Thin wrapper: pkm:md-convert's offline check lives beside its script
# (stub markitdown, no network). Run it from the repo's tests/ entry point.
#
# Usage:
#   bash tests/md-convert-check.sh
# Exits 0 when every assertion passes, 1 otherwise.

set -uo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$REPO_ROOT/skills/md-convert/lib/md-convert.selfcheck.sh"
