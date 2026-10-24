#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project MyPlayer.xcodeproj -scheme MyPlayer -configuration Release -derivedDataPath ../work/ReleaseDerivedData -destination 'platform=macOS' OTHER_SWIFT_FLAGS=-disable-sandbox ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO build
