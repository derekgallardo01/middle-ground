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

# Warm the app before the tape rolls.
#
# simctl writes frames only when the screen changes, and under load it stops writing at all: a
# cold first launch — installing, creating the SwiftData store, the first location fix, the first
# search, the first Look Around fetch — put **two minutes of the tour into ten seconds of video**.
# The footage was not trimmed away or mistimed; those frames were never captured. Everything after
# the app had warmed up recorded fine.
#
# So the expensive first run happens off camera.
APP=$(find "$OUT/dd/Build/Products" -name "MiddleGround.app" -maxdepth 3 2>/dev/null | head -1)
if [ -n "$APP" ]; then
  echo "==> warming up"
  xcrun simctl install "$UDID" "$APP" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" app.middleground.MiddleGround -MGMockMode >/dev/null 2>&1 || true
  sleep 25
  xcrun simctl terminate "$UDID" app.middleground.MiddleGround >/dev/null 2>&1 || true
  sleep 3
fi

rm -f "$VIDEO"
echo "==> recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$VIDEO" &
RECORDER=$!

# Recording either started or it did not, and finding out now costs three seconds. A killed
# recorder can leave the simulator believing one is still in progress — "Host recording is already
# in progress" — and the run then executed the whole tour against a device that was writing
# nothing, three minutes to reach a file that never existed.
sleep 3
if ! kill -0 "$RECORDER" 2>/dev/null; then
  echo "The recorder did not start. Usually a previous one is still holding the device:" >&2
  echo "  xcrun simctl shutdown $UDID && xcrun simctl boot $UDID" >&2
  exit 1
fi
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
# Re-time by frame index, then cut to where the app is actually on screen.
#
# `-fps_mode cfr` samples the source by its timestamps, and this capture's timestamps are not
# wall-clock: on one run that sampling threw away nearly every frame of the app and held the home
# screen instead, producing a 73-second film of a wallpaper from a recording that did contain the
# tour. `setpts=N/(30*TB)` renumbers each decoded frame in order at 30fps and ignores the source
# clock entirely, so no frame can be dropped or duplicated by a bad one.
#
# The consequence worth knowing: the output runs faster than real time, because simctl captured
# roughly ten frames a second of a three-minute tour. Every frame it did capture is in there.
ALLFRAMES="${VIDEO%.mp4}-allframes.mp4"
if ! ffmpeg -loglevel error -i "$VIDEO" -vf "setpts=N/(30*TB)" -r 30 \
     -c:v libx264 -crf 23 -preset veryfast -movflags +faststart "$ALLFRAMES" -y; then
  echo "Re-timing failed. The raw recording is at $VIDEO" >&2
  exit 1
fi

# Head and tail together, by brightness: the app is a light UI, the home screen is a wallpaper.
read -r ASTART AEND <<<"$(python3 "$SCRIPT_DIR/trim-tour.py" "$ALLFRAMES" --window)"
if [ "${AEND:-0}" -le "${ASTART:-0}" ]; then
  echo "Could not find the app in the recording — see $ALLFRAMES" >&2
  exit 1
fi

if ! ffmpeg -loglevel error -ss "$ASTART" -t "$(( AEND - ASTART ))" -i "$ALLFRAMES" \
     -c copy -movflags +faststart "$TRIMMED" -y; then
  echo "Trim failed. The re-timed recording is at $ALLFRAMES" >&2
  exit 1
fi
rm -f "$ALLFRAMES"

SIZE=$(du -h "$TRIMMED" | cut -f1)
LENGTH=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TRIMMED")
FRAMES=$(ffprobe -v error -select_streams v -count_frames \
  -show_entries stream=nb_read_frames -of default=nw=1:nk=1 "$TRIMMED")
echo "Video: $TRIMMED  ($SIZE, ${LENGTH}s, ${FRAMES} frames, app on screen ${ASTART}s–${AEND}s)"

# A duration and a file size both looked right on a twelve-frame file. The frame count is the
# number that would have caught it, so it is checked rather than merely printed.
MIN_FRAMES=$(python3 -c "print(int(float('${LENGTH:-0}') * 10))")
if [ "${FRAMES:-0}" -lt "$MIN_FRAMES" ]; then
  echo "That is ${FRAMES} frames for ${LENGTH}s — a slideshow, not a recording." >&2
  exit 1
fi

exit "$TOUR_STATUS"
