#!/bin/bash
#
# Captures the screenshots used on seekmiddleground.com and writes them, web-sized, into
# site/assets/shots/.
#
# Sibling of Scripts/screenshots.sh, which produces the App Store set. The two want different
# images and different sizes: the store wants full-resolution 6.9" frames, the site wants
# something a phone can load over cellular in one go.
#
# Usage:
#   ./Scripts/site-screenshots.sh
#
# Re-run whenever a screen in SiteScreenshotTests changes. A screenshot showing a design that no
# longer exists is worse than no screenshot.
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="$REPO/site/assets/shots"
DEVICE="${MG_SHOT_DEVICE:-iPhone 17 Pro}"
WORK="$(mktemp -d)"

cd "$APP_DIR"
xcodegen generate >/dev/null

echo "==> capturing on $DEVICE"
xcodebuild \
  -project MiddleGround.xcodeproj \
  -scheme MiddleGroundApp \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:MiddleGroundUITests/SiteScreenshotTests \
  -resultBundlePath "$WORK/shots.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test >"$WORK/build.log" 2>&1 \
  || echo "!! some screens failed to capture — see $WORK/build.log"

# Extraction runs either way. A run that captured eight of ten screens is worth keeping; the
# first version exited here and threw away everything the run *did* manage to photograph.
if ! [ -d "$WORK/shots.xcresult" ]; then
  echo "no result bundle — the build itself failed, see $WORK/build.log"
  exit 1
fi

echo "==> extracting"
xcrun xcresulttool export attachments --path "$WORK/shots.xcresult" --output-path "$WORK/raw" >/dev/null

mkdir -p "$OUT"
python3 - "$WORK/raw" "$OUT" <<'PY'
import json, os, sys
from PIL import Image

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

# WebP at 540px wide. Displayed around 190px, so this is comfortably retina, and a UI
# screenshot of flat colour compresses to a fraction of the equivalent PNG — which matters for
# a page people open from a text message on cellular.
WIDTH = 540
seen = set()
for name, fn in sorted(found):
    base = name.split('_0_')[0]
    if base in seen:
        continue
    seen.add(base)
    image = Image.open(os.path.join(raw, fn)).convert('RGB')
    height = round(image.height * WIDTH / image.width)
    image.resize((WIDTH, height), Image.LANCZOS).save(
        os.path.join(out, base + '.webp'), 'WEBP', quality=82, method=6
    )

total = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out))
for f in sorted(os.listdir(out)):
    size = os.path.getsize(os.path.join(out, f))
    print(f"  {f:24} {size // 1024:>4} KB")
print(f"\n{len(seen)} screenshots, {total // 1024} KB total")
PY

echo
echo "==> $OUT"
echo "    now run: python3 site/build.py"
