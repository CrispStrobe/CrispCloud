# Textbox range separators and intentional blank paragraphs

[MS-DOC §2.8.32 PlcftxbxTxt](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/9f17f89a-64d6-4546-a811-e62e1d238102)
and [§2.8.23 PlcfHdrtxbxTxt](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/efaa9508-5dcb-4bcb-8468-87939ea34181)
define a final CR separator in each real textbox range. The final reusable range
is separately ignored. [FTXBXS](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d0a81fe8-f9e8-4130-9233-84732e3d9420)
requires the endpoints of a real range to be more than one character apart.

The parser validates the same raw ranges, final CR, shape references and chain
links, then excludes exactly the separator from the editable story. It does not
trim all trailing paragraph marks. A literal `ALPHA\r\r` range contains one
paragraph; `ALPHA\r\r\r` contains that paragraph and an intentional blank. The
minimum `\r\r` range retains one empty paragraph, including in a header textbox.
The content's paragraph-mark formatting remains attached to the content mark.

## Verification

The isolated increment passes 638 Dart tests and 108 Python tests. Twenty-two
new Dart controls cover both story kinds, empty boxes, leading/interior/trailing
blanks, adjacent ranges, reusable slots, linked frames, content-mark formatting,
invalid ranges, field boundaries and the retained Word14 file. The full package
analysis is clean. Existing compact and extended native linked-chain tests pass.
No completed native resize receipt is claimed for this increment.

`tool/fidelity/textbox_boundary_fixture.dart NEW_DIRECTORY` emits 14 literal
binary DOC controls and converted DOCX files. These are deterministic: all 29
files, including the expected-case manifest, repeat byte-for-byte. The
[independent SDK receipt](evidence/textbox-boundary-schema.json) records zero
schema errors for all 14 DOCX outputs, including empty main/header boxes. The
validator's positive and negative controls pass. Their minimal binary drawing
scaffolding is suitable for parser regression tests; LibreOffice ignores those
minimal shapes, so those DOCs are not presented as native rendering oracles.

`tool/fidelity/textbox_boundary_probe.py` instead authors literal OOXML controls
without this parser or writer. It compares the seven independently specified
paragraph sequences with native DOCX → DOC → DOCX and DOC → parser routes.
All seven main-story controls retain their authored paragraphs in both routes.
The probe selects one supported Markup Compatibility branch and still counts
independent duplicate boxes; it does not deduplicate boxes by text. Four Python
tests check that distinction and reject missing boxes or missing empty paragraphs.

The [complete native receipt](evidence/textbox-boundary-native.json.gz) retains
the seven header import failures below and exits nonzero for those failures.
It records exact source hashes, renderer/compiler identities and the separate
before-converter receipt. Its source base is `34e1484` with the then-uncommitted
separator correction explicitly marked dirty, rather than claiming a clean
commit contained that edit.

## Word14 result and remaining layout differences

The retained `word14-margin-origin.doc` has six real ranges, each containing a
content paragraph mark followed by its separator. Before correction the parser
wrote two paragraphs per textbox. After correction it writes one per textbox,
matching all six uniquely labelled native paragraph sequences. Native export
orders two independent boxes differently; the receipt retains that order
difference instead of treating traversal order as paragraph loss.

| Native frame projection | Before correction | After correction | Native DOC reference |
| --- | ---: | ---: | ---: |
| Basic Color Fill height | 46.20 pt | 38.15 pt | 38.85 pt |
| Pattern / one-color / two-color / texture heights | 46.20 pt | 33.40 pt | 22.15 pt |
| Picture Fill height | 90.75 pt | 90.75 pt | 91.45 pt |

The extra paragraph is removed and its height inflation is reduced. The page
remains one page, but exact rendered text/geometry/RGB comparisons are still
red before and after the correction. The remaining frame dimensions, wrapping,
placement and paint differences are not certified by this paragraph-boundary fix.

## Retained native header failure at the separator checkpoint

The subsequent [header-alias increment](header-textbox-aliases.md) handles the
bounded normal/first-header case below. The original red fixture and receipt
remain unchanged so the earlier failure is reproducible.

The separately authored default-header control survives the native bridge with
the expected paragraph sequence, but its binary drawing references are rejected
by both the unchanged `34e1484` converter and the patched converter. The exact
[DOC input](../test/fixtures/word_native/header-textbox-duplicate-chain.doc),
[authored DOCX](../test/fixtures/word_native/header-textbox-duplicate-chain-source.docx)
and [source receipt](../test/fixtures/word_native/header-textbox-duplicate-chain-source.json)
are retained. This was a red fixture at the separator-only checkpoint.

The duplicate occurs across **distinct header ranges**. Header-relative CP 2
anchors shape 1025 in the normal header's raw range `[2,5)`; CP 5 anchors shape
1026 in the first-page header's raw range `[5,8)`. Both shapes store
`ClientTextbox=0x00010000`, meaning the same FTXBXS index and chain index zero.
`PlcfHdrtxbxTxt` contains only one real FTXBXS, with `cTxbx=1` and `lid=1025`,
followed by its spare. The duplicate-chain guard therefore rejected the second
shape. The separator increment did not invent a link, a second text range, or
independent ownership for that alias. The later recovery has separate native
activation controls and retains the ordinary chain guards.

To reproduce the native measurements, supply the native office executable and
Dart. A saved baseline converter and its hash-bound source receipt are optional:

```sh
python3 tool/fidelity/textbox_boundary_probe.py \
  --office /path/to/soffice --dart /path/to/dart \
  --output build/textbox-boundary-native
```

This historical probe compares a single box across the entire package. Use the
separate header-alias probe above for the later two-occurrence semantics; the
historical result remains red rather than silently changing its assertions.
