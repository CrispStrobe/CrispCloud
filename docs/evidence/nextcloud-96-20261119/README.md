# Nextcloud issue 96 compatibility acceptance — 2026-11-19

Rebased the existing iPad scene fix onto upstream `main` at `49b13011`, then
revisited [issue 96](https://github.com/CrispStrobe/CrispCloud/issues/96), including
the newer email-login, 404, WebDAV authorization and pane-swap reports.

## Changes

- Separate the installation URL, authentication name and DAV home. Accept
  installation roots, modern home DAV URLs and legacy `remote.php/webdav` URLs,
  including subdirectory installations. Preserve the verified home on restore.
- When a derived home returns 401/403/404, discover the authenticated principal
  on the same installation. Only successful DAV principal properties inside
  that installation can select a replacement home. Explicit home URLs are
  preserved; foreign saved homes and redirected credential probes are rejected.
- Keep email-style authentication names intact, encode path components once,
  and identify the collection itself by its href instead of response position.
- Send supplied WebDAV Basic credentials on the initial request, retain the
  verified client, and preserve Digest challenge negotiation. This avoids
  depending on a browser-hidden `WWW-Authenticate` header for Basic access.
- Perform byte GET/PUT directly. The dependency's byte helpers required a
  preparatory OPTIONS response to be exactly 200; the scoped CORS policy
  legitimately returns 204. Preserve automatic parent creation and browser
  upload size limits.
- Bound optional delta-app detection to five seconds. Update setup instructions
  for full home URLs, subdirectory CORS routes and Digest challenge exposure.

## Observed results

The owner's VPS runs Nextcloud **33.0.11**. Two dedicated accounts covered a
normal account ID, a distinct email login alias, and an email-shaped account ID.
A temporary Apache alias exposed the same prepared instance under a subdirectory.
DAV authentication and the exact allowed browser origin remained enabled.

- **178 focused regression checks passed.**
- The final acceptance run passed **47 checks**: four authentication unit checks,
  39 real-I/O mock-server integration checks, and four VPS live tests. Three of
  the four authentication checks also occur in the earlier focused run; these
  counts are not an additive unique-test total.
- **12/12 native adapter scenarios** and **12/12 real Chrome scenarios** passed
  login, upload, repeated listing, download, credential restore and exact-content
  checks. Filenames include Unicode, spaces, `#` and literal `%20`.
- Actual pane controllers verified distinct account markers before swapping,
  and after swapping and refreshing. Both Nextcloud/Nextcloud and
  WebDAV/Nextcloud arrangements passed without listing errors.
- The old duplicated DAV path returned **404** on both root and subdirectory
  mounts. Chrome reproduced the prior WebDAV challenge failure as **401** with
  `WWW-Authenticate` hidden from JavaScript; corrected adapters succeeded without
  changing that header exposure.
- Approved-origin preflight returned **204**. Unapproved origins remained
  blocked, and actual unauthenticated DAV requests still returned **401**.
- Targeted Dart analysis and `git diff --check` passed.

The first browser acceptance exposed the OPTIONS/204 issue after listing had
already succeeded; the byte-transfer fix was then included in the final run.
An earlier live run lost its SSH tunnel and is excluded from qualification.
The final run used a keepalive tunnel. The mock DAV server also needed to emit
URI-encoded hrefs instead of raw Unicode; its corrected wire fixture passed the
complete integration suite.

Both dedicated accounts were deleted. The temporary mount and CORS edits were
removed, and both Apache files matched their original bytes afterward. Nextcloud
remained installed, out of maintenance mode, with no pending database upgrade.

[acceptance.json](acceptance.json) records sanitized results, source hashes,
the probe artifact hash and cleanup checks. Credentials and the compiled probe
bundle are private and are not committed. Browser custom delta/OCS API access
has a separate CORS scope from DAV and is not qualified by this matrix.

## Reproducing the live checks

Supply a private JSON file with `url`, `username`, `password`, `email`,
`second_username`, `second_password`, `second_created: true`, and optionally
`mounted_url`. The email must authenticate the first dedicated account; the
second account ID should itself be email-shaped. Use disposable test accounts.

```sh
CRISPCLOUD_NEXTCLOUD_TEST_CONFIG=/private/accounts.json flutter test --no-pub \
  test/nextcloud_connection_live_test.dart \
  test/nextcloud_prepared_instance_live_test.dart --tags live --run-skipped

flutter build web --no-pub --no-wasm-dry-run \
  --target tool/probes/nextcloud_connection_web.dart \
  --dart-define-from-file=/private/accounts.json --output /private/probe-web
```

Serve that probe only on loopback at the exact origin allowed by the prepared
server. Its document title becomes `CRISP_NEXTCLOUD_PASS` only after every
scenario succeeds; sanitized results are in the page's `pre` element. Revoke
fixture credentials and remove the credential-bearing test build afterward.

The reporter's Shadow and research-institution deployments are still unavailable
for direct verification. A server that requires an app password or disallows
cross-origin DAV continues to require its own authentication/CORS configuration.
No GitHub Actions runs or CI status endpoints were queried or awaited.
