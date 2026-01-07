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

CONFIG_PATH="${SETTINGS_CONFIG:-$ROOT/settings_sources.json}"

# Warm sudo if available for system updates
if command -v sudo >/dev/null 2>&1; then
  sudo -v || true
fi

# Sync VS Code settings if config exists
if [[ -f "$CONFIG_PATH" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/settings_manager.py" --config "$CONFIG_PATH" sync || true
  elif command -v python >/dev/null 2>&1; then
    python "$SCRIPT_DIR/settings_manager.py" --config "$CONFIG_PATH" sync || true
  else
    echo "settings sync skipped: python not found" >&2
  fi
fi

"$SCRIPT_DIR/workspace-pull.sh" --root "$ROOT" || true

# System package updates
if command -v apt-get >/dev/null 2>&1; then
  sudo /usr/bin/apt-get update || true
  sudo /usr/bin/apt-get -y upgrade || true
fi

# TeX Live update (if installed)
TLMGR="$(command -v tlmgr 2>/dev/null || true)"
if [[ -z "$TLMGR" ]]; then
  for cand in /usr/local/texlive/*/bin/*/tlmgr; do
    if [[ -x "$cand" ]]; then
      TLMGR="$cand"
      break
    fi
  done
fi
if [[ -n "$TLMGR" ]]; then
  sudo "$TLMGR" update --self --all || echo "tlmgr update failed; continuing."
fi

# Node package managers
if command -v corepack >/dev/null 2>&1; then
  corepack enable || true
  corepack prepare pnpm@latest --activate || true
  corepack prepare yarn@stable --activate || true
fi
if command -v npm >/dev/null 2>&1; then
  npm -g update || true
fi
if command -v pnpm >/dev/null 2>&1 && ! command -v corepack >/dev/null 2>&1; then
  pnpm -g add pnpm@latest || true
fi

# Other package systems (best-effort)
if command -v pipx >/dev/null 2>&1; then
  pipx upgrade-all || true
fi
if command -v rustup >/dev/null 2>&1; then
  rustup update || true
fi
if command -v brew >/dev/null 2>&1; then
  brew update || true
  brew upgrade || true
fi

"$SCRIPT_DIR/scrub.sh" --root "$ROOT" || true
