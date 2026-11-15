# Print, image tools and notification integration — 15 November 2026

This integration adds File → Print/Cmd/Ctrl+P for suitable document hosts,
vertical PDF toolbar defaults outside docked panels, visible two-axis crop
handles, awaitable Text opening and recovery, and disposal guards. Printing
uses unsaved current content without saving it. Supported formats and text-layout
limits are recorded in [document-printing.md](document-printing.md).

Copy/move accepts Enter or Start without a mandatory Preview step. Internal
planning, conflicts and source checks remain enforced. Successful foreground
dialogs close after refresh. The embedded queue hides after completion without
discarding recovery/history, and can be dismissed without cancelling work.
Notifications have X buttons, a 30-second default timeout (including Undo),
persisted settings and bounded session-only history. See
[notifications.md](notifications.md).

## Observed checks

- Full parser suite before the final recovery reconciliation: 4,105 passed.
  The latest bounded recovery/detection delta: 47 passed.
- Initial complete Office engine run: 1,872 passed, three conditional skips,
  three failures. Two CLI timeouts passed on a separate 22-test rerun with a
  longer limit. The live corpus now checks explicit unsupported-profile
  refusals without claiming every private workbook is importable.
- Latest Office ODS/geometry/formatting regression: 97 passed; latest parser
  bridge: 14 passed. Both original comment implementations' regressions remain.
- 41 copy/move dialog tests passed, including Enter without Preview, close on
  success and failed validation gates.
- Notification policy/history/settings, embedded queue lifecycle, 12 image
  desktop lifecycle variants, print generation/scope and PDF viewport tests
  passed. Platform variants exercise desktop UI behavior in the widget runner;
  they are not native Windows/Linux application acceptance.
- Source sync guards: 8 Office controls and 19 parser controls passed.
  Office host evidence controls: 34 passed. All 2,281 managed files match their
  pinned source repositories. Packaged notices verify 318 native dependency
  versions and all 14 bundled Office fonts.
- Native AppKit toolbar stress: 900 updates and queued teardown checks passed.

No new macOS crash report accompanied the reported Text-tool exit. The disposed
viewer-provider cleanup error was observed and corrected, but the original
process-exit cause is not established. Dart guards cannot catch a native
segmentation fault. Native window lifecycle breadcrumbs now distinguish normal
last-window closure from an OS crash report without logging document contents.

The first native integration build ran out of internal disk space before
launch. Generated build output was moved to the attached build volume and the
native test was retried. Native test/build results are recorded separately from
widget results; no physical print job is submitted by the checks.

Historical feature evidence remains source-bound to its original snapshots;
it is not certification of this later combined tree. Hosted CI remains a
separate gate, and queued runs are left to GitHub's scheduler.
