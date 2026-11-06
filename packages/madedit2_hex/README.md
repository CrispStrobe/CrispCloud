# madedit2_hex

An embeddable native Flutter hex editor maintained in the CrispStrobe MadEdit2
fork. This is the reusable package, not the complete MadEdit2 desktop app.
It does not require Rust, Tree-sitter, a WebView or MadEdit2 application settings.
See UPSTREAM.md and LICENSE for source provenance and the MIT notice.

## Components

- `HexByteSource`: immutable, exact random-access bytes supplied by the host.
- `HexDocument`: byte-only persistent AVL rope, insert/overwrite/delete,
  undo/redo, revision-aware saved state and stable snapshots.
- `HexEditorController`: serialized editing, nibble input, selection,
  clipboard parsing and cancellable byte search.
- `HexEditor`: virtualized hex/text rows, keyboard navigation, toolbar,
  offset navigation, ASCII/Latin-1 display and an optional touch hex keypad.

Display encoding does not change byte-edit granularity. Neither opening the
model nor its first edit requires a text newline index.

## Embed

Create the controller once in the host State, not inside `build`:

```dart
final controller = HexEditorController(
  HexDocument(MemoryHexByteSource([0x48, 0x65, 0x6c, 0x6c, 0x6f])),
);
```

Place the surface in a bounded area, such as a Scaffold body or Expanded:

```dart
HexEditor(
  controller: controller,
  showKeypad: false,
  onSave: requestHostSave,
)
```

The host serializes save requests, awaits `controller.idle`, captures
`controller.document.snapshot`, and streams `snapshot.chunks()` to a verified
staged destination. Only after a successful commit should it call
`controller.markSaved(snapshot)`. Newer edits then remain dirty. A failed save
or exporting a separate copy must not mark the original clean.

The host must keep the source immutable and open for the lifetime of the
controller AND all outstanding reads/snapshots. Wait for queued commands,
search and saves before disposal. Never edit the original backing file in place
while snapshots still refer to it. CrispCloud owns its staging, conflict checks,
account identity, input size limits and unsaved-close confirmation.

## Limits and validation

Undo and redo share an edit-count cap (default 500) and a 64 MiB inserted-byte
budget (`maxUndoBytes`). Shared buffers count once, including the full buffer
when history retains only a slice. Original-source ranges use no byte budget.
Current content and caller-held snapshots can retain additional memory; this
is a history limit, not a limit on the whole process. Each inserted operation
is capped at 16 MiB. Rendering caches at most eight 64 KiB pages; search is
chunked and patterns are capped at 1 MiB.
Browser clipboard permissions and physical-device accessibility/IME behavior
must be validated by the embedding application. Large-file throughput and
save durability are also properties of the host backend, not just this widget.

From this directory:

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter test --platform=chrome --reporter expanded
```

The fork workflow runs the standalone package on Linux, Windows and macOS,
plus Chrome on Linux. A workflow being configured or queued is not evidence
of a passing run. The complete desktop application is outside this package's
CI scope. Pin a reviewed, tested commit when importing into another app.
