# CrispCloud 1.3.5 (44) qualification

The refreshed source combines canonical CrispOffice main `a652a205` and all
3,017 managed files, retaining the independently maintained legacy parser pin.
It includes the recent Downloads, Mail, Zotero table/citation, VBA and incremental
Word layout work. Native model/library pins remain the qualified immutable inputs;
AOT/RML code and data remain excluded. CrispEmbed main was refreshed to `038c8253b`.

The independent engine comparison caught an incoming cache bug in all three
structured random-edit sequences. Paragraph line breaks from before a wrapped
edit could survive that edit and later be reused away from the wrapping frame.
The repaired engine invalidates that entry. The discarded candidate and initial
wrong-runner attempt are not qualification. A stale expected VBA diagnostic was
also updated to match the intentional omitted-argument rejection.

Final passing logs are attached: 2,351 engine tests; 154 controller tests with
8 image-only skips; 876 Mail/Downloads/theme/layout host tests; 85 Mail reader/UI
tests; and 105 CrispCloud PDF/routing/editor/font regressions. Signing (15),
distribution (11), crypto-evidence (42), TestFlight guards (27), and release
publication (12) tests also passed. The native credential-store temporary-keychain
suite passed during the Mail continuation.

The final local development-signed app reached credential-policy readiness,
rendered its startup UI and remained healthy for 20 seconds. Its stored designated
requirement is identical to the actual App Store-signed app's requirement. Local,
Developer ID and App Store signing now use the same bundle/team predicate; no
keychain password is retained and unrelated applications receive no access.

The Mac application was compiled at `2f3a31f8`. Later changes add release signing,
workflow/provenance metadata and the final Office source pin; application runtime
source is byte-identical. `qualification.json` records both revisions, the exact
post-compile paths and package SHA-256. The standalone Office build 48 contains
the same repaired runtime at `bbfc015a`; its later main commit changes only the
distribution signing helper. Neither older preview bundles nor user documents
were overwritten.

The standalone Mail changes support up to 20 remembered IMAP/SMTP accounts and
one connected foreground account at a time. Physical Mail scrolling-flicker and
live-provider acceptance remain separate from synthetic tests; the new Office
preview awaited macOS sandbox initialization on a locked desktop. No successful
physical flicker qualification is claimed.

Apple artifact, live availability/group checks and upload/distribution receipts
are recorded separately after delivery. The reviewed outside-France route,
recipient allowlist and public-link settings are retained. No GitHub Actions
runs, jobs, checks or status endpoints were queried or awaited.


## Delivery — 20 November 2026

CrispCloud **1.3.5 (44)** was accepted and processed as **VALID** for both macOS
and iOS/iPadOS. Both builds are **IN_BETA_TESTING** internally and are assigned
to the existing reviewed external group, with external state
**WAITING_FOR_BETA_REVIEW**. The group/recipient allowlist, disabled public links
and outside-France availability policy are unchanged. Exact Apple resource IDs
and the final read-back are in `testflight-final-state.json`; upload and guarded
assignment logs are attached.

The iOS archive uses the same qualified runtime source at main `dc6e417e`.
Xcode export omitted the authorized shared App Group, which was restored to both
the app and File Provider extension before strict signature verification,
artifact/live checks, validation and upload. Both bundles have version 1.3.5,
build 44. Apple accepted the IPA with a future SDK-deadline warning for April
2027; this is not a current rejection. `packages.json` records both submitted
package hashes and their compilation sources.

The `v1.3.5` tag points to qualified release code `15ffe8f0`, with the platform
binary workflow triggered and its release draft created. The existing publisher
keeps the release private until its complete required binary inventory exists.
No Actions job/status endpoints were queried or awaited.

The local signed CrispCloud preview (44, runtime `2f3a31f8`) is open for testing.
The signed standalone CrispOffice preview (48, runtime `bbfc015a`) is staged;
its application startup was held by macOS sandbox initialization while the
screen was locked. Physical Mail scrolling/flicker acceptance remains pending.
The standalone Office app has no App Store Connect record under its current
bundle ID; these TestFlight uploads belong to CrispCloud.
