#!/bin/sh
# Builds Cursor Zoo.app.
#
# Deliberately a shell script rather than a Makefile: /usr/bin/make is an Xcode
# shim and refuses to run until `sudo xcodebuild -license accept` has been run on
# the machine. The Command Line Tools toolchain below has no such gate, so this
# works on a fresh Mac. A Makefile with the same targets is included for once the
# license is accepted.
set -eu

APP="Cursor Zoo.app"
BIN="CursorZoo"
CONFIG="${CONFIG:-release}"

: "${DEVELOPER_DIR:=/Library/Developer/CommandLineTools}"
export DEVELOPER_DIR

cd "$(dirname "$0")"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/$BIN" "$APP/Contents/MacOS/$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. There is no Developer ID on this machine yet, so the bundle is
# not notarised: see README for what someone else has to do to open it.
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null

echo "built $APP"
