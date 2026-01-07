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

# Config
DEFAULT_MSG="Auto-commit: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2> /dev/null || echo main)"
CONFIG_PATH="${SETTINGS_CONFIG:-$ROOT/settings_sources.json}"

# Keep settings_master in sync before staging/commit (if config exists)
if [[ -f "$CONFIG_PATH" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/settings_manager.py" --config "$CONFIG_PATH" merge
  elif command -v python >/dev/null 2>&1; then
    python "$SCRIPT_DIR/settings_manager.py" --config "$CONFIG_PATH" merge
  else
    echo "settings merge skipped: python not found" >&2
    exit 1
  fi
fi

# Guardrails: block obvious secrets by pattern (edit as needed)
BLOCK_PATTERNS=(
  '\.env'
  'id_rsa|id_ed25519|_key$'
  'token|apikey|secret'
)
BLOCK_PATTERN="$(IFS='|'; echo "${BLOCK_PATTERNS[*]}")"

# 1) Refuse if patterns present in staged or untracked
if git -C "$ROOT" ls-files -o -m --exclude-standard | grep -E "$BLOCK_PATTERN" -iq; then
  echo "Potential secret-like files changed. Review before pushing." >&2
  git -C "$ROOT" ls-files -o -m --exclude-standard | grep -E "$BLOCK_PATTERN" -i || true
  exit 1
fi

# 2) Stage & skip if nothing
git -C "$ROOT" add -A
git -C "$ROOT" diff --cached --quiet && {
  echo "No changes to commit in $ROOT."
  exit 0
}

# 3) Commit with message (arg or default)
MSG="${1:-$DEFAULT_MSG}"
git -C "$ROOT" commit -m "$MSG"

# 4) Ensure upstream once
if ! git -C "$ROOT" rev-parse --symbolic-full-name --verify "@{u}" > /dev/null 2>&1; then
  git -C "$ROOT" push -u origin "$BRANCH"
else
  git -C "$ROOT" push
fi

echo "Pushed to $(git -C "$ROOT" remote get-url origin) on branch $BRANCH"
