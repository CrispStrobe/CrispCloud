Rebuild refresh — 2026-11-16

The build integrates CrispCloud PR #176 with current main, Quds PRs #63 and #72 (the latter includes the former and the proofing continuation by ancestry), the newer ODS default-page-layout fix, and a stable snapshot of five uncommitted local ODS-export files. The original working copy is preserved. The shared package is regenerated using the guarded canonical updater, retaining the independently pinned legacy parser.

Other relevant default heads were checked: MadEdit, crisp-docx, legacy-doc-parser, crisperbooks, libdbm, filen-dart and crisp-cloud-rs remain at their previously integrated pins. The incoming-refs inventory records ancestry; older ODS vendor/docs heads not literally in ancestry retain their previously documented squash/patch-equivalent implementations. The two new ODS page-layout branch writer blobs match the combined canonical source exactly.

Local checks:
- 242 editor/host tests passed, including actual Flutter PDF-font subset rendering, font-cache identity/lifecycle, proofing corrections/dialogs, Zotero session backoff, Save As, layout controls, ODS conversions and app launching.
- 271 selected pure-Dart engine tests passed for typography, layout, proofing, ODS and Zotero identity/backoff.
- After the latest page-layout refresh, 110 ODS reader/writer tests passed.
- The local ODS-export snapshot and affected host workflows passed 52 tests.
- 36 Python sync/distribution/signing/startup utility tests passed.
These cohorts overlap; their counts must not be added as a unique-test total. The font fixture test was made portable between package and host working directories and rerun successfully. The dependency lock was enforced offline without version upgrades. No GitHub CI checks or jobs were queried or awaited.

The release rebuild preserves the existing App Store/sandbox distribution profile, bundle identifier and Apple Development team. It is a local build for this Mac’s native architecture. The existing installed builds remain intact; the new signed build is staged separately and checked for signature, distribution policy and startup health.

Built and installed: `/Users/christianstrobele/Applications/CrispCloud 1.3.4 (2fcea746).app`. The release AOT embeds source `2fcea746f2cc5f8f37956bfb67b4e34d513c0c6f`; its SHA-256 is `ee3bcf4f7b46864d028a39aef852c548dec5428a6d7db161a66478afab0fcc58`. Native architecture: ARM64. Deep code-signature and appstore/sandbox distribution checks passed, using the existing development team. The signed app rendered startup UI, reached “Credential policy ready”, and remained healthy for 15 seconds. Runtime logs containing user configuration stay outside Git; only the safe result and milestone are recorded. Older installed builds and the running user instance were preserved.

The rendering branch’s late reconciliation commit was also incorporated into Quds main. It changed only history/inventory records and had no production-code differences from the source compiled here. Further incoming Office capability documentation and ODS export translations were merged before the build freeze.
