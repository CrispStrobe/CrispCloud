# Independent Open XML SDK validation

`Program.cs`, `OfficeValidation.csproj`, and `LICENSE.quds` are unchanged copies
from the CrispStrobe Quds fork. `upstream.json` records their exact commit, paths,
and SHA-256 hashes. The MIT notice is retained beside the copied source. This
validator uses Microsoft's Open XML SDK 3.3.0 with the Office 2019 validation
rules. It opens packages read-only and records the hash of each inspected file.

Run the complete gate from the parser repository after `dart pub get`:

```sh
python3 tool/fidelity/schema.py --out build/schema-gate-001
```

Dart, Python 3.10+, and a .NET 8 SDK must be available. Explicit executables can
be selected with `--dart` and `--dotnet`. The default path builds the copied
project with `dotnet publish`. The separate GitHub Actions job runs this gate
without LibreOffice, Word, or Quds installed.

The required DOC-to-DOCX inventory is defined by `EXPECTED_CASES` in
`tool/fidelity/schema.py` and currently contains 1,114 conversions. It covers
table geometry and revisions, shapes, metafiles, media, ink, fields, list
labels and sequences, section formatting, notes, headers, footers and textbox
boundaries, alongside retained native DOC inputs. The generator calls the
existing fixture producers and retains independently assembled binary inputs.
The fixed inventory catches missing cases, duplicate output aliases, and
unregistered Office files. The fifth audit adds generated Unicode/ASCII field
trees, both field export modes, source field visibility, binary scalar bounds,
literal list templates, sparse marker inheritance/reset properties and numbered
paragraph visibility. Invalid binary controls remain retained source inputs;
they do not count as successful conversions.

The [14 November follow-up](../../doc/parser-audit-20261114-followup.md) adds
57 binary property-contract conversions: direct/Prm0 embedded-object Boolean
flags, current and historical built-in heading levels, ordinary outline
levels, and bounded indirect paragraph-property ordering and replacement.
Twelve malformed binary controls retain their DOC inputs without successful
outputs. The same contracts run in compiled JavaScript.

The same gate generates and validates 419 public-model controls in nine
separately named groups: `public_metafile_fixture.dart` (24),
`public_compound_fixture.dart` (17), `public_formatting_fixture.dart` (106),
`public_table_formatting_fixture.dart` (53),
`cached_field_structure_fixture.dart` (88),
`display_field_evidence_fixture.dart` (46),
`public_section_geometry_fixture.dart` (44),
`public_bookmark_fixture.dart` (21), and
`public_textbox_reference_fixture.dart` (20). The required names and output/raw
input paths are independently pinned by `PUBLIC_CORPORA` in
`tool/fidelity/schema.py`. Together with the DOC-derived corpus, the gate
requires 1,533 successful package validations, excluding validator controls.

The public groups cover image/OLE/VBA activation, formatting, field-event
structure, revision evidence, current/historical section scalar bounds,
direct cell-shading precedence, bookmark ownership and hidden metadata, and
textbox chain ordering, source-domain ownership and inert placement evidence.
They are authored public models, not binary-DOC-derived cases. Each group
retains its model descriptions in `cases.json`; metafile and compound cases
also retain their raw inputs beside the DOCX/DOCM packages. Missing or extra
cases/files, output aliases, substituted paths, escaping paths, and unchecked
baseline manifests fail the gate. Package schema validation does not validate
or execute the contents of an OLE object or a VBA project.

The complete follow-up gate passed on clean tested source
`a25e4ea824886327b97bde2873e6ef175a5ab971`: 3,903 Dart tests, 197 Python controls,
38 compiled-JavaScript groups and all 1,533 SDK packages. The 24-input oracle
check also passed, 353 Dart files were already formatted, and the publish dry
run reported zero warnings. The
[saved evidence](../../doc/evidence/parser-audit-20261114-followup/README.md)
distinguishes this tested source from later documentation commits and retains
the earlier dated passes separately.

Each DOC-derived and public corpus is generated twice, and every retained
source, output, and metadata file must match byte-for-byte. Both generations
are checked against their complete required inventories before validation.

Every run compiles fresh validator sources, checks all three resolved dependency
assembly hashes, and requires the validator's positive, malformed XML,
mislabeled package, and discovery self-tests. Additional independently authored
OOXML controls exercise its normal directory/report path: a valid table, an
invalid child under `w:body`, and invalid `w:noWrap w:val="0"`. A successful exit
with missing files, stale hashes, contradictory counts, or an accepted negative
control fails the gate. Inputs and validator artifacts must remain unchanged.

`report.json` records source hashes for the parser, generator, fixture helpers,
native DOC inputs, dependency declarations, and validator; compiler/runtime
identity and hashes; per-case binary/output hashes; all stage results; and the
hash of each complete SDK report. Its `publicCorpora` entries separately record
each public generator, manifest hash, output/raw-input hashes, determinism
receipt, and SDK validation receipt; `counts` distinguishes DOC-derived and
public-model packages. The SDK reports preserve every error, part,
and XPath. Git HEAD and dirty-worktree status are separate fields; an uncommitted
run is identified by its source hashes rather than assigned to a clean commit.
Failed stages leave their completed artifacts and receipts in place.
Use a new output directory for each run; passing receipts are never reused.

For a restricted host where MSBuild cannot create its named mutexes,
`--cached-nuget DIRECTORY` performs a fresh build with the installed .NET 8 SDK
C# compiler and the three hash-pinned `.nupkg` archives in that directory. It
verifies the unchanged project contract, reference assemblies, SDK implicit
imports, package bytes, and resulting dependency assembly bytes. This mode has
no network access and runs exactly the same validator and gate controls; it
does not substitute the previously built Quds validator. The build receipt
states which compiler path was used.

Schema validity is a separate gate from pagination, rendering, and review
semantics. A passing schema result does not establish visual fidelity, correct
accept/reject behavior, complete geometry/effects, or ink reconstruction. Use
the native fidelity and review oracles for those questions.
