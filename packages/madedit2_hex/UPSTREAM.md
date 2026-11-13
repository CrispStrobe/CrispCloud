# Native hex package provenance

Maintained fork: https://github.com/CrispStrobe/madedit2
Pinned review branch: `fix/crispcloud-scrollbar-provenance-20261113`
Original integration branch: `feature/crispcloud-hex-package`
Pinned package revision: `912b1f7527e5f48793a8e0834cc7c7ab8dbb7f5f`
Package path in the fork: `packages/madedit2_hex`

Upstream: https://github.com/madedit/madedit2
Upstream revision: `288d35747faccb1cb997c4a30afc40c6cb48b0ae` (v1.0.2), MIT.
The original copyright and permission notice are retained in LICENSE.

`lib/hex_layout.dart` adapts the byte-column layout, offset and nibble helpers
from upstream `lib/editor/hex_view.dart`. The embeddable Flutter widget,
serialized controller and persistent byte-only AVL document are integration
code, not an unchanged upstream widget. The package deliberately omits text
newline indexing, encoding-aligned byte mutations, global application settings,
Rust, scripting and Tree-sitter.

The manually created fork is now writable and contains the complete reusable
package and its regression tests. Its implementation was preserved from
CrispCloud's `bf12c3ac97526d2fd33a70b38148fa86c097db47` checkpoint.

CrispCloud continues to build the vendored path dependency. This retains the
existing reproducible build and does NOT introduce a moving Git dependency.
`FORK.json` records the exact maintained fork commit and Git blob fingerprints.
`python3 tool/verify_hex_vendor.py` checks code, tests, license and package
configuration against that manifest; checkout CRLF conversion is normalized.
This read-only, offline check is included in CI. It does not execute or fetch
code from the network.

Make reusable package fixes on a fork review branch, validate them, then
copy the reviewed package changes here and update the pin/fingerprints together.
Keep host-specific staging, account identity, conflict checks and UI routing in
CrispCloud. Fork and application main branches remain unchanged by this work.

The pinned revision includes a 64 MiB shared undo/redo byte budget, navigation
cancellation for stale search results, and horizontal caret reveal. These fixes
were committed to the fork before copying the exact package source here.

## Scrollbar fix provenance repair, 2026-11-13

CrispCloud commit
[`87333f4557c47bc9034be04b96e2aeac61f0d01a`](https://github.com/CrispStrobe/CrispCloud/commit/87333f4557c47bc9034be04b96e2aeac61f0d01a)
added an 18-pixel scrollbar-gutter check and its regression test, but did not
update the maintained fork or this manifest. The existing offline gate correctly
reported the mismatch for `lib/hex_editor.dart` and
`test/hex_ui_regression_test.dart`, including in CI run
[`43371831404`](https://github.com/CrispStrobe/CrispCloud/actions/runs/43371831404).
The mismatch already existed at CrispCloud baseline
`794bde82693e07a6e04ed1490bfa228f154e6e5c` before the File Viewer integration.

The repair preserves those exact two existing files in fork commit
[`912b1f7527e5f48793a8e0834cc7c7ab8dbb7f5f`](https://github.com/CrispStrobe/madedit2/commit/912b1f7527e5f48793a8e0834cc7c7ab8dbb7f5f),
whose parent is the previously pinned
`50d033cc70d9121819c890fe587f8b3dc4c82311`. Its tree is
`9aac7225fd2dc0077bc803649c39793d67678d89`. No editor behavior, dependency, license,
or verification rule is changed by the application-side provenance repair.

| File | Git blob at the new immutable fork revision |
| --- | --- |
| `lib/hex_editor.dart` | `9409dde9fa9799887355fdef59a411895c8c3349` |
| `test/hex_ui_regression_test.dart` | `7e5991271dc4e1dead15b41ce4e376e86d535eae` |

All 12 source, test, license and package-configuration files checked by
`FORK.json` were compared with that remote tree before updating the revision and
the two changed hashes. The existing manifest verifier remains unchanged.

The reviewed behavior keeps primary-mouse presses on the vertical/horizontal
scrollbar gutter out of byte-selection handling. The preserved regression checks
that a gutter drag leaves caret and anchor unchanged and a press on actual rows
still places the caret. Before the fork checkpoint was created, all 25 standalone
package tests passed locally with Flutter 3.47.8 (`flutter test --no-pub --reporter
expanded`). `flutter analyze --no-pub --no-fatal-infos` exited successfully with two
existing informational lints in unchanged `test/hex_regression_test.dart`.

This is provenance repair for the pre-existing MIT-licensed hex editor. It does
not expand the separately documented Apache-only File Viewer source import.

Validation is separate from provenance: matching source fingerprints does not
mean tests passed. See `docs/hex-editor-validation.md` in CrispCloud for the
executed package and host results and remaining platform acceptance checks.
