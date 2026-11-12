# Fidelity status and remaining acceptance gaps

This is the support boundary for the eight requested fidelity areas. **Editable
conversion** means supported properties become native DOCX/DOCM structures.
**Portable preview** means the package can display a bounded subset without an
Office engine. **Retained evidence** means original bytes or decoded metadata
remain inspectable; it does not mean that content is editable or rendered.

The [measured results](fidelity-results.md) report the recorded source revision,
fixtures, renderer, fonts, semantic comparisons and visual differences. Exact
rendering is a result for that environment and input, not a property inferred
from a feature name or a passing parser test. The
[oracle contract](fidelity-oracles.md) separates authored-OOXML-to-DOC bridge
changes, package conversion changes, native rendering and a second import.

## Exact pagination

**Implemented:** editable page and section geometry, equal/unequal columns and
their direction, explicit breaks, paragraph pagination controls, line/page
numbering, document grids, note placement/numbering, source compatibility flags
and character kerning thresholds. The writer does not invent paragraph breaks
to freeze a printer's pages. See [layout](layout-fidelity.md),
[notes](note-settings.md) and [kerning](kerning-fidelity.md).

**Independent checks:** binary-to-XML assertions in the
[layout](../test/legacy_word_layout_test.dart),
[compatibility](../test/legacy_word_compatibility_test.dart) and
[kerning](../test/legacy_word_kerning_test.dart) tests; native source/conversion
page-word, word-box and raster comparisons; reviewed source-render goldens.

**Remaining acceptance gap:** matching XML, text or page count does not establish
identical pagination. Font substitution/shaping, wrapping, fields, tables,
notes and Office versions still affect layout. Exactness requires matching page
dimensions, per-page content, positions and rasters for the recorded environment.
A matching *source* golden only confirms the source-render baseline. Microsoft
Word pagination has not been validated here.

## Arbitrary OfficeArt geometry and effects

**Implemented:** editable simple VML presets and explicit move/line/cubic/close
paths, source positioning, signed rotation, flips, direct solid colors/opacity,
line styles and simple offset shadows. Picture output retains supported
DrawingML transforms, crop and effects. Referenced OfficeArt bytes remain
evidence. See the [media contract](media-fidelity.md).

**Independent checks:** independently assembled OfficeArt records and parsed
output XML in [geometry](../test/legacy_word_officeart_test.dart) and
[conversion](../test/legacy_word_officeart_conversion_test.dart) tests, plus
authored native corpus controls.

**Remaining acceptance gap:** arbitrary guides/adjusted presets, unsupported
path escapes, grouped transforms, gradients/patterns, unresolved palette colors,
wrap contours and perspective/3D effects are not complete. Retained records do
not imply active geometry, and editable VML does not imply an equivalent HTML
preview. Each added geometry/effect needs independent native position, shape
and raster checks; no universal OfficeArt fidelity is claimed.

## Metafile rendering

**Implemented:** bounded referenced EMF/WMF decoding and validation, byte-exact
eligible native image parts, and SVG playback for supported state/transforms,
solid/null pens and brushes, lines, polygons, rectangles, ellipses and supported
curves. Unsupported rendering records disable the portable SVG for the whole
metafile rather than silently skipping visible operations. Active escape-bearing
metafiles remain inert. See [media](media-fidelity.md) and
[HTML preview](html-preview.md).

**Independent checks:** [record validation](../test/legacy_word_metafile_test.dart),
[SVG playback](../test/legacy_word_metafile_render_test.dart),
[authored corpus](../test/metafile_corpus_test.dart) and
[cross-story preview bounds](../test/legacy_word_html_media_test.dart), plus
[JavaScript media acceptance](../tool/media_web_acceptance.dart).

**Remaining acceptance gap:** this is not a complete GDI renderer. Text/font
operations, clipping, raster operations, palette/pattern behavior and unsupported
mapping modes need further work. Original native bytes can remain usable when
portable playback is unavailable. Aggregate preview budgets can replace images
with placeholders without removing the assets from the model or preventing DOCX
conversion. Neither byte preservation nor geometric SVG playback proves native
pixel equality.

## Complex or conditional table styles

**Implemented:** nested cell blocks, bounded depth-specific markers, inherited
table/paragraph/character style properties, ordered style resets and conditional
bands, edges and corners. Resolved borders, shading, margins, signed origins,
shared grids, merges, row height/header/split controls and alignment become
editable current-cell properties. See [tables](table-and-list-fidelity.md).

**Independent checks:** authored binary
[nested-table](../test/legacy_word_nested_tables_test.dart),
[conditional-style](../test/legacy_word_table_styles_test.dart) and
[origin/grid](../test/legacy_word_table_origin_test.dart) tests; independent XML
oracle mutations detect changed conditional regions, flattening and cell merges.

**Remaining acceptance gap:** the source reusable table-style definition is not
recreated; later editing does not dynamically reapply its conditional rules.
Floating placement, cell spacing, percentage sizing, text rotation/fit/nowrap,
backdrop shading and some border effects remain partial. Native bridge loss of
note tables is recorded as bridge disagreement, not copied by dropping cells.
Broader style/geometry combinations need semantic and native layout acceptance.

