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
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spacepin-dmg-mount.XXXXXX")"
RW_DMG_PATH=""
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
  if [[ -n "$RW_DMG_PATH" ]]; then
    rm -f "$RW_DMG_PATH"
  fi
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

APP_SIZE_KB="$(du -sk "$APP_PATH" | awk '{print $1}')"
DMG_SIZE_MB="$((APP_SIZE_KB / 512 + 20))"
RW_DMG_BASE="$(mktemp "${TMPDIR:-/tmp}/spacepin-release.XXXXXX")"
rm -f "$RW_DMG_BASE"
RW_DMG_PATH="${RW_DMG_BASE}.dmg"
rm -f "$DMG_PATH"
rm -f "$RW_DMG_PATH"
hdiutil create \
  -size "${DMG_SIZE_MB}m" \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  "$RW_DMG_PATH"

hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
ditto --norsrc --noextattr "$STAGE_DIR/SpacePin.app" "$MOUNT_DIR/SpacePin.app"
ln -s /Applications "$MOUNT_DIR/Applications"
sync
hdiutil detach "$MOUNT_DIR" -quiet

hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

echo "Created DMG at $DMG_PATH"
