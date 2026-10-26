#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /private/tmp/MyPlayer-release23.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
python3 Tests/Release22/av_fixture.py "$stage/sample.mov"
sources=()
for source in Sources/*.swift; do
 [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -whole-module-optimization -disable-sandbox -swift-version 5 -parse-as-library "${sources[@]}" Tests/Release23/main.swift -o "$stage/checks"
"$stage/checks" "$stage"
python3 Tests/Navigation19/check_frozen.py
