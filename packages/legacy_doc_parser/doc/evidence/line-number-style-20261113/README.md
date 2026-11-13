# Line Number style: source, counterfactual and committed runtime

Runtime commit: `a1784cde69397e70fa6e8d6dd4dfe9c96e03f08a`.
Runtime tree: `f19662675e270f377d6356138ca064a71ab91283`.
The native and SDK runs both record this exact clean checkout. This evidence
checkpoint adds documentation and retained artifacts without changing runtime
code. The [source contract](../../line-number-style.md) describes the mapping
and the remaining native bridge discrepancies.

## Result and limits

| Measurement | Recorded result |
| --- | --- |
| Authored DOCX to retained native DOC | Exact page RGB, layout text and word boxes |
| Pre-fix output | Line style missing; RGB differs; 0.9 pt maximum word-origin drift |
| Output-only restoration of the source line style | Exact page RGB, layout text and word boxes; only `styles.xml` changed |
| Actual committed parser import | Exact page RGB, layout text and word boxes; 0.0 pt drift |
| Three successive native DOC save/import cycles | Each exact against its binary source, previous parser output and first parser output |
| Existing `word`, `word-compatibility`, `bookmarks` outputs | Byte-identical to their retained `48bf3a` outputs |
| Focused Dart tests | 20 passed, including 9 new Line Number tests |
| Fresh Open XML SDK gate | 230 DOCX, zero errors; positive and negative controls passed |
| Schema determinism | Both complete 488-file generated corpora are byte-identical |

The installed renderer is LibreOfficeDev `26.8.0.0.alpha0`, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, with its exact font inventory and
Poppler identities retained. Exact rendering applies to this deliberately
discriminating one-page control on this environment. Native DOCX and parser
DOCX still differ in structural/default serialization. The native report
keeps all semantic differences from the initial import and repeated saves;
it does not label the entire semantic comparison exact.

The diagnostic pre-fix run predates the runtime change. Its original files,
conversion metadata and render receipts remain intact. It is a failing
control, not a second clean-build gate. The independently authored source and
native DOC bytes are identical to those used by the actual committed-runtime
gate. No source input or original golden was modified to improve a metric.

## Independent source evidence

`audit.py` reads the retained CFB/STSH bytes without calling the Dart parser.
It verifies the pinned DOC hash, the exact 62-byte STD, built-in identity 40,
character kind, index 16, parent 15 and raw CHPX. Font index 8 resolves to
Courier New; explicit formatting is 28 half-points, bold and `CC2233`.
The source DOCX intentionally gives body text a different font and size.

The regression fixtures separately cover a localized built-in name at a
different index, inherited properties and explicit false resets; an ordinary
same-name user style; absent built-in style; duplicate identity, wrong kind,
missing parent and cyclic inheritance; and the optional public field without
any body/table style. The existing compatibility fixture retains its valid
note numbering, line numbering and enabled width-balance semantics.

`diagnostic/generated-label-results/` retains the rejected output-only note
style and bookmark width-balance probes. The custom marker style does not
resolve the generic Word case; built-in marker style names alter anchors.
Removing enabled width balancing makes the bookmark render closer but
contradicts its source. These probes are not runtime changes or passing
acceptance cases. Original `48bf3a` source archives remain linked by exact
archive hash and member names in `native/report.json`.

## Artifact contents

`artifacts.tar.xz` contains **1,430 files**, **26,026,111 bytes** before
compression and **1,536,332 bytes** compressed. The adjacent manifest lists
every exact path, size and SHA-256, along with the five omitted reproducible
executables/assemblies and their hashes. Native profile directories and
incidental .NET home caches are excluded; measured document outputs, logs,
reports and rasters are retained.

The archive contains the complete native three-cycle measurement, original
DOCX render, old-case byte comparisons, focused test logs, source and binary
control generators, original diagnostic/counterfactual results, both complete
schema corpora, SDK controls and build logs, 211 source files used by one or
both gates, exact Git commit/tree objects, and the independent source audit.
The SDK gate uses .NET SDK 8.0.428, runtime 8.0.34 and Open XML SDK 3.3.0;
compiler, reference assembly and pinned NuGet hashes are recorded. It makes
no additional layout claim.

```sh
python3 doc/evidence/line-number-style-20261113/verify.py --check-git .
python3 -O doc/evidence/line-number-style-20261113/verify.py
python3 doc/evidence/line-number-style-20261113/test_verifier.py
python3 -O doc/evidence/line-number-style-20261113/test_verifier.py
```

The verifier checks exact archive membership, hashes and sizes; clean runtime
identity and recorded commands; source/log/compiler/output bindings; raw
STSH semantics; Poppler word coordinates and lossless raster bytes; each
repeated input/output; the single-part counterfactual; all three unchanged
old outputs; and both full generated schema corpora against the SDK's exact
230-file validation report. Optional Git verification binds captured tracked
sources and the authored control to the runtime commit. Checks use explicit
errors and remain active under optimized Python.

The verifier controls accept the valid evidence and reject 22 mutations,
including a failed actual command, an unrelated command with a retained success
log, an omitted second-corpus output, a stale SDK output hash even after its
report receipt is resealed, changed source bytes, an omitted native cycle,
replacement of the restored output by the failing baseline, a changed old
output and an altered font receipt. Each of the 13 SDK stage commands is also
individually replaced by an unrelated executable with its valid original
success log retained; every replacement is rejected. The same controls pass
under `python -O`. This command binding was strengthened after independent
review; the original captured run records and archive bytes are unchanged.
