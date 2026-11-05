#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pnpm install --frozen-lockfile --ignore-scripts
pnpm gen
pnpm exec tsc --noEmit
pnpm test
node --test tools/tests/*.test.mjs
