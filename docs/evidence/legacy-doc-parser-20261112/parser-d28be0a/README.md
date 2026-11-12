# App integration at parser d28be0a

This receipt records parser `d28be0a173415ebb392a8309aacdbe2bb1a50da7` with Quds `da0979a5c6c4273ea68f360ce9a079bfa747384f`. All 422
standalone parser files match their source bytes and Git modes; all
843 Office-managed files verify. The separate 278-file ebook
checkout and the existing dependency lock remain unchanged.

The integration passes **131 Flutter tests across 17 Word conversion/UI suites**,
including the current attached-content inspection checks, and **101 Python
sync/render harness tests**. Production DOC/RTF/PPT/MSG JavaScript acceptance and
installed-Office checks for built-in DOCX and native DOCX/DOCM pass. Native
acceptance checks independent PDF text/images and header/footer/note content,
output inspection, and unchanged source/prepared bytes.

App `lib/` and `test/` sources equal public base `4bbd323263f4c97a057bc74be8411e6a629e4100`.
`summary.json` retains exact source pins, configuration/source-binding hashes
and complete compressed logs. Temporary test hooks restored the release
pubspec byte for byte. Existing non-digest policy decisions are unchanged.

The upstream source separately passes 761 Dart tests, 129 Python tests,
51 media JavaScript checks and 193 SDK package checks. Its full native run
retains all 24 initial imports, six exact initial renders and 23 complete
three-cycle cases. The first-page-enabled header fails its first regenerated
DOC import; the full error and all 281 emitted documents are retained upstream
in `doc/evidence/8367ce0/`. A later oracle correction also distinguishes real
text tabs from tab-stop properties. This host acceptance is a scoped app result;
it does not turn those upstream findings into an exact-fidelity claim.
