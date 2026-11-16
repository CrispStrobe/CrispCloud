# Shared SSH shell widget inspection

These five PNG files were captured from the production `TerminalTabs` and
`TerminalPanel` widgets by `test/ssh_connection_sharing_visual_test.dart`.
The test supplies an in-memory connection and deterministic terminal output.
It establishes widget behavior and layout; it does not connect to an SSH server.

The implementation agent opened and inspected each original image individually.
The files here are byte-for-byte copies of the generated PNGs. Dimensions,
SHA-256 hashes, original capture paths, the test command, and individual review
findings are recorded in [review.json](review.json).

| Capture | Viewport | Inspection |
| --- | --- | --- |
| [Desktop menu](shared-shell-menu-desktop.png) | 1180 × 700 | All three explicit shared-shell actions appear before ordinary pane actions. The menu can scroll to additional workspace actions. |
| [Desktop split](shared-shell-split-desktop.png) | 1180 × 700 | Independent output appears in both production terminal panels; both display the shared-route badge. |
| [Desktop close confirmation](shared-shell-close-desktop.png) | 1180 × 700 | The disclosure explains that remaining terminals retain the connection, forwards, and permitted agent access. |
| [Compact terminal](shared-shell-compact.png) | 320 × 320 | The split collapses to the active terminal and retains the shared-route badge. Long endpoint labels use the existing ellipsis behavior. |
| [Compact menu](shared-shell-menu-compact.png) | 320 × 320 | All three shared SSH actions remain readable at the top of the scrollable workspace menu. |

## Focused execution

The capture ran together with four related widget files:

```sh
../toolchain/run flutter test --no-pub --concurrency=2 --reporter expanded \
  --dart-define=SSH_SHARING_VISUALS=true \
  test/ssh_connection_sharing_widget_test.dart \
  test/terminal_tabs_test.dart \
  test/terminal_arrangements_widget_test.dart \
  test/ssh_tmux_panel_lifecycle_test.dart \
  test/ssh_connection_sharing_visual_test.dart
```

That focused invocation completed with **44 passed, 0 failed, 0 skipped**.
The separate ownership/session/adapter cohort completed with **35 passed,
0 failed, 0 skipped**. Static analysis of the twelve changed UI/backend and
test files reported **No issues found**. The original logs and command
provenance are retained in
[the focused receipt](../focused/ui-backend-focused.json). These are development
subsets; they must not be added to overlapping full-cohort totals.

The capture is opt-in and otherwise skipped. It writes to
`build/ssh-sharing-visuals` by default; the `SSH_SHARING_VISUAL_DIR` Dart define
can select another destination. The receipt preserves the exact executed
widget command. Ownership and analyzer commands in the focused receipt are
reproduction commands matching the executed file lists because those stdout
logs do not embed the full original argument vector.

## Provenance and limits

[visual-source-snapshot.json](visual-source-snapshot.json) records exact current
hashes for 76 relevant project files plus the toolchain wrapper and Material
Icons font. It includes the capture fixture, changed sources, focused tests,
direct project imports of the fixture/widgets/session, dependency manifests,
and explicitly loaded fonts. It was recorded when this evidence was packaged,
after the focused executions. It is a scoped working-tree identity receipt,
not an execution-time frozen inventory of the whole application.

The widget-test renderer used a device pixel ratio of one at 1180 × 700 and
320 × 320. These sizes do not establish browser, packaged desktop, or physical
mobile-device acceptance. English labels were inspected; translated labels
and placeholder preservation are covered by behavioral assertions rather than
separate locale screenshots. The fixture font set does not qualify platform
font fallback: some existing auxiliary keyboard-row glyphs appear as fallback
boxes in the desktop captures.

No SDK command was run while packaging this evidence. No GitHub Actions were
queried or awaited. Independent review, complete terminal regression results,
the optimized application build, and final source identity are recorded
separately by the integration owner.
