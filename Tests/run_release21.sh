#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /private/tmp/MyPlayer-release21-tests.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
python3 Tests/Release21/fixtures.py "$stage"
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -whole-module-optimization -disable-sandbox -swift-version 5 -parse-as-library "${sources[@]}" Tests/Release21/main.swift -o "$stage/checks"
"$stage/checks" "$stage"
python3 Tests/Navigation19/check_frozen.py
