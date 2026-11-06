# Shared macOS releases

Both hosts compile `RK*.swift` directly into their executable. These are the same updater and maintainer Publish implementation; product hosts supply `ReleaseConfiguration`, bundle metadata and save/busy/quit hooks. Ordinary source and release builds hide Publish. An ordinary source build without its feed cannot replace itself. `MaintainerUpdatePolicy` determines whether a maintainer can install public releases: the default `allowPublicReleases` preserves UniMagic's guarded feed, while ClipEdge chooses `preserveBuild`. For that policy, the publisher-enabled build flag blocks checks, installs and old Go Back receipts, including with legacy feeds or a missing helper. Saved consent is retained; the Settings and menu explain rebuilding. For `allowPublicReleases`, a separate `<prefix>MaintainerUpdateFeed` is honored only when the Publish capability resolves and it matches the configured GitHub endpoint. Ordinary sources and releases cannot gain Publish from a stray maintainer-feed key.

`UpdateController.Environment.live(bundle:support:configuration:isBusy:saveBeforeQuit:quit:)` provides the macOS adapter. `choose(.automatic)` is the explicit opt-in, `choose(.manual)` opts out, `check()` checks without enabling automatic installation, and `observe(owner:_:)` supports multiple live surfaces. Existing `state.json` consent survives upgrades. `UpdateStatus.Snapshot` takes the product name. Signature, version, archive bounds, save-before-quit and rollback checks stay in the shared implementation.

`PublishController(environment: .live(bundle:configuration:))` drives a maintainer control through `presentation`, `observe(owner:_:)` and `performAction(presenting:)`. Only the product's configured helper suffix and maintainer metadata grant that capability; a release feed disables it. Review names the product/version and the exact frozen notes. Approval binds both archive and candidate receipt digests. Publication must pass a fresh public readback before the control hides.

## Download and archive safety

Downloads are streamed to a private file with a 100 MiB compressed ceiling; metadata responses have a 1 MiB ceiling. Announced lengths and every received chunk are checked before writing. HTTPS redirects cannot downgrade to HTTP.

Updater and maintainer candidate preparation use the same ZIP32 preflight before extraction: at most 20,000 regular-file/directory entries, 250 MiB per file and 750 MiB total expanded content. It rejects links/special files, path aliases, duplicate/colliding names, encryption, ZIP64, alternate-path metadata, inconsistent local/central headers and descriptors, overlaps and hidden payload ranges. Streaming raw-deflate validation checks actual expanded size and CRC with a fixed 64 KiB buffer, so lying size fields cannot evade the limits. Extraction disables resource-fork/xattr restoration. Signature and exact-version checks still follow extraction before installation.

Run the synthetic transfer/archive regression suite with `bash release-kit/tests/run-security.sh`.

## Immutable candidate engine

Run `bash release-kit/publisher/run.sh SOURCE_ROOT identity|status|prepare|publish [options]`. The source root supplies `release-product.json`; `publisher/ProductSpec.swift` defines its fields. Script hooks are relative file paths run as separate arguments, with no interpolated shell command. The export hook receives a new destination directory. Verification hooks run against that frozen export. The release hook writes the configured app/archive paths with `{version}` substituted. It receives `RELEASE_KIT_UPDATE_FEED` (plus the legacy ClipEdge variable).

`identityPrefixes` and `identityExact` select runtime/build inputs. `excludePrefixes` skips derived/private trees before examining symlinks. `sourceMappings` projects canonical relative fallback files/directories into portable export paths; an existing real export path takes precedence. Export and local fingerprints must match. Source mappings apply only to source roots carrying the product spec, never to a signed app's tree digest.

`prepare --running-fingerprint HEX64` freezes, verifies, builds, hashes and verifies the signed app/archive. `publish --running-fingerprint HEX64 --candidate ID --archive-sha256 HEX64 --receipt-sha256 HEX64 --approve` uploads those frozen bytes. The decoder in `RKPublishProtocol.swift` defines the native response protocol. `--progress-file` optionally names an already-created writable JSONL file.

Initial publication requires `allowInitialRelease: true`, a verified GitHub 404 for latest release, an existing main commit as the concurrency baseline and a certificate-signed first app. Later candidates must satisfy the preceding release's signing requirement. Source publication preserves contributor commits and refuses uncontained public changes. No operation overwrites an unrelated public tag or silently treats a network failure as equality.

## ClipEdge packaging

Canonical ClipEdge root files are compatibility stubs; its shell tools compile the shared kit. Its portable exporter writes the same shared files under their original root filenames and includes the standalone identity dependencies. The public export builds without the vault. Content identity overlays the effective shared bytes for canonical ClipEdge only, so it matches the portable frozen tree.

## Verification

`tests/SourceGraphTests.swift` checks the canonical/frozen source graph with synthetic files, exclusions and symlink refusals. The ClipEdge retained updater, file, self-update, installer, Publish and Settings suites exercise the shared implementation. No real history or personal store is required by these checks.

## Protecting an old Mac release

UniMagic's product config pins GitHub’s **Latest** label to `v1.0.3`. Older copies read that endpoint and can otherwise replace themselves with an application requiring a newer system. New UniMagic builds read the 12 most recent GitHub releases, select the largest stable three-part version with a complete, exact-name Apple Silicon archive, and verify the app signature, declared macOS floor and version before replacement. Publishing checks the protected tag, promotes the reviewed draft with `--latest=false`, then verifies the public artifact and both endpoints. Incomplete metadata, a changed protected tag, or a list without a matching stable archive stops that operation. Products without a protected tag retain the single-release behavior.

On macOS 26 or later, install the first new UniMagic build manually from the full Releases list. An existing v1.0.3 update checker cannot discover the new lane, even if automatic updates were enabled. Replacing the app bundle preserves its external library and consent. Mac builds with the new paired helper select the same stable release for phone payloads, still subject to that phone’s current consent, signing, artifact checks and device verification. A paired Mac staying on 1.0.3 continues to see its original feed.
