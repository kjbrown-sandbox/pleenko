#!/usr/bin/env bash
# Bring a feature worktree's commits onto main in the primary checkout so you
# can test them with a warm Godot import cache, then optionally clean up the
# worktree.
#
# Usage:
#   tools/land_worktree.sh <kebab-case-name>           # fast-forward merge only
#   tools/land_worktree.sh <kebab-case-name> --remove  # merge, then remove the worktree + branch
#
# The merge is intentionally fast-forward-only: it refuses if main has moved
# since the worktree was cut (run `git rebase main` inside the worktree first).
# This keeps history linear and testing strictly sequential.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: tools/land_worktree.sh <kebab-case-name> [--remove]" >&2
    exit 1
fi

NAME="$1"
REMOVE=""
if [[ ${2:-} == "--remove" ]]; then
    REMOVE="yes"
elif [[ -n "${2:-}" ]]; then
    echo "error: unknown option: $2" >&2
    exit 1
fi

BRANCH="feature/$NAME"
WT="$REPO_ROOT/.claude/worktrees/$NAME"

if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "error: branch not found: $BRANCH" >&2
    exit 1
fi

# The merge must happen in the primary checkout, which must be on main and clean.
CUR="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ "$CUR" != "main" ]]; then
    echo "error: primary checkout is on '$CUR', not 'main'. switch to main first." >&2
    exit 1
fi
if ! git -C "$REPO_ROOT" diff-index --quiet HEAD --; then
    echo "error: primary checkout has uncommitted changes; commit or stash first." >&2
    exit 1
fi

# Fast-forward only: clean linear land, or a clear instruction to rebase.
if ! git -C "$REPO_ROOT" merge --ff-only "$BRANCH"; then
    echo "" >&2
    echo "main has advanced since '$BRANCH' was cut, so it can't fast-forward." >&2
    echo "rebase the feature first, then re-run:" >&2
    echo "    git -C $WT rebase main" >&2
    echo "    tools/land_worktree.sh $NAME" >&2
    exit 1
fi
echo "merged $BRANCH -> main (fast-forward)"

if [[ -n "$REMOVE" ]]; then
    git -C "$REPO_ROOT" worktree remove "$WT"
    git -C "$REPO_ROOT" branch -d "$BRANCH"
    echo "removed worktree $WT and branch $BRANCH"
else
    echo "worktree left in place at $WT (re-run with --remove to clean up)"
fi
