#!/bin/bash
#
# Screenshots and a screen recording of every feature, from one continuous run.
#
# Drives FullTourUITests on a simulator while `simctl io recordVideo` records the screen, then
# pulls the numbered screenshots out of the result bundle and tiles them into a contact sheet.
#
# The contact sheet is not decoration. A modal left open photographs itself over every frame that
# follows, and the filenames still look perfectly sensible — the only way that gets noticed is by
# putting the images side by side and looking at them. It has happened here before: four
# "different" screenshots turned out to be the same stuck sheet.
#
# Usage:
#   ./Scripts/full-tour.sh [output-dir]
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
OUT="${1:-$HOME/Desktop/MiddleGround-Tour}"
DEVICE="${MG_TOUR_DEVICE:-iPhone 17 Pro}"
WORK="$(mktemp -d)"

mkdir -p "$OUT"
cd "$APP_DIR"
xcodegen generate >/dev/null

udid=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
name = sys.argv[1]
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == name:
            print(d['udid']); raise SystemExit
raise SystemExit('no simulator named ' + name)
" "$DEVICE")

echo "==> $DEVICE ($udid)"

# Erased first: mock mode is in-memory now, but the *simulator* still carries permission alerts
# and keyboard tutorial overlays from previous runs, and those photograph beautifully.
xcrun simctl shutdown "$udid" 2>/dev/null || true
xcrun simctl erase "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

echo "==> recording"
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$OUT/tour.mp4" &
RECORDER=$!

# Stop the recorder however this script exits, or it keeps running with no owner.
cleanup() {
  if kill -0 "$RECORDER" 2>/dev/null; then
    kill -INT "$RECORDER" 2>/dev/null || true
    wait "$RECORDER" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> touring"
set +e
xcodebuild \
  -project MiddleGround.xcodeproj \
  -scheme MiddleGroundApp \
  -destination "id=$udid" \
  -only-testing:MiddleGroundUITests/FullTourUITests \
  -resultBundlePath "$WORK/tour.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test >"$WORK/build.log" 2>&1
STATUS=$?
set -e

# Give the recorder a moment to flush the last frames before it is signalled.
sleep 2
cleanup
trap - EXIT

if [ "$STATUS" -ne 0 ]; then
  echo "!! the tour reported failures — see $WORK/build.log"
  echo "   extracting whatever it did capture anyway"
fi

if ! [ -d "$WORK/tour.xcresult" ]; then
  echo "no result bundle — the build itself failed, see $WORK/build.log"
  exit 1
fi

echo "==> extracting screenshots"
xcrun xcresulttool export attachments --path "$WORK/tour.xcresult" --output-path "$WORK/raw" >/dev/null

python3 - "$WORK/raw" "$OUT" <<'PY'
import json, os, shutil, sys
from PIL import Image

raw, out = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(raw, 'manifest.json')))

# Only the frames this tour deliberately took. xcresult also stores UI-hierarchy dumps and
# automatic failure captures, some of them named .png without being images at all — which is
# what made the first run explode on `Image.open`.
import re
NUMBERED = re.compile(r'^(\d{2}-[a-z0-9-]+)')

shots = []
def walk(node):
    if isinstance(node, dict):
        for attachment in node.get('attachments', []):
            raw_name = attachment.get('suggestedHumanReadableName') or ''
            match = NUMBERED.match(raw_name)
            if not match:
                continue
            path = os.path.join(raw, attachment['exportedFileName'])
            if os.path.exists(path):
                shots.append((match.group(1) + '.png', path))
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)

walk(manifest)
shots.sort(key=lambda pair: pair[0])

shot_dir = os.path.join(out, 'screens')
os.makedirs(shot_dir, exist_ok=True)
for old in os.listdir(shot_dir):
    os.remove(os.path.join(shot_dir, old))

saved = []
for name, path in shots:
    target = os.path.join(shot_dir, name)
    try:
        Image.open(path).verify()
    except Exception:
        print(f'  skipped {name}: not a readable image')
        continue
    shutil.copyfile(path, target)
    saved.append(target)

print(f'  {len(saved)} screenshots -> {shot_dir}')

# Contact sheet, so duplicates and stuck modals are visible at a glance.
if saved:
    thumbs = []
    for path in saved:
        image = Image.open(path)
        image.thumbnail((300, 650))
        thumbs.append((os.path.basename(path), image))

    columns = 6
    rows = (len(thumbs) + columns - 1) // columns
    cell_w = max(t.width for _, t in thumbs) + 12
    cell_h = max(t.height for _, t in thumbs) + 28
    sheet = Image.new('RGB', (columns * cell_w, rows * cell_h), 'white')
    for index, (_, thumb) in enumerate(thumbs):
        x = (index % columns) * cell_w + 6
        y = (index // columns) * cell_h + 6
        sheet.paste(thumb, (x, y))
    sheet_path = os.path.join(out, 'contact-sheet.png')
    sheet.save(sheet_path)
    print(f'  contact sheet -> {sheet_path}')

    # Identical frames are the failure this is guarding against, so say so rather than
    # leaving it to the eye alone.
    import hashlib
    digests = {}
    for path in saved:
        digest = hashlib.md5(open(path, 'rb').read()).hexdigest()
        digests.setdefault(digest, []).append(os.path.basename(path))
    duplicates = [names for names in digests.values() if len(names) > 1]
    if duplicates:
        print('  !! identical frames — a modal probably stayed open:')
        for names in duplicates:
            print('     ' + ' == '.join(names))
    else:
        print('  every frame is distinct')
PY

ls -la "$OUT/tour.mp4" 2>/dev/null && echo "  video -> $OUT/tour.mp4" || echo "  !! no video was written"
echo
echo "Done: $OUT"
