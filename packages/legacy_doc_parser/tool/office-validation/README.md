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
`tool/fidelity/schema.py` and currently contains 279 conversions. It covers
table geometry and revisions, shapes, metafiles, media, ink, fields, list
labels and sequences, section formatting, notes, headers, footers and textbox
boundaries, alongside retained native DOC inputs. The generator calls the
existing fixture producers and retains independently assembled binary inputs.
The fixed inventory catches missing cases, duplicate output aliases, and
unregistered Office files.

The separate `public_metafile_fixture.dart` and `public_compound_fixture.dart`
generators produce caller-built public-model controls for native image and
OLE/VBA activation. These outputs are not binary-DOC-derived cases. Their raw
inputs and model descriptions must remain alongside the DOCX/DOCM outputs
when validating them with the built validator. Package schema validation does
not validate or execute the contents of an OLE object or a VBA project.

The corpus is generated twice, and every retained source, output, and metadata
file must match byte-for-byte. The second generation is also checked against
the complete required inventory.

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
hash of the complete SDK report. The SDK report preserves every error, part,
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