## Linked-textbox reflow

**Implemented:** validated source story/shape chains, editable linked VML boxes,
text stored once in the first box, and supported positions, insets, anchoring,
flow, fit and wrapping. Successor boxes link to that story; the writer does not
duplicate text or guess line breaks. See [textboxes](textbox-fidelity.md).

**Independent checks:** [chain graphs](../test/legacy_word_textbox_chain_test.dart),
[layout properties](../test/legacy_word_textbox_layout_test.dart), the
[pinned native source](../test/legacy_word_native_textbox_test.dart) and its
independent word-box/raster path. The narrow kerning receipt is explicitly scoped
to its source, font and LibreOffice build.

**Remaining acceptance gap:** reflow belongs to the receiving Office engine.
Nonrectangular regions, unsupported text directions/margins/effects and overflow
across pages are not fully reconstructed. Matching one chain does not establish
all-box flow or all-version pagination. Additional consumers need per-box text,
word positions, overflow and page-boundary checks under recorded fonts.

## Threaded/ink comments

**Implemented:** comment text/ranges/authors and validated binary reply trees
become native comment parts. `commentsExtended.xml` joins each comment's last
paragraph, including a required terminal paragraph after a table. Hidden/private
parents keep their reply branches inert. The original extended record and ink
flag remain evidence. See [comments](revisions-comments.md).

**Independent checks:** independently assembled binary records and ZIP/XML
joins in [comment-thread tests](../test/legacy_word_comment_threads_test.dart);
the [structural oracle](../tool/fidelity/test_structure.py) detects changed
parents, annotation metadata and thread associations.

**Remaining acceptance gap:** the binary record does not encode a resolved/done
state; no `w15:done` value is inferred. The ink flag is not decoded pen-stroke
data or rendered ink. Modern collaboration identities and mentions are not
reconstructed. Native Word's threaded-comment UI and ink playback still need
acceptance; an OOXML oracle's ability to compare resolved state is not evidence
that the binary parser supplies that state.

## Some list-continuation behavior

**Implemented:** bounded source-order counters, compatible shared-LSID
continuation, unmodified-instance aliases, explicit restart/resume values,
multilevel restart thresholds, ancestor identity, marker formatting and story
isolation. Output uses editable numbering instances rather than literal prefixes.
See [list semantics](table-and-list-fidelity.md).

**Independent checks:** [sequence](../test/legacy_word_list_sequences_test.dart)
and [alias/continuation](../test/legacy_word_list_continuation_test.dart) binary/XML
tests, numbering-graph oracle mutations, and the pinned
[native receipt](list-sequence-native-check.json). Its complete source/output
labels are `1, 2, 3, 4, 5` for continuation and `1, 2, 7, 8, 3, 9` for an explicit
restart followed by resumed instances. Marker agreement is separate from layout.

**Remaining acceptance gap:** first-occurrence `fStartAt` ordering and the
excluded-current-paragraph rule have unresolved specification ambiguity.
Incompatible base starts/restart policies and ambiguous combinations remain
reported. Minimal multilevel/formatting fixtures are not full native
interoperability evidence. More independently authored producer/consumer cases
are needed before removing these limitations.

## Full revision semantics

**Implemented:** insertion/deletion provenance, paragraph-mark state and one
previous supported character/paragraph/section formatting snapshot become native
revision markup. Missing metadata stays missing; unrepresentable section-break
history stays disclosed evidence. A narrowly recovered unformatted terminal
mark remains unknown rather than being called unrevised. See
[revision semantics](revisions-comments.md) and
[terminal-mark recovery](terminal-mark-formatting.md).

**Independent checks:** [character/paragraph](../test/legacy_word_revisions_test.dart),
[section](../test/legacy_word_section_revisions_test.dart) and
[terminal-mark](../test/legacy_word_terminal_mark_test.dart) binary/XML tests;
independent accepted/rejected text projections and prior-state/author mutations.

**Remaining acceptance gap:** table/row/cell history, moves, list/display-field
revisions and multi-step edit history are incomplete. Document-wide tracking,
review visibility, annotation-date removal and editing/write-protection policies
are not reconstructed; the [policy-gap table](revisions-comments.md#document-tracking-review-and-protection-settings)
states the resulting defaults. Preserving existing revision records does not
preserve future tracking or restrictions. Native Word accept/reject behavior,
complete topology/numbering outcomes and Open XML SDK validation have not been
established by the semantic tests.

## Acceptance required for broader claims

Each extension needs independently authored source records, expected parsed
semantics, independent XML checks, malformed-input boundaries and a native
source/conversion/second-import comparison. The
[measurement runner](../tool/fidelity/run.py) records source and output hashes,
renderer/tool/font identity and unchanged input; its exactness checks do not
turn bridge losses into accepted parser behavior. Consult the
[results report](fidelity-results.md) for measured matches and mismatches rather
than treating this support inventory as a pass certificate. No Microsoft Word
execution or Open XML SDK validation run is implied by links to their format
documentation.
