Office editor and viewer acceptance — 2026-11-16

Save As and Save a copy are separate actions. F12 and Ctrl/Cmd+Shift+S invoke Save As. A completed desktop Save As verifies and adopts the new file, changes the editor title, and directs subsequent Save operations to that file. Cancellation or failure retains the previous target and dirty state. Edits made during the picker remain dirty. Save a copy exports without changing the active file. Both device pickers start in the captured local source folder; after Save As, that means the newly adopted folder. Remote provider paths are never passed to a device picker as filesystem directories.

The native File menu and editor File menu expose both actions. Save As preserves the current format; incompatible extensions are rejected before writing. Legacy XLS/ODS imports can Save As XLSX and subsequently save directly to the adopted workbook. Browser downloads remain copy exports because they do not establish a writable file target.

Added or checked shortcuts:
- Save: Ctrl/Cmd+S; Save As: F12, Ctrl/Cmd+Shift+S.
- Hyperlink: Ctrl/Cmd+K; font dialog: Ctrl/Cmd+D.
- Undo: Ctrl/Cmd+Z; redo: Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z.
- Alignment: Ctrl/Cmd+L/E/R/J; page break: Ctrl/Cmd+Enter.
- Find/replace: Ctrl/Cmd+F/H and Ctrl/Cmd+Shift+F; F3/Shift+F3.
- Print: Ctrl/Cmd+P; close: Ctrl/Cmd+W or Escape after nested tools close.
- Existing selection, clipboard, formatting and F7 proofing bindings remain available.

Bare Ctrl+Shift direction changes run on release. Chords with a further key, including Save As and redo, do not change paragraph direction or clear redo history.

Office modal fields acquire focus (the hyperlink address is selected); Word, Sheet and Slide IME bridges reject late input/actions/macOS selectors while another control or route owns focus. Controller replacement retires the old bridge.

Page Setup now previews paper, orientation, margins, header/footer distances and columns. Inches/cm/mm selection is remembered, and metric rulers use centimeter divisions/millimeter snapping. Explicit unit suffixes and decimal commas are accepted. Existing point geometry is preserved on untouched Apply or unit changes. Spreadsheet row/column dimension dialogs accept the same physical units. Paragraph indents/spacing use the selected metric unit, retaining conventional point presentation for the default imperial configuration.

Ordinary spaces following a hyphen at a soft wrap are consumed with the preceding line. Explicit hard-break indentation remains intact. Native underlines gain gaps around descenders without changing glyph ink above the baseline, shaping or layout width. Synthetic before/after PNGs accompany the rendering tests; this does not claim complete font/layout equivalence with other office suites.

Viewer Escape returns to folders, with nested find/dialog dismissal first. Saved notices are compact, dismissible and expire after 30 seconds even with persistent-notification preferences. A later save result replaces the earlier notice so errors are visible immediately.

Acceptance logs record local Flutter widget/host and Dart engine runs; no GitHub CI queue was used. The previously published terminal acceptance (including real loopback SSH and tmux) is documented in ../canonical-refresh-20261116/. No installed application bundle was replaced during these checks.

The combined regression run passed 117 tests with two existing platform skips. The ODS reader/writer/line-breaking/Word-layout engine run passed 141 tests (including the newly merged ODS writer). The separate paragraph/font/layout run passed 31 tests (overlapping targeted cases are not counted twice). Static analysis of 13 host/test targets reported no issues. File-target checks use actual temporary files with injected native-picker results; they do not exercise an interactive macOS save panel.

Concurrent ODS writer updates were integrated from Quds main (bounded writer and metadata/number-format support). A synthetic ODS was opened and converted by an isolated headless LibreOffice Calc process; values, computed formulas, bold, merged cells, comments, hyperlinks, percentage formatting, named ranges and print area survived the independent output checks. Hyperlinks and named metadata were verified directly in LibreOffice's XLSX XML because the engine deserializer does not hydrate every such field. This verifies these fixtures, not unrestricted ODS feature fidelity.

Final incoming refresh: Quds main ed5facb4bd503667749ed3d13378da6a1b34738b also includes the concurrent writer picture, conditional-format and validation updates. All 144 reader/writer/line-breaking/layout engine tests pass. The last synchronization changes only the engine changelog; the managed mirror and staged inventory are checked again before publication.
