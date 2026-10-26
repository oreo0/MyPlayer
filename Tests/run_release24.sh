#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d /private/tmp/MyPlayer-release24.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Sources"
cp "${MYPLAYER24_BASELINE:-.}"/Sources/*.swift "$stage/Sources/"
python3 - "$stage" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]);p=root/'Sources/ContentView.swift';s=p.read_text().replace('    var body: some View {\n        windowContent','    var body: some View {\n        let _ = RenderProbe24.tick()\n        windowContent',1);p.write_text(s)
p=root/'Sources/UserDataStore.swift';s=p.read_text().replace('static let shared = UserDataStore()',f'static let shared = UserDataStore(root: URL(fileURLWithPath: "{root}/shared-data"))');p.write_text(s)
PY
sources=()
for source in "$stage"/Sources/*.swift; do
 [[ "$source" == */LyricPlayerApp.swift ]] || sources+=("$source")
done
swiftc -whole-module-optimization -disable-sandbox -swift-version 5 -parse-as-library "${sources[@]}" Tests/Release24/main.swift -o "$stage/checks"
"$stage/checks" "$stage" "$@"
python3 Tests/Navigation19/check_frozen.py
