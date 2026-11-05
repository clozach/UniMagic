#!/bin/bash
# Shared immutable-candidate release engine. Product-specific scripts only
# supply release-product.json, portable export, verification and bundle build.
set -euo pipefail
kit=$(cd "$(dirname "$0")/.." && pwd)
root=${1:?Usage: run.sh SOURCE_ROOT status|prepare|publish [options]}
shift
root=$(cd "$root" && pwd)
mkdir -p "$root/.build/publisher"
sources=("$kit/RKPublishLimits.swift" "$kit/RKUpdateModel.swift" "$kit/RKUpdateArchiveValidation.swift" "$kit/publisher/"*.swift)
key=$(shasum -a 256 "${sources[@]}" | shasum -a 256 | awk '{print $1}')
binary="$root/.build/publisher/$key"
if [[ ! -x "$binary" ]]; then
    stage="$binary.$$"
    trap 'rm -f "$stage"' EXIT
    xcrun swiftc -swift-version 5 "${sources[@]}" -o "$stage" >&2
    mv "$stage" "$binary"
fi
exec "$binary" --source "$root" "$@"
