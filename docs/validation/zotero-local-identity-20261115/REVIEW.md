# Zotero local identity continuation — source review

## Current verification status

This change adds 39 regression cases. None was executed in this continuation:
the command execution service was unavailable. No Dart formatter, parser,
analyzer, native build, live Zotero session or GitHub Actions result is claimed.
Earlier test logs remain historical evidence tied to their recorded revisions.

The implementation and tests received independent source review before being
checkpointed. This can identify logic, API and fixture problems, but does not
establish compilation or runtime correctness.

## Reviewed behavior

- Request routes and saved citation identities are separate. A local source
  retains `users/local/<profileKey>/items/<itemKey>`; network requests use
  `/api/users/0`. The request alias is never manufactured as a new linked ID.
- Every connected dialog operation passes the complete expected identity.
  Individual item reads prove it from the same JSON response.
- Basic refresh and missing-CSL item completion use metadata-only requests.
  They do not send style/locale parameters or ask for formatted text.
- The dialog validates every source and its connection compatibility before
  refresh starts. It gathers all metadata before one guarded document update.
  A wrong profile, incompatible source or failed request leaves existing
  citation instructions and editor history unchanged.
- URI aliases are normalized for comparison only. Original IDs, URI lists,
  source locators, prefixes/suffixes and unknown citation JSON are preserved.
- Local profiles with colliding item keys remain separate. Aggregate operations
  require one source scope. Basic bibliography deduplication recognizes local
  HTTP/HTTPS and hostname aliases without merging different profile keys.
- Selected exports and formatted bibliographies first request a bounded metadata
  selection and require an exact key set with matching identities. A duplicate,
  missing, additional or substituted item refuses the whole operation.
- Desktop aggregate output additionally requires a pinned `Zotero-Server-ID`
  and a usable `Last-Modified-Version`. The formatted response must retain
  the database identity and reported library version; a supplied result count
  must match. This detects changes reported between responses, not a snapshot
  transaction inside Zotero's server.
- Older desktops can still use same-response item verification for preview and
  metadata refresh. The aggregate refusal provides Zotero 10/reconnect guidance
  and preserves offline/basic alternatives.
- New linked DOCX sources reject zero-valued numeric identities, leading-zero
  IDs, malformed local keys and explicit ports. Existing `fromJson` imports
  remain opaque and preserve unsupported URI forms without automatic repair.
- Existing asynchronous document/caret/story/revision checks remain in place.
  Imported rich/locked/nested/cross-paragraph field limitations remain intact.

## Added regression inventory

| Area | New registered cases | Main assertions |
| --- | ---: | --- |
| Pure API client | 19 | Same-response identity; aliases; wrong profile; missing identity; invalid route/key; cloud isolation; format routing; complete selection; database/version/count changes; backoff; metadata-only reads |
| Word citation model and DOCX | 3 | New-identity rejection; three save/reopen cycles with colliding profile/account/group keys; opaque imported identities |
| Shared format helpers | 5 | Local routing/identity separation, profile scopes, alias preservation and bibliography deduplication |
| Shared dialog widgets | 12 | Refresh/undo/save; wrong-profile and online refusal; numeric aliases; mixed profiles; preview success/failure; export success/failure; bibliography review; old-desktop refusal; bare-key refusal |
| **Total added** | **39** | **Committed, not executed** |

Three existing helper cases were also updated to reflect the new supported
local-address behavior and stricter raw-URI parsing. Existing API, controller
and dialog regressions remain in their original files.

Client export tests preserve arbitrary mocked Unicode response bodies; they
verify request routing, guards and raw-body preservation, not Zotero translator
output. Widget tests exercise mocked transport responses, not an installed
Zotero instance. The two-value preview loop registers two widget cases.

## Protocol review

Checked against Zotero's official
[local API documentation](https://www.zotero.org/support/dev/web_api/v3/local_api)
and [pinned implementation](https://github.com/zotero/zotero/blob/045d5204410f1abfd80910e1cd0aa92dceec741b/chrome/content/zotero/xpcom/server/server_localAPI.js).

The implementation supplies `Total-Results` and library-local
`Last-Modified-Version` on aggregate responses and retains them for bibliography
and export formats. It supplies `Zotero-Server-ID` on responses and rejects a
mismatched incoming identifier with HTTP 412. Local and online versions are
never compared to each other.

## Repository integration

Before feature changes, Quds main through #42 was merged with the existing
Zotero branch. Five retained squash-equivalent feature heads were checked by
identical tree IDs. The one overlapping Word-deserializer file was merged by
eight unique exact-context patch matches; the remaining incoming paths retain
the incoming blobs. The merge retains both parents.

CrispCloud main through #152 and newer terminal draft #140 work were integrated
with parent-preserving commits. Canonical Office files are mirrored through
the existing manifest. Every managed blob identity, mode and size is compared
with its pinned source; changed/new text is freshly hashed. Unchanged immutable
blobs reuse earlier SHA-256 evidence. This comparison does not claim that the
repository's Python guard executed in the unavailable local environment.

All branch writes use a previously observed expected head and fast-forward
updates. Checkpoint messages include `[skip ci]`. No workflow status was awaited.

## Remaining acceptance work

Run the commands in [the validation guide](../../zotero-validation.md), including
the old client/controller/field regressions and new cases. Then perform a native
Quds Studio/CrispCloud build and a live desktop workflow with an unsynced
library. Exercise a wrong database with a colliding key, source switching,
older Zotero behavior, and delayed responses after document/caret changes.

Document-wide CSL numbering, disambiguation and ibid, native Zotero picker/HTTP
citing transactions, active ODT citation transfer and native Word/Zotero refresh
acceptance remain outside this increment.
