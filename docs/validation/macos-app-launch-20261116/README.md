macOS application bundles — 2026-11-16

Local `.app` directories launch through Launch Services on double-click, Enter, or Open. The context menu exposes Launch application and Browse package contents separately, including verified local search results. Ordinary directory navigation, remote folders and archive members retain their browsing behavior. Column view selection and Right-arrow navigation do not launch applications.

The launcher passes the exact absolute bundle path to `/usr/bin/open -a` as an argument without a shell. The original verified local source and filesystem access scope are retained across awaits. Failed launches do not navigate into the bundle. Strings are localized in all eight translated Commander locales.

Acceptance: 50 tests passed with no skips, including an actual Launch Services launch of a temporary compiled background app. The fixture writes a marker, exits, and is deleted. Eight focused analysis targets are clean; broader panel analysis reports only 13 pre-existing informational lints. Tests cover exact arguments, unsupported/invalid targets, scope ownership, source stability during navigation, remote folders, unverified rows, denied access, menu actions, column selection/keyboard/double-click behavior, and existing navigation/column regressions.

Two drag-review assertions failed on unchanged production code as well. They were updated to assert that a valid review enables its explicit Start button; the tests still prove that dropping files alone creates no writes or queued operations. The baseline failure log is retained separately from accepted results.

No installed application bundle was replaced. The previous Office, Save As, ODS and terminal qualification records remain in the neighboring validation directories.
