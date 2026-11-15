# Zotero references in Word documents

Open a Word document with F4, then choose **Insert → Zotero…** or the **Zotero**
button in the Insert ribbon's References group.

## Connect an online library and cite

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

## Use Zotero desktop without an API key

On Linux, Windows or macOS, choose **Reference library source → Zotero desktop
(this computer)** in the Library tab. Open Zotero and enable **Settings →
Advanced → Allow other applications on this computer to communicate with
Zotero**, then choose **Connect desktop**. Browse the local personal library,
locally available group libraries, collections and search results. Local
browsing includes unsynced sources and works offline.

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

Unsynced local links and detached offline sources currently use basic citations,
basic bibliographies and **Document → Copy embedded CSL JSON**. Connected
refresh, individual style previews, selected-reference export and
Zotero-formatted bibliographies still require numeric user/group identities.
A style absent from the desktop installation may cause Zotero itself to fetch
it, even though library browsing works offline.

This option is available in native desktop builds. It is not the native Zotero
citation picker or HTTP citing adapter. See the official
[local API setup](https://www.zotero.org/support/dev/web_api/v3/local_api).

## Credentials and networking

The key is session-only by default. **Remember key when connecting** is offered
only when CrispCloud's selected credential store supports persistence. This
uses the existing secure-storage backend. Unchecking the option removes the
stored key immediately, and **Disconnect & forget** clears it and the session.
The in-memory connection is cleared when the Office editor closes.

Online requests reuse CrispCloud's selected proxy and TLS policy with HTTPS and
API-key headers. Desktop requests use a separate direct client with strictly
allowed headers and no credentials. Both refuse redirects, have a 20-second
timeout and 8 MB response limit, and are closed when the editor closes. Errors do not include API keys,
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
acceptance remain outside this increment. The native app talks directly to the
local API; the desktop option is not exposed through a server-side proxy.

## Shared source and local checks

The implementation is maintained in
[Quds Office](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-support-20261115).
`tool/office_fidelity_manifest.json` records the exact immutable Quds source and
hashes of managed files. Its standalone legacy DOC parser pin is unchanged.

The desktop continuation audited all current branches/recent PRs and brought
terminal-workspace draft #140 into the integration branch. Main `50b45932`
(through PR #148) and Quds main `c210315` (through PR #39) remain included.
All feature work is saved incrementally to remote branches using `[skip ci]`.
No GitHub Actions queue was awaited.

Fresh checks passed 34 Quds API client tests and 16 tests of the actual
production host transport, with clean focused analysis. They do not represent
a full native or Flutter widget build. See [zotero-validation.md](zotero-validation.md)
for exact source hashes, reproducible commands, logs and remaining limits.
