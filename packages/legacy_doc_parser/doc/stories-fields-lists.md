# Referenced stories, fields, bookmarks and paragraph formatting

The parser follows the selected `0Table`/`1Table` stream, the CLX piece table,
and the document's reference tables. It does not recover a header, note, shape,
or field by scanning unreferenced compound-file bytes for plausible content.
Malformed ranges, dangling references, inconsistent markers and cyclic or
ambiguous relationships produce `FormatException`.

## Public content model

`LegacyWordDocument.blocks`, `plainText` and `safeHtml` continue to describe only
the main story. `stories` contains formatted auxiliary content. Every start,
end, anchor, bookmark and field CP is a **document-global UTF-16 code-unit
position**, with an exclusive end. A paragraph's end includes its terminator.
Header/footer guard paragraph marks are excluded from story contents.

| Content | Reference source | Exposed information |
| --- | --- | --- |
| Headers and footers | `PlcfHdd`, section order | Section index and even/normal/first type; empty inheritance slots are omitted, explicitly blank stories remain present |
| Footnotes and endnotes | Paired reference/text PLCs | One-based note ID, main-story anchor, note story, automatic or custom mark |
| Comments | `PlcfandRef`, `PlcfandTxt`, owner strings, annotation bookmarks, optional `AtrdExtra` | Anchor, range, author, initials, wall-clock date, validated reply parent and ink flag |
| Textboxes | `PlcftxbxTxt`/`PlcfHdrtxbxTxt`, FSPA and OfficeArt identifiers | Referenced story, first shape/anchor, declared chain length, validated per-shape chain indices and next-shape links |
| Bookmarks | Name STTB, start PLC and indexed end PLC | Name, global range, optional inclusive first/last table-cell selection |
| Complex fields | Logical field markers and corresponding `Plcfld` records | Original instruction, cached result, type, parent, global range, separator, locked/dirty/private flags |
| Numbering | `PlfLst`, appended LVLs and `PlfLfo` | Per-level formats, text templates, styles, indents, suffix, legal/restart rules, and start/format overrides |

Stored header parts do not enable a header variant. `evenAndOddHeaders` comes
from `DopBase.fFacingPages`, and `LegacyWordSection.titlePage` comes from
`sprmSFTitlePage`. Consumers must use these settings independently of which
even-page or first-page stories are stored.

Comment and revision timestamps contain source wall-clock fields without a
time-zone assertion. Their Dart `DateTime` representation is a container for
those fields; conversion must not infer that the original document recorded
UTC or a local offset.

## Fields, visibility and revisions

Fields are never evaluated. A TOC, REF, PAGEREF, PAGE, embedded-object field or
external-link instruction is source metadata, not a request to update content
or access a URL. Nested field instruction slices can contain original field
control characters. They must not be copied directly into XML or HTML.

Visible main/story text uses stored field results and omits instructions.
Private cached results are omitted from the block/run model and HTML while
remaining explicitly marked in field metadata. Hidden character runs remain
in the model but are omitted from generated preview text/HTML. Insertions and
deletions retain their state instead of silently producing an accepted view.

Media occurrences and note/comment anchors carry presentation metadata for
hidden content, insertions, deletions and revision authors/dates. Field
instructions and private cached results also mark those occurrences hidden.
Auxiliary story contents remain available for source inspection; a consumer
must not expose a hidden note/comment story by blindly rendering every entry
in `stories`. The package writer suppresses these active references and keeps
the recoverable information as inert evidence.

## List interpretation

The FIB length for `PlfLst` excludes the LVL array that follows its headers.
The parser reads the exact referenced level count, then resolves each LFO to
its LSTF and applies its individual level overrides. It retains the original
`lsid` as `sourceListId` and the paragraph's signed `ilfo` as `listId`.

