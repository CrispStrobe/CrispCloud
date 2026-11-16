# Zotero references in Word documents

Open a Word document with F4, then choose **Insert → Zotero…** or the **Zotero**
button in the Insert ribbon's References group.

## Faster refresh with verified source identities

**Document → Refresh basic citations** fetches up to 1,000 distinct linked
sources in sequential requests of at most 50 per library. Repeated citations
share the same request, while personal libraries, group libraries and unsynced
local profiles remain separate even when their item keys match. For one library,
101 sources require three requests and 1,000 require twenty. Every requested
source and its CSL data must be present before any citation changes. Results
from all batches apply as one undo step. A changed document or insertion point,
a failed batch, an API pause, or closing the dialog discards staged results and
prevents further requests. More than 1,000 distinct sources are rejected before
fetching metadata.

Collection pages keep one entry per collection key. Renamed or repeated entries
update in place without losing the selected collection or selected references;
responses for an obsolete library or a closed dialog are ignored. See the
[large-library validation](validation/zotero-large-library-20261116/README.md).

Native **Refresh all with Zotero** now resolves field IDs directly and builds
note order once per field-list response. Later responses recalculate that order
after insertions, deletions and conversions. Existing protected-field and stale
document checks remain in place. See the [optimization qualification](validation/zotero-optimization-20261116/README.md)
for exact source pins, local tests and the engine benchmark's scope.

## Use Zotero's picker and format the whole document

In a native Linux, Windows or macOS build, open Zotero on the same computer and
choose **Document → Zotero desktop citation tools**. No online key or catalog
connection is needed for these controls:

| Control | Use |
| --- | --- |
| **Citation in Zotero…** | Insert using Zotero's native source picker and locator controls |
| **Document style…** | Choose the document's installed CSL style, language and supported note placement in Zotero |
| **Refresh all with Zotero** | Reprocess the complete supported citation sequence and bibliography together |
| **Bibliography in Zotero…** | Add or edit the document bibliography through Zotero |
| Citation menu → **Edit in Zotero…** | Edit that existing citation in the native picker |
| Library selection → **Insert with Zotero…** | Seed the native picker with linked sources selected in CrispCloud |

**Insert with Zotero…** is the primary desktop catalog action. If the document
has no selected style, it opens Zotero's style chooser first, then carries the
selected sources into the citation picker with the chosen inline, footnote or
endnote placement. The two stages become one undo step; cancelling either stage
or losing the connection keeps the document and source selection. The Document
tab shows the saved style ID, language and placement. You can choose **Document
style…** directly at any time, or use **Citation in Zotero…** without selecting
catalog sources.
If Zotero changes the note placement while opening a catalog seed, the result
is discarded and you are asked to select the style before retrying.

For German **Ebd.**, choose a German locale and a style that actually uses
*ibid.*; then use **Refresh all with Zotero**. Zotero controls repeated-source
logic, locators and punctuation. The checked real-processor example
`chicago-notes-bibliography-subsequent-ibid` with `de-DE` produces `Ebd.` for
the same source/page and `Ebd., 34.` for a changed page. The engine also uses
real-processor fixtures for numeric renumbering and author-year disambiguation.
Other styles can produce a different short form or avoid *ibid.*.

Document preferences are stored as native `ZOTERO_PREF_*` custom properties and
survive save/reopen. **Preview / export style ID** and locale belong to the
older individual-preview workflow; they do not change the native document style.

### Bibliography paragraphs and spacing

Use **Bibliography in Zotero…** for the bibliography controlled by the
document's native CSL style. Its entries occupy real Word paragraphs inside
one linked bibliography field. Structural entry breaks are kept separate from
soft line breaks within an entry. **Refresh all with Zotero** can add or remove
entries while retaining the field and neighboring text.

