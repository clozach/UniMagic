src := justfile_directory()

default:
    just --list

# Regenerate pinned Unicode data and the complete inherited vocabulary.
gen:
    pnpm run gen

test:
    pnpm test
    pnpm run typecheck

# The native Mac build bundles the pinned Node runtime and optional command.
build:
    pnpm run build:tinycast
    node macos/build.mjs

ios-build:
    bash ios/build.sh simulator

ios-payload out:
    node ios/package-payload.mjs "{{out}}"

# Local inspection only. Nothing is installed or published by a build.
open: build
    open "{{src}}/macos/build/UniMagic.app"

tinycast-build:
    pnpm run build:tinycast

# Refetch pinned inputs, verify coverage, and prove the bridge is reproducible.
annual-regen:
    bash scripts/annual-regen.sh

export out:
    bash tools/export-source.sh "{{out}}"

release:
    bash tools/release.sh

# Maintainer workflow; prepare freezes/tests a candidate before any publication.
publish-status:
    bash tools/publisher.sh status

publish-prepare:
    bash tools/publisher.sh prepare
