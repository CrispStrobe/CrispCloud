# App integration at parser 713973f

This receipt records parser `713973fb27330d190281cbe66193f6b22ec722f8`
with Quds `94ba00188be8f91f3aafb82d58fe05cf0268c22d`, preserving the newer
main release preparation and independently pinned ebook Git dependency.
All 356 standalone parser files match source bytes and Git executable bits;
777 Office files verify, as do all 278 files in the separate ebook checkout.
App implementation and test sources equal pushed app base `6ddf921`.

The integration passes 99 Flutter tests across 16 Word/native-conversion suites,
101 sync/render harness tests, production DOC/RTF/PPT/MSG JavaScript/Node
acceptance, and installed-Office checks for built-in DOCX and native DOCX/DOCM.
Native checks include independent PDF text/images, headers/footers/notes,
output inspection and unchanged source/prepared bytes. These checks verify
app behavior and do not certify arbitrary Word pagination or full semantics.

`summary.json` binds the exact pins, file/configuration hashes, source review
and complete compressed logs. Negative harness controls are intentionally
rejected within the passing test suite. Temporary system-SQLite/optional-ebook
hooks restored the release pubspec byte for byte. Native ebook conversion is
outside this scope. The root dependency lock and non-digest policy decisions
are unchanged; only technical source fingerprints are refreshed.

Upstream's exact production tree passes 647 Dart, 109 Python and 144 SDK checks.
Its full native run was interrupted by ENOSPC and is explicitly retained as an
incomplete environment run upstream. The app acceptance here completed; neither
that outcome nor a schema pass turns the interrupted corpus into a pass.
