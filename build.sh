#!/bin/bash
set -e

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
BUTLER="$HOME/bin/butler"
EXPORT_PRESET="Web"
EXPORT_OUTPUT="builds/web/index.html"
ITCH_TARGET="itchy-dev-games/now-with-more-plunk:html5"

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

echo ""
echo "Starting local test server at http://localhost:8000"
echo "Test your build in the browser, then:"
echo "  - Press Ctrl+C to stop the server and push to itch"
echo "  - Or press Ctrl+C twice to abort without pushing"
echo ""

# Start server with COOP/COEP headers required by Godot 4 web exports
python3 -c "
import http.server, functools

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

s = http.server.HTTPServer(('', 8000), functools.partial(Handler, directory='builds/web'))
s.serve_forever()
" &
SERVER_PID=$!

# Open in default browser
open "http://localhost:8000" 2>/dev/null || true

echo "Press Enter when you're done testing..."
read -r

kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

echo ""
read -p "Build looks good? Push to itch? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Build is still in builds/web/ if you want to inspect it."
    exit 0
fi

echo "Pushing to itch.io..."
"$BUTLER" push builds/web "$ITCH_TARGET" --userversion "$VERSION"

echo "Done. Check status: $BUTLER status itchy-dev-games/now-with-more-plunk"
