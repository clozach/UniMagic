#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_root="${UNIMAGIC_BUILD_ROOT:-/tmp/unimagic-build}"
mode="${1:-simulator}"
release_version="${BUILD_VERSION:-1.0.0}"
release_build="${BUILD_NUMBER:-1}"
[[ "$release_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ && "$release_build" =~ ^[0-9]+$ ]] || { echo 'Invalid BUILD_VERSION or BUILD_NUMBER' >&2; exit 64; }
mkdir -p "$build_root/project/Resources"
node "$source_dir/../scripts/ios-corpus.mjs" "$build_root/resources/corpus.sqlite"
node "$source_dir/prepare-inventory.mjs" "$build_root/resources/corpus.sqlite"
for item in App Shared Engine Keyboard Controls Resources; do
  # Mirror only source-owned trees; preserve generated projects and build caches.
  mkdir -p "$build_root/project/$item"
  rsync -a --delete "$source_dir/$item/" "$build_root/project/$item/"
done
cp "$source_dir/project.yml" "$build_root/project/project.yml"
node "$source_dir/configure-stage.mjs" "$build_root/project" "${UNIMAGIC_APP_GROUP:-group.com.clozach.unimagic.visibility}"
cp "$build_root/resources/corpus.sqlite" "$build_root/project/Resources/corpus.sqlite"
rm -f "$build_root/project/Resources/RecentsSeed.json"
notice_source="$source_dir/../seeds/GLYPHFINDER-NOTICE.md"
if [[ ! -f "$notice_source" ]]; then notice_source="$source_dir/../../seeds/GLYPHFINDER-NOTICE.md"; fi
[[ -f "$notice_source" ]] || { echo 'Glyphfinder notice missing from source export' >&2; exit 66; }
cp "$notice_source" "$build_root/project/Resources/GLYPHFINDER-NOTICE.md"
[[ -d "$source_dir/../licenses" && -f "$source_dir/../LICENSE" ]] || { echo 'Original/dependency licenses missing from source export' >&2; exit 66; }
mkdir -p "$build_root/project/Resources/Licenses"
rsync -a --delete "$source_dir/../licenses/" "$build_root/project/Resources/Licenses/"
cp "$source_dir/../LICENSE" "$build_root/project/Resources/Licenses/UniMagic-MIT-LICENSE.txt"
cd "$build_root/project"
xcodegen generate --spec project.yml --quiet
case "$mode" in
  simulator) destination='generic/platform=iOS Simulator'; signing=(CODE_SIGNING_ALLOWED=NO) ;;
  device|unsigned-device) destination='generic/platform=iOS'; signing=(CODE_SIGNING_ALLOWED=NO) ;;
  *) echo 'Usage: build.sh [simulator|unsigned-device|device]' >&2; exit 64 ;;
esac
xcodebuild -project Unimagic.xcodeproj -scheme Unimagic -configuration Debug \
  -destination "$destination" -derivedDataPath "$build_root/DerivedData" \
  MARKETING_VERSION="$release_version" CURRENT_PROJECT_VERSION="$release_build" "${signing[@]}" build

if [[ "$mode" == device || "$mode" == unsigned-device ]]; then
  echo "Unsigned device app built. Sign through the paired-Mac delivery tooling before installation."
fi
