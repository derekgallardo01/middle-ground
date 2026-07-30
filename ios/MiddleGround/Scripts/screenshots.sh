#!/bin/bash
#
# Captures App Store screenshots and extracts them as PNGs.
#
# Runs ScreenshotTests on a 6.9" simulator (1320x2868, which App Store Connect accepts in the
# 6.7" slot, APP_IPHONE_67). The app runs in mock mode so the screens are populated and
# deterministic — a fresh real account has no partner and no requests, so every screen would be
# an empty state.
#
# Usage:
#   ./Scripts/screenshots.sh [output-dir]
#
# Then upload with Scripts/upload-screenshots.mjs.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
OUT="${1:-$HOME/Desktop/MiddleGround-Screenshots}"
DEVICE="${MG_SHOT_DEVICE:-iPhone 17 Pro Max}"
WORK="$(mktemp -d)"

cd "$APP_DIR"
xcodegen generate >/dev/null

echo "==> capturing on $DEVICE"
xcodebuild \
  -project MiddleGround.xcodeproj \
  -scheme MiddleGroundApp \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:MiddleGroundUITests/ScreenshotTests \
  -resultBundlePath "$WORK/shots.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test >"$WORK/build.log" 2>&1 \
  || { echo "capture failed — see $WORK/build.log"; exit 1; }

echo "==> extracting"
xcrun xcresulttool export attachments --path "$WORK/shots.xcresult" --output-path "$WORK/raw" >/dev/null

rm -rf "$OUT"; mkdir -p "$OUT"
# xcresulttool writes UUID filenames; the readable name lives in manifest.json, and the
# attachment name is what orders the screenshots on the store listing.
python3 - "$WORK/raw" "$OUT" <<'PY'
import json, os, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(raw, 'manifest.json')))
found = []
def walk(node):
    if isinstance(node, dict):
        name = node.get('suggestedHumanReadableName') or node.get('name')
        fn = node.get('exportedFileName')
        if name and fn and fn.endswith('.png'):
            found.append((name, fn))
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
walk(manifest)

seen = set()
for name, fn in sorted(found):
    base = name.split('_0_')[0]           # strip the UUID suffix xcresulttool appends
    if base in seen:
        continue
    seen.add(base)
    shutil.copy(os.path.join(raw, fn), os.path.join(out, base + '.png'))
print('\n'.join(sorted(seen)))
PY

echo
echo "==> $OUT"
for f in "$OUT"/*.png; do
  printf "  %-22s %s\n" "$(basename "$f")" \
    "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done
