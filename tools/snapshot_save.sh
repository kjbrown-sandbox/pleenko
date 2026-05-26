#!/usr/bin/env bash
# Snapshot the live Godot save into a new top-level file in the repo.
#
# Usage:
#   tools/snapshot_save.sh              # auto-numbers: save_1.json, save_2.json, ...
#   tools/snapshot_save.sh <name>       # writes save_<name>.json
#
# Auto-numbering picks the lowest N >= 1 such that save_N.json doesn't already
# exist in the repo root. Other saves (save_orange_prestige.json, dane_save.json,
# etc.) don't affect the count.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HOME/Library/Application Support/Godot/app_userdata/Plunk/save.json"

if [[ ! -f "$SRC" ]]; then
    echo "error: live save not found at $SRC" >&2
    exit 1
fi

if [[ $# -ge 1 ]]; then
    DEST="$REPO_ROOT/save_$1.json"
    if [[ -e "$DEST" ]]; then
        echo "error: $DEST already exists" >&2
        exit 1
    fi
else
    n=1
    while [[ -e "$REPO_ROOT/save_$n.json" ]]; do
        n=$((n + 1))
    done
    DEST="$REPO_ROOT/save_$n.json"
fi

cp "$SRC" "$DEST"
echo "snapshot -> $DEST"
