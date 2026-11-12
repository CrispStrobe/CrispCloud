# Separate source font slots

The parser previously kept only the ASCII `sprmCRgFtc0` face and wrote that
same face into all three `ascii`, `hAnsi` and `eastAsia` OOXML attributes. This
discarded independently authored East Asian/non-ASCII font choices. The
character model now retains the separate script faces, resolves their own STSH
defaults, and preserves them through direct runs, paragraph marks, character
style resets, list markers and explicitly masked table-style properties.

## Source evidence

[MS-DOC character properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18)
assign separate font-table indices to `sprmCRgFtc0` (`0x4A4F`, ASCII),
`sprmCRgFtc1` (`0x4A50`, East Asian), `sprmCRgFtc2` (`0x4A51`, other
non-ASCII) and `sprmCFtcBi` (`0x4A5E`, complex script). The corresponding
defaults come from [Stshif](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/0e246123-e907-4ad1-9dfc-558512e2b052)
and the optional `ftcBi` field in [STSHI](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/982c0460-4958-4f72-8cec-21b3ac15bd8e).

Direct inspection of the retained `formatting.doc` binary found font indices
4/5/4/6 in Normal's character properties. The source font table maps those
indices to `Cambria`, `ＭＳ 明朝`, `Cambria`, and an empty complex-script face.
The exact Normal property bytes are retained in [summary.json](summary.json),
and the complete unchanged DOC remains in the artifact archive. The source
text contains `東京`; the correction does not infer a font from a native DOCX
export or substitute a preferred installed font.

`LegacyWordCharacterStyle.scriptFonts` distinguishes independently resolved
slots from the existing single-face public API. An absent/invalid slot is not
silently replaced with the ASCII face. Invalid explicit indices retain the
existing unsupported-formatting warning. List markers without a source font
continue to inherit paragraph-mark formatting. Table-style output includes
only source properties in its explicit mask. Run equality now includes these
font choices, so runs with different script fonts cannot be merged.

## Tests and actual native result

**57 focused Dart tests passed**, including ten new source-driven font tests
and existing list precedence, table text, kerning, revision and structured
conversion suites. The full log is losslessly compressed in
`font-tests.log.gz`; its raw/compressed hashes are in the summary. The tests
cover separate STSH defaults, direct override/reset behavior, run boundaries,
three invalid-slot controls, marker inheritance, table masks and the retained
authored DOC.

The actual native `formatting` measurement completed with one repeat import.
Its full report, source, converted documents, PDFs, text, geometry and five
losslessly compressed raster pages are sealed here. The original source golden
still reproduces. With the font slots preserved, the parser output displays
the source `東京` text that this native binary render omits. Consequently the
whole-page word sequences differ and a corresponding-word displacement cannot
be reported for the initial comparison. The repeat parser render matches the
first parser render exactly. **This is source-property preservation, not an
exact native-rendering result or a claim that the earlier 11.902-point drift
has been resolved.**

The run records base commit `63eb2911156533d04f20946f6e62889eae8a22dd` with
the font implementation changes present in the worktree. Its exact measured
source/build fingerprint is
`0039500891f906544b6fa6e5a7ea239b0d28f18f92cd81e2e9a43f82c37aacc8`;
inputs were unchanged during compilation. The full compiler, executable,
LibreOffice, Poppler and installed-font identities remain in the report. This
receipt does not relabel the run as a clean-commit execution.

Verify the complete sealed measurement from the repository root:

```sh
python3 doc/evidence/native-corpus-7308125/verify_native_artifacts.py \
  --directory doc/evidence/script-font-slots-20261112
```

The verifier checks all 58 retained files and all five decoded raster pages.
The old [22-case receipt](../native-corpus-7308125/README.md), original inputs,
goldens and strict comparison rules are unchanged.

## Remaining boundaries

Font-language IDs and font-selection hints are separate source properties;
this bounded change does not implement them or full complex-script shaping.
The existing HTML preview still uses its single-face CSS path. Further layout
work must retain these source choices and attribute native renderer/default
differences separately. No renderer-specific font replacement, whitespace
deletion or compatibility-mode guess is introduced.
