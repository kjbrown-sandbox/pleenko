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
echo ""

# Bail early if something is already on the port (e.g. a server orphaned by a
# previous run that was SIGKILLed before its cleanup trap could fire).
if lsof -nP -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1; then
    STALE_PID=$(lsof -nP -tiTCP:8000 -sTCP:LISTEN 2>/dev/null | head -1)
    echo "❌ Port 8000 is already in use (pid ${STALE_PID:-unknown})."
    echo "   Kill it and re-run:  kill ${STALE_PID:-<pid>}"
    exit 1
fi

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

# Tear the server down no matter how this script ends: normal exit, Ctrl+C
# (SIGINT), kill (SIGTERM), or the terminal window being closed (SIGHUP).
# Without this, `python3 ... &` is orphaned when the shell dies and keeps
# holding port 8000. (SIGKILL / `kill -9` can't be trapped — the port
# precheck above is the backstop for that case.)
cleanup() {
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
on_signal() {
    echo ""
    echo "Interrupted — shutting down the local server and exiting."
    cleanup
    exit 130
}
trap cleanup EXIT
trap on_signal INT TERM HUP

# Wait until the server is actually accepting connections before opening the
# browser. Python needs ~0.5s to import + bind; opening the browser before the
# socket is listening is what causes "connection refused".
echo "Waiting for server to come up..."
for i in $(seq 1 50); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "❌ Server process exited before it could bind to port 8000."
        wait "$SERVER_PID" 2>/dev/null || true
        exit 1
    fi
    if curl -s -o /dev/null "http://localhost:8000/"; then
        break
    fi
    sleep 0.2
    if [ "$i" -eq 50 ]; then
        echo "❌ Server did not become ready within 10s."
        kill "$SERVER_PID" 2>/dev/null || true
        exit 1
    fi
done
echo "Server is up at http://localhost:8000"

# Open in default browser
open "http://localhost:8000" 2>/dev/null || true

echo "Test the build in the browser."
echo "  - Press Enter when done   → stops the server, then asks about pushing to itch"
echo "  - Press Ctrl+C any time   → shuts the server down and exits (no push)"
read -r

cleanup

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
