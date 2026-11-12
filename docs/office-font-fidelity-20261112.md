# Host font dialog fidelity

The actual Word font dialog previously rounded half-point sizes to integer
points and clamped imported sizes to 8–96 points. Pressing Apply rewrote every
run property on the selection, even when no control had changed. This could
flatten mixed formatting, replace complex-script fonts and dirty an unchanged
document.

The dialog and ribbon now display the exact imported size, including 10.5, 7
and 144 point cases outside the usual preset list. An unchanged Apply creates
no history entry and leaves the document clean. An explicitly used control
applies only that property to the selected runs. Choosing the caret's current
value can deliberately normalize a mixed selection. Existing Latin and complex-script fonts,
size, color, highlight, underline, strike, bold and vertical alignment survive
unrelated changes. An explicit family change continues to set the selected
font family. The action checks editing mode, controller identity, content revision, active
story and selection after the modal result. A stale result cannot mutate a
replacement document or newly selected target; paint-only refreshes remain safe.

## Executable evidence

`test/widget/office_font_fidelity_test.dart` authors its source DOCX directly as
ZIP/XML and drives the real host Font action and dialog. It inspects exported
ZIP/XML independently of Quds deserialization. Seventeen widget tests cover:

- Exact imported half-point and out-of-preset sizes, no-op Apply and clean
  history.
- Editing italic, font size or font family across differently formatted runs,
  with undo and redo.
- The active header story while preserving body formatting.
- Cancellation, controller replacement while the dialog is open, and viewing
  mode.
- Explicitly choosing a displayed family, size or underline for a mixed
  selection, and rejecting stale story/selection/content results.

Ten scenarios produce three save/reopen exports each. All 30 paths are
mandatory entries in `tool/office_host_evidence.json`, and the test is part of
`tool/check_office_fidelity.sh`. The normal tests never regenerate expected
formatting from the exporter. The independent XML assertions include distinct
Latin and complex-script font names (`Cambria` and `Amiri`).

The focused 17-test run passes under the app's pinned Flutter 3.47.8.
Targeted analysis reports no warnings or errors. Full host/schema acceptance
belongs to this feature branch's final execution evidence. This semantic
coverage does not claim complete font fallback, mixed-value dialog UI, native
Word rendering equivalence or character-style authoring support.

The resumed integration also retains the shared custom-tab dialog and its
existing save/history regressions. The combined 70-case host cohort passed
69 cases initially; its remaining upload case passed after awaiting the new
picture decoder and correcting its independent expectation for the authored
2 by 2 pixel PNG (1.5 by 1.5 points at 96 dpi). These are focused integration
results, separate from the final source-pinned host gate.

```sh
flutter test test/widget/office_font_fidelity_test.dart
python3 -m unittest discover -s tool -p 'test_office_host_*.py'
```
