#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /tmp/MyPlayer-tests48.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
module_cache="$(cd .. && pwd)/work/Test48Modules"
mkdir -p "$module_cache"
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/LyricPlayerApp.swift" ]] || sources+=("$source")
done
swiftc -disable-sandbox -module-cache-path "$module_cache" -target "$(uname -m)-apple-macos26.0" -swift-version 5 -parse-as-library "${sources[@]}" Tests/Interface48/main.swift -o "$stage/interface-tests"
python3 Tests/PlaybackSession39/video_fixture.py "$stage/sample.mov"
python3 - "$stage/interface-tests" "$stage/sample.mov" <<'PY'
import subprocess,sys
subprocess.run(sys.argv[1:],check=True,timeout=30)
PY
