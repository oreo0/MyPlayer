#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/ModuleCache
xcrun swiftc -module-cache-path build/ModuleCache Sources/MetadataText.swift Tests/MetadataText/main.swift -o build/metadata-checks
build/metadata-checks
