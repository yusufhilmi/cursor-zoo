#!/bin/sh
# Escape hatch: give the pointer back if Cursor Zoo ever leaves it hidden.
#
# Quitting the app runs its restore handler AND tears down its window-server
# connection, either of which brings the cursor back. This targets the one bundle
# by name - it never pattern-matches or kills anything else.
osascript -e 'tell application "Cursor Zoo" to quit' 2>/dev/null
echo "asked Cursor Zoo to quit; your pointer should be back"
echo "if it is not, log out and back in (the window server restores it on session end)"
