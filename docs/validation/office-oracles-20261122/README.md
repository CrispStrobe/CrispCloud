# Local Zotero and VBA interchange

CrispOffice source is `bbc4f82c7562e1004c59804b30a5baafcf53e4d1`.
That revision adds Mail evidence to `5d18df8dc` and leaves the Office package code
and tests identical. The CrispCloud sync also restores 48 omitted VBA example
files. The example directory now follows the upstream pin so unchanged inputs
are present even when a sync only advances documentation.

Use the native Zotero before/after fixtures from the exact Office revision,
under `docs/validation/zotero-continuation-20261116/live-zotero/fixtures/`.
These are retained native Zotero documents from a synthetic library. Each
contains three active footnote citations and a bibliography.

From the CrispCloud checkout, run the native fixture harness with:

```sh
flutter pub get
dart tool/office_native_zotero_roundtrip.dart /path/to/native-refreshed.docx
dart tool/office_native_zotero_roundtrip.dart /path/to/native-refreshed.docx \
  /path/to/office-saved.docx
```

The second argument checks a file saved by an external app or modified by a
macro. The harness compares field kind, exact visible result and structured
metadata. It rejects empty and invalid field inventories.

For the VBA/citation interaction, run this locally authored BAS with the engine
CLI `run-word-vba` on a copy of `native-refreshed.docx`.

```vb
Sub Main()
    Dim result As Long
    result = 17 Mod 5
    ActiveDocument.Paragraphs(1).Format.SpaceBefore = result + 10
End Sub
```

The independent OOXML check expects first-paragraph spacing of 240 twips and
unchanged concatenated field instructions in the body, footnotes and endnotes.
The DOCX harness independently checks the field model before and after the edit.

The engine's `tool/zotero/transfer_acceptance.dart` verifies carrier restoration
after LibreOffice conversion. Its `tool/zotero/odt_roundtrip_acceptance.dart`
checks two LibreOffice saves with a CrispOffice DOCX cycle between them.
These tools use synthetic content and isolated LibreOffice profiles.

## Mac results

Installed LibreOffice 26.8.2.2 preserved all four exact fields in the native
refreshed DOCX. All three carrier routes restored the five active citations
and bibliography, including the DOCX → ODT → DOCX path. All five editable ODT
fixtures passed two actual LibreOffice saves and the intervening CrispOffice
DOCX save/reopen.

The VBA spacing edit preserved the four native fields and their OOXML
instructions. On the larger user-supplied Word file, its first default CLI
run reached the 30-second deadline and wrote no output. A diagnostic run took
30.9 seconds with an extended budget. A second run at the default budget
succeeded. Independent XML and ZIP checks confirmed 12-point spacing,
identical body text, and eight unchanged media parts on both successful runs.

The live CrispCloud connector completed an isolated Zotero refresh on both
8.0 beta 16 and 11.0 beta 5. The bibliography matched the retained native
reference. The Zotero instances selected English shortened Chicago notes,
whereas the reference used German subsequent-ibid notes selected interactively
in Zotero 10.0.8. A retry carrying the German preference record and with the
exact CSL style available reached the Zotero progress window and timed out
before publishing. This leaves exact live style parity open. Zotero applied
its pending beta update between the two runs. The isolated instance was
closed after validation.

Microsoft Word 16.111.1 answered version queries but timed out opening a
disposable DOCX and creating an empty document through AppleScript. There is
no fresh Microsoft Word VBA execution or Word save oracle in this record.

The 59 editor suites passed all 1,087 cases. Six focused engine suites passed
all 218 cases, and all 16 host transport cases passed using the pure Dart
runner. The host transport source and assertions were identical. The local
copy used the Dart test import and avoided unrelated Flutter native builds.

The broad engine replay reached 7,714 successful cases in a selection of 176
suites. It is an incomplete run because it stopped reporting progress and
was interrupted. Its four case timeouts passed in isolated reruns. The
engine replay used a temporary copy of the test driver with a shared CLI
kernel compiled from the pinned source, avoiding repeated CLI compilation.
The four timeout reruns changed the test runner budget. They did not change
the macro execution deadline. The sync unit tests passed all ten cases and
the manifest verified 3,367 tracked Office files against their pinned bytes.

## Microsoft Word follow-up

The original AppleScript timeout was caused by a Word file access dialog.
The native oracle now opens disposable fixture copies with macOS Open With
(`open -a "Microsoft Word"`) and stages every destination inside Word's
sandbox. AppleScript handles document operations after the file is open.
This works in a logged-in macOS session without clicking through file access
prompts. It closes its fixtures in a cleanup step, including after failures.
Use a dedicated logged-in user session for unattended batches.

