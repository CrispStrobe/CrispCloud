# Office reconciliation for the storage continuation — 15 November 2026

The `integration/office-reconcile-storage-20261115` branch preserved the first
Office snapshot before storage recovery implementation continued. It incorporates
Excel PR #108 at `a77364501d274e0fde2e9fffeefb121258ae9614` and worksheet
navigation at `8c7f8ac78593661d415a23d52048de6053f378c9`. DOC recovery PR #109
at `1b7680583ac69649b17287ab68738288fec10f51` was already included in the storage
branch. Existing main `8a24763fb4b2c720ff6b617cebbea8971191bdca` is retained.

## Initial canonical source checkpoint

At that checkpoint, all 2,214 managed files matched Quds integration
`01f167cc84e7064d4d9dbeecf3d3cff9e3d8a9ca` and the unchanged standalone DOC
parser `f9d10b5a5e68b4216892d64622caa8b0a15c7afd`. The Quds checkpoint is saved
on `integration/office-storage-reconcile-20261115` with these explicit parents:

- main `4f7d0e0064cb430cc14e3daca663cffade777938`, already containing worksheet
  navigation and the newer Word selection, fields and preservation fixes;
- Excel palette import `fd749d8ee140be623597493cdbc05ce20f1f5151`;
- shape preservation PR #20, `5278aafd512640608fe06b8f7d357c4cffe8520a`;
- heading inheritance and theme shading PR #21,
  `1f30a823b30678e3684c98fee6a2cd5c4945c4f2`.

The guarded sync checks the original manifest and the full canonical source
before updating the mirror and pin. No upstream PR is closed or merged into
main by this reconciliation.

## Office evidence discovery

The existing host workflow passed 283 tests at navigation source `1a86e790`
but rejected 57 inventory paths because recursive discovery counted archived
build outputs inside committed evidence. Those are historical results; they
are not acceptance for this combined source.

Checkout verification inspects only the current declared `build/` roots.
Historical copies cannot create duplicate results or substitute for a missing
current output. The initial checkpoint used `--downloaded-artifacts` for
downloaded bundles. The later navigation reconciliation below supersedes that
interface with explicit layout names and broader artifact-root checks. The
required 182 files and their rendering/schema scopes remain unchanged.

## Qualification at the reconciliation checkpoint

- The exact managed-source check passes for all 2,214 files.
- All 25 inventory controls pass against the explicit layout modes; all eight
  guarded-sync controls pass. These include rejection of missing current
  outputs despite archived copies and duplicate downloaded artifact roots.
- Runtime, rendering and external schema acceptance for this combined source
  are pending. Earlier test totals are not relabeled as current results.

## Final source cutoff incorporated into storage

The final audit observed remote refs from 06:34:41 through 06:37:21 UTC on
15 November 2026. It found 105 advertised CrispCloud branch/PR refs and 28
canonical Quds branch/PR refs. The initial implementation already contained
102 app refs; current main and the navigation branch/PR alias contributed
17 additional distinct commits. The audit is preserved in
`evidence/storage-carving-20261115/remote-cutoff-audit.json`.

The combined storage candidate incorporates:

- CrispCloud main `fa030137fd203467d5560b68b767019194b95ebd`, including the
  merged Office PRs, newer PDF interactions and legacy save protection;
- navigation / PR #110 `7e5af83c4e6d26247ccf91d2b03c47a816f46231`, including
  complete worksheet-view captures and the newer evidence inventory repair;
- exact canonical Quds main `eae58542dffd73cf30e97cc60a59a5474656d676` and
  standalone DOC parser `d422fa99a3a84830794f0e2dc332d59f923779f7`, as pinned
  in the incoming main manifest. The 2,214-file managed-source check passes.

The current checker uses `--layout checkout` for a working checkout and
`--layout artifact` for downloaded bundles. Artifact discovery includes partial
and otherwise-unused wrappers so duplicate or undeclared output cannot hide
outside the principal host tree. Both checkout-history regression cases are
retained with the explicit checkout layout. Historical evidence remains intact.

The earlier canonical integration branch remains a durable history checkpoint;
the final app mirror follows the newer canonical main pin. This reconciliation
does not close another PR or merge the storage branch into upstream main.

The storage evidence directory records qualification against the saved combined
source. Earlier totals above remain historical and do not establish current
runtime, rendering or external schema acceptance.

## Resumed source cutoff and wrap-text repair

The next audit captured 106 app branch/PR refs and 30 canonical Quds refs at
07:07:43–07:07:49 UTC on 15 November 2026. App main and worksheet navigation
were unchanged. The app Excel branch had advanced to `ca6156e8` after its PR
merged; its managed wrap-text changes originate at canonical `4b51c5c0`.
Canonical Word `4637ddce` adds inline-picture preservation and repairs the
scripted heading oracle's incorrect assumption that outline levels must be
direct paragraph properties.

Canonical integration `dcefdc051ac8dddcef0f07baaa00bfbc2c35817a` combines those
heads and corrects three defects in the incoming wrap support: shifted imported
XF flags, accidental reuse of a wrapped style for an unwrapped cell, and missing
style emission for a new workbook's wrap-only edit. Seven new wrap tests cover
native/prefixed XML, explicit overrides, repeated saves and HTML import; six
additional oracle controls exercise inherited headings and reject incorrect
overrides, missing properties and cyclic inheritance.

The app merge retains `ca6156e8` as a parent, while guarded synchronization takes
the final managed bytes from that exact canonical integration. The incoming
Excel manifest's older DOC parser pin is not adopted: the standalone parser
remains `d422fa99`. The managed inventory now covers 2,217 files. Audit receipts
are in `evidence/storage-carving-20261115/resume-audit/`; runtime acceptance is
recorded separately against the saved combined candidate.
