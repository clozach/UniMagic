#!/bin/bash
set -euo pipefail
kit=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/initial-publisher.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
sources=("$kit/RKPublishLimits.swift" "$kit/RKUpdateModel.swift" "$kit/RKUpdateArchiveValidation.swift")
for file in "$kit/publisher/"*.swift; do [[ "$file" == */PMain.swift ]] || sources+=("$file"); done
xcrun swiftc -swift-version 5 "${sources[@]}" "$kit/tests/InitialPublishTests.swift" -o "$fixture/tests"
"$fixture/tests"
