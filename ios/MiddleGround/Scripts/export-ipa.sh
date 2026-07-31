#!/bin/bash
#
# Archives and exports a distribution-signed .ipa for App Store Connect.
#
# The signing story here is not obvious, and getting it wrong fails in ways that look like
# something else entirely. What is actually true:
#
#   1. Distribution signing happens at EXPORT, not at archive. With CODE_SIGN_STYLE: Automatic
#      Xcode signs the archive with the *development* identity by design, and rejects a manually
#      set CODE_SIGN_IDENTITY as a "conflicting provisioning setting". So an archive showing
#      `aps-environment: development` and `get-task-allow: true` is expected — that artifact is
#      not what gets uploaded. `-exportArchive` re-signs the payload, and that is where
#      MiddleGroundRelease.entitlements takes effect.
#
#   2. Importing the certificate and private key SEPARATELY into the login keychain produces an
#      identity that `security find-identity` happily lists but that codesign cannot use:
#      every signing attempt dies with `errSecInternalComponent`, accompanied by a misleading
#      "unable to build chain to self-signed root" warning. The key and certificate matched, the
#      WWDR intermediates were present and valid, and `security verify-cert` passed — none of
#      that is the problem. Importing a PKCS#12 (key + leaf + intermediate together) into a
#      dedicated keychain, with a partition list, is what works.
#
# Prerequisites:
#   - MG_P12 points at the Apple Distribution .p12  (default: ~/Desktop/MiddleGround-Distribution.p12)
#   - MG_P12_PASSWORD is its password
#   - The ASC API key at ~/.appstoreconnect/private_keys/AuthKey_<MG_ASC_KEY_ID>.p8
#
# Usage:
#   MG_P12_PASSWORD=... ./Scripts/export-ipa.sh
#
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
OUT="${MG_OUT:-$(mktemp -d)}"
P12="${MG_P12:-$HOME/Desktop/MiddleGround-Distribution.p12}"
P12_PASSWORD="${MG_P12_PASSWORD:-}"
ASC_KEY_ID="${MG_ASC_KEY_ID:-T79AHBMV3J}"
ASC_ISSUER="${MG_ASC_ISSUER:-7080ef6c-0e05-48e7-b508-72b9259dff45}"
ASC_KEY_PATH="${MG_ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

KC_NAME="mgsign.keychain-db"
KC_PATH="$HOME/Library/Keychains/$KC_NAME"
KC_PASSWORD="mgkc-$(openssl rand -hex 8)"

# Always put the keychain search list back, even on failure. Restore it by explicit path —
# parsing `security list-keychains` output and stripping quotes with `tr` concatenates the
# entries into one bogus path and silently breaks keychain access for the whole login session.
ORIGINAL_KEYCHAINS=()
while IFS= read -r line; do
  ORIGINAL_KEYCHAINS+=("$(sed -e 's/^[[:space:]]*"//' -e 's/"$//' <<<"$line")")
done < <(security list-keychains -d user)

cleanup() {
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" || true
  security delete-keychain "$KC_PATH" 2>/dev/null || true
}
trap cleanup EXIT

# The .p12 is the portable path, not the only one. It is also an artifact that goes missing —
# so when it is absent, fall back to whatever Apple Distribution identity is already in the
# login keychain rather than failing outright. The export is identical either way; only where
# the identity is read from changes.
if [[ -f "$P12" && -n "$P12_PASSWORD" ]]; then
  echo "==> signing keychain (from $P12)"
  security delete-keychain "$KC_PATH" 2>/dev/null || true
  security create-keychain -p "$KC_PASSWORD" "$KC_NAME"
  security set-keychain-settings -lut 21600 "$KC_NAME"
  security unlock-keychain -p "$KC_PASSWORD" "$KC_NAME"
  security import "$P12" -k "$KC_NAME" -P "$P12_PASSWORD" -A -T /usr/bin/codesign -T /usr/bin/xcodebuild >/dev/null
  # Without this, codesign fails with errSecInternalComponent regardless of the ACL above.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASSWORD" "$KC_NAME" >/dev/null
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KC_PATH"
  security find-identity -v -p codesigning "$KC_NAME"
else
  echo "==> no .p12 — using the Apple Distribution identity in the login keychain"
  security find-identity -v -p codesigning | grep 'Apple Distribution' \
    || { echo "FAIL: no Apple Distribution identity available, and no MG_P12/MG_P12_PASSWORD to import one"; exit 1; }
fi

cd "$APP_DIR"
xcodegen generate >/dev/null

echo "==> archive  (build $(date -u +%Y%m%d%H%M))"
xcodebuild \
  -project MiddleGround.xcodeproj \
  -scheme MiddleGroundApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/MiddleGround.xcarchive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER" \
  MG_BUILD_NUMBER="$(date -u +%Y%m%d%H%M)" \
  archive

echo "==> export"
xcodebuild -exportArchive \
  -archivePath "$OUT/MiddleGround.xcarchive" \
  -exportPath "$OUT/ipa" \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER"

IPA="$OUT/ipa/Middle Ground.ipa"

# Check the artifact rather than trusting that the export "succeeded". A development-signed
# payload exports perfectly happily and is then refused at upload.
echo "==> verifying the exported payload"
WORK="$(mktemp -d)"
(cd "$WORK" && unzip -q "$IPA")
ENTS="$(codesign -d --entitlements - --xml "$WORK/Payload/Middle Ground.app" 2>/dev/null | plutil -p -)"
AUTHORITY="$(codesign -dvv "$WORK/Payload/Middle Ground.app" 2>&1 | grep -m1 'Authority=Apple')"

echo "$AUTHORITY"
grep -E 'aps-environment|get-task-allow' <<<"$ENTS"

grep -q '"aps-environment" => "production"' <<<"$ENTS" \
  || { echo "FAIL: aps-environment is not production"; exit 1; }
grep -q '"get-task-allow" => false' <<<"$ENTS" \
  || { echo "FAIL: get-task-allow is not false — this is a development build"; exit 1; }
grep -q 'Apple Distribution' <<<"$AUTHORITY" \
  || { echo "FAIL: not signed with an Apple Distribution certificate"; exit 1; }

echo "==> validating with App Store Connect"
# Requires the app record to exist in App Store Connect. Until it does this reports
# "Cannot determine the Apple ID from Bundle ID", which is not a problem with the build.
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER" || true

echo
echo "IPA: $IPA"
echo "Upload with:"
echo "  xcrun altool --upload-app -f \"$IPA\" -t ios --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER"
