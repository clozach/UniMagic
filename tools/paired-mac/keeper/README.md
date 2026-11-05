# Paired-Mac delivery and frozen signing renewal

The existing `keeper.mjs` remains PowWorm’s renewal entry point. Its frozen-release policy, extension set and paused notification behavior are preserved. The paired device identifier now comes from private `native-device.json` (`{"identifier":"…"}`) under the keeper state root, or an explicit `UNIMAGIC_DEVICE_ID` environment value; it is not embedded in source. A missing legacy configuration stops with an error.

`product-cli.mjs` is the standalone, explicitly configured delivery entry point. `products.mjs` supplies UniMagic’s identities; `--config /private/product.json` supplies another operator’s own team, certificate, App Group, extension set, private state and shared lock. New users need matching Apple profiles for their device. There is no paid enrollment or credential collection. All source/profile bootstrap, renewal and installation actions use the shared maintenance lock.

```bash
node product-cli.mjs provision-profiles
node product-cli.mjs sign --app /private/Unimagic.app
node product-cli.mjs install --app /private/signed/Unimagic.app --bootstrap
node product-cli.mjs check-updates --trusted-app /Applications/UniMagic.app
node product-cli.mjs renew
node product-cli.mjs status
```

`provision-profiles` uses `xcodebuild -allowProvisioningUpdates` with the existing Xcode account to request profiles for the app, keyboard and Controls extension. It does not install or launch anything. `sign` uses exact valid cached profiles; an unavailable account/profile is an explicit bootstrap limitation. `--bootstrap` requires an absent destination; subsequent explicitly authorized operator upgrades use `--operator`. Signing renewal only re-signs the registered frozen release; it does not discover a new version or use feature-update consent. Near expiry it requests fresh profiles, retaining the originals if authentication fails. The portable Mac app may check frozen signing every six hours, independently of feature-update consent. Al’s additional vault `renew-unimagic` task checks every fifteen minutes, including while the Mac app is closed. Both call the same idempotent `renew` path and share the installation/build lock; neither discovers a feature release or sends phone alerts. The existing `renew-powworm` task remains separate.

`check-updates` reads the iPhone’s current `paired-mac-updates-v1.json` under the install lock. Missing, malformed, inaccessible or off policy means no network release lookup, except a fresh manual check request permits discovery. The default-off “Install updates through my paired Mac” switch is app-owned. A manual check does not authorize installation while off. This check uses `clozach/UniMagic`’s stable `v<version>` release and the single `UniMagic-<version>-macOS-arm64.zip` asset. It verifies the downloaded Mac app against the independently installed app’s certificate-backed designated requirement and bundle identity. The signed Mac app seals `Contents/Resources/iOS/{manifest.json,UniMagic-iOS.unsigned.zip}`. The manifest pins product/version/build and archive digest. Target identities, profile team, signed entitlements, certificate, extension set, matching corpus, Full Access off and data preservation are checked before/after installation. Current consent is re-read immediately before installation; a changed revision defers it. Results return to `paired-mac-update-status-v1.json` for in-app status. A digest or a GitHub URL alone is not accepted as authenticity.

Device build/signing material and migration exports stay private. Public iOS payloads contain no provisioning profiles, copied icon font or personal screenshot-history seed. The public Mac archive must avoid resource-fork `__MACOSX` entries (`ditto --norsrc`) and contain a single `UniMagic.app` root.

## Separate app and keyboard migration

Run these only while the source/destination app and keyboards are stopped. No process is terminated by these tools.

```bash
node product-cli.mjs migration-export --out /private/new-source-export
node product-cli.mjs migration-verify --snapshot /private/new-source-export
node product-cli.mjs migration-inspect --destination --out /private/new-destination-baseline
node product-cli.mjs migration-import --snapshot /private/new-source-export --out /private/new-import-receipt
# If the standalone app has already created initial stores, explicitly approve
# that observed baseline; any later changes still refuse the import:
node product-cli.mjs migration-import --snapshot /private/new-source-export --out /private/new-import-receipt --expected /private/new-destination-baseline/manifest.json
```

The exporter performs two stable reads, verifies SQLite integrity/version, and keeps app/keyboard learning, preferences and histories separate. No histories are merged. SQLite sidecars stop transfer until a clean checkpoint/close. The importer snapshots the destination, accepts only absent/identical files or an explicit exact baseline, rechecks each host before writing, skips identical retry files and verifies every transferred byte. Existing or newer unapproved data stops the operation. Originals, destination snapshots and receipts remain private. These primitives do not retire PowWorm’s embedded picker or keyboard; that follows verified standalone migration and physical acceptance in the parent delivery run.

Tests: `node --test *.test.mjs`. Fixture tests cover default-off and malformed consent, fresh-read revocation, manual discovery without install authority, signature/archive boundaries, bootstrap readback, distinct app/keyboard stores, byte preservation, idempotence and refusal to overwrite newer data. Tests and Simulator captures do not certify physical-phone delivery.
