#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export SPACEPIN_BUNDLE_ID="${SPACEPIN_BUNDLE_ID:-com.zoochigames.spacepin}"
export SPACEPIN_TEAM_ID="${SPACEPIN_TEAM_ID:-TQW4K2Z6UW}"

ARCHIVE_PATH="${SPACEPIN_ARCHIVE_PATH:-$ROOT_DIR/.derived/SpacePin.xcarchive}"
DERIVED_DATA_PATH="${SPACEPIN_DERIVED_DATA_PATH:-$ROOT_DIR/.derived}"
CODE_SIGNING_ALLOWED_VALUE="${SPACEPIN_CODE_SIGNING_ALLOWED:-}"

ruby scripts/generate_xcodeproj.rb

if [[ -z "$CODE_SIGNING_ALLOWED_VALUE" ]]; then
  if [[ -n "${SPACEPIN_TEAM_ID}" ]]; then
    CODE_SIGNING_ALLOWED_VALUE="YES"
  else
    CODE_SIGNING_ALLOWED_VALUE="NO"
  fi
fi

xcodebuild \
  -project SpacePin.xcodeproj \
  -scheme SpacePin \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED_VALUE" \
  archive
