# UniMagic

A Unicode picker that learns your words. Find a character, browse a category, teach an alias, then paste the exact Unicode string. It works offline.

On Mac, the standalone menu-bar app and the optional Tinycast command run the same picker. Both use Tinycast’s palette renderer, with the same grouped grid, category dropdown, glyph actions, details and learned words. The standalone app includes its own single-command host. You can use it on a Mac without Tinycast installed.

Press **Control–Command–Space** to open the picker. Press it again immediately to dismiss. Navigate to an emoji with skin tones and the same shortcut opens its tone choices. Arrow keys move the selection while the search field is empty. Scroll past the last visible row to load more automatically. **Return** inserts the selection, **Command–Return** inserts and keeps the picker open, and **Command–K** opens its actions.

On iPhone, drag to browse a few rows or flick to coast through long categories. Hold a glyph for details, then go back to its place in the browser.

## Install

Download the Apple Silicon Mac app from [Releases](https://github.com/clozach/UniMagic/releases). Current direct downloads are development-certificate signed, not Developer ID notarized; macOS may require an explicit security allowance. No App Store/TestFlight distribution is offered yet. The iPhone build uses your own Apple development signing and a paired Mac; an app cannot install its own iOS updates.

**Version 1.0.4 and later require macOS 26+.** If you already use 1.0.3 on a compatible Mac, download the new app once from Releases. Its opt-in updater follows subsequent compatible releases. Macs running macOS 14–15 stay on [1.0.3](https://github.com/clozach/UniMagic/releases/tag/v1.0.3). GitHub’s Latest badge stays on that legacy release because its updater cannot check operating-system requirements. The newer public releases appear in the release list.

To use the integrated picker, open UniMagic’s menu-bar **Settings**, choose **Categories & controls → Install optional Tinycast command**, then import the revealed folder from **Tinycast Settings → Extensions**. In Tinycast, search for **Unimagic**. For direct invocation, assign Control–Command–Space to that command in Tinycast. Use **Open UniMagic** in the app’s menu to try its standalone window alongside the integrated picker.

Settings contains category visibility, a small installed version/build, and explicit update consent. Automatic feature updates start off. On iPhone the switch says **Install updates through my paired Mac**. Turning it off preserves that release; re-signing the same frozen release is separate maintenance and still depends on available Apple signing access. Updates never use keyboard Full Access.

## Build from source

The shared Mac picker uses the macOS 26 SDK and runs on macOS 26 or later. Building it requires Xcode, XcodeGen, Git, Node **22.21.1** and pnpm. The build fetches a pinned public Tinycast revision for the dedicated picker host. The Mac build bundles that pinned runtime and its full license; installed users do not need Node. Set `UNIMAGIC_NODE` to that executable if your shell uses another Node version.

```bash
pnpm install --frozen-lockfile
pnpm gen
pnpm test
pnpm typecheck
node macos/build.mjs
```

The app is written to `macos/build/UniMagic.app`. A source build has no automatic-update feed and does not publish anything. The canonical maintainer build exposes Publish; another trusted checkout can request it with UNIMAGIC_MAINTAINER=1. Public release builds strip this machine-local capability. The release pipeline freezes the source, runs checks, builds one signed candidate, reviews version/notes, verifies its artifacts, then publishes that same candidate. `release-product.json` configures the shared engine. Default release build numbers advance with the semantic version; the Mac and embedded phone payload must match.

The iOS project and CLI recipes live in `ios/`. Build an unsigned portable payload with `node ios/package-payload.mjs OUTPUT_DIRECTORY`. Use your own signing team, certificate and device configuration for installation; provisioning profiles and device identifiers are not public source inputs. The paired-Mac CLI lives in `tools/paired-mac/keeper/product-cli.mjs`.

## Data and recovery

The Mac app and optional Tinycast command share a local UniMagic library. Migration preserves both learning/usage and the separate full-history/category-preferences store from the retired Obsidian host. Native iPhone app and keyboard histories, learning and symbol overrides remain separate. There is no automatic Mac–phone vocabulary sync.

Paired-Mac installation takes preservation snapshots and verifies installed identity and saved data. Migration must be verified before an old app is retired. Keep recovery snapshots private; they are not test fixtures or public release artifacts.

## Licenses

UniMagic’s own picker command, controller, and release tools use the [MIT license](LICENSE). The bundled PickerHost process and its modifications use [AGPL-3.0-or-later](macos/picker-host/LICENSE). Its exact [Tinycast revision](macos/picker-host/TINYCAST_REVISION), [source modifications](macos/picker-host) and [build script](macos/build-picker-host.mjs) are public. Unicode data, inherited curation and bundled dependencies retain their [third-party notices](THIRD_PARTY_NOTICES.md). The optional copied Tinycast folder carries its own complete notices and licenses too. Categories, keywords and character coverage are preserved; the copied UniChar category-icon font is replaced with system artwork.
