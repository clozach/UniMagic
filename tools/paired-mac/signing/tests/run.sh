#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d /tmp/powworm-profile-tests.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
swiftc "$root/SigningProfiles.swift" "$root/tests/main.swift" -o "$build_dir/check"
"$build_dir/check"
