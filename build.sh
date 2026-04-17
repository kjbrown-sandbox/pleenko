#!/bin/bash
set -e

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
BUTLER="$HOME/bin/butler"
EXPORT_PRESET="Web"
EXPORT_OUTPUT="builds/web/index.html"
ITCH_TARGET="itchy-dev-games/now-with-more-plinko:html5"

cd "$(dirname "$0")"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
DIRTY=""
if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    DIRTY="yes"
fi

if [ "$BRANCH" != "main" ] || [ -n "$DIRTY" ]; then
    echo "⚠️  Heads up:"
    [ "$BRANCH" != "main" ] && echo "   - You're on branch '$BRANCH', not 'main'"
    [ -n "$DIRTY" ] && echo "   - Working tree has uncommitted changes"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }
fi

VERSION=$(git describe --tags --always --dirty)
echo "Building version: $VERSION"

mkdir -p builds/web
echo "Exporting Web preset..."
"$GODOT" --headless --export-release "$EXPORT_PRESET" "$EXPORT_OUTPUT"

echo "Pushing to itch.io..."
"$BUTLER" push builds/web "$ITCH_TARGET" --userversion "$VERSION"

echo "✅ Done. Check status: $BUTLER status itchy-dev-games/now-with-more-plinko"
