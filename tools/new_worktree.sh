#!/usr/bin/env bash
# Create an isolated git worktree for a feature so an agent can work without
# disturbing the primary checkout, then pre-seed the Godot import cache so the
# worktree is testable warm (no cold reimport on first open).
#
# Usage:
#   tools/new_worktree.sh <kebab-case-name>
#
# Creates .claude/worktrees/<name>/ on a new branch feature/<name> off main,
# then copies .godot/imported from the primary checkout into it. Open that
# folder as its own Godot project, or test it later via tools/land_worktree.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

if [[ $# -ne 1 ]]; then
    echo "usage: tools/new_worktree.sh <kebab-case-name>" >&2
    exit 1
fi

NAME="$1"
BRANCH="feature/$NAME"
WT="$REPO_ROOT/.claude/worktrees/$NAME"

if [[ -e "$WT" ]]; then
    echo "error: worktree path already exists: $WT" >&2
    exit 1
fi
if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "error: branch already exists: $BRANCH" >&2
    exit 1
fi

# Cut the worktree from main so the merge back is a clean fast-forward.
git -C "$REPO_ROOT" worktree add "$WT" -b "$BRANCH" main
echo "worktree -> $WT  (branch $BRANCH)"

# Pre-seed the import cache so Godot opens warm. Falls back to a headless
# import if the cache copy isn't available.
SRC_CACHE="$REPO_ROOT/.godot/imported"
if [[ -d "$SRC_CACHE" ]]; then
    mkdir -p "$WT/.godot"
    cp -R "$SRC_CACHE" "$WT/.godot/imported"
    echo "import cache -> seeded from primary checkout"
elif [[ -x "$GODOT" ]]; then
    echo "primary .godot/imported not found; running headless import..."
    "$GODOT" --headless --import --path "$WT"
else
    echo "warning: no import cache to copy and Godot not found at $GODOT" >&2
    echo "         the worktree will reimport on first editor open." >&2
fi

echo ""
echo "done. to test later, from the primary checkout on main:"
echo "    tools/land_worktree.sh $NAME      # fast-forward merge into main"
echo "  or:  git switch $BRANCH             # check out in isolation"