```sh
~/miniconda3/bin/python tool/verify_word_roundtrip.py \
  --out build/word_verification /path/to/fixtures/*.docx
```

Microsoft Word 16.111.1 opened, saved, reopened and rendered four files:
the two native Zotero DOCX fixtures, the active transfer fixture, and the
larger user-supplied DOCX. The independent DOCX and PDF checks passed on
all four. The Zotero field comparison retained exact cached results and
metadata across 4, 4, and 6 active fields respectively in the three Zotero
fixtures. A separate Word object-model edit set first-paragraph spacing to
12 points and retained all four Zotero fields. The Word test documents were
closed and a final check found zero open fixtures.

Broader coverage can use the same inputs with Word and LibreOffice as
independent producers. Keep content/field comparisons separate from PDF
layout and from macro results. For a true native VBA oracle, add disposable
trusted DOCM files containing our own BAS modules and run their named entry
points in Word. Compare the resulting DOCX/DOCM semantics and preserved
package parts with CrispOffice's output. The spacing check above exercised
Word's object model through AppleScript.

The cleanup also passed an injected save failure after Word opened a fixture.
A subsequent Word query confirmed the failed fixture and all batch fixtures
were closed.

The newer Office intake at `a9bfc961a7efdf2c8da198108bd71174b91f89fd`
passed 415 cases in seven focused VBA suites, including its actual BAS
CLI compile/validate/run/replay test. The guarded mirror verifies all
3,401 tracked files. The Word roundtrip results above are independent of
this engine-only VBA gate.

## Broader converter and VBA recheck

CrispCloud's guarded mirror advanced to CrispOffice
`4cc604810fb2f41ac7ba04cbed65cb76300bff59`, the merge of PR #382. The
mirror verifies 3,435 tracked files. This intake includes the editable Zotero
converter paths and VBA `Split`. Its `Split` implementation is already present
through the accepted converter merge. PR #383 initially conflicted with that
upstream main in Mail account navigation and related tests. The update below
records its reconciled head.

The Mac passed 1,231 engine cases and 125 editor cases. These include the
`Split` BAS CLI, conformance, editor citation controls, import and refresh,
and the long adjacent citation chain. A separate run verified the 15 external
app scenarios individually:

- Installed LibreOffice performed two saves each from native DOCX and native
  ODT for body, table-cell, and footnote citations. All 12 fresh files matched
  the retained semantic snapshot, including colors, note ownership, editable
  fields, and preferences. They also matched after a CrispOffice DOCX reopen.
- Installed Word saved three matching story fixtures. Both citations in each
  file retained exact metadata and cached text, remained editable, and stayed
  in their original story with balanced fields.

The Word verifier saved, reopened, and rendered all 15 staged documents.
Six of 12 general corpus files passed every strict comparison after replaying
the corrected note marker check on the saved output. The other six exposed
dynamic reference caches, markup compatibility choices, content control
text extraction differences, note text extraction, or removed separator
stubs. The separate citation story set preserved its six editable fields even
though it also triggered strict PDF text or separator comparisons. These
comparisons distinguish an external app or verifier difference from a lost
citation. Word showed zero open test fixtures after both batches.

The reconciled PR #383 head, `8bbe17bc7d82964b67385aa796b7f43248c65149`, is
the final local mirror pin. It includes the Zotero formatting fix that keeps
invisible field-code formatting out of refreshed citation results. The
guarded inventory stays at 3,435 files. The exact head passed all 1,240
selected engine cases and 125 editor cases without failures or skips. The
engine total includes the 15 installed-app file comparisons.

The fresh-file comparison is now available in
`packages/quds_office_engine/tool/office_app_roundtrip_test.dart`. Run it from
the engine package after saving the three `original` fixtures in each format
through LibreOffice twice and the three original DOCX files through the Word
verifier. Point `CRISP_OFFICE_ORACLE_OUTPUT` at the output root. The runner
expects four LibreOffice folders under `fresh-converter`, named
`docx-cycle-1`, `docx-cycle-2`, `odt-cycle-1`, and `odt-cycle-2`. It reads the
three Word-saved DOCX files from `word-citation-stories`. Missing output is
a failure. The tool checks installed-app saves and their CrispOffice reopen
results. Live Zotero style parity and execution of VBA inside Microsoft Word
remain separate.
