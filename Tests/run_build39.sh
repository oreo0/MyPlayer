#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /tmp/MyPlayer-tests39.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
module_cache="$(cd .. && pwd)/work/Test39Modules"
mkdir -p "$module_cache"
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -disable-sandbox -module-cache-path "$module_cache" -target "$(uname -m)-apple-macos26.0" -swift-version 5 -parse-as-library "${sources[@]}" Tests/PlaybackSession39/main.swift -o "$stage/session-tests"
python3 Tests/PlaybackSession39/video_fixture.py "$stage/sample.mov"
"$stage/session-tests" "$stage/sample.mov"
