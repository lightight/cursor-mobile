#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ios/CursorMobile"
xcodegen generate
DEST="$ROOT/dist"
mkdir -p "$DEST"
DERIVED="$DEST/DerivedData"
rm -rf "$DERIVED"
xcodebuild \
  -project CursorMobile.xcodeproj \
  -scheme CursorMobile \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

APP="$(find "$DERIVED" -name 'Cursor Mobile.app' -o -name 'CursorMobile.app' | head -n 1)"
if [[ -z "$APP" ]]; then
  echo "Could not find built .app" >&2
  find "$DERIVED" -name '*.app' >&2 || true
  exit 1
fi
STAGE="$DEST/ipa-payload"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
(cd "$STAGE" && zip -qry "$DEST/CursorMobile-unsigned.ipa" Payload)
echo "Wrote $DEST/CursorMobile-unsigned.ipa"
