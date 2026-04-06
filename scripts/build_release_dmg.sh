#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export SPACEPIN_BUNDLE_ID="${SPACEPIN_BUNDLE_ID:-com.zoochigames.spacepin}"
export SPACEPIN_TEAM_ID="${SPACEPIN_TEAM_ID:-TQW4K2Z6UW}"

DERIVED_DATA_PATH="${SPACEPIN_DERIVED_DATA_PATH:-$ROOT_DIR/.derived}"
ARCHIVE_PATH="${SPACEPIN_DIRECT_ARCHIVE_PATH:-$DERIVED_DATA_PATH/SpacePin-DirectDist.xcarchive}"
EXPORT_PATH="${SPACEPIN_DIRECT_EXPORT_PATH:-$DERIVED_DATA_PATH/export-direct}"
DMG_PATH="${SPACEPIN_DMG_PATH:-$DERIVED_DATA_PATH/SpacePin.dmg}"
EXPORT_OPTIONS_PLIST="${SPACEPIN_DIRECT_EXPORT_OPTIONS_PLIST:-$ROOT_DIR/Support/ExportOptions-DirectDistribution.plist}"
VOLUME_NAME="${SPACEPIN_DMG_VOLUME_NAME:-SpacePin Installer}"

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spacepin-dmg-stage.XXXXXX")"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [[ ! -d "$ROOT_DIR/SpacePin.xcodeproj" ]]; then
  ruby scripts/generate_xcodeproj.rb
fi

if [[ "${SPACEPIN_SKIP_DIRECT_EXPORT:-0}" != "1" ]]; then
  xcodebuild \
    -project SpacePin.xcodeproj \
    -scheme SpacePin \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=YES \
    archive

  rm -rf "$EXPORT_PATH"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
fi

APP_PATH="$EXPORT_PATH/SpacePin.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected exported app at $APP_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" "$STAGE_DIR/SpacePin.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created DMG at $DMG_PATH"
