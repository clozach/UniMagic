# Shared macOS releases

Both hosts compile `RK*.swift` directly into their executable. These are the same updater and maintainer Publish implementation; product hosts supply `ReleaseConfiguration`, bundle metadata and save/busy/quit hooks. Ordinary source and release builds hide Publish. An ordinary source build without its feed cannot replace itself. A canonical maintainer can carry a separate `<prefix>MaintainerUpdateFeed`; it is honored only when the existing Publish capability resolves and it exactly matches the product’s configured GitHub release endpoint. This keeps Publish available while making explicit update consent operational. Ordinary sources and released builds cannot gain that capability from a stray maintainer-feed key.

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