Each LVL's own MSONFC format and explicit placeholder positions are used.
Marker character formatting does not become paragraph text formatting.
List paragraph formatting is applied in its specified cascade order.
Negative `ilfo` values preserve the paragraph's own logical left/first-line
indentation. The no-list sentinel and skipped level do not become fabricated
list numbering. Literal bullet characters and their font metadata remain
unchanged; the parser does not guess a different bullet glyph.

`restartAfterLevel` uses the OOXML one-based restart threshold: zero means no
restart and null means the default preceding level. Distinct LFO instances
sharing one `lsid` can continue a common sequence; this currently produces an
explicit `numberingNotReconstructed` warning for consumers that cannot
reconstruct that continuation. Generated preview HTML includes labels for
common decimal, Roman, alphabetic and bullet formats, using the source
definition, level and restart metadata. Less common formats remain explicit
approximations. The full definition/override metadata is available to the
DOCX writer; generated labels do not modify source `plainText`.

## Tabs, borders and shading

Character runs retain every defined `Kul` underline style as an exact
`underlineStyle` name, alongside the compatible `underline` boolean. This
includes words-only, double, dotted, dashed and wavy variants and their heavy
forms. Run coalescing, style inheritance and plain-format resets account for
the underline kind. The DOCX writer preserves the exact value; HTML uses its
closest supported decoration and marks approximations.

Paragraph custom tab stops are resolved through the same style/direct-format
cascade as other paragraph properties. Both tab-change operands are supported,
including their deletion tolerance, separate close-distance array and extended
length form. The model retains each stop's position, alignment and leader.
`defaultTabStopTwips` comes from the document's options; a missing or zero
stored interval is not replaced with an invented source value. Source tab
characters remain literal tabs in runs.

Legacy and modern paragraph border operands retain independently resolved
top, left, bottom, right, between and bar sides. The model records the fixed
border style, width, color, spacing, shadow and frame flags. The old bar-border
property has no visual effect; it remains metadata. Consumers must also obey
the source rules that ignore shadow on top/left borders and frame on sides
other than bottom/right.

Paragraph and table-cell shading retain separate foreground and background
colors, the raw pattern value and its exact OOXML pattern name when one exists.
Clear shading uses its background; solid shading uses its foreground. The
parser supports legacy palette shading and the modern row arrays for cells
1–22, 23–44 and 45–63, with explicit reset semantics for trailing omitted
entries. Valid legacy percentage patterns without an OOXML equivalent have a
null mapped pattern and an `unsupportedFormatting` warning. Conditional table
styles are not reconstructed; a raw shading entry that defers to such a style
remains explicit and produces the same warning.

The DOCX writer emits supported tab stops, paragraph borders and paragraph/cell
shading as editable Word properties. HTML previews approximate tab positioning,
pattern fills and complex border layout; their source metadata remains in the
model. These properties do not make the preview a pagination engine.

## Boundaries and remaining limitations

The implementation shares its CP-to-FC, CHPX/PAPX, terminal-paragraph mark,
style/PRM cascade, table and revision logic across all referenced stories.
It has no separate permissive text decoder for auxiliary content.

Limits include 4 Mi UTF-16 units for the main story or one auxiliary document
part, 8 Mi units in total, 50,000 paragraphs, 200,000 runs/media spans, 20,000
referenced stories and fields, 64 nested fields, bounded list definitions and
levels, and 64 MiB combined generated preview HTML. Individual HTML fragments
retain the renderer's smaller per-fragment limit. Property expansion and
application budgets continue to apply across all stories and numbering.

The model is not a Word pagination engine. It does not certify exact line or
page breaks, note numbering/placement settings, linked-textbox reflow,
threaded-comment/ink rendering, arbitrary legacy property revisions or
conditional table styles. Unsupported formatting is reported. See
[media-preservation.md](media-preservation.md) for
supported picture/shape/OLE/VBA/signature extraction and preservation limits.

## Validation

