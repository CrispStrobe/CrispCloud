# Office reconciliation for the storage continuation — 15 November 2026

The `integration/office-reconcile-storage-20261115` branch preserves the latest
Office work before storage recovery implementation continues. It incorporates
Excel PR #108 at `a77364501d274e0fde2e9fffeefb121258ae9614` and worksheet
navigation at `8c7f8ac78593661d415a23d52048de6053f378c9`. DOC recovery PR #109
at `1b7680583ac69649b17287ab68738288fec10f51` was already included in the storage
branch. Existing main `8a24763fb4b2c720ff6b617cebbea8971191bdca` is retained.

## Canonical source

All 2,214 managed files match Quds integration
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

Checkout verification now inspects only the current declared `build/` roots.
Historical copies cannot create duplicate results or substitute for a missing
current output. Downloaded workflow artifacts use the explicit
`--downloaded-artifacts` option, retaining discovery of wrapper roots and the
duplicate, unexpected-file and split-root checks. The required 182 files and
their rendering/schema scopes remain unchanged. The report records the chosen
layout.

## Qualification at the reconciliation checkpoint

- The exact managed-source check passes for all 2,214 files.
- All 25 inventory controls pass against the explicit layout modes; all eight
  guarded-sync controls pass. These include rejection of missing current
  outputs despite archived copies and duplicate downloaded artifact roots.
- Runtime, rendering and external schema acceptance for this combined source
  are pending. Earlier test totals are not relabeled as current results.

The separate storage implementation and its qualification will be recorded on
the storage continuation branch.
