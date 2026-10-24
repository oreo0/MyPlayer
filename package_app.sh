#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")" && pwd)"
workspace="$(dirname "$project_root")"
mkdir -p "$workspace/work" "$workspace/outputs"
if [[ "${1:-}" != "--skip-build" ]]; then
    xcodebuild -project "$project_root/MyPlayer.xcodeproj" -scheme MyPlayer -configuration Release -derivedDataPath "$workspace/work/ReleaseDerivedData" -destination 'platform=macOS' OTHER_SWIFT_FLAGS=-disable-sandbox ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO build > "$workspace/work/release-build.log" 2>&1
fi
stage="$(mktemp -d /tmp/MyPlayer-package.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc "$workspace/work/ReleaseDerivedData/Build/Products/Release/MyPlayer.app" "$stage/MyPlayer.app"
xattr -cr "$stage/MyPlayer.app"
codesign --force --deep --sign - "$stage/MyPlayer.app"
codesign --verify --deep --strict "$stage/MyPlayer.app"
ditto -c -k --keepParent "$stage/MyPlayer.app" "$workspace/outputs/MyPlayer.zip"
echo "Ready: $workspace/outputs/MyPlayer.zip"
