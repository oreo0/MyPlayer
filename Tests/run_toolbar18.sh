#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /tmp/MyPlayer-toolbar18.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -disable-sandbox -swift-version 5 -parse-as-library "${sources[@]}" Tests/PlaybackToolbar18/main.swift -o "$stage/toolbar-tests"
"$stage/toolbar-tests"
