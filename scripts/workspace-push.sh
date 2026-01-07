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

"$SCRIPT_DIR/push.sh" --root "$ROOT" "$@"

if git -C "$ROOT" submodule status --recursive >/dev/null 2>&1; then
  git -C "$ROOT" submodule foreach --recursive "\
    \"$SCRIPT_DIR/push.sh\" --root \"$PWD\""
fi
