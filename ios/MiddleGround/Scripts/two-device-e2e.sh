#!/bin/bash
#
# Two-device end-to-end walkthrough against the real Firebase backend.
#
# Drives two simulators in sequence: device A creates a relationship, device B joins with
# its invite code, B sends a request, and A receives it live and accepts. Each xcodebuild
# invocation drives one simulator, so the invite code is handed between runs via
# TEST_RUNNER_MG_INVITE_CODE (xcodebuild forwards TEST_RUNNER_-prefixed vars to the test).
#
# Prerequisites:
#   - Email/Password enabled in Firebase Auth (the DEBUG test accounts use it)
#   - firebase deploy --only firestore:rules,firestore:indexes  (indexes must be Enabled)
#   - GoogleService-Info.plist present in ios/MiddleGround/App/
#
# Usage:  ./Scripts/two-device-e2e.sh
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
OUT="${MG_E2E_OUT:-$(mktemp -d)}"
# mktemp -d creates the directory; an MG_E2E_OUT handed in from outside may not exist,
# and every step below redirects into it — so the first run died before the first test.
mkdir -p "$OUT"
DEVICE_A="${MG_DEVICE_A:-iPhone 17}"
DEVICE_B="${MG_DEVICE_B:-iPhone 17 Pro}"

cd "$APP_DIR"
echo "Results -> $OUT"

udid_for() {
  xcrun simctl list devices available -j | python3 -c "
import json,sys
name = sys.argv[1]
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == name:
            print(d['udid']); raise SystemExit
raise SystemExit('no simulator named ' + name)
" "$1"
}

A=$(udid_for "$DEVICE_A")
B=$(udid_for "$DEVICE_B")
echo "Device A: $DEVICE_A ($A)"
echo "Device B: $DEVICE_B ($B)"

# Fresh state so onboarding actually runs on both devices.
# A full erase, not just an uninstall: Firebase Auth persists its session in the keychain,
# which survives uninstall, and onboarding would then be skipped.
for u in "$A" "$B"; do
  xcrun simctl shutdown "$u" 2>/dev/null || true
  xcrun simctl erase "$u" 2>/dev/null || true
  xcrun simctl boot "$u" 2>/dev/null || true
  xcrun simctl bootstatus "$u" -b >/dev/null 2>&1 || true
done

run_test() {
  local udid="$1" test_name="$2" label="$3"
  echo ""
  echo "──── $label ────"
  xcodebuild -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$OUT/dd" \
    -resultBundlePath "$OUT/$label.xcresult" \
    -only-testing:"MiddleGroundUITests/PairingE2ETests/$test_name" \
    -allowProvisioningUpdates \
    test > "$OUT/$label.log" 2>&1 || true

  if grep -qE "^\*\* TEST SUCCEEDED" "$OUT/$label.log"; then
    echo "  PASS"
  else
    echo "  FAIL — see $OUT/$label.log"
    grep -E "error: -\[|XCTAssert|XCTSkip|Test skipped" "$OUT/$label.log" | head -5 | sed 's/^/    /'
    return 1
  fi
}

# 1. Device A creates the relationship and publishes its invite code.
run_test "$A" "testA1_createsRelationshipAndPublishesInviteCode" "01-A-create"

CODE=$(grep -oE "MG_E2E_INVITE_CODE=[A-Z0-9]{6}" "$OUT/01-A-create.log" | head -1 | cut -d= -f2)
if [ -z "$CODE" ]; then
  echo "Could not extract an invite code from device A's run" >&2
  exit 1
fi
echo "  invite code: $CODE"

# 2. Device B joins with that code.
export TEST_RUNNER_MG_INVITE_CODE="$CODE"
run_test "$B" "testB1_joinsWithInviteCode" "02-B-join"

# 3. Device B sends a request to its now-paired partner.
run_test "$B" "testB2_createsRequestForTheirPartner" "03-B-send"

# 4. Device A receives it live and accepts, earning XP.
run_test "$A" "testA3_seesPartnersRequestLiveAndAccepts" "04-A-receive"

# 5. The reward loop is reflected in the Activities tab.
run_test "$A" "testA4_activitiesReflectTheAccept" "05-A-activities"

echo ""
echo "All two-device steps passed. Screenshots are in the .xcresult bundles under $OUT"
