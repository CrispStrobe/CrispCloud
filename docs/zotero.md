# Zotero references in Word documents

Open a Word document with F4, then choose **Insert → Zotero…** or the **Zotero**
button in the Insert ribbon's References group.

## Connect and cite

1. Create a dedicated read-only API key at
   <https://www.zotero.org/settings/keys/new>. Enable personal-library and group
   read access only as needed. Public user/group libraries can be opened by
   numeric ID without a key.
2. Enter the key and choose **Connect**. The Library tab browses personal/group
   libraries, collections, and paged title/creator/year search results.
3. Select sources and choose **Insert citation**. Review basic author-year text,
   optional single-source Zotero style text, and each source's locator, label,
   prefix/suffix and author options before inserting.
4. Use the Document tab to inspect/edit citations, create a bibliography,
   refresh basic citations, export embedded CSL JSON, or explicitly convert a
   field to text. All document changes participate in undo/redo and save
   revisions.

Set the style ID and locale in Document (defaults: `apa` and `en-US`) before
requesting a bibliography or individual preview. Expand a source's title in the
citation composer to edit its locator and affixes.

For offline work, export references from Zotero as CSL JSON and paste the file
contents into **Import CSL JSON**. The importer accepts single items, arrays,
and the API's `items` envelope. Unlinked records retain embedded source data
without claiming to be present in a Zotero library. Selected online references
from one library can be copied as BibTeX, BibLaTeX, RIS or CSL JSON. Use
**Document → Copy embedded CSL JSON** for a mixed-library or offline document.

## Credentials and networking

The key is session-only by default. **Remember key when connecting** is offered
only when CrispCloud's selected credential store supports persistence. This
uses the existing secure-storage backend. Unchecking the option removes the
stored key immediately, and **Disconnect & forget** clears it and the session.
The in-memory connection is cleared when the Office editor closes.

Requests reuse CrispCloud's selected proxy and TLS policy. They use HTTPS and
API-key headers, refuse redirects, have a 20-second timeout and 8 MB response
limit, and are closed when the editor closes. Errors do not include API keys,
response bodies or diagnostic dumps. Keys never enter document metadata or
reference exports. Zotero library access is read-only.

## Scope and preservation

New citations use complex DOCX fields following Zotero field-code conventions
and embed CSL source snapshots. Imported Zotero field JSON, cached text, and
native document preferences are preserved on ordinary saves. Unsupported locked/nested/rich or
multi-paragraph field replacements are refused; explicit unlink retains text.
Track-changes mode and unresolved revisions in affected paragraphs also guard
reference edits. A changed document, caret, story or selection invalidates an
asynchronous insertion instead of targeting a different place.

Basic author-year formatting is an offline fallback. Zotero's individual
citation preview is not a full document-wide CSL run. Complete online
bibliographies are requested in one operation for at most 50 distinct sources
in one library, then reviewed and inserted as plain text. Larger/mixed-library
sets can use the basic bibliography or CSL export. Refresh updates Quds basic
citations for at most 50 distinct linked sources atomically; imported and
custom-style caches are left alone. Bibliographies with imported nonempty
`uncited`, `omitted`, or `custom` settings refuse both basic and online updates
to preserve those choices. Update those choices in Zotero before regenerating
the bibliography here.

Full CSL numbering/disambiguation/ibid, the native Zotero desktop picker and
HTTP citing adapter, ODT active-citation transfer, and native Word/Zotero refresh
acceptance are outside this increment. This support uses the online Web API,
not a server-side proxy to the user's localhost.

## Shared source and local checks

The implementation is maintained in
[Quds Office](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-support-20261115).
`tool/office_fidelity_manifest.json` records the exact immutable Quds source and
hashes of managed files. Its standalone legacy DOC parser pin is unchanged.

The continuation first fetched/reviewed recent branch and PR heads, integrated
the terminal documentation checkpoint, and synchronized Quds' latest UTF-16
bibliography preservation and ODS conditional formatting changes. Engine,
editor and host work is saved incrementally in remote feature branches. It does
not depend on the starved GitHub Actions queue. The final local qualification
and remaining platform limits are recorded in `docs/zotero-validation.md`.

The final refresh also integrates Quds main `c210315` (PRs #36–39) and CrispCloud
main `50b45932` (through PR #148). Concurrent terminal-workspace draft PR #140
continues separately; the Office change does not absorb its later unfinished
implementation.
