# Terminal continuation visual inspection

These PNGs come from the production Flutter widgets, rendered by the opt-in
`test/terminal_parity_visual_test.dart` fixture. Connections, SSH profiles, and
key mappings use synthetic data and local in-memory stores. No credentials,
external SSH hosts, or real commands are used. Terminal output is fixture text;
the words displayed inside a terminal are not validation results.

## Results

All four capture scenarios passed and every saved image was visually inspected.
The saved-profile manager had one concrete regression at 320 × 320: the new
Import action stacked above Cancel in the footer and left only a clipped line
for the list. Moving Import into the scrollable content restores list scrolling
and keeps Cancel visible. The normal application test run covering profiles,
OpenSSH import parsing/storage, and import widgets passed all 48 tests after
that repair.

| View | Logical size | Evidence and observation |
| --- | --- | --- |
| Four nested terminal panes | 1280 × 960 | [Desktop](nested-panes-desktop.png): four live synthetic sessions, with the active pane highlighted and nested dividers visible. The panel is intentionally 720 pixels high inside the test host. |
| Zoomed active pane | 1280 × 960 | [Zoom](nested-pane-zoom.png): the selected session fills the panel; its content is retained. |
| Compact terminal and restoration | 390 × 720, then 1280 × 960 | [Compact](nested-panes-narrow.png) shows only the active terminal, with horizontally scrollable controls. [Restored](nested-panes-restored.png) restores all four panes and is byte-identical to the initial desktop capture. |
| OpenSSH source form | 1000 × 960 | [Source](ssh-import-source-desktop.png): bounded multiline input, optional default username, and disabled Import until a preview is selected. The field is scrolled to the end of the pasted fixture. |
| OpenSSH preview | 1000 × 960 and 390 × 720 | [Desktop](ssh-import-desktop.png) and [narrow](ssh-import-narrow.png): selected alias, destination, jump host, explicit renamed profile, and identity-file hint are readable. Long endpoints wrap in the narrow view. |
| Unsupported route | 390 × 720 | [Blocked entry](ssh-import-blocked-narrow.png): ProxyCommand diagnostic wraps in the card; its checkbox is disabled, while selected supported entries remain importable. |
| Key bindings list | 1000 × 900 and 320 × 640 | [Desktop](key-bindings-desktop.png) and [narrow](key-bindings-narrow.png): chord, enable/delete controls, and actions remain accessible. The narrow summary ellipsizes; the text payload is never displayed in the list. |
| Key binding editor | 1000 × 900 and 320 × 640 | [Desktop](key-binding-editor-desktop.png) and [narrow](key-binding-editor-narrow.png): shortcut, text, enable switch, persistence/execution notices, and Save/Cancel fit. |
| Send-key editor | 320 × 640 | [Send key](key-binding-key-action-narrow.png): modifier chips wrap; long content scrolls and Save/Cancel stay visible. |
| Saved profiles regression | 320 × 320 | [Before](before-ssh-profiles-narrow.png) shows the crowded footer. [After](ssh-profiles-narrow.png) and [scrolled profile](ssh-profiles-scrolled-narrow.png) show restored scrolling with the same profile entry retained. |

No additional pane, importer, or key-binding editor overflow was observed in
these captures. This is a widget rendering check, not a complete native-device
acceptance pass. It does not verify OS keyboard routing, IME, clipboard, native
window behavior, or real SSH transport. The bundled Roboto fonts used by this
test host omit Unicode arrow glyphs in the existing terminal shortcut row, so
those glyphs appear as fallback boxes here; native system-font fallback is not
represented by this fixture.

## Reproduction

From the repository root, with the pinned Flutter SDK and locked dependencies:

```sh
flutter test --no-pub --reporter expanded \
  --dart-define=TERMINAL_PARITY_VISUALS=true \
  --dart-define=TERMINAL_PARITY_VISUAL_DIR=build/terminal-parity-visuals \
  test/terminal_parity_visual_test.dart
```

The fixture is skipped during ordinary test runs. It loads bundled fonts,
uses a pixel ratio of 1, waits for widget transitions to settle, and captures
the navigator through a `RepaintBoundary`. The JSON
[receipt](capture-receipt.json) records image dimensions, hashes, source hashes
at evidence save, and scope limitations. Captures remain representative of the
states shown; changes to their widgets should be followed by a fresh opt-in run.
