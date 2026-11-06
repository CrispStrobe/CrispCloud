# Native hex package provenance

Maintained fork: https://github.com/CrispStrobe/madedit2
Fork branch: `feature/crispcloud-hex-package`
Pinned package revision: `50d033cc70d9121819c890fe587f8b3dc4c82311`
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

Make reusable package fixes on the fork feature branch, validate them, then
copy the reviewed package changes here and update the pin/fingerprints together.
Keep host-specific staging, account identity, conflict checks and UI routing in
CrispCloud. Fork and application main branches remain unchanged by this work.

The pinned revision includes a 64 MiB shared undo/redo byte budget, navigation
cancellation for stale search results, and horizontal caret reveal. These fixes
were committed to the fork before copying the exact package source here.

Validation is separate from provenance: matching source fingerprints does not
mean tests passed. See `docs/hex-editor-validation.md` in CrispCloud for the
executed package and host results and remaining platform acceptance checks.
