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
		echo ""
	fi
}

checkout_target_branch() {
	local repo="$1"
	local branch="$2"
	local current

	current="$(git -C "$repo" branch --show-current)"
	if [[ "$current" == "$branch" ]]; then
		return 0
	fi

	if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$repo" checkout "$branch"
	else
		git -C "$repo" checkout -b "$branch" --track "origin/$branch"
	fi
}

pull_repo() {
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

	if ! is_clean "$repo"; then
		echo "Skipping pull in $repo (dirty working tree)"
		return 0
	fi

	if ! git -C "$repo" fetch origin --prune; then
		echo "Fetch failed in $repo"
		return 0
	fi

	branch="$(target_branch "$repo")"
	if [[ -z "$branch" ]]; then
		echo "Skipping $repo (no origin/main or origin/master)"
		return 0
	fi

	checkout_target_branch "$repo" "$branch"
	git -C "$repo" pull --no-rebase origin "$branch" || true
}

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	echo "No git repo at $ROOT"
	exit 0
fi

while IFS= read -r repo; do
	[[ -n "$repo" ]] || continue
	pull_repo "$repo"
done < <(list_repos)
