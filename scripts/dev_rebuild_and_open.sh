#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${SPACEPIN_DERIVED_DATA_PATH:-$ROOT_DIR/.derived}"
CODE_SIGNING_ALLOWED_VALUE="${SPACEPIN_CODE_SIGNING_ALLOWED:-NO}"
APP_PATH="${SPACEPIN_APP_PATH:-$DERIVED_DATA_PATH/Build/Products/Debug/SpacePin.app}"

killall SpacePin SpacePinMenuBar 2>/dev/null || true

if [[ ! -d "$ROOT_DIR/SpacePin.xcodeproj" ]]; then
  ruby scripts/generate_xcodeproj.rb
fi

xcodebuild \
  -project SpacePin.xcodeproj \
  -scheme SpacePin \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED_VALUE" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app at $APP_PATH" >&2
  exit 1
fi

open "$APP_PATH"
