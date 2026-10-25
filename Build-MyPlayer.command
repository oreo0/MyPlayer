#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodebuild >/dev/null; then
    echo "需要在 Mac 上安装并打开一次 Xcode 后再运行此脚本。"
    exit 1
fi
bash Tests/run_build36.sh
bash Tests/run_navigation19.sh
bash Tests/run_toolbar18.sh
bash Tests/run_build39.sh
bash Tests/run_build44.sh
bash package_app.sh
workspace_dir="$(dirname "$PWD")"
open "$workspace_dir/outputs"
