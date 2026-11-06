# Preserved implementation checkpoint

This branch preserves the implementation developed in this session before the
shared `feature/madedit2-hex-editor` branch advanced independently during a
browser authentication interruption. It is retained so that source edits and
tests are not lost. It is an alternate implementation, not the current app
integration, and must not be merged wholesale over the shared branch.

Continue release work on `feature/madedit2-hex-editor` and reusable package work
on `CrispStrobe/madedit2` branch `feature/crispcloud-hex-package`.

This checkpoint includes a raw-byte AVL piece model, retained source leases,
immutable snapshots, bounded undo history, a native Flutter editor, captured
storage session, localization and host routing tests. The isolated core suite
passed 18 tests and the controller/widget suite passed 14 tests with Flutter
3.47.8. The app-level tests in this alternate implementation have not been run.

Review improvements individually against the shared branch's current API.
The shared branch uses a persistent rope and different public package API.
