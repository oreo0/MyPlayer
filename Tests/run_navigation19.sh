#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /tmp/MyPlayer-navigation19.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -disable-sandbox -swift-version 5 -parse-as-library "${sources[@]}" Tests/Navigation19/main.swift -o "$stage/navigation-tests"
"$stage/navigation-tests"

python3 Tests/Navigation19/check_frozen.py
