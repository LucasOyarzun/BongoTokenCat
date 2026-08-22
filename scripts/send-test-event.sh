#!/bin/bash
# Push a synthetic hook event into a running BongoTokenBar.
#
# Lets you exercise every state without installing hooks or waiting for a real
# agent to reach that state — which matters most for the ones you cannot summon
# on demand, like StopFailure.
#
# Usage: send-test-event.sh <event> <session-id> [cwd] [text]
set -euo pipefail

EVENT="${1:?usage: send-test-event.sh <event> <session-id> [cwd] [text]}"
SESSION="${2:?missing session id}"
CWD="${3:-/Users/$USER/workspace/demo}"
TEXT="${4:-}"

RUNTIME="$HOME/.bongotokenbar/runtime.json"
[ -f "$RUNTIME" ] || { echo "BongoTokenBar is not running (no runtime.json)"; exit 1; }
PORT=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$RUNTIME")
TOKEN=$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/p' "$RUNTIME")

python3 - "$EVENT" "$SESSION" "$CWD" "$TEXT" <<'PY' | \
  curl -s -m 1 -X POST -H 'Content-Type: application/json' \
    -H "x-bongo-token: $TOKEN" --data-binary @- "http://127.0.0.1:$PORT/event"
import json, sys
event, session, cwd, text = sys.argv[1:5]
payload = {"hook_event_name": event, "session_id": session, "cwd": cwd}
if text:
    payload["message_text"] = text
print(json.dumps(payload))
PY
echo "sent $EVENT for $SESSION"
