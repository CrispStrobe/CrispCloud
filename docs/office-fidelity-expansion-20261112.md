# Office fidelity expansion — 12 November 2026

This branch combines the recovered host workflows with the expanded shared Quds
implementation. It continues the prior follow-up branch and is saved
incrementally as `feature/office-fidelity-expansion-20261112`.

## Recovered host behavior

The font and picture changes from the interrupted workflow branch are integrated
with the later custom-tab controls and actual-upload save tests. The font dialog
retains fractional values and mixed formatting until the user explicitly changes
a property; an explicit choice can apply even when it matches the caret value.
Cancellation, no-ops and stale story/selection changes are tested. Picture
insertion uses decoded dimensions and orientation, preserves proportions and
respects page/slide bounds.

These changes were saved at `36a3634`. The current authored host inventory has
**122 captures**, preserving the previous 62 and adding the recovered font and
picture scenarios. Test uploads wait for worker image decoding before saving and
check the independently authored input's dimensions.

## Shared Quds source

The guarded sync pins **417 managed files** to Quds commit
`73ad0c42a8ecc81fb11dbde05c6f0cf10b9a1c74`. Every existing managed hash and changed
unpinned file was checked before applying the update. No host customization was
overwritten. The manifest is the authoritative exact commit and file inventory.

The final pin also corrects the shared native bounds oracle to the legal
100 × 72 point host fixture and its exact `(10, 7.2, 90, 45)` picture rectangle.
All 56 renderer controls and the three focused native saves pass; the oracle
continues to reject clipped overflow, including a one-EMU extent change.
The earlier failed SDK attempt and interrupted rerun remain preserved as such.

The complete native host run also exposed six deliberately image-only Word
GIF/JPEG captures. Their original image-only fixtures are retained. The shared
oracle now checks their exact A4/paragraph/inline/media constraints and complete
page pixels against geometry established by independently authored references.
All 66 renderer controls and six focused native captures pass, including both
three-save groups and exact reference RGB equality. The prior full native failure
remains preserved under `attempt4-host-image-only-word`.

The shared implementation includes both recovered table-width/Unicode-wrapping
work and the later merged-cell, font-metric, custom-tab, style and history fixes.
The new expansion adds worksheet-local defined-name resolution and typed error
handling, complete native bookmark insertion copies, and reversible slide
alignment/distribution/grouping with stable geometry and unique native IDs.
Generated paragraph bookmark merges that would discard their identity reject
before selection deletion. Unsupported formula and complex document cases retain
the explicit limits recorded in the source ledger.

## Required acceptance

The complete host gate verifies the managed pin, runs the curated shared engine
suite and independent oracles, exercises the real host save/upload workflows,
collects source-bound LCOV and verifies every authored capture. Its declared
outputs are **346 engine files plus 122 actual-host files**, or **468 files** for
independent Open XML schema validation.

The native phase renders **all 122 host captures**, including DOCM, DOTX and DOTM.
Picture-only slides require the independently authored black-rectangle geometry
and pixel checks. Repeated saves must preserve native page count, text and pixels.
The source repository separately requires its full 375-file engine/editor corpus
and independent references for the newly supported features.

The host coverage collector uses a new immutable output directory for each run
and requires a successful collection receipt. The acceptance runner records the
exact documented temporary system-SQLite pubspec hook, checks every other input,
and requires restoration of the committed pubspec after the gate. Coverage is
reported as executed lines, not branch correctness or complete Office support.

Frozen aggregate receipts and the reproducible producer/schema/native runners
are stored under
[`docs/evidence/office-fidelity-expansion-20261112`](evidence/office-fidelity-expansion-20261112/).
They identify the accepted implementation pins; later documentation commits do
not change those historical inputs. Broader application CI is separate from the
Office acceptance and is not represented as green by these receipts.
