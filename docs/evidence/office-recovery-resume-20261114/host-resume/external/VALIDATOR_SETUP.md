# Native-fill external validator provenance

## Final result

The corrected independently authored source and all three actual host-saved
workbooks passed the existing OpenXML SDK validator: **4 files, 0 failures,
exit code 0**. The validator's own positive and negative self-tests passed
immediately before this invocation. The final host input capture identifies app
commit `9101520b12b7a9f17af10757775b9f6e98cbc4bf`.

The final receipt is `attempt-2/validation-summary.json`; the SDK's direct output
is `attempt-2/schema-report.json`. All four hashes agreed with the host agent's
finalized inventory and remained equal before, during, and after validation.
The copies under `attempt-2/artifacts/` have the same exact bytes.

| Package | SHA-256 | Schema errors |
| --- | --- | ---: |
| `source.xlsx` | `f5ce92914660d846682688046f843d6fad26e8206201e10ac305ad05cfb16f97` | 0 |
| `saved-1.xlsx` | `6c5d72466efcf72823e605ffb8c80fc8a61e73e466294bfeb19037bb40ce48c8` | 0 |
| `saved-2.xlsx` | `f0082d65160634491318cbc462cebcc727060182689bb7ee26b6c1f1d824fe95` | 0 |
| `saved-3.xlsx` | `4256287299bafb51fc7271ffb2fa77b2fcd165ca3f36975e29b6d4b0bb220ac9` | 0 |

## Preserved diagnostic sequence

- `native-fill/` is the first four-file external validation attempt. Its three
  actual host outputs had zero schema errors. Its independently authored input
  had one error in `xl/styles.xml`, at
  `/s:styleSheet[1]/s:fonts[1]/s:font[1]`: an unexpected `s:sz` child.
- `font-order-diagnostic/` retains a separately labeled diagnostic copy. Changing
  only `s:color, s:sz` to `s:sz, s:color` in that one font removed the SDK error;
  every other uncompressed package part was byte-identical. This file was
  assembled as a diagnostic and was never presented as an actual host upload.
- `attempt-2/` contains the separately executed final acceptance after the
  canonical raw fixture's font order was corrected and the real native-fill
  widget case reran through all three host uploads. The earlier evidence remains
  unchanged.

The XML values, fills, and font name were preserved by the correction. The
schema-valid font order is:

```xml
<s:font><s:sz val="11"/><s:color rgb="FF000000"/><s:name val="Calibri"/></s:font>
```

## Frozen validator and dependencies

The validator is the unchanged repository file
`CrispCloud/tool/office-validation/Program.cs`, SHA-256
`4d41f286855ed11a12ecdf0641773c33285847180a3e5cdbf43ce2385a099880`. The project file SHA-256 is
`e9e7985f8af8396d5b0dea81555e3c8ca51b7dba1af68a0e2cd4d2b238347e27`. It targets `net8.0` and requests
`DocumentFormat.OpenXml` 3.3.0. Its runtime dependency declarations resolve to
`DocumentFormat.OpenXml.Framework` 3.3.0 and `System.IO.Packaging` 8.0.1.
Validation uses the existing program's `Office2019` format target.

The official .NET SDK is **8.0.428**, with .NET runtime and reference pack
**8.0.34**. The downloaded SDK archive matched the SHA-512 in Microsoft's
release metadata. The NuGet archives and extracted assemblies matched the
previously recorded pinned SHA-256 values. `validator-provenance.json` contains
all official download URLs, checksums, dependency declarations, source hashes,
exact build and self-test commands, environment overrides, and exit codes.
The three retained `.nuspec` files preserve the complete package declarations.

The existing repository helper was copied unchanged as `validator-build.py`,
SHA-256 `f4af656d4c2c0a6149b6fe8b38476c92f9aae80896a1eceb1dfa7594524dce19`. It invokes the official SDK's Roslyn
compiler directly with the SDK reference pack and pinned NuGet assemblies.
This is the project's existing restricted-host build method. It uses the
unchanged validator and standard implicit usings. All runtime files stayed
within the task workspace; no system installation or renderer setup was used.

## Reproduce the schema check

1. Download the SDK archive and the three NuGet packages from the official URLs
   in `validator-provenance.json`, and verify their recorded checksums.
2. Extract the SDK into `toolchain/dotnet`. Place the NuGet archives and a copy
   of `validator-build.py` named `build_validator.py` in
   `toolchain/office-validation`. Create a workspace temporary directory.
3. Build from the repository's unchanged `Program.cs`, run its self-test, and
   validate the archived final XLSX files. For example, after setting these two
   task-specific paths:

```sh
VALIDATION_WORKSPACE=/path/to/workspace
VALIDATION_EVIDENCE=/path/to/this/evidence
export DOTNET_ROOT="$VALIDATION_WORKSPACE/toolchain/dotnet"
export DOTNET_CLI_HOME="$VALIDATION_WORKSPACE/toolchain/office-validation/dotnet-home"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export TMPDIR="$VALIDATION_WORKSPACE/toolchain/tmp"
python3 "$VALIDATION_WORKSPACE/toolchain/office-validation/build_validator.py" "$VALIDATION_WORKSPACE/CrispCloud/tool/office-validation/Program.cs"
"$DOTNET_ROOT/dotnet" "$VALIDATION_WORKSPACE/toolchain/office-validation/OfficeValidation.dll" --self-test
"$DOTNET_ROOT/dotnet" "$VALIDATION_WORKSPACE/toolchain/office-validation/OfficeValidation.dll" "$VALIDATION_EVIDENCE/attempt-2/artifacts" "$VALIDATION_WORKSPACE/repeated-schema-report.json"
```

A fresh build writes its own `build-receipt.json`; the assembly hash can vary
with build paths. Preserve that new receipt and compare source, project,
package, and reference versions against this frozen record. Keep the original
receipts unchanged.

`validate_fill_outputs.py` is the exact collector used for final acceptance.
It verifies the recorded validator and dependency hashes, checks that the host
input capture matches the current test and raw fixtures, reruns the self-test,
requires exactly four Office packages, validates the original host files,
and retains byte-identical copies. Its invocation is preserved in
`attempt-2/collector-invocation.json`; each actual SDK command and exit code is
in `attempt-2/commands.json`.

The schema receipts establish validation of these package bytes. The actual UI
operations and upload assertions are documented by the separate host test
collector and its frozen command in `attempt-2/host-inputs.json`. Rendering was
outside this scoped run.

## Publication files

Retain the three attempt/diagnostic directories and these small setup files:
`validator-provenance.json`, `validator-build-receipt.json`,
`validator-build.py`, `validate_fill_outputs.py`, `validator-build.log`,
`validator-self-test.log`, the three `.nuspec` files, and this note.
`publication-manifest.json` lists their byte sizes and SHA-256 values.
The SDK archive, runtime binaries, DLLs, and NuGet binary archives are excluded.
