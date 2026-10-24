#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /tmp/MyPlayer-tests51.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
module_cache="$(cd .. && pwd)/work/Test51Modules"
mkdir -p "$module_cache"
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -disable-sandbox -module-cache-path "$module_cache" -target "$(uname -m)-apple-macos26.0" -swift-version 5 -parse-as-library "${sources[@]}" Tests/Covers51/main.swift -o "$stage/cover-tests"
python3 - "$stage/cover-tests" <<'PY'
import subprocess,sys
subprocess.run([sys.argv[1]],check=True,timeout=30)
PY
