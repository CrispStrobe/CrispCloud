# Shared native header textbox instances

The retained literal-source controls exposed two independent shapes with
`ClientTextbox=0x00010000` in normal and first-page headers, backed by one
`FTXBXS` text range. That record declares one shape and names shape 1025; shape
1026 independently refers to the same text. Neither shape has a next link.
The previous global uniqueness check rejected the entire document.

This is an explicit native interoperability recovery. The
[ClientTextbox definition](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3ea806f3-8ff6-4ce4-8cb2-3ba732af4ec4)
specifies the source range and continuation index, and
[FTXBXNonReusable](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5aaa54b6-f38c-440a-82b1-8d61beb95b31)
requires a count matching the linked chain. The recovery does not turn a
contradictory set of independent instances into a continuation chain.

## Bounds and representation

Recovery requires a declared singleton, index zero on every instance, exactly
one matching primary shape, no next-shape links, and a distinct actual
header/footer owner for every anchor. Duplicate indices in one owner, ordinary
body duplicates, missing primary shapes, multi-shape declarations, gaps, and
unsupported linked aliases still fail.

The model retains one parsed text story. `anchors` describes the primary
singleton and `replicaAnchors` records its independent placements; `chainLength`
remains one. Conversion emits the shared text in each corresponding header or
footer part and records all instances in `sharedHeaderTextbox` evidence.
Textbox deduplication and inline event cursors include the output part, so a
field in shared content remains editable in every instance. The parser reports
`recoveredSharedHeaderTextbox`.

## Independent observations

[The retained measurement](evidence/shared-header-textboxes-20261112/README.md)
compares the exact same native DOC inputs before and after the change.

| Control | Before import | After import | Geometry observation |
| --- | --- | --- | --- |
| Textbox anchored in a header paragraph | Failed on duplicate reference | Two editable header instances | Same text and relative table geometry; +0.35 pt absolute textbox offset |
| Textbox anchored in a header table | Failed on duplicate reference | Two editable header instances | Same text and relative table geometry; +0.35 pt absolute textbox offset |
| Explicit first/even/default header parts across three pages | Already succeeded with three independent source ranges | DOCX bytes unchanged | All three page variants retained; existing +0.35 pt offset unchanged |

The three-page control did **not** reproduce shared source identity: the native
bridge wrote three independent FTXBXS ranges. Its successful baseline import is
retained as a control, not presented as a newly repaired case. The two shared
controls have one displayed page; their otherwise inactive first-header
instances are checked directly in the editable package. No exact RGB claim is
made, and the existing table-containment indentation remains unchanged.

Portable regressions cover all six header/footer variant slots, one source
primary occurring after its replica, field-event replay in every part, the
three original native binaries, and malformed owner/count/link cases.
