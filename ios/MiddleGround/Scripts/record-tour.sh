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
# When the tape started rolling, so the dead head can be measured rather than guessed at.
RECORD_EPOCH=$(date +%s)
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
#
# Measured, not detected. trim-tour.py looks for the first frame that differs from the last, and
# the simulator obliges long before the app appears — waking the display counts as motion. It left
# 36 seconds of home screen at the front of a 144-second tour, which is a quarter of the film.
#
# xcodebuild stamps its first line with a wall clock, and that line lands within a second of
# `Launch app.middleground.MiddleGround`. Subtracting the moment recording began gives the offset
# exactly. The frame-difference version stays as the fallback for when the log has no timestamp.
TRIMMED="${VIDEO%.mp4}-trimmed.mp4"
#
# The two signals together. The wall clock says when the test began, which is a floor nothing
# earlier can beat; the frame difference then finds when the app actually drew, which is a further
# twenty-odd seconds on this volume. Either alone gets it wrong: the clock leaves the launch wait
# in, and the detector on its own fires on the simulator waking its display.
LAUNCH_STAMP=$(grep -oE "^20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" "$OUT/tour.log" | head -1)
FLOOR=0
if [ -n "$LAUNCH_STAMP" ]; then
  LAUNCH_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LAUNCH_STAMP" +%s 2>/dev/null || true)
  if [ -n "$LAUNCH_EPOCH" ]; then
    FLOOR=$(( LAUNCH_EPOCH - RECORD_EPOCH ))
    [ "$FLOOR" -lt 0 ] && FLOOR=0
  fi
fi
START=$(python3 "$SCRIPT_DIR/trim-tour.py" "$VIDEO" "$FLOOR")
#
# `-fps_mode cfr -r 30` is not a nicety. simctl records variable-rate and writes nothing while the
# screen is still, so re-encoding without it produced a "video" of **twelve frames stretched over
# 144 seconds** — a slideshow that reported a sane duration and a sane file size, and that looked,
# when scrubbed, exactly like a tour stuck on one screen. That is what "it swipes on the same
# screen" was. A constant rate fills the gaps and makes the file seekable.
if ! ffmpeg -loglevel error -ss "$START" -i "$VIDEO" -c:v libx264 -crf 23 -preset veryfast \
     -fps_mode cfr -r 30 -movflags +faststart "$TRIMMED" -y; then
  echo "Trim failed. The untrimmed recording is at $VIDEO" >&2
  exit 1
fi

SIZE=$(du -h "$TRIMMED" | cut -f1)
LENGTH=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TRIMMED")
FRAMES=$(ffprobe -v error -select_streams v -count_frames \
  -show_entries stream=nb_read_frames -of default=nw=1:nk=1 "$TRIMMED")
echo "Video: $TRIMMED  ($SIZE, ${LENGTH}s, ${FRAMES} frames, trimmed from ${START}s)"

# A duration and a file size both looked right on a twelve-frame file. The frame count is the
# number that would have caught it, so it is checked rather than merely printed.
MIN_FRAMES=$(python3 -c "print(int(float('${LENGTH:-0}') * 10))")
if [ "${FRAMES:-0}" -lt "$MIN_FRAMES" ]; then
  echo "That is ${FRAMES} frames for ${LENGTH}s — a slideshow, not a recording." >&2
  exit 1
fi

exit "$TOUR_STATUS"
