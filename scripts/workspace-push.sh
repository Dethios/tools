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

list_repos() {
	find "$ROOT" \( -name .git -type d -o -name .git -type f \) -prune -print |
		sed 's#/\.git$##' |
		sort -u
}

target_branch() {
	local repo="$1"
	if git -C "$repo" show-ref --verify --quiet refs/remotes/origin/main; then
		echo main
	elif git -C "$repo" show-ref --verify --quiet refs/remotes/origin/master; then
		echo master
	else
		git -C "$repo" branch --show-current
	fi
}

push_repo() {
	local repo="$1"
	local branch

	if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
		echo "Skipping $repo (not a git repo)"
		return 0
	fi

	if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
		echo "Skipping $repo (no origin remote)"
		return 0
	fi

	branch="$(target_branch "$repo")"
	if [[ "$branch" == "master" ]]; then
		echo "Skipping push in $repo (origin/master repos are pull-only)"
		return 0
	fi

	"$SCRIPT_DIR/push.sh" --root "$repo" "$@"
}

while IFS= read -r repo; do
	[[ -n "$repo" ]] || continue
	push_repo "$repo"
done < <(list_repos)
