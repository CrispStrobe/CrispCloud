# German noun agreement and licensed syntax/model evaluation

The app now includes the separately ignorable `de.grammar.noun-verb` rule:
`Die Kinder spielt im Garten → spielen`, `Das Kind spielen im Garten → spielt`.
It uses the existing reviewed noun morphology and finite verb facts. It
preserves ambiguous `die Leiter`, fronted objects, coordination, relative
clauses and unsupported tails. Suggestions retain source ownership and the
editor's correction, recheck, undo, redo and ignore/restore behavior.

No Python/parser dependency, dictionary or neural weight is added to the app.
The optional model remains disabled by default. The new syntax prototype and
separately pinned v2.2 artifacts are evaluation tools in the canonical repo.

The final source pin is in `tool/office_fidelity_manifest.json`: 2,598 managed
files, comprising 741 canonical files and the unchanged 1,857-file standalone
parser. Source reconciliation preserves the arriving upstream ODT table,
paragraph and tab-stop work alongside the grammar change. The native host
dependencies are unchanged; the existing export-policy source hash is refreshed
for the reviewed manifest changes without changing its policy decision.

Fresh checks pass: 94 host preview, annotation, license, grammar and review
dialog tests; 865 selected engine/proofing/ODF tests; 59 editor tests; five
candidate-admission tests. Focused final runs also pass all 47 noun-agreement
cases and all 13 writer cases after the tab-stop arrival; these overlap the
selected suites and must not be added to their unique-test counts. The guarded
source verifier, nine sync-guard tests and existing crypto-input check pass.
The host SQLite test override is restored after the run.

On the frozen 56-case diagnostic panel, the bounded Dart rule improves 0/20 to
10/20 exact corrections with no flagged valid controls out of 36. VM and
JavaScript results match. The existing morphology panel retains 68/73 target
corrections and no flagged valid controls out of 175. These are diagnostic
panels, not general accuracy estimates. The actual real-model combined policy
improves 9/18 to 10/18 on the original panel, with no changed valid controls.

The spaCy experiment gives 15/20 corrections; a guard using the actual Dart
noun readings removes its singular-ladder false correction while retaining
those fixes. It remains an evaluation-only Python prototype. The publisher's
MIT model license and source notices are retained separately from training
corpus terms. Proofbird v2.2, evaluated through its unmodified publisher
reference, does not improve these panels and introduces another valid-text
deletion; its guarded application quality is not established here. The
approved v2.1 bundle pin remains unchanged and rejects unapproved v2.2 assets.

Exact sources, artifact hashes, model/code/data license findings, actual outputs
and reproduction commands are in the
[canonical report](https://github.com/CrispStrobe/quds_office_suite/blob/388bd745/docs/validation/german-syntax-20261117/README.md).
`evidence.json` binds the final host test log, implementation and source pin;
`host-tests.log.gz` retains the actual log. Original developer working trees
were preserved through isolated worktrees.
