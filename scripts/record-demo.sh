#!/bin/zsh
# Runs the launch demo in the real app while Recordly records the screen.
#
# Before running:
#   1. Open the demo Google Doc in Chrome (full screen) and select the line
#      "Draft · Opening line goes here" (the pasted answer replaces it).
#   2. Start recording in Recordly (full display).
# Then run this script. It waits 3s, runs the demo, and pastes the result.
set -euo pipefail
DONE="$HOME/Library/Application Support/BlackBarAI/demo-done"
rm -f "$DONE"
sleep 3
open -g "blackbar://demo"
for _ in {1..240}; do [[ -f "$DONE" ]] && break; sleep 0.5; done
sleep 1.2
# Paste the copied line into the doc (BlackBarAI handed focus back to Chrome).
osascript -e 'tell application "System Events" to keystroke "v" using command down'
sleep 3
echo "Demo finished. Stop the Recordly recording."
