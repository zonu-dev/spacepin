#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ARCHIVE_PATH="${SPACEPIN_ARCHIVE_PATH:-$ROOT_DIR/.derived/SpacePin.xcarchive}"
EXPORT_PATH="${SPACEPIN_EXPORT_PATH:-$ROOT_DIR/.derived/export-app-store}"
EXPORT_OPTIONS_PLIST="${SPACEPIN_EXPORT_OPTIONS_PLIST:-$ROOT_DIR/Support/ExportOptions-AppStore.plist}"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
