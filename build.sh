#!/bin/bash
# Builds Breather.app into ./build.
#   ./build.sh            build the app
#   ./build.sh --run      build, then (re)start it
#   ./build.sh --install  build, then copy it to /Applications and start it
set -euo pipefail
cd "$(dirname "$0")"

# Compiles with swiftc directly, so only the Command Line Tools are needed (no Xcode).
APP="build/Breather.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -sdk "$(xcrun --show-sdk-path)" \
  Sources/Breather/*.swift \
  -o "$APP/Contents/MacOS/Breather"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

case "${1:-}" in
  --run)
    pkill -x Breather 2>/dev/null || true
    open "$APP"
    ;;
  --install)
    pkill -x Breather 2>/dev/null || true
    rm -rf /Applications/Breather.app
    cp -R "$APP" /Applications/
    open /Applications/Breather.app
    echo "Installed to /Applications/Breather.app"
    ;;
esac
