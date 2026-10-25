#!/bin/zsh
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
cd "$(dirname "$0")"

TEAM="${EMBLEM_DEVELOPMENT_TEAM:-}"
[[ -z "${TEAM}" ]] && TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
  | grep -m1 -o 'teamID = [A-Z0-9]*' | awk '{print $3}')
[[ -z "${TEAM}" ]] && TEAM=$(security find-identity -v -p codesigning | grep -o '([A-Z0-9]\{10\})' | head -1 | tr -d '()')
if [[ -z "${TEAM}" ]]; then
  echo "No team found. Sign into Xcode → Settings → Accounts first." >&2
  exit 1
fi
echo "Using team ${TEAM}"

DEVICE_ID="${EMBLEM_DEVICE_ID:-}"
[[ -z "${DEVICE_ID}" ]] && DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | awk '
  !found && /physical/ {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^[0-9A-F-]{36}$/) { print $i; found = 1 }
    }
  }
')
if [[ -z "${DEVICE_ID}" ]]; then
  echo "No physical iPhone connected. Plug it in (and trust this Mac)." >&2
  exit 1
fi
echo "Deploying to device ${DEVICE_ID}"

BUNDLE_ID="${EMBLEM_DEVICE_BUNDLE_ID:?Set EMBLEM_DEVICE_BUNDLE_ID to your own bundle identifier, for example com.yourname.emblem}"
DERIVED_DATA="${EMBLEM_DERIVED_DATA_PATH:-build-device}"
echo "Using bundle identifier ${BUNDLE_ID}"

if [[ -z "${EMBLEM_OBJECT_ASSET_DIR:-}" && -f "../server/objects-256/meta.json" ]]; then
  export EMBLEM_OBJECT_ASSET_DIR="${PWD}/../server/objects-256"
fi
if [[ -n "${EMBLEM_OBJECT_ASSET_DIR:-}" ]]; then
  export EMBLEM_REQUIRE_LICENSED_ICONS=YES
  echo "Using private licensed icon pack"
fi

DEVELOPMENT_TEAM="$TEAM" ./generate-project.sh
xcodebuild -project Emblem.xcodeproj -scheme Emblem \
  -destination "platform=iOS,id=${DEVICE_ID}" \
  -configuration Debug -derivedDataPath "${DERIVED_DATA}" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
  EMBLEM_HOMEKIT="${EMBLEM_HOMEKIT:-NO}" \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" build

APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphoneos/Emblem.app"
if [[ "${EMBLEM_REQUIRE_LICENSED_ICONS:-NO}" = "YES" ]]; then
  source_icon_count=$(find "$EMBLEM_OBJECT_ASSET_DIR/images" -type f -name '*.png' | wc -l | tr -d ' ')
  app_icon_count=$(find "$APP_PATH/ObjectImages" -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
  if [[ ! -f "$APP_PATH/ObjectMeta.json" || "$app_icon_count" != "$source_icon_count" ]]; then
    echo "Licensed icon verification failed: expected ${source_icon_count}, found ${app_icon_count}." >&2
    exit 1
  fi
  echo "Verified ${app_icon_count} bundled object icons"
fi

xcrun devicectl device install app --device "${DEVICE_ID}" \
  "$APP_PATH"
xcrun devicectl device process launch --device "${DEVICE_ID}" \
  --terminate-existing "${BUNDLE_ID}"
echo "Installed and launched ${BUNDLE_ID}."
