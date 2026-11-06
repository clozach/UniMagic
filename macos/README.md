# UniMagic on macOS

UniMagic and the optional Tinycast command run the same bundled extension with the same native Tinycast renderer. Open UniMagic.app directly, choose Open UniMagic from its menu, or run the command from Tinycast. The standalone app includes its own single-command renderer and works without Tinycast installed. The renderer uses macOS 26.

The command uses ⌃⌘Space. Press again immediately to close. After navigating to an emoji with skin tones, press the same chord for its variants. Type to search, use the arrows to navigate, and scroll to continue through results. Return inserts the glyph, ⌘Return inserts and keeps the picker open, and ⌘K opens its actions. Use the menu bar item or `unimagic://settings` for category visibility, automatic-update consent and the version. The updates tab includes the Publish controls on a maintainer build.

With the UniMagic command shortcut assigned in a running Tinycast, Tinycast owns the global chord. UniMagic can still open independently from its menu. The launcher forwards the chord to the standalone picker when that picker has focus. Both hosts share the Mac library in `~/Library/Application Support/UniMagic/Library`. A Tinycast command configured with an explicit custom file retains that override. Accessibility permission for UniMagic allows the standalone app to insert into the preceding application. The controller copies the glyph if permission is unavailable.

## Build

Use macOS 26+, Xcode 26+ command-line tools, XcodeGen, pnpm, and the Node 22.21.1 distribution (including its license). From the source root:

```sh
pnpm install --frozen-lockfile
node macos/build.mjs
```

The app is written to `macos/build/UniMagic.app`. The original UniMagic sources are MIT. The standalone renderer in `Contents/Helpers/PickerHost.app` is a separate AGPL-3.0-or-later process. The build fetches the exact public Tinycast commit named in `macos/picker-host/TINYCAST_REVISION`, applies the single-command patch and compiles one target. The build excludes the Tinycast app entry point, dictation/indexing helpers and launcher startup services. Its license, upstream commit, build scripts, and exact helper adaptations travel inside the signed helper’s Resources/CorrespondingSource directory.

`UNIMAGIC_TINYCAST_SOURCE` can point to an existing Git repository containing the pinned commit. Only the committed tree is read. `UNIMAGIC_BUILD_DIR`, `UNIMAGIC_NODE`, `BUILD_VERSION`, `BUILD_NUMBER` and `SIGN_IDENTITY` configure output and signing. The built app includes the JS engine and the extension, so users can run it offline.
