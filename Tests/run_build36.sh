#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/MyPlayer-tests36.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
cd "$project_root"
swift_target="$(uname -m)-apple-macos26.0"
swiftc -disable-sandbox -module-cache-path "$test_dir/module-cache" -target "$swift_target" -swift-version 5 Sources/UserDataFiles.swift Sources/VideoMoreState.swift Tests/UserDataFiles/main.swift -o "$test_dir/data-tests"
"$test_dir/data-tests"
swiftc -disable-sandbox -module-cache-path "$test_dir/module-cache" -target "$swift_target" -swift-version 5 -parse-as-library Sources/UserDataFiles.swift Sources/UserDataStore.swift Sources/Shortcuts.swift Tests/Shortcuts36/main.swift -o "$test_dir/shortcut-tests"
"$test_dir/shortcut-tests"
swiftc -disable-sandbox -module-cache-path "$test_dir/module-cache" -target "$swift_target" -swift-version 5 -parse-as-library Sources/UserDataFiles.swift Sources/UserDataStore.swift Tests/UserDataMigration36/main.swift -o "$test_dir/migration-tests"
"$test_dir/migration-tests"
swiftc -disable-sandbox -module-cache-path "$test_dir/module-cache" -target "$swift_target" -swift-version 5 Sources/RepeatMode.swift Sources/LRCParser.swift Sources/TimedTextParser.swift Sources/PlaybackButtonContrast.swift Tests/PlaybackAndSubtitles/main.swift -o "$test_dir/playback-tests"
"$test_dir/playback-tests"

swiftc -disable-sandbox -module-cache-path "$test_dir/module-cache" -target "$swift_target" -swift-version 5 Sources/StableMediaOrder.swift Tests/StableMediaOrder/main.swift -o "$test_dir/sort-tests"
"$test_dir/sort-tests"

swiftc -disable-sandbox -module-cache-path "$test_dir/module-cache" -target "$swift_target" -swift-version 5 -parse-as-library Sources/NativeTableDensity.swift Sources/CoverCardLayout.swift Tests/CoverAndDensity38/main.swift -o "$test_dir/layout-tests"
"$test_dir/layout-tests"
