# Cloud connections and Nextcloud browser failures

## Issue 98: keep two live cloud connections

Opening another connection previously called `logout()` on the primary client.
That disconnected the first pane and could delete the first provider's saved
credentials. Provider switching now registers the exact old client as a live
secondary connection before constructing the new primary session. Retained
file-encryption wrappers keep their own key; key-management state is cleared
for the new primary. Opening another account on the same provider creates a
fresh adapter instead of reauthenticating the old pane's adapter.

A pane displaying the old primary is pinned to that retained client and path.
The connection dialog installs the newly authenticated source in a local pane
when the active pane already shows another cloud. Source dropdown labels include
account identity. Captured secondary capabilities use a revision for that client;
adding an unrelated connection does not invalidate them. Removing and readding
the original client cannot revive old capabilities.

Disposing the multi-cloud provider now drops its connection registry without
calling account logout. Closing the app must not delete saved credentials or
revoke provider tokens. Explicit removal remains an account logout.

Additional connections remain session-only. This change does not implement a
persistent multi-account profile manager or independently saved credential slots
for multiple accounts on the same provider.

## Issue 96: actionable browser transport diagnosis

The reported `ClientException: Load failed` contains no HTTP status. Browser
JavaScript cannot distinguish CORS rejection, certificate trust, mixed content,
or a network failure from that opaque result. The app must not report it as a
bad password, invent a particular cause, or forward credentials to another host.

Failed browser PROPFIND now has a distinct structured error with the exact DAV
endpoint, app origin, original transport failure, required CORS method/headers,
HTTPS requirements, browser-console instructions, and the native-app alternative.
All nine app languages have this explanation. PROPFIND requests have a 30-second
timeout and close their HTTP client on success or failure. Failed probes do not
save credentials or mark the session authenticated. Native HTTP status handling
and authentication errors retain their existing semantics.

[Provider setup](PROVIDER_SETUP.md#browser-access-webpwa) explains installation
root URLs, preflight, response metadata, and safe same-origin/native alternatives.
The reported server URL is redacted; no live reproduction or server configuration
change was possible. Issue 96 therefore still needs verification against the
reporter's real deployment. These client changes cannot bypass server CORS policy.

## Observed validation

Flutter 3.47.8 / Dart 3.13.7, macOS arm64:

- Native focused regression: **143 passed, one existing conditional skip** across
  session retention, source identity, Nextcloud, key lifecycle, cloud transfer,
  pane source/header controls, and connection dialogs.
- Actual Chrome execution: **2 passed**. The adapter's browser transport path
  receives a deliberately opaque HTTP failure; checks verify structured
  diagnostics and that no authenticated session or saved credentials are created.
- Source-bound crypto release inputs and dependency checks passed. No encryption
  algorithm, dependency lockfile, or distribution policy changed.

Commands:

```sh
flutter test --no-pub test/cloud_connection_retention_test.dart \
  test/nextcloud_browser_failure_test.dart test/nextcloud_browser_transport_test.dart \
  test/panel_file_origin_test.dart test/nextcloud_adapter_test.dart \
  test/nextcloud_operation_localization_test.dart test/encryption_key_lifecycle_test.dart \
  test/multi_cloud_test.dart test/multi_cloud_transfer_regression_test.dart \
  test/widget/panel_source_selector_widget_test.dart \
  test/widget/panel_header_navigation_test.dart test/connection_dialog_test.dart
flutter test --no-pub --platform chrome test/nextcloud_browser_failure_test.dart \
  test/nextcloud_browser_transport_test.dart
python3 tool/crypto_release_evidence.py --check
```

These are focused tests, not live provider acceptance or a completed release build.

## Prepared-instance acceptance after the maintenance refresh

The owner's prepared Nextcloud instance was located from the saved deployment
records and updated from **33.0.5 to 33.0.11** using the official verified release.
The prior source, configuration and database remain backed up. Core integrity
passed, maintenance is off and no database upgrade is pending. The installed
delta app matches source `f6117d9` and passed **12/12** live checks, including the
eight-reader finalize race. A dedicated PHP-FPM pool supplies private temp paths
within the existing AppArmor storage policy; that policy was not weakened.

The browser failure was reproduced against this real instance: native DAV
returned **207**, while Chrome received `PreflightMissingAllowOriginHeader`.
The [Apache recipe](examples/nextcloud-apache-cors.inc), configured for one exact
origin, produced **204** preflight and **207** DAV. Chrome then wrote (**201**),
read (**200**) and deleted (**204**) a test file with exact content verification.
An unapproved origin remained blocked; a real DAV request without credentials
still returned **401**. The endpoint was accessible through a loopback tunnel;
these results do not validate an arbitrary public server's TLS or proxy setup.

Live app testing also exposed RFC HTTP timestamps reaching an ISO-only pane
parser. The adapter now converts valid HTTP dates to UTC ISO timestamps on native
and web targets, while missing/malformed optional dates remain unknown. The
existing locked `http_parser 4.1.2` supplies that parser; its version and checksum
are unchanged. The dependency is now declared directly.

Final checks: **60 focused native tests**, **9 Chrome tests**, and **2 actual app
live tests** passed. The live two-account test requires both pane listings to
be verified and free of listing errors; authentication flags alone are
insufficient. No test account password or original server credential is stored
in these records. The reporter's redacted deployment still needs its own
configuration verification; the app cannot bypass server CORS restrictions.

Machine-readable results: [acceptance.json](evidence/cloud-issues-96-98-20261113/acceptance.json).
