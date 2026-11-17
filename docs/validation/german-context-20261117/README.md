# German context and non-AOT Office integration

17 November 2026. Quds runtime pin:
`3b451f9284c9b31db8d7f1819cb9af8c68586dbb`, including the late upstream cached
ODT table-of-contents export. The canonical report and detailed synthetic-text
receipts are [published in Quds](https://github.com/CrispStrobe/quds_office_suite/blob/97f6553c3fdca35be0270a66d6eaeb286c884fef/docs/validation/german-context-20261117/README.md).

The AOT.ru/RML analyzer, dictionaries, package, Studio registration and daemon /
pipe transports are excluded. Existing AOT/RML feature branches are retained.
The default application uses independent offline Dart rules and the existing
licensed lexical data. The experimental neural provider stays disabled by
default and is not newly bundled or registered by this change.

The original frozen panel is 18/18 exact with 0/12 valid controls flagged in the
default writing + spelling path, without a model. Further context panels score
21/23 and 45/46, with 0/60 and 0/58 controls flagged. A separate completion panel
is 8/8 with 0/20 controls flagged. These small synthetic panels are not a claim
to cover all German grammar. The optional model introduces four false positives
on completion controls and exceeds the provisional native F32 memory budget.

The actual final host source (`c41f7e66`) passed 120 native Flutter tests covering
Office previews, annotation privacy, license attribution, grammar correction,
undo/redo, manual review and dialogs. The test helper temporarily selects the
CI-compatible Apple SQLite dependency, restores pubspec.yaml, and leaves the
worktree clean. Nine sync-guard tests also pass. The final tracked fidelity gate
verifies 2,620 files against the canonical source and standalone parser pin;
crypto/export-policy input checks pass after the source fingerprint refresh.

Canonical qualification also includes 835 engine proofing tests, 508 Office
export tests, 118 editor tests, and 193 optional-provider tests (one native
fixture skipped). Actual ONNX in-process inference was separately exercised
inside the Quds worker, with matching Dart JIT/AOT corrections. This QA transport
ships no native binary or weights and has no daemon or pipe.

The earlier guarded sync rejected six existing host files whose recorded bytes
differed from their claimed source revision. Each recorded host hash was
verified, the differences reviewed, and the candidate preserved their Office
features while removing AOT-only review labels. The reconciliation receipt and
patch are retained with the canonical evidence. Normal guarded syncs then
succeeded, including the final TOC update.
