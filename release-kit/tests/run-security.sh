#!/bin/bash
set -euo pipefail
kit=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/release-security.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
xcrun swiftc -swift-version 5 "$kit/RKUpdateModel.swift" "$kit/RKUpdateArchiveValidation.swift" "$kit/RKBoundedDownload.swift" "$kit/tests/ArchiveSecurityTests.swift" -o "$fixture/archive-tests"
"$fixture/archive-tests"
xcrun swiftc -swift-version 5 "$kit"/RK*.swift "$kit/tests/MaintainerFeedTests.swift" -o "$fixture/maintainer-tests"
"$fixture/maintainer-tests"
