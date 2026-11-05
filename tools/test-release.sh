#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash release-kit/tests/run-security.sh
bash release-kit/tests/run-initial-publish.sh
pnpm run build:tinycast
node macos/build.mjs
node macos/verify-bridge.mjs
node macos/verify-native.mjs
