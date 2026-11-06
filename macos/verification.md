# Verify the Mac picker

Run from the source root after building the app:

```sh
node macos/verify-bridge.mjs
node macos/verify-native.mjs
node macos/verify-picker.mjs macos/build/UniMagic.app /tmp/unimagic-picker-proof
```

The last command starts the actual bundled PickerHost process using a temporary synthetic home and its own non-key palette. It sends window-local events, reads the focused AppKit field editor and the Tinycast render tree, captures the light and dark windows, and closes the helper by closing its input pipe. It does not post system keyboard events or paste into other apps. The fixtures use a disposable library and disable the global shortcut. The bridge and settings fixtures cover persisted category changes, external category changes, serialized keeper checks and the phone renewal cadence.

Use these gestures in either host to check the visible result:

- Invoke the picker twice without another interaction. The second press dismisses it.
- Search for `arrow`. Scroll past the end of the first batch and continue through the results.
- With the caret at the end of the search text, press ⌘A and type `x`. Only `x` should remain.
- Clear the focused search field and press Right. The selection should move one tile.
- Navigate to 👋, press ⌃⌘Space and choose a tone. Escape returns to that search.
- Open Settings from the menu or `unimagic://settings`. Change a category, check update consent and read the version in the lower corner.
- With Tinycast owning its configured chord, use its shortcut to open the integrated command. Open the standalone app directly, navigate in its palette and repeat the chord there.
- To check delivery manually, invoke UniMagic over a disposable editor, insert a glyph and try ⌘Return to keep the picker open. Without Accessibility permission UniMagic copies the glyph and explains how to allow insertion.

The standalone helper has a separate bundle identity. It sends normal and keep-open text insertions back to the signed UniMagic controller. The controller validates the captured target process and current pasteboard contents before posting a PID-specific ⌘V. The isolated fixture does not validate macOS permission on a particular user's live machine.

## November 5 verification

The independent standalone fixture passed in light and dark appearances against public Tinycast commit `250280455c682c310b45459cde42e87ffc5f2323`. Actual appearance readbacks were `NSAppearanceNameAqua` and `NSAppearanceNameDarkAqua`.

Verified through the real bundled extension and native panel:

- The untouched second shortcut invocation hides the picker.
- Scrolling the native viewport to the loaded edge increases the item count beyond 200.
- ⌘A changes the focused field’s selection from a caret at 5 to range 0…5. Typing x replaces arrow.
- With the empty field still focused, Right moves the selected grid cell.
- The selected U+1F44B opens six skin tones through the original command action.
- Escape returns to the exact query and selected glyph.
- The Settings model persists category visibility and sees an externally updated category file.
- Both paste modes use the fixture-only pasteboard without changing the system pasteboard.
- The assembled bundle passes deep, strict code-signature verification and its helper links only system libraries. The minimum system is 26.0 and the URL scheme is unimagic.

The window-local tests avoid sending system keyboard events and avoid activating any of the user’s applications. Therefore they do not establish a particular live Accessibility grant or physical paste into another app. The parent release verification owns signed installation and coexistence with the live launcher.

The forced-dark bitmap fixture reports DarkAqua but SwiftUI’s primary footer label can retain the system color scheme when the view is captured without activation. Treat that bitmap’s footer contrast as a capture limitation until compared with the displayed window.

Cohesion review found the source files under 200 lines. The controller owns app entry points, the picker process owns the helper lifetime/pipe, the shortcut owns global registration and launcher handoff, and the paste service owns target validation. These are separate runtime concerns. The retired standalone grid/detail models and views are removed.