`legacy_word_stories_fields_test.dart` uses independently assembled binary
references with logical stories deliberately stored in a different physical
order. It covers formatted notes, header inheritance and guard marks, inactive
header variants, comment range/name relationships, textbox anchors, nested and
private fields, bookmark end indices, and rejected malformed references.
`legacy_word_lists_test.dart` covers per-level formats, appended LVLs, LFO
overrides, marker-only formatting, style inheritance, signed list indices and
malformed definitions. `legacy_word_decorations_test.dart` covers tab inheritance,
extended operands, descriptor/range limits, default tab intervals, border-side
cascades, exact shading colors/patterns, all three cell-array ranges and malformed
operands. The writer's independent binary fixture checks these properties through
DOCX serialization. `legacy_word_underlines_test.dart` covers the complete
defined underline enumeration, invalid gaps, style reset and adjacent-run
separation. Existing bounds/cascade/revision tests remain active.
The media suite also parses the authored real `formatting.doc` fixture through
this same structured parser.

## Primary specifications

The new story, field, list and decoration modules are independently implemented from the
Microsoft Open Specifications. Existing JSDoc-derived core traversal retains
its separate 0BSD provenance in the package notices.

- [Headers and inheritance (MS-DOC 2.3.3)](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8465bee7-6c79-45a9-812e-58b0c5fd6cdc)
- [Document options and header activation (DopBase)](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f885b87a-15b3-460e-aecc-213bd17f960e)
- [Section properties, including title pages](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e)
- [Footnote references](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3ed81d85-ea74-4790-8579-ab7f8eb651f7) and [footnote text ranges](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b30472e7-569e-4c9c-a8ca-07fd5432f365)
- [Comment references](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/9d82ca25-ff21-488c-bee2-dd654935c65a) and [extended comment records](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/19181fe7-a62a-4e70-9a5f-a0cb1ebe0921)
- [Textbox records](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d0a81fe8-f9e8-4130-9233-84732e3d9420) and [OfficeArtClientTextbox references](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3ea806f3-8ff6-4ce4-8cb2-3ba732af4ec4)
- [Field PLCs](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/751b09bb-72f0-45ef-8e87-666dea68219f) and [end-marker flags](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/28ab752b-055a-4725-8797-159bba0d125c)
- [Bookmark begin records](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/4dfad7b0-37bb-443a-8933-3bb79d2c5994) and [column selections](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b59cbd01-2391-4b70-994c-b58104d3f4c0)
- [List formatting algorithm](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1a0bc623-211f-44f6-828b-51993f16e586), [LVLF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/500d1b05-cd15-46af-bc8f-03bc290d1bdd) and [LFOLVL overrides](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2555c6ec-604b-48fd-8484-a2fdbb95b42c)
- [MSONFC to OOXML number-format mapping](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/57c8f7d4-1426-44e0-b58d-6fa1a5a81659)
- [Tab-change operand and extended length](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/0fa864c2-4660-402f-b726-3e9895748a49), [close-distance deletions](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/908cede7-b294-471a-afe8-add61f2078e7) and [tab descriptors](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d61a8147-7c7e-42f8-8bdd-226e6a82ec4e)
- [Modern borders](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5d99e9e0-d7a4-488a-91fb-6c046277e076), [legacy borders and ignored flags](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/cfab8014-e477-4e33-b50f-a23b8476f6f3) and [border-type mappings](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/6d25d117-9fa4-42ed-af5b-672771a9d1be)
- [Shading foreground/background](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/cee0b9de-272e-4898-994c-bae4627e5abb), [legacy shading](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46589ef4-c686-4ff6-ad84-82c15d631491) and [pattern mappings](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3f7d0bde-4e59-4395-a6d6-a1242c577e3f)
- [Cell-shading array bounds and ranges](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d415bdd8-63cb-44b9-941b-4999430d6ac9) and [table-property semantics](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469)
- [Kul underline styles](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f6d2ad93-87cf-4e46-a992-a38ccf2ef295) and [WordprocessingML underline values](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.underlinevalues)
