# Native corpus engine

Run from `projects/unimagic/src`. Generate SQLite from the canonical corpus, add the reviewed compact browse projection, then run the pure checks:

```bash
node --no-warnings scripts/ios-corpus.mjs /tmp/unimagic-build/corpus.sqlite
node --no-warnings ios/Engine/Tests/inventory.mjs /tmp/unimagic-build/corpus.sqlite
node --no-warnings ios/prepare-inventory.mjs /tmp/unimagic-build/corpus.sqlite
swiftc ios/Engine/*.swift ios/Engine/Tests/main.swift ios/Engine/Tests/BrowseEngineTests.swift -o /tmp/unimagic-build/engine-tests -lsqlite3
/tmp/unimagic-build/engine-tests /tmp/unimagic-build/corpus.sqlite ios/Resources/BrowseInventory.json unimagic-corpus.json
```

The generators import the shared tokenizer, field definitions, weights, score constants, sets and skin variants. App and keyboard bundle the generated database and original system-symbol mapping `CategoryArtwork.json`; the source catalogue is `Resources/BrowseInventory.json`. Fresh installs start with empty history. The copied font and personal screenshot seed are not shipped. The normal build scripts regenerate resources and mirror source-owned staging directories, removing obsolete source files without discarding signing/cache siblings.

## Catalogue and paging

The schema-2 catalogue has **354 destinations**: 36 fixed collections, 316 Unicode-block destinations and two utilities (Recents and Frequently used). Settings retain every destination; browsing uses the enabled projection. Emoji is the first fixed category with exact default 🐻‍❄️. Other fixed categories use immutable lowest-member numeric scalar-sequence order; utilities sit outside that order. Same-title or overlapping collections retain distinct stable IDs and source labels. Exemplar overrides never reorder membership.

All **39,626 canonical rows remain unchanged**. The native projection adds 68 absent exact strings, making 39,694 searchable records. All 6,825 observed UniChar sample occurrences retain source order, duplicates, variation selectors and multi-scalar strings; representative samples and complete membership are separate. Complete traversal covers 86,009 occurrences across 352 ordinary destinations. Unresolved source metadata is explicit, not guessed corpus content. See [catalogue contract](../../../research/browse-catalogue.md) and [native browse API](../../../native-browse-engine.md).

`GlyphSearch(databaseURL:) throws` opens a read-only database. It is deliberately not Sendable: a serial worker owns SQLite and decoding. Search and legacy browsing default to 100 and cap at 500. The native UI consumes occurrence-aware pages/cursors through `PickerModel`, including preceding windows and keyset history pages. Each page window holds up to 300 occurrences. The cache keeps visible categories, the active and most recently loaded windows, three additional warm windows, and up to 512 glyphs. A jump to an unseen history page starts from the first page’s saved cursor, so newer picks cannot shift an active browsing session. Late set/block pages use indexed order rather than sorting large payload prefixes. Unsupported native glyphs display codepoints while keeping exact copying/insertion strings.

`BrowseCategory` identifies a destination; `BrowseOccurrence` identifies an ordered source occurrence or history event. A `PickerGlyphItem` carries either a search record or an exact browse occurrence. New UI uses category IDs and occurrence IDs, preserving duplicate names and repeated characters. Context targets retain the selected exact glyph, category, source occurrence and absolute position; hidden destinations can be previewed without changing visibility. Back restores the prior query or browse anchor.

## Native interfaces

The app reserves the full height of each category when browsing begins. A flick can travel directly to a distant page while the table reuses native glyph buttons and fills the visible rows. The category headings stay pinned and the chooser floats at the bottom. The chooser reverses presentation order for thumb reach, has glyphs in a reserved left column, and filters enabled category names/source labels. The old side index and More component are removed. See [app browser behavior and evidence](../../../native-app-browse.md).

The keyboard has a compact Browse/Search rail and a horizontal section browser. It lays out the visible strip and fetches the page at the current position as a flick crosses columns. Both hosts consume the same category definitions and enabled projection. App-published visibility can be read by the keyboard through the approved group provider; history and custom symbols remain in their separate local sandboxes. Shared writes/Full Access are deferred roadmap work. Details/settings retain the exemplar’s rendering identity: legacy PUA defaults map to OS symbols, while user-assigned Unicode/emoji symbols use native rendering with a display-only coverage fallback. Tap picks, long press opens details, and VoiceOver exposes a Details action.

See [keyboard restoration](../../../keyboard-restoration.md), [native browse API](../../../native-browse-engine.md) and [storage contract](../../../personalization-storage.md) for current interfaces and their own verification limits. Do not infer physical-phone acceptance from an SDK build or simulator capture.

