#!/usr/bin/env bash
# skills/karakeep-add/lib/karakeep-env.sh
#
# The env + base URL contract shared by pkm:karakeep-add and
# pkm:karakeep-classify. Both skills used to carry a byte-identical copy of
# this block in their own references/*.md — two copies of an auth contract
# that can drift apart silently. This is the single copy.
#
# Usage:
#   . karakeep-env.sh        source it — sets BASE and AUTH, or exits non-zero
#   bash karakeep-env.sh     print the resolved BASE (never the key), exit 0/1
#   bash karakeep-env.sh -h  print this text
#
# NEXTAUTH_URL and KARAKEEP_API_KEY come from the working directory's .env.
# Neither is ever guessed and there is no localhost:3001 fallback — that is
# the config.yaml internal value and it is wrong for live writes.

karakeep_env_usage() {
    cat <<'EOF'
karakeep-env.sh — env + base URL contract for the two pkm:karakeep skills

Usage:
  . karakeep-env.sh
      Source it. Loads ./.env (if present), asserts NEXTAUTH_URL and
      KARAKEEP_API_KEY are set, then exports:
        BASE  the trailing-slash-stripped NEXTAUTH_URL
        AUTH  the "Authorization: Bearer ..." header line
      A missing variable is fatal: the message names it and the shell exits.

  bash karakeep-env.sh
      Same checks, then print BASE on stdout. The API key is never printed.

  bash karakeep-env.sh -h | --help | help
      Print this text.
EOF
}

karakeep_env_load() {
    # The `[ -f ]` guard is load-bearing: sourcing a missing file aborts a
    # POSIX shell before any later line can report why.
    if [ -f ./.env ]; then
        set -a
        # shellcheck disable=SC1091  # user-supplied file, not resolvable here
        . ./.env
        set +a
    fi
    : "${NEXTAUTH_URL:?NEXTAUTH_URL not set — refusing to guess base URL}"
    : "${KARAKEEP_API_KEY:?KARAKEEP_API_KEY not set — cannot authenticate}"
    BASE="${NEXTAUTH_URL%/}"
    AUTH="Authorization: Bearer ${KARAKEEP_API_KEY}"
    export BASE AUTH
}

# Only run when executed, never when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    case "${1:-}" in
        -h | --help | help)
            karakeep_env_usage
            exit 0
            ;;
    esac
    karakeep_env_load
    printf '%s\n' "$BASE"
fi
