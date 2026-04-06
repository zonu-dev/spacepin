#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${SPACEPIN_DERIVED_DATA_PATH:-$ROOT_DIR/.derived}"
EXPORT_PATH="${SPACEPIN_DIRECT_EXPORT_PATH:-$DERIVED_DATA_PATH/export-direct}"
APP_PATH="${SPACEPIN_DIRECT_APP_PATH:-$EXPORT_PATH/SpacePin.app}"
DMG_PATH="${SPACEPIN_DMG_PATH:-$DERIVED_DATA_PATH/SpacePin.dmg}"
ZIP_PATH="${SPACEPIN_NOTARY_ZIP_PATH:-$DERIVED_DATA_PATH/SpacePin-notary.zip}"
GITHUB_RELEASE_TAG="${SPACEPIN_GITHUB_RELEASE_TAG:-}"

notary_args=()

if [[ -n "${SPACEPIN_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  notary_args+=(--keychain-profile "$SPACEPIN_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${SPACEPIN_NOTARY_KEY:-}" && -n "${SPACEPIN_NOTARY_KEY_ID:-}" ]]; then
  notary_args+=(--key "$SPACEPIN_NOTARY_KEY" --key-id "$SPACEPIN_NOTARY_KEY_ID")
  if [[ -n "${SPACEPIN_NOTARY_ISSUER_ID:-}" ]]; then
    notary_args+=(--issuer "$SPACEPIN_NOTARY_ISSUER_ID")
  fi
elif [[ -n "${SPACEPIN_NOTARY_APPLE_ID:-}" && -n "${SPACEPIN_NOTARY_TEAM_ID:-}" ]]; then
  notary_args+=(--apple-id "$SPACEPIN_NOTARY_APPLE_ID" --team-id "$SPACEPIN_NOTARY_TEAM_ID")
  if [[ -n "${SPACEPIN_NOTARY_PASSWORD:-}" ]]; then
    notary_args+=(--password "$SPACEPIN_NOTARY_PASSWORD")
  fi
else
  cat >&2 <<'EOF'
Missing notarization credentials.

Set one of the following before running:
  1. SPACEPIN_NOTARY_KEYCHAIN_PROFILE
  2. SPACEPIN_NOTARY_KEY + SPACEPIN_NOTARY_KEY_ID [+ SPACEPIN_NOTARY_ISSUER_ID]
  3. SPACEPIN_NOTARY_APPLE_ID + SPACEPIN_NOTARY_TEAM_ID [+ SPACEPIN_NOTARY_PASSWORD]

Examples:
  xcrun notarytool store-credentials spacepin-notary \
    --apple-id 'you@example.com' \
    --team-id 'TEAMID1234' \
    --password '<app-specific-password>'

  SPACEPIN_NOTARY_KEYCHAIN_PROFILE=spacepin-notary scripts/notarize_release_dmg.sh
EOF
  exit 1
fi

if [[ ! -d "$APP_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "Direct distribution app or DMG is missing. Run scripts/build_release_dmg.sh first." >&2
  exit 1
fi

submit_and_wait() {
  local path="$1"
  local label="$2"
  local output
  output="$(xcrun notarytool submit "$path" "${notary_args[@]}" --wait --output-format json)"

  ruby -rjson -e '
    payload = JSON.parse(STDIN.read)
    status = payload["status"]
    id = payload["id"] || payload["submissionId"]
    unless status == "Accepted"
      warn("#{ARGV[0]} notarization failed with status=#{status || "unknown"} submission_id=#{id || "unknown"}")
      exit 1
    end
    puts("#{ARGV[0]} notarization accepted: #{id}")
  ' "$label" <<<"$output"
}

echo "Submitting app for notarization..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
submit_and_wait "$ZIP_PATH" "app"

echo "Stapling app..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Rebuilding DMG with stapled app..."
SPACEPIN_SKIP_DIRECT_EXPORT=1 scripts/build_release_dmg.sh

echo "Submitting DMG for notarization..."
submit_and_wait "$DMG_PATH" "dmg"

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

if [[ -n "$GITHUB_RELEASE_TAG" ]]; then
  echo "Uploading notarized DMG to GitHub release $GITHUB_RELEASE_TAG..."
  gh release upload "$GITHUB_RELEASE_TAG" "$DMG_PATH#SpacePin.dmg" --clobber
fi

echo "Notarized DMG ready at $DMG_PATH"
