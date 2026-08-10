#!/bin/bash
#
# What fraction of the app the unit tests actually execute, and where the holes are.
#
# Until today this was never measured — no `-enableCodeCoverage` anywhere, no percentage in any
# document. That was a deliberate position ("coverage would not have caught one bug found this
# week") and it was right about coverage as a *target*. It was wrong as a reason not to look:
# the first measurement pointed straight at `SpontaneousRequestViewModel` at 0%, which turned out
# to contain two live bugs — an arbitrary group's invite code, and a recipient picker that labelled
# every member of a group with the group's own name.
#
# So this is a *pointer*, not a score. A high number proves nothing; a 0% file is a place nobody
# has looked.
#
# The split matters more than the total. Views are exercised by UI tests, which do not run here,
# so their ~0% is expected and not interesting. The non-view figure is the one to read.
#
#   ./Scripts/coverage.sh            # iOS unit tests
#   ./Scripts/coverage.sh --functions  # Cloud Functions too
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${MG_COV_BUNDLE:-/tmp/mg-coverage.xcresult}"
DEVICE="${MG_COV_DEVICE:-iPhone 17 Pro}"

cd "$ROOT"
rm -rf "$BUNDLE"

echo "==> running the unit suite with coverage"
xcodebuild test \
  -scheme MiddleGround \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -enableCodeCoverage YES \
  -resultBundlePath "$BUNDLE" >/tmp/mg-coverage.log 2>&1

grep -E "Executed .* tests" /tmp/mg-coverage.log | tail -1

xcrun xccov view --report --files-for-target MiddleGround --json "$BUNDLE" >/tmp/mg-coverage.json

python3 - <<'PY'
import json

groups = json.load(open('/tmp/mg-coverage.json'))
files = [f for g in groups for f in g.get('files', [])]

SUFFIXES = ('View.swift', 'Card.swift', 'Row.swift', 'Sheet.swift', 'Bubble.swift',
            'Indicator.swift', 'Prompt.swift', 'Badge.swift', 'Button.swift',
            'Skeleton.swift', 'State.swift', 'Strip.swift', 'Mark.swift')

def is_view(name):
    return name.endswith(SUFFIXES) or '+Overview' in name

rows = [(f.get('name', ''), f.get('executableLines', 0), f.get('coveredLines', 0))
        for f in files if f.get('executableLines', 0)]

logic = sorted((r for r in rows if not is_view(r[0])), key=lambda r: r[1] - r[2], reverse=True)
views = [r for r in rows if is_view(r[0])]

def pct(rs):
    ex = sum(r[1] for r in rs) or 1
    return sum(r[2] for r in rs) / ex * 100

print()
print(f"  non-view logic : {pct(logic):5.1f}%   ({len(logic)} files)")
print(f"  views          : {pct(views):5.1f}%   ({len(views)} files, exercised by UI tests instead)")
print(f"  everything     : {pct(rows):5.1f}%")
print()

# A file nobody has executed is where the next bug is. Named, not summarised.
never = [r for r in logic if r[2] == 0 and r[1] >= 40]
if never:
    print("  never executed by any unit test (40+ lines):")
    for name, ex, _ in never[:15]:
        print(f"    {name[:48]:48} {ex:5} lines")
    print()
PY

if [ "${1:-}" = "--functions" ]; then
  echo "==> Cloud Functions"
  cd "$ROOT/CloudFunctions"
  # rules.test.js is excluded: it needs the Firestore emulator, which needs Java.
  node --test --experimental-test-coverage \
    test/time.test.js test/push.test.js test/handlers.test.js \
    test/alerts.test.js test/discovery.test.js test/paging.test.js 2>&1 \
    | sed -n '/start of coverage report/,/end of coverage report/p'
fi
