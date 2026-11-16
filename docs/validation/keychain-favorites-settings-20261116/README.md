# Keychain settings and pane controls, 16 November 2026

Qualified code is recorded in summary.json with exact Dart/Swift hashes.

- 76 focused tests passed: keychain controls, existing credential adapters and
  settings, direct favorites and exchanges, panel header navigation, active border.
- The final 11-test favorites rerun passes after moving overlay capture before
  the async readiness boundary. This is a subset, not 11 additional unique tests.
- The actual native Security.framework fixture passes. It creates disposable
  keychains, checks both default flags off and all four persisted combinations,
  validates timeout bounds, proves isolation from another keychain, and retains
  the original scope/unlock/bookmark/default/search-list regressions.
- Strict analysis has no issues across 11 targets; all 11 Dart files are formatted.
  AppDelegate's new method-channel cases also pass Swift syntax parsing.

Commands: use Flutter 3.47.8 / Dart 3.13.7 with the production lockfile. Run
`flutter test --no-pub --concurrency=2` on the seven files recorded in widget-tests.log.
For native tests, compile macos/Runner/CustomKeychainStore.swift together with
 test/native/custom_keychain_store_test.swift using xcrun swiftc, then run the binary.
The fixture uses only newly created test keychains and checks global preferences
before and after. It neither reads real credentials nor requests their passwords.

The production keychain defaults and per-keychain policy are documented in
../../keychain-lock-settings.md. Favorites keep original account identity and
captured-pane safety, with add/edit/filter actions below the direct list. Active
pane borders remain; redundant radio-circle markers are removed.

The first widget attempts and analysis suggestions remain in development/ and
are excluded from accepted counts. One real UI state update was corrected after
native save; fake platform setup was moved into a proper widget-test variant.
Earlier terminal/ODS integration evidence remains under canonical-refresh-20261116.
No GitHub Actions checks were queried or awaited. This pass does not rebuild or
replace the currently running packaged application; it qualifies source/widgets
and the actual file-keychain native adapter.
