# Catalogue GUI acceptance — 2026-11-14

Pinned Flutter 3.47.8 / Dart 3.13.7, macOS arm64 host. This records focused acceptance; hosted full application CI and device-level mobile acceptance are separate.

- Catalogue GUI plus existing storage analytics, analyzer widget/origin, localization and browser menu regression: **151 passed**. Includes 13 new cases for format routing, library CAS recovery, cancellation/grant lifetime, paging, empty-folder parent navigation, small-screen accessibility, scan/import/open/remove, global search identity and symlink escape rejection.
- Native catalogue Rust: **13 passed**, one intentionally ignored million-row scale test. Includes exact-path filtering, pagination, snapshot copy/validation, stale identity, failed refresh preservation and cancellable CAF work.
- Canonical MIT format codec: **23 passed**. Source verification matches CrispSorter main `c1881142` exactly for CAF and index implementations.
- Focused package/GUI analyzer: **no issues**.
- Both standalone CLI executables built with native assets and notices. Actual `crispcloud` and `crisp` each passed help, native scan and indexed JSON ranking checks. Earlier CLI regression after the naming change: **148 passed**.
- Native engine release builds: **aarch64-apple-ios and aarch64-linux-android passed**. This is engine cross-compilation, not device GUI or sandbox acceptance.
- Third-party notice collection: **48 packages** across the supported desktop/iOS/Android target graph; bundled in the GUI license screen. CLI host bundles collect their selected graph.
- Reviewed source/provenance, export-input consistency and whitespace checks passed. No encryption classification, territory policy or distribution-group changes.

The Nextcloud follow-up independently rechecked Nextcloud 33.0.11: native DAV 207; approved-origin preflight 204; unauthenticated DAV 401; unapproved origin lacks an allow-origin header. Real headless Chrome completed PROPFIND/PUT/GET/DELETE with identical content and no network/CORS errors. Generated test users were removed afterward. Issue #96 now has a concise explanation and the exact-origin proxy configuration link. Its reporter's redacted server remains unverified.

Scope limits: SQLite remains the working catalogue; CAF is optional dated interchange with explicit coverage/encoding limits. Global GUI search intentionally bounds previews. Web catalogue execution and public Rust crate publication remain pending. New feature branches published during qualification require their own integration; this record does not claim they were merged.
