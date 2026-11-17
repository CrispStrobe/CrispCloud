# German grammar and latest Office integration — 17 November 2026

The host implementation checkpoint is `6539b63a`. The app mirrors canonical
Quds runtime `6572e6588e2212cdd026ce8e2f90464cab483d04`; canonical main's
`8d0a86f0` adds the comparison report and reproduction instructions without
changing that runtime. The fidelity manifest binds 2,597 files: 740 canonical
files and the unchanged 1,857-file standalone legacy parser.

The integration includes the latest captured German morphology, manual model
hooks, Office continuation and upstream nested lists, section layouts,
bookmarks/links, ODP hyperlinks and ODF metadata. Historical feature branches
already landed through squash merges remain represented by their accepted
source changes. Both active Quds PRs (#101 and #105) are included in canonical
history. Original developer working trees were preserved by isolated worktrees.

Fresh host checks pass: **81** preview, annotation, license, German grammar and
manual-proofing tests; scoped analysis is clean. The final test command used
the repository's reversible CI SQLite override with the original pubspec
restored afterward. Source fidelity verification, nine sync-guard unit tests
and the existing crypto release-input check pass. The policy source hash was
refreshed for the reviewed source changes; crypto dependencies are unchanged.

Canonical checks pass: **816** selected engine/proofing/ODF tests, **193**
optional-model tests (one native fixture skipped), **57** editor tests. These
are selected suites, not a full repository-wide qualification. Final host log
SHA-256 and source identities are in `evidence.json`; the actual log also lives
in the canonical evidence archive.

German morphology improves the targeted corpus from **1/73 to 68/73** exact
corrections with **0/175 valid controls flagged**. Broader syntax still has
gaps. On a separate matched panel, rules alone correct **7/18**, the actual
guarded model **6/18**, and the tested deterministic-first combination **9/18**;
the combination changes none of twelve valid controls. Real F32 ONNX inference
ran locally, through the Quds worker/decoder/guards. This does not qualify the
shipping CrispEmbed macOS FFI or mobile memory use. The optional model backend
and weights are not bundled or enabled in CrispCloud.

Keep the current reviewed rules/Unicode morphology as the default. Continue
the optional Apache-2.0 Proofbird work with explicit model/runtime qualification;
evaluate MIT spaCy German syntax analysis for independently authored broader
rules. LanguageTool resources remain outside the selected license policy and
HORST's model card explicitly leaves its license provisional. A newer Proofbird
v2.2.0 is a research candidate, not a tested replacement for the pinned v2.1.0.

The full comparison, raw evidence and primary license sources are in the
[canonical report](https://github.com/CrispStrobe/quds_office_suite/blob/8d0a86f0/docs/validation/german-options-20261117/README.md).
