#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash release-kit/tests/run-security.sh
bash release-kit/tests/run-initial-publish.sh
bash release-kit/tests/run-release-tree.sh
pnpm run build:tinycast
for notice in LICENSE THIRD_PARTY_NOTICES.md licenses/MiniSearch-LICENSE.txt licenses/emojibase-LICENSE.txt licenses/EmojiOne-LICENSE.md assets/Notices.txt assets/GLYPHFINDER-NOTICE.md assets/EMOTIF-NOTICE.md; do
    test -s "build-tinycast/$notice"
done
node macos/build.mjs
node macos/verify-bridge.mjs
node macos/verify-native.mjs
node macos/verify-picker.mjs "$PWD/macos/build/UniMagic.app"
