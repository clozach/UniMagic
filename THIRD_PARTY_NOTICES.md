# Third-party material

UniMagic’s controller, extension command and release-system code use the MIT license in LICENSE. Third-party material retains its own notices and terms. This file does not relicense that material.

- Unicode Character Database, CLDR and security data: Copyright © 1991–2026 Unicode, Inc., Unicode License v3. The full notice is bundled in `ios/Resources/Notices.txt`. Source: https://www.unicode.org/license.txt
- emojibase data: Copyright © 2017–2019 Miles Johnson, MIT. The full MIT notice is in `ios/Resources/Notices.txt` and the installed package's LICENSE.
- MiniSearch: Copyright © Luca Ongaro and contributors, MIT. Its package LICENSE is copied into release notices.
- The dedicated Tinycast PickerHost executable, its source patches and dedicated entry point use AGPL-3.0-or-later. Tinycast copyright © 2026 Abue Ammar. The outer application runs it as a separate process. The exact upstream revision is in `macos/picker-host/TINYCAST_REVISION` in this release, available at https://github.com/clozach/tinycast. The same release includes the adaptations under `macos/picker-host/` and the build instructions in `macos/build-picker-host.mjs`. The installed helper contains its upstream license, notices and corresponding-source locations in its Resources folder.
- React and the build-time libraries retain their package licenses; lockfiles pin the source build. Tinycast's API adapter uses the host's Raycast-compatible API, not a bundled Raycast application.
- Node.js: the Mac app bundles the same Node runtime used to build it. Its complete exact distribution LICENSE, including third-party notices, ships as `Contents/Resources/Node-LICENSE.txt`.
- Glyphfinder-derived tags, sets and entity lookup retain `seeds/GLYPHFINDER-NOTICE.md`. The upstream discontinued project's README invites forks: https://github.com/ueberdosis/glyphfinder . The full original custom license is retained with the data; those files are not represented as newly MIT-licensed by UniMagic.
- Emotif's built-in names/keywords are retained in `seeds/emotif-builtins.json`; original application work © Chris Lozac'h, with EmojiOne-era keyword provenance. No EmojiOne artwork is bundled. See `seeds/EMOTIF-NOTICE.md` for the source data attribution.
- Category icons are rendered using the operating system's SF Symbols and Unicode fonts. The copied UniChar icon-font binary is excluded. `reference/unichar-inventory.json` records observed category/glyph membership; it does not include the font or grant ownership over Unicode characters.

Releases include the full applicable license texts. Third-party source provenance is retained alongside the build inputs; personal history, private signing profiles and the former screenshot Recents seed are not release inputs.
