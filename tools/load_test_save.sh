#!/usr/bin/env bash
# Copy a test save JSON into the live Godot user data slot so the next launch
# loads that state. Backs up the current save first.
#
# Usage:
#   tools/load_test_save.sh <save-file>
#   tools/load_test_save.sh                 # lists candidates in repo root
#
# Examples:
#   tools/load_test_save.sh save_orange_prestige.json
#   tools/load_test_save.sh ./dane_save.json

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# config/name in project.godot is "Plunk".
DEST="$HOME/Library/Application Support/Godot/app_userdata/Plunk/save.json"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <save-file>"
    echo
    echo "Candidates in repo root:"
    ls "$REPO_ROOT"/*.json 2>/dev/null | sed 's|^|  |'
    exit 1
fi

SRC="$1"
# Allow either an absolute path or a name relative to repo root.
if [[ ! -f "$SRC" && -f "$REPO_ROOT/$SRC" ]]; then
    SRC="$REPO_ROOT/$SRC"
fi
if [[ ! -f "$SRC" ]]; then
    echo "error: save file not found: $1" >&2
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
if [[ -f "$DEST" ]]; then
    BACKUP="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$DEST" "$BACKUP"
    echo "backed up live save -> $BACKUP"
fi

cp "$SRC" "$DEST"
echo "loaded $(basename "$SRC") -> $DEST"
