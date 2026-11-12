# App integration at parser 53a7f0d

This receipt records the app integration of parser `53a7f0d` through Quds
`09f5ec4`. All 341 upstream parser files match their immutable source bytes and
modes; 680 shared Office files and the separate 246-file CrisperBooks inventory
verify against their own pins. App implementation and test files are unchanged
from `8b0c01597c231814815bf5456ab0a616102e7307`.

The run passed 99 focused Flutter tests across 16 Word/native-conversion suites,
74 guarded-sync/native-render harness tests, production DOC/RTF/PPT/MSG
JavaScript/Node acceptance, and installed-Office checks for built-in DOCX and
native DOCX/DOCM routes. The native checks include independent PDF text/images,
headers/footers/notes, output inspection, and unchanged source/prepared bytes.
They do not certify arbitrary pagination or complete format semantics.

`summary.json` identifies exact source pins, configuration hashes and compressed
logs. Each gzip expands to the complete original stdout/stderr. Deliberate
negative-harness failures are part of the passing control suite. The existing
system-SQLite wrapper temporarily disabled the optional ebook build hook; it
restored the release pubspec byte for byte. Native ebook conversion is outside
this test scope. Tests ran on the described integration worktree before commit;
the receipt does not claim that the changed mirror belonged to the base commit.
