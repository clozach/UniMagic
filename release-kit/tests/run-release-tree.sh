#!/bin/bash
set -euo pipefail
kit=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/release-tree.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
xcrun swiftc -swift-version 5 "$kit/publisher/ProductSpec.swift" "$kit/publisher/PIdentity.swift" "$kit/publisher/PSupport.swift" "$kit/publisher/PReleaseState.swift" "$kit/tests/ReleaseTreeTests.swift" -o "$fixture/tests"
"$fixture/tests"
