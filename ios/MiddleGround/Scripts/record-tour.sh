#!/bin/bash
#
# Films the simulator while a UI test drives the nearby-places tour.
#
# `simctl io recordVideo` runs until it is interrupted, so it is started in the background, the
# test is run against the same device, and the recorder is then sent SIGINT — a kill -9 leaves an
# unplayable file, because the mp4 is only finalised on a clean exit.
#
# Usage:  ./Scripts/record-tour.sh [simulator name]
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../App" && pwd)"
DEVICE="${1:-iPhone 17 Pro}"
OUT="${MG_TOUR_OUT:-/tmp/mg-tour}"
mkdir -p "$OUT"
VIDEO="$OUT/nearby-tour.mp4"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
name=sys.argv[1]
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name']==name: print(d['udid']); raise SystemExit
raise SystemExit('no simulator named '+name)
" "$DEVICE")

echo "Device: $DEVICE ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

cd "$APP_DIR"
xcodegen generate >/dev/null

# Build first, so the recording contains the tour rather than a compile.
echo "==> building"
xcodebuild build-for-testing -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/dd" \
  -allowProvisioningUpdates > "$OUT/build.log" 2>&1

rm -f "$VIDEO"
echo "==> recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$VIDEO" &
RECORDER=$!
sleep 2

echo "==> running the tour"
xcodebuild test-without-building -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/dd" \
  -only-testing:MiddleGroundUITests/NearbyTourVideo \
  > "$OUT/tour.log" 2>&1 && TOUR_STATUS=0 || TOUR_STATUS=$?

sleep 2
# SIGINT, not SIGKILL: the file is only finalised on a clean exit.
kill -INT "$RECORDER" 2>/dev/null || true
wait "$RECORDER" 2>/dev/null || true

grep -E "Test Case '.*(passed|failed)'" "$OUT/tour.log" | sed 's/.*NearbyTourVideo //' | cut -c1-80 || true

# The recording is stopped either way — footage of a failure is how the last two bugs were
# found — but the run is not called a success. This printed a tidy "Video: ... 48s" line over a
# tour that had failed its own assertion, and the file it named was the couple filmed twice.
if [ "$TOUR_STATUS" -ne 0 ]; then
  echo
  echo "The tour FAILED. The video below is of a failed run — do not use it."
  grep -E "error:.*NearbyTourVideo" "$OUT/tour.log" | sed 's|.*/||' | head -5
  echo "Full log: $OUT/tour.log"
fi
if [ ! -f "$VIDEO" ]; then
  echo "No video was produced — see $OUT/tour.log"
  exit 1
fi

# Cut the dead head. See Scripts/trim-tour.py for why there is one.
TRIMMED="${VIDEO%.mp4}-trimmed.mp4"
START=$(python3 "$SCRIPT_DIR/trim-tour.py" "$VIDEO")
if ! ffmpeg -loglevel error -ss "$START" -i "$VIDEO" -c:v libx264 -crf 23 -preset veryfast \
     -movflags +faststart "$TRIMMED" -y; then
  echo "Trim failed. The untrimmed recording is at $VIDEO" >&2
  exit 1
fi

SIZE=$(du -h "$TRIMMED" | cut -f1)
LENGTH=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TRIMMED")
echo "Video: $TRIMMED  ($SIZE, ${LENGTH}s, trimmed from ${START}s)"

exit "$TOUR_STATUS"