The native layout preserves body/first-line or hanging indents, line spacing,
spacing after entries and tab stops. These properties survive DOCX save/reopen,
refreshes without another layout callback, and undo/redo. They come from
Zotero's [`Document.setBibliographyStyle`](https://www.zotero.org/support/dev/client_coding/http_integration_protocol#documentsetbibliographystyle)
callback: indent, entry-spacing and tab values use twips; line spacing is
stored as an automatic line multiplier using the callback value divided by
240, matching Zotero's [bibliography parameter generator](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/cite.js).
The first-line indent is relative to the body indent, as described in
Zotero's [wire protocol](https://www.zotero.org/support/dev/client_coding/libreoffice_plugin_wire_protocol#document_setbibliographystyle).

This replacement supports only complete, contiguous bibliography paragraphs
owned by one field in a single block container. Surrounding prose, interleaved
blocks, ranges across cells or sections, outside bookmarks, comments,
hyperlinks, note references, embedded visuals, content-control wrappers and
locked/nested/opaque fields prevent it. Multi-paragraph citation replacement
remains unsupported, and a new citation cannot be inserted inside a bibliography
entry. An otherwise editable inline bibliography may retain the existing
protected plain-text path after an explicit formatting review; its surrounding
paragraph is not restyled.

For a bibliography flattened into one paragraph by an older version, use
**Refresh all with Zotero** or **Bibliography in Zotero…** to retrieve new
entry boundaries. A style-only callback or unchanged plain-text reply cannot
reconstruct those boundaries. The editor keeps the old layout, reports the
limitation and requests the native layout again later. The separate
**Document → Zotero bibliography** API review still uses one paragraph; choose
the native controls for entry paragraph layout.

### Small capitals

