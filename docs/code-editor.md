# Code editor (F4)

CrispCloud's F4 editor is built on [Re-Editor](https://pub.dev/packages/re_editor)
0.10.0 with [re_highlight](https://pub.dev/packages/re_highlight) 0.0.3 for
syntax highlighting. Both packages are MIT licensed.

The previous implementation was a `TextField` with a hand-written tokenizer.
It offered no folding, no find/replace, no selection toolbar and no reliable
encoding/line-ending handling. The evaluation in
`crispcloud-editor-evaluation.zip` (2026-11-05) recommended Re-Editor as the
first native prototype, subject to the correctness tests now included in this
repository.

## Features

- Line numbers, current-line highlight, bracket folding and both-axis scrolling.
- Syntax highlighting for the languages already mapped by
  `lib/widgets/code_highlighting.dart` (the same mapping used by the read-only
  F3 viewer).
- Find and replace (`Ctrl/Cmd+F`, `Ctrl/Cmd+H` / `Cmd+Alt+F`), with literal,
  case-sensitive and regex modes.
- Undo/redo, multi-line selection, cut/copy/paste, and a selection toolbar.
- Go to line (`Ctrl/Cmd+G`).
- Word-wrap and highlighting toggles in the editor menu.
- The macOS app menu mirrors the editor commands (File/Edit/View/Go), like
  the Office and image editors, instead of limiting them to the editor's
  local overflow button.
- Status bar with cursor position, line count, language, line ending, encoding
  and save state. On narrow screens it drops optional document information
  first and collapses the save state to an icon, so it fits a phone without
  overflowing.

## Document model

`lib/services/editor_document.dart` decodes a file once and keeps:

- the text, normalized to LF for editing;
- the source encoding: UTF-8, UTF-8 with BOM, UTF-16 LE/BE, UTF-32 LE/BE, or
  Latin-1 (the fallback for bytes that are not valid UTF-8);
- the dominant line ending: LF, CRLF or CR;
- whether the source mixed line-ending styles.

Saving encodes the edited text back with the retained metadata. This means:

- a CRLF file stays CRLF;
- a Latin-1 file is not silently converted to UTF-8;
- a UTF-8 BOM or UTF-16/32 BOM is preserved;
- a file that already existed is not re-encoded just because it was opened.

Mixed line endings are normalized to the dominant style on load. The status
bar shows a warning when this happened. If the document is edited and saved,
the whole file is written with the dominant style. The goal is a defined,
predictable policy rather than byte-preserving mixed endings, which Re-Editor's
line model cannot represent.

If a Latin-1 document gains characters outside Latin-1 (for example an emoji),
saving fails with an actionable message instead of writing corrupted bytes.
The user can switch the encoding to UTF-8 from the snackbar action or the
status-bar encoding menu.

The line ending and encoding can be changed explicitly from the status bar.

## Save correctness

`lib/services/save_coordinator.dart` implements revision-aware saves:

- every text change increments a revision;
- a save snapshots the revision and text it is about to upload;
- the document becomes clean only when the current revision still matches the
  saved revision;
- saves are serialized, and a save requested during an upload is queued and
  writes the newest text.

This fixes the previous race where typing during an upload was marked as saved.
The conflict check is now centralized in `_saveFile`, so autosave, the toolbar
button, `Ctrl/Cmd+S` and the conflict banner all use the same path. The loaded
timestamp is advanced after every successful write.

## Regex replace

The find panel expands `$1`, `$2`, `${name}`, `$&` and `$$` in replacement
templates (`lib/services/search_replace.dart`). Re-Editor's own replace-all
passes templates through literally, so the panel implements the replacement
against the LF-normalized document. Because search and replace both use LF
internally, the previous CRLF find/replace mismatch does not apply.

## Tests

```bash
flutter test test/editor_document_test.dart
flutter test test/editor_save_coordinator_test.dart
flutter test test/editor_highlighting_test.dart
flutter test test/search_replace_test.dart
flutter test test/code_editor_widget_test.dart
flutter test test/code_editor_status_bar_test.dart
```

The document tests cover every supported encoding, BOM handling, CRLF/CR/LF
round-trips, mixed-ending normalization and the Latin-1 failure path. The save
coordinator tests pause an upload with a `Completer`, edit during the upload,
and assert that the buffer remains dirty. Widget tests mount the real
`CodeEditor`, open the find panel and check the responsive status bar at phone
and desktop widths.

## Validation status

The suites above were executed on macOS arm64 with Flutter 3.47.8 (Dart
3.13.7), the version pinned by `.fvmrc`. The evaluation's re_editor 0.10.0
suite also ran in an isolated scratch package: 30 core/characterization cases
passed. Its CRLF desired-invariant still fails as predicted, which is why this
editor keeps LF internally and performs replacement through its own panel.

A debug macOS app build (`flutter build macos --debug`) also completed and the
resulting `CrispCloud.app` launched to the browser UI. This validates
compilation, controller behavior, find/replace, highlighting and widget
rendering on a real Flutter host. It is not a physical-device or App Store
pass; touch selection, IME composition and mobile rendering still need that
pass.

## Known limitations and follow-up work

- Rendering, scrolling, touch selection and IME composition have only been
  exercised in Flutter widget tests, not on physical iOS/Android devices.
  A device pass is still required before App Store submission.
- Folding uses Re-Editor's brace/bracket analyzer. Python and other
  indentation-based languages do not get semantic folds.
- Re-Editor replaces the line model on replace-all, so folded sections expand
  after a replace-all. This matches the package's documented behavior.
- Syntax highlighting is disabled above 2 MiB (`kEditorHighlightMaxChars`) to
  keep typing responsive. The file remains editable.
- Large-document performance on target hardware has not been benchmarked
  against the previous editor.
- Conflict detection remains a timestamp comparison because the cloud upload
  interface has no expected revision/ETag precondition. It is centralized and
  no longer bypassed by any save path, but the check-then-upload sequence is
  not atomic on a server that changes between those two requests.
- CodeMirror remains a possible embedded alternative, but it still needs a
  real WebView integration, keyboard and accessibility validation.
