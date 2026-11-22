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
