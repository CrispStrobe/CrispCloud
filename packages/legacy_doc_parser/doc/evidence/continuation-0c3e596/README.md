# Combined portable and schema acceptance at 0c3e596

The final combined runtime is clean remote commit
`0c3e59682952cce0e11301afec789e7ae2a1256a`, tree
`e763288ee642c26854572e1cae212c36bf683918`. Later documentation and evidence
commits do not change the runtime identified by these receipts.

## Results and boundaries

| Gate | Recorded result |
| --- | --- |
| Dart portable suite | 918 passing tests |
| Python fidelity controls | 162 passing tests, including deliberate negative controls |
| Formatting and analysis | 188 files, no formatting changes; fatal-info analysis clean |
| JavaScript acceptance | Actual binary DOC conversion and 51 media checks passed |
| Corpus integrity | Original fixture identities unchanged |
| Package dry run | Zero warnings; no package was published |
| Primary independent SDK gate | 228 required DOCX outputs; zero errors; exact file/hash coverage |
| Determinism | All 484 files from two complete corpus generations match |
| Extra table SDK gate | 21 actual final-runtime outputs; zero errors; exact file/hash coverage |

All eight portable stages succeeded against the same clean source. The 655
captured tracked/configuration input hashes match before and after execution.
The primary schema gate checks its own positive and negative controls, builds
the pinned Open XML SDK 3.3.0 validator, verifies complete output coverage and
hashes, and rechecks source and validator artifacts after execution. Its
Office2019 schema/semantic validation establishes package validity, not
rendering or editor behavior.

The 21 extra table packages are additional to the 228 required corpus outputs.
They comprise thirteen context controls, four signed-origin/asymmetric-cell
controls and four row-padding reset controls. Each was regenerated using a
freshly compiled converter from the combined runtime. Every OPC part matches
the independently measured table-branch output. The extra gate reuses the
fresh primary gate's hash-verified validator; it does not claim another
independent validator build. The extra receipt includes a post-run exact
coverage/hash check using `tool/fidelity/schema.py::verify_report`. The retained
reproduction helper now performs that same check directly.

The [native corpus receipt](../native-corpus-0c3e596/README.md) records all 24
source cases and 72 repeat imports separately. The
[table investigation](../floating-table-origin-20261112/README.md) retains the
failed candidate, supported geometry mapping and independently authored
source controls. The [textbox investigation](../textbox-wrap-stroke-20261112/README.md)
retains the rejected automatic stroke default and the accepted wrap clearances.

## Retained bytes

`validation-artifacts.tar.xz` contains 1,065 unchanged files under three roots:

- `portable/`: complete command logs and before/after source receipt.
- `schema/`: validator build commands/logs, positive/negative controls, complete
  SDK reports and both complete generated corpora, including DOC inputs.
- `extra-table-schema/`: all 21 independently authored DOC inputs, actual final
  DOCX outputs, conversion logs and SDK/source/equivalence receipts.

The manifest binds every archive member's path, length and SHA-256, together
with the archive itself. Reproducible validator/converter executables are
omitted; their exact hashes remain in the receipts and the manifest's separate
omission inventory. Original absolute paths and command arguments remain in
the measured receipts rather than being rewritten to look like a later run.

Verify all retained bytes and the recorded source, log, SDK coverage and output
hash relationships without extracting or rerunning the compiler:

```sh
python3 seal_validation_evidence.py --directory .
```

The helper also verifies that both retained primary corpus generations contain
identical DOCX output bytes. This is an archive/receipt check, not a fresh
native rendering or schema execution.

## Reproduction

Use a clean checkout of the exact runtime above with the recorded Dart 3.13.7
dependencies and a fresh output directory. `run_parser_gate.py` retains all
portable logs and before/after identities:

```sh
python3 /path/to/evidence/run_parser_gate.py \
  --repo /path/to/clean-parser --out /path/to/new-portable \
  --dart /path/to/dart
```

The primary independent gate is `tool/fidelity/schema.py`; its original
commands, pinned SDK/compiler identities and package hashes are retained in
`schema/report.json`. The extra gate's `validate_extra_tables.py` takes the
clean parser path, extracted table-diagnostics root, successful primary SDK
output directory, a new output path, and explicit Dart/dotnet paths, in that
order. It rejects a source mismatch and requires complete unchanged inputs,
all-part output equivalence and validator hash agreement.

These gates used no modified source fixture or updated reviewed golden.