CSL small capitals now remain native Word formatting through refresh,
save/reopen and undo/redo, including mixed styles and explicit `normal` resets.
The source text keeps its authored case. The supported values follow the
[CSL formatting specification](https://docs.citationstyles.org/en/stable/specification.html#formatting).

The editor, formatted preview and PDF use synthetic capital outlines at
**0.8 times the run size** for lowercase letters, keeping existing capitals,
numbers and uncased text at their normal size. They do not select a font's
designed small-capital glyphs. Layout measures those displayed glyphs before
wrapping; caret positions stay at the original grapheme boundaries. PDF stores
the authored text in `/ActualText`, including when a display expands `ß` to
`SS`. DOCX retains native `w:smallCaps` for other word processors.

The fallback uses default Unicode casing, supplemented by [Unicode 17.0.0's
unconditional uppercase expansions](https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt),
without Turkish/Azeri/Lithuanian locale tailoring. A grapheme split across
separate run-format records keeps its original display. Unsupported variants
such as `all-small-caps` or `petite-caps` still require review before
simplification.

### Apply, cancel and note conversion

All changes are staged until the native operation succeeds. A reported desktop
error discards the staging even if Zotero subsequently sends its completion
message. The document, revision, caret and selection must still match. Applying
the result creates one undo step, including preferences, note changes and
bibliography updates. Undo restores the original selection.

Footnotes and endnotes participate in reading order, with ordinary notes counted
too. Conversion between inline, footnote and endnote is supported for a note
containing only its citation and optional whitespace/reference marker.
Explanation-bearing notes, multiple citations in one note or extra structural
fields refuse conversion. Supported citations in those notes can still refresh.
Automatic note labels now follow document order in the canvas, note bodies and
Notes pane, including after earlier insertion or conversion. Native link IDs
remain unchanged. Common decimal, letter and Roman formats, starting numbers
and section restarts are supported; custom marks remain authored text.
Page-based restarts and unsupported native number formats retain their settings
and use source-ID labels in the Notes pane; check those in the target word
processor.

Zotero may open its native window behind CrispCloud. Finish or cancel that
window to let a pending operation return. **Cancel operation** requests
cooperative cancellation; it does not abandon an unanswered desktop POST and
start another. A lost connection may require restarting Zotero. Native dialogs
can wait up to ten minutes. Requests are never automatically retried.

## Connect an online library and cite

1. Create a dedicated read-only API key at
   <https://www.zotero.org/settings/keys/new>. Enable personal-library and group
   read access only as needed. Public user/group libraries can be opened by
   numeric ID without a key.
2. Enter the key and choose **Connect**. The Library tab browses personal/group
   libraries, collections, and paged title/creator/year search results.
3. Select sources and choose **Insert with Zotero…** for the document's native
   style, or **Insert basic citation** for the offline author–year workflow
   (**Insert citation** in hosts without native transport). Review basic text,
   optional single-source Zotero style text, and each source's locator, label,
   prefix/suffix and author options before inserting.
4. Use the Document tab to inspect/edit citations, create a bibliography,
   refresh basic citations, export embedded CSL JSON, or explicitly convert a
   field to text. All document changes participate in undo/redo and save
   revisions.

Set the preview/export style ID and locale in Document (defaults: `apa` and `en-US`) before
requesting a bibliography or individual preview. Expand a source's title in the
citation composer to edit its locator and affixes.

For offline work, export references from Zotero as CSL JSON and paste the file
contents into **Import CSL JSON**. The importer accepts single items, arrays,
and the API's `items` envelope. Unlinked records retain embedded source data
without claiming to be present in a Zotero library. Selected linked references
from one matching library can be copied as BibTeX, BibLaTeX, RIS or CSL JSON. Use
**Document → Copy embedded CSL JSON** for a mixed-library or offline document.

## Use Zotero desktop without an API key

On Linux, Windows or macOS, choose **Reference library source → Zotero desktop
(this computer)** in the Library tab. Open Zotero and enable **Settings →
Advanced → Allow other applications on this computer to communicate with
Zotero**, then choose **Connect desktop**. Browse the local personal library,
locally available group libraries, collections, saved searches and search results. Local
browsing includes unsynced sources and works offline.

Choose **Saved searches** beside **Collections**, then choose a search from
the **Saved search** menu. **More searches** loads another page of saved-search
names. **Refresh saved searches** reloads the list after changes in Zotero and
asks you to choose again. **Search within saved search** adds a
title/creator/year filter to that search's results; normal pagination remains
available. Selected references survive view changes and can be inserted with
**Insert with Zotero…** or the basic citation action.

Zotero evaluates the saved conditions against the local library. Create or
change those conditions in Zotero; CrispCloud browses the results without
modifying the search. Notes and attachments are not offered as citation
sources. A deleted search clears stale results and asks you to refresh.
Saved-search execution is available only through a desktop version that
implements the [local `/searches/<searchKey>/items` endpoint](https://www.zotero.org/support/dev/web_api/v3/local_api).
The online API exposes search metadata but does not evaluate saved searches.

The connection is explicitly chosen and read-only. It goes directly to
`localhost:23119`, bypasses the selected remote proxy, and never receives your
online key. Changing the source does not make a request. Your remembered
online key remains available when you switch back; **Disconnect desktop** does
not delete it. A disabled local API gives setup guidance, and an unavailable or
changed Zotero database gives a safe reconnection error.

Signed-in sources keep their real account/group URI and support the existing
linked-reference workflows through the desktop API. Unsynced sources keep their
`users/local/…` URI in DOCX and imported CSL. If the desktop API exposes only a
citation key without a persistent URI, the editor explicitly embeds an offline
reference with a generated ID. The `/users/0` request alias never becomes a
saved citation URI.

Unsynced local links now also support **Refresh basic citations** and individual
style previews through the matching desktop library. Basic refresh requests
only metadata and CSL data, so it does not ask Zotero to load a citation style.
With Zotero 10 or later, selected-reference exports and **Zotero bibliography**
can also use those local links. A style absent from the desktop installation
may cause Zotero itself to fetch it for previews or formatted bibliographies.

The editor verifies the complete saved identity, including the local profile
key. Another database with the same item key cannot silently replace the
source. Original citation IDs, URI aliases, locators, affixes and unknown
metadata remain intact. Two local profiles are separate libraries even though
the local API routes both through `/users/0`.

Before export or formatted bibliography, the client verifies every selected
source in one bounded metadata request. It refuses missing, duplicate,
additional or mismatched records. Desktop aggregate output requires Zotero's
stable database identifier and an unchanged reported library version across
verification and formatting. If the database or reported version changes, the
result is refused and the document is left unchanged. This is a change check,
not a server-side snapshot transaction.

Older desktop versions can still browse, insert, refresh basic citations and
provide individual previews when their item response proves the saved identity.
For aggregate output with an older desktop, or a detached reference without a
persistent URI, use the basic bibliography or **Document → Copy embedded CSL
JSON**. A local link cannot be resolved by the online API; connect the matching
Zotero desktop library instead.

This catalog connection is available in native desktop builds. Native citation
commands use the separate HTTP Citing Protocol described above. See the official
[local API setup](https://www.zotero.org/support/dev/web_api/v3/local_api).

## Credentials and networking

The key is session-only by default. **Remember key when connecting** is offered
only when CrispCloud's selected credential store supports persistence. This
uses the existing secure-storage backend. Unchecking the option removes the
stored key immediately, and **Disconnect & forget** clears it and the session.
The in-memory connection is cleared when the Office editor closes.

Online requests reuse CrispCloud's selected proxy and TLS policy with HTTPS and
API-key headers. Desktop requests use a separate direct client with strictly
allowed headers and no credentials. Catalog requests refuse redirects, have a
20-second timeout and 8 MB response limit, and are closed when the editor closes.
Native citing allows POST only to the two fixed localhost connector routes,
with bounded JSON payloads and a longer native-dialog timeout. Errors do not include API keys,
response bodies or diagnostic dumps. Keys never enter document metadata or
reference exports. Catalog access is read-only; native citation commands let
Zotero process the document through its own integration service.

## Formatted bibliographies and citation preservation

Choose **Document → Zotero bibliography** to review a formatted result before
inserting it. **Keep Zotero formatting** preserves bold, italics, underline,
strike-through, superscript, subscript and small capitals as native Word formatting. Numeric
labels stay beside their bibliography entries. Turn the option off to edit and
insert the text explicitly as plain text. Cancelling leaves the document
unchanged. The reviewed result also refuses insertion if the document or caret
changed while it was open.

Small capitals are preserved with the synthetic-display limits described above.
This API review still simplifies hanging indents, paragraph spacing,
multi-column margins and arbitrary paragraph CSS, with known limitations shown
before insertion. Entry order and line breaks are retained in one paragraph.
Use native **Bibliography in Zotero…** for the entry-paragraph layout described
above. Links are inert text; external
resources and active content are never loaded. Malformed formatted output is
refused rather than silently replacing a field.

Rich bibliographies can be saved, reopened, updated and undone/redone. Rich
replacement requires a complete bibliography paragraph without surrounding
text or outside structural markers. The plain-text workflow remains available
for other editable fields.

Imported citations with several styled runs now keep their Zotero link,
metadata and styles through DOCX saves, including Word simple fields. Numeric
citation results and the locator label `page` are no longer confused with a
Word page-number field. Editing a citation without changing its visible text
keeps its rich result and processor-specific formatting metadata. The composer
shows the actual field cache even when imported plain-text metadata is stale.

## Scope and preservation

New citations use complex DOCX fields following Zotero field-code conventions
and embed CSL source snapshots. Imported Zotero field JSON, cached text, and
native document preferences are preserved on ordinary saves. Locked, nested and
opaque replacements are refused; multi-paragraph replacement is limited to
complete native bibliography ranges. Explicit unlink retains text.
Track-changes mode and unresolved revisions in affected paragraphs also guard
reference edits. A changed document, caret, story or selection invalidates an
asynchronous insertion instead of targeting a different place.

Basic author-year formatting is an offline fallback. Zotero's individual
citation preview is not a full document-wide CSL run. Complete connected
bibliographies use one identity-verification request followed by one formatted
request for at most 50 distinct sources in one library, then are reviewed with
the rich-formatting or plain-text choice described above. Larger/mixed-library
sets can use the basic bibliography or CSL export. Refresh updates Quds basic
citations for at most 1,000 distinct linked sources atomically; imported and
custom-style caches are left alone. Bibliographies with imported nonempty
`uncited`, `omitted`, or `custom` settings refuse both basic and online updates
to preserve those choices. Use Zotero's native bibliography controls to manage
those choices.

The desktop adapter now delegates complete CSL processing to Zotero, including
style-dependent numbering, disambiguation and *ibid.*. Native processing marks
its citations separately so **Refresh basic citations** cannot overwrite them.
Uniform and mixed inline character formatting, including italic titles, bold
text, superscript and small capitals, remain inside one protected citation field. Typing,
deleting, copying, pasting and splitting paragraphs preserve the complete linked
field. Unsupported character variants and layout outside the native bibliography
contract are simplified only after a review explains the change. Rich bibliography runs retain their
supported character formatting.

Document-wide native processing refuses active Track changes, any unresolved
revision, protected documents, uneditable Zotero fields and citations in
unsupported stories such as headers, footers, comments and text boxes. This
keeps Zotero from processing a silently incomplete citation sequence.

ODT active-citation transfer, font-designed or locale-tailored small capitals,
arbitrary bibliography CSS and page-based note restarts remain implementation
boundaries. In the previous continuation, the Quds catalog/Studio transport and
citing driver/Word adapter passed live desktop
Zotero style-selection, refresh, first-use seeded picker acceptance and DOCX
save/reopen checks with synthetic sources, including German `Ebd.` and page
locators. Native locator-popup editing remains outside the successful live
acceptance scope; the seeded locator was accepted and preserved. Protocol, controller and UI
regressions also use deterministic transports and pinned real CSL fixtures.
This increment's shared Quds source has separate completed qualification and
live acceptance: running Zotero 10.0.8 verified saved-search evaluation/query
scoping and four native refresh transactions across German Chicago and a
synthetic small-capital/double-line style, including DOCX reopen. The
[Quds feature overview](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-support-20261116/docs/validation/zotero-fidelity-20261116/README.md)
links the exact source, protocol receipts and before/after files. This is an
integration-component exercise through the actual Studio transport; it does
not claim a compiled CrispCloud application run.
Full compiled application builds, private-account/keychain acceptance and
opening the exported DOCX in Microsoft Word or LibreOffice remain separate
acceptance steps. The native app talks directly to localhost without a
server-side proxy.

## Shared source and local checks

The implementation is maintained in
[Quds Office](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-support-20261116).
`tool/office_fidelity_manifest.json` records the exact immutable Quds source and
hashes of managed files. Its standalone legacy DOC parser pin is unchanged.

The previous continuation started after Quds #47, CrispCloud #149 and terminal
#140 work was merged. Before its feature edits, all **60 branch heads and 198 PR
heads** were accounted for. Its final incoming-work snapshot at **16 November
2026, 05:17:13 UTC** accounts for **62 branches and 199 PR heads**. It includes
the new terminal #160 at `49d63f78d0b854ba76289dba69fdb6584f8a1260`, with both
merge parents retained. All 259 external refs are actual ancestors; the two
continuation branches are listed separately. Later concurrent commits are
outside that explicit cutoff.

Work is saved incrementally to `codex/zotero-support-20261116` in both
repositories. Every new checkpoint uses `[skip ci]`. No GitHub Actions are
queried, polled, awaited or rerun.

Local execution uses official Flutter/Dart and genuine locked dependency
graphs. Recorded evidence covers protocol, native preferences, the document
adapter, controller, UI and actual host transports. See
[zotero-validation.md](zotero-validation.md) for exact tested source identities,
current results, reproducible commands and the remaining native acceptance limits.