## History, learning and search

`LearningStore` remains a Codable value for aliases, provisional votes and usage; it is separate from full pick history. Native personalization uses indexed SQLite. Each successful glyph copy/insertion records its actual string and a stable event ID, retaining repeated picks. Metadata-only copies do not become glyph picks; Undo learning does not erase history. Historical aggregates have explicit aggregate provenance/counts and unknown dates, not invented repeated events. Existing imported history keeps its original timestamps/provenance; production startup no longer imports a screenshot seed. Recents keeps its snapshot while paging/picking and refreshes on return or explicit selection. [Storage API and checks](../../../personalization-storage.md) describe preservation, migration and provider selection.

Native search uses FTS5 prefix AND with diacritic folding disabled, canonical pretokenized fields and BM25 field boosts. It does not implement MiniSearch fuzzy recall or claim exact cross-host ranking parity. Canonical curation influences the 500-result candidate window; exact/learned signals and bounded canonical completions add candidates. Codepoints, pasted glyphs, names, shortcodes and aliases retain their documented weights; presentation-selector-only differences resolve through canonical identity. Generated metadata exports the shared SCORE values. Search runs off the main actor and updates as the query changes.

Details retain entities, twins, related IDs, block/script/age, annotations and presentation metadata. Sibling IDs resolve on demand through `glyph(id:)`; the UI does not keep a second full corpus map. Skin variants use the shared TypeScript helper; history records the resulting inserted string. A tapped tone learns under its own id (`1F9D8 1F3FB 200D 2640`); `glyph(id:)` rebuilds such ids from their base, mirroring `recordFor` in core/glyphs.ts.

## Verification

Engine, projection, model and persistence commands/results live in the linked owner notes. Native UI verification uses the separate `ios/UITests/project.yml` runner, with no application test hooks. Build/install with `ios/build.sh simulator`; copy the test sources outside the vault, run `xcodegen generate`, then:

```bash
xcodebuild -project UnimagicUI.xcodeproj -scheme UnimagicUITests \
  -destination 'platform=iOS Simulator,id=<owned-device-id>' \
  -collect-test-diagnostics never test
```

The default app bundle is `com.clozach.unimagic`; runner environment `UNIMAGIC_TEST_APP_BUNDLE=com.clozach.amaanah.alerts` selects PowWorm and its `--show-unimagic` route. Keep one owner per simulator. Set appearance through `simctl ui <device-id> appearance light|dark` and inspect actual pixels; a requested style alone is insufficient. UI checks cover continuous paging, exact context/Back, stable chooser geometry, history refresh, font kinds, exact copies/insertion, settings and own-keyboard app geometry. Source and simulator proof do not replace the managed release's physical-device and saved-data checks.

## Standalone Settings and paired-Mac delivery

UniMagic 1.0.0 has its own application and keyboard identifiers. Settings retain category visibility and symbol controls, add the default-off “Install updates through my paired Mac” switch, a manual check request and visible status, and reserve a bottom corner for the actual bundle version/build. The keyboard never reads the update policy. App/keyboard learning, histories and exemplar overrides remain local; only visibility is published through the configured App Group, with Full Access off.

`ios/build.sh simulator` builds without account access. `ios/build.sh unsigned-device` produces an unsigned device app. `node ios/package-payload.mjs /tmp/unimagic-public-ios` prepares a profile-free, seed-free ZIP and digest manifest for sealing inside the signed Mac release. A digest alone is not authenticity: the paired Mac verifies the outer release against the independently trusted installed Mac app’s designated signing requirement before accepting the archive.

Private delivery/operator primitives live in the vault’s `iphone-agent-alerts/src/keeper/product-cli.mjs`, separately from the public iOS source. The explicit product config selects bundle, extension set, signing certificate, App Group, private state and the global signing/install lock. `provision-profiles` uses the existing Xcode account’s official CLI; no new enrollment is attempted. `sign` uses matching cached profiles. `install --bootstrap` requires an absent app; automatic upgrades require fresh phone consent under the same lock and immediately before installation. `renew` re-signs only the registered frozen release, separately from feature updates. Automatic invocation belongs to the vault scheduler.

Migration commands export both PowWorm-owned native stores without merging them, require stopped source/destination processes, verify stable source hashes and SQLite integrity, retain destination snapshots, and compare expected bytes before writing. Newer/unapproved destination data stops the import. Byte-identical retries are idempotent. Keep migration exports private; they contain personal learning/history. These commands do not remove the embedded picker or keyboard. Retirement requires the parent run’s verified physical standalone acceptance.
