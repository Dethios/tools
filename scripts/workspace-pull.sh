#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${WORKSPACE_ROOT:-}"
if [[ -z "$ROOT" ]]; then
	ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [[ "${1:-}" == "--root" ]]; then
	ROOT="${2:-}"
	shift 2
fi

if [[ "$ROOT" != /* ]]; then
	ROOT="$(cd "$ROOT" && pwd)"
fi

is_clean() {
	git -C "$1" diff --quiet || return 1
	git -C "$1" diff --cached --quiet || return 1
	[[ -z "$(git -C "$1" ls-files -o -m --exclude-standard)" ]]
}

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	echo "No git repo at $ROOT"
	exit 0
fi

if is_clean "$ROOT"; then
	git -C "$ROOT" pull --ff-only || true
else
	echo "Skipping pull in $ROOT (dirty working tree)"
fi

# Ensure submodules are present
git -C "$ROOT" submodule update --init --recursive || true

# Pull each submodule if clean
if git -C "$ROOT" submodule status --recursive >/dev/null 2>&1; then
	git -C "$ROOT" submodule foreach --recursive '
    if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files -o -m --exclude-standard)" ]; then
      git pull --ff-only || true
    else
      echo "Skipping $name (dirty working tree)"
    fi
  ' || true
fi
