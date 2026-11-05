# UniMagic

A Unicode picker that learns your words. Find a character, browse a category, teach an alias, then paste the exact Unicode string. It works offline.

UniMagic includes a native Mac menu-bar app, an optional Tinycast command using the same Mac library, and a standalone iPhone app with a searchable keyboard. The Mac app opens with **Control–Command–Space**; Return pastes, Command–Return reverses Keep open for one pick, and Shift–Command–C copies. Glyph details expose encodings, variants, related characters and learned words.

## Install

Download the Apple Silicon Mac app from [Releases](https://github.com/clozach/UniMagic/releases). Current direct downloads are development-certificate signed, not Developer ID notarized; macOS may require an explicit security allowance. No App Store/TestFlight distribution is offered yet. The iPhone build uses your own Apple development signing and a paired Mac; an app cannot install its own iOS updates.

Settings contains category visibility, a small installed version/build, and explicit update consent. Automatic feature updates start off. On iPhone the switch says **Install updates through my paired Mac**. Turning it off preserves that release; re-signing the same frozen release is separate maintenance and still depends on available Apple signing access. Updates never use keyboard Full Access.

## Build from source

Requirements: macOS, Xcode command-line tools, Node **22.21.1**, pnpm, and XcodeGen for iOS. The Mac build bundles that pinned runtime and its full license; installed users do not need Node. Set `UNIMAGIC_NODE` to that executable if your shell uses another Node version.

```bash
pnpm install --frozen-lockfile
pnpm gen
pnpm test
pnpm typecheck
pnpm run build:tinycast
node macos/build.mjs
```

The app is written to `macos/build/UniMagic.app`. A source build has no automatic-update feed and does not publish anything. The canonical maintainer build exposes Publish; another trusted checkout can request it with UNIMAGIC_MAINTAINER=1. Public release builds strip this machine-local capability. The release pipeline freezes the source, runs checks, builds one signed candidate, reviews version/notes, verifies its artifacts, then publishes that same candidate. `release-product.json` configures the shared engine. Default release build numbers advance with the semantic version; the Mac and embedded phone payload must match.

The iOS project and CLI recipes live in `ios/`. Build an unsigned portable payload with `node ios/package-payload.mjs OUTPUT_DIRECTORY`. Use your own signing team, certificate and device configuration for installation; provisioning profiles and device identifiers are not public source inputs. The paired-Mac CLI lives in `tools/paired-mac/keeper/product-cli.mjs`.

## Data and recovery

The Mac app and optional Tinycast command share a local UniMagic library. Migration preserves both learning/usage and the separate full-history/category-preferences store from the retired Obsidian host. Native iPhone app and keyboard histories, learning and symbol overrides remain separate. There is no automatic Mac–phone vocabulary sync.

Paired-Mac installation takes preservation snapshots and verifies installed identity and saved data. Migration must be verified before an old app is retired. Keep recovery snapshots private; they are not test fixtures or public release artifacts.

## Licenses

Original code is [MIT](LICENSE). Unicode data, inherited curation and bundled dependencies retain their [third-party notices](THIRD_PARTY_NOTICES.md). Categories, keywords and character coverage are preserved; the copied UniChar category-icon font is replaced with system artwork.
