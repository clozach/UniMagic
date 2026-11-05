#!/usr/bin/env bash
set -euo pipefail

unimagic_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$unimagic_src"

regen_scratch="$(mktemp -d "${TMPDIR:-/tmp}/unimagic-annual-regen.XXXXXX")"
regen_complete=0
artifacts=("unimagic-corpus.json" "unimagic-corpus.json.gz" "macos/build/bridge.cjs")

for artifact in "${artifacts[@]}"; do
  if [[ -f "$artifact" ]]; then
    mkdir -p "$regen_scratch/$(dirname "$artifact")"
    cp "$artifact" "$regen_scratch/$artifact"
    touch "$regen_scratch/$artifact.existed"
  fi
done

restore_or_clean() {
  if [[ "$regen_complete" -eq 0 ]]; then
    for artifact in "${artifacts[@]}"; do
      if [[ -f "$regen_scratch/$artifact.existed" ]]; then
        mkdir -p "$(dirname "$artifact")"
        cp "$regen_scratch/$artifact" "$artifact"
      else
        rm -f "$unimagic_src/$artifact"
      fi
    done
    echo "Annual regeneration failed/interrupted; prior corpus and bundle restored." >&2
  fi
  rm -rf "$regen_scratch"
}
trap restore_or_clean EXIT

# Annual runs explicitly re-fetch immutable, pinned URLs. fetch.ts validates
# SHA-256 before atomically replacing any verified cache entry.
UNIMAGIC_REFRESH_SOURCES=1 pnpm run gen
pnpm test
pnpm run typecheck

# Attribution is a release gate, not a prose reminder.
seeds_root=seeds
[[ -d "$seeds_root" ]] || seeds_root=../seeds
test -f "$seeds_root/GLYPHFINDER-NOTICE.md"
test -f "$seeds_root/EMOTIF-NOTICE.md"
test -f licenses/MiniSearch-LICENSE.txt
grep -Fq "Unicode" THIRD_PARTY_NOTICES.md
grep -Fq "emojibase" THIRD_PARTY_NOTICES.md

# Build twice and require byte identity: the gzipped corpus is inlined, so this
# proves the production artifact is reproducible from the accepted inputs.
node esbuild.macos.mjs
cp macos/build/bridge.cjs "$regen_scratch/bridge.first-build.cjs"
node esbuild.macos.mjs
cmp "$regen_scratch/bridge.first-build.cjs" macos/build/bridge.cjs

pnpm exec tsx scripts/version-report.ts \
  "$regen_scratch/unimagic-corpus.json" \
  "$unimagic_src/unimagic-corpus.json"
echo "  bridge.cjs:  $(shasum -a 256 macos/build/bridge.cjs | awk '{print $1}')"
echo "Annual regeneration PASS — corpus, tests, typecheck, attribution, and reproducible build."
regen_complete=1
