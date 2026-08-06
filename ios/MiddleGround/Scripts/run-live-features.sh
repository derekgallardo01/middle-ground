#!/bin/bash
#
# Exercises the features whose real backend path had never run, and reads the verdict.
#
# Every step here was learned by getting it wrong first, which is why they are in a script rather
# than a README:
#
#   - The project is generated from project.yml, and XcodeGen collects files by directory glob at
#     generation time. A test added since the last generate is simply absent, and the run reports
#     "** TEST SUCCEEDED **" having executed nothing.
#   - Location sharing needs an accepted plan timed within an hour before and four hours after now.
#     Re-dating an existing plan does not work — the client serves its cached copy until updatedAt
#     moves — so the fixture writes a new document.
#   - Without a simulated location CoreLocation fails, `shareLocation` never gets a coordinate, and
#     the test fails saying "location was never shared", which is true and points at the wrong
#     thing entirely.
#   - The permission grant has to be re-applied; the test also carries an interruption monitor for
#     when it is not enough.
#
# The test result is not the evidence. `verify-live-features.mjs` reads the documents, and that is
# the verdict — a passing UI test proved nothing when the whole suite ran against mock
# repositories.
#
# Prerequisites: Scripts/two-device-e2e.sh has run, so accounts A and B exist and are paired.
#
# Usage:  ./Scripts/run-live-features.sh
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
OUT="${MG_LIVE_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
DEVICE="${MG_DEVICE_A:-iPhone 17}"
BUNDLE_ID="app.middleground.MiddleGround"

echo "Results -> $OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
name = sys.argv[1]
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == name:
            print(d['udid']); raise SystemExit
raise SystemExit('no simulator named ' + name)
" "$DEVICE")
echo "Device: $DEVICE ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

echo "==> seeding a plan inside its location window"
node "$ROOT/Scripts/seed-location-fixture.mjs"

echo "==> granting location and placing the device"
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl location "$UDID" set 40.7128,-74.0060

cd "$APP_DIR"
echo "==> regenerating the project so newly added tests are actually in it"
xcodegen generate >/dev/null

echo "==> running the live feature pass"
xcodebuild -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$OUT/dd" \
  -resultBundlePath "$OUT/live.xcresult" \
  -only-testing:MiddleGroundUITests/RealBackendFeatureTests \
  -allowProvisioningUpdates \
  test > "$OUT/live.log" 2>&1 || true

grep -E "Test Case '.*(passed|failed)'|Test skipped" "$OUT/live.log" \
  | sed 's/.*RealBackendFeatureTests //' | cut -c1-120 || true

echo ""
echo "==> the verdict, read from Firestore rather than from the test result"
node "$ROOT/Scripts/verify-live-features.mjs"
