#!/bin/bash
#
# Photographs the views whose colours changed, once per appearance.
#
# The appearance is set on the simulator here rather than in the test, because
# `-AppleInterfaceStyle Dark` as a launch argument looks like it works and does not: SwiftUI reads
# the trait collection, not that default. The first version of this captured light mode twice and
# labelled one of them dark — which is worse than not capturing dark at all, because it looks like
# evidence.
#
# Usage:  ./Scripts/capture-colours.sh [simulator name]
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
DEVICE="${1:-iPhone 17 Pro}"
OUT="${MG_SHOT_OUT:-/tmp/colour-shots}"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
name=sys.argv[1]
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name']==name: print(d['udid']); raise SystemExit
raise SystemExit('no simulator named '+name)
" "$DEVICE")

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
cd "$APP_DIR"
xcodegen generate >/dev/null

for scheme in light dark; do
  echo "==> $scheme"
  xcrun simctl ui "$UDID" appearance "$scheme"
  MG_SCHEME="$scheme" xcodebuild -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$OUT/dd" \
    -resultBundlePath "$OUT/$scheme.xcresult" \
    -only-testing:MiddleGroundUITests/ColourFixScreenshots \
    -allowProvisioningUpdates test > "$OUT/$scheme.log" 2>&1 || true
  grep -E "Test Case '.*(passed|failed)'" "$OUT/$scheme.log" | sed 's/.*ColourFixScreenshots //' | cut -c1-60 || true
done

xcrun simctl ui "$UDID" appearance light
echo "Result bundles in $OUT"
