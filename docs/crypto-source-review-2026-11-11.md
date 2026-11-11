# Workspace source and dependency review — 11 November 2026

This technical review refreshes the source bindings in
[apple-export-policy.json](apple-export-policy.json) after the workspace UX
changes. The reviewed application revision is
[`6a8e24c917479d83cc468e072d47405eda8d86a1`](https://github.com/CrispStrobe/CrispCloud/commit/6a8e24c917479d83cc468e072d47405eda8d86a1),
compared with main at
[`92078b5d7db04c2f1c211cff62c08eceaf9ddf8a`](https://github.com/CrispStrobe/CrispCloud/commit/92078b5d7db04c2f1c211cff62c08eceaf9ddf8a).

The updated `reviewed_on` date records this engineering reassessment. The
policy's encryption declaration, documentation decision, application identity,
France history/availability references and TestFlight audience references retain
their existing values and their previously recorded evidence. No live store or
distribution review, legal classification, upload or deployment was performed
for this refresh. Artifact verification and live distribution checks remain
separate release requirements described in
[export-compliance.md](export-compliance.md).

## Reviewed changes

The [inventory](crypto-inventory.json) lists 81 source files. Comparing their
exact Git blob identities found changes in only the three UI files below. The
other 78 inventoried files and the inventory itself match the baseline.

| Input | Reviewed change | Effect on the recorded crypto scope |
| --- | --- | --- |
| [`lib/widgets/settings_dialog.dart`](../lib/widgets/settings_dialog.dart) | Adds the entry that opens keyboard-shortcut settings and its localization import. | Credential storage selection, setup and App Lock controls retain their existing logic. |
| [`lib/screens/screen_dialogs.dart`](../lib/screens/screen_dialogs.dart) | Shows current shortcut bindings, adds customization access and corrects shortcut descriptions; reformats the existing logout dialog. | Logout and credential-deletion retry/error behavior retain the same control flow. No encryption implementation or credential storage backend changes. |
| [`lib/widgets/command_palette.dart`](../lib/widgets/command_palette.dart) | Adds navigation/reopen commands, ranked command discovery, live bindings, enabled-state checks and dispatch through existing workspace command handlers. | Existing encryption, key-management and account handlers remain in use. The changes add no cryptographic algorithms, key formats or provider protocols. |
| [`pubspec.yaml`](../pubspec.yaml) and [`pubspec.lock`](../pubspec.lock) | Add the pinned `cupertino_icons` 2.0.0 package for the adaptive control font. | The exact published archive contains font/image/documentation assets and test code, with no production Dart library, native implementation or runtime dependency additions. No existing locked package entry changes. |

### Exact icon-package verification

The [published package](https://pub.dev/packages/cupertino_icons/versions/2.0.0)
identifies the package as icon assets for Flutter's adaptive widgets. The review
downloaded the [2.0.0 archive](https://pub.dev/api/archives/cupertino_icons-2.0.0.tar.gz)
without executing its contents and checked its SHA-256 against both the package
metadata and the committed lockfile:

```text
b7cc2390aac296c083bea762859413eb1cf5b630c70e0c7e4d831018f762a8b2
```

The archive is 2,602,507 bytes and contains 77 regular files. Its three Dart
files are all under `test/`; its manifest declares the
`assets/CupertinoIcons.ttf` font and development dependencies only. The review
found no native implementation files. This establishes the scope of this
dependency addition; it is not a font-parser security audit or a binary scan of
the finished application.

## Refreshed bindings

These values were computed with the repository's existing
[`apple_export_preflight.py`](../tool/apple_export_preflight.py) hashing rules:

```json
{
  "inventory_sha256": "db7392a4c6f94305bece8f17e5d629091073583ca81fec0d264e914ec377c3f0",
  "pubspec_lock_sha256": "20ea99fe42a831b47a4a71092923d7f766b09c77b25ffd2e6d62762430e8038c",
  "reviewed_source_sha256": "a20f74f2a93ed5f6c1d3a79e2aa1bbd9089c2154cbb8b9bc27a5718cc4999eae"
}
```

The source digest hashes the exact bytes of all 81 inventory-listed files in
sorted path order. The lockfile digest covers its complete bytes. Only the
review date, lockfile digest and reviewed-source digest change in the policy.
The validators and their failure-path tests are unchanged.

## Validation context

Hosted [CI run 42930629411](https://github.com/CrispStrobe/CrispCloud/actions/runs/42930629411)
tested the reviewed application revision. Its
[Linux analysis/test job](https://github.com/CrispStrobe/CrispCloud/actions/runs/42930629411/job/130228172217)
reported 7,644 tests passed and 35 skipped. All 18 Unix socket protocol fixtures
passed on that runner. The iOS, macOS and Android build commands succeeded;
their evidence-recording steps and the standalone evidence job rejected the
stale lockfile binding. This refresh preserves that rejection mechanism and
records the reassessed inputs instead of bypassing it.

Local validation of the refreshed bindings used the existing Python suites:

- `python3 -m unittest discover -s tool -p test_crypto_release_evidence.py`:
  41 tests completed, with the two existing platform-dependent skips.
- `python3 -m unittest discover -s tool -p test_apple_export_preflight.py`:
  all 37 tests passed.
- `python3 tool/crypto_release_evidence.py --check`: passed against these
  source inputs.

Any further edit to the inventory, lockfile or an inventory-listed source file
requires another delta review before its fingerprint is updated. A passing
source check does not validate a later binary or establish current store state.
