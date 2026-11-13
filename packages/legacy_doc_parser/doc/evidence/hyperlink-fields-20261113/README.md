# Source-qualified hyperlink and reference fields

Two independent reader probes exposed real losses in the binary DOC conversion:
external hyperlink targets disappeared, and a native reference field became
cached text without its reference instruction. Both now have bounded fixes,
separate runtime commits, unchanged source fixtures and retained before/after
outputs. These are semantic preservation checks for two source DOCs, not a new
whole-corpus layout or pixel-equality certification.

| Runtime change | Exact published commit | Targeted result |
| --- | --- | --- |
| Exact HFD URLMoniker qualification | `3c8d22d2a2e2277d53547378bf66e62e951f0ccf` | Four URL fields restored: body, footnote, normal header and first header. |
| Reference-field HFD qualification, including one documented producer padding word | `d7e7883325d454a2bf01a44810c6f8336177d7a8` | REF retained with its original cached text; standard and padded REF/PAGEREF/NOTEREF forms have discriminating controls. |

The second runtime has tree `59fcbba75c55f75a809ea2e317b15f5116cafba5`.
This folder is a later evidence-only closure. The
[field contract](../../binary-hyperlink-fields.md) describes the exact supported
forms and their inert fallback. The earlier
[independent-reader research](../independent-readers-20261113/README.md) retains
the initial Antiword/Pandoc probes and their failures and limitations.

## External URLs: exact bytes, actual readers

The external-link source is the unchanged `word` binary from the sealed c5ff
native corpus, SHA-256
`2d2943d799d3a48430a90bff0bee68d7ab30fc2e5c26666d793160439e1f483d`.
Its four fields each spell a literal URL followed by U+0001. Actual
`CFSpec`, `CFData` and `CPicLocation` operands reference a `Data` stream HFD with
the exact same URL. These are the stored targets:

| Story | Marker CP | Marker FC | Data offset | Target |
| --- | ---: | ---: | ---: | --- |
| Body | 67 | 2182 | 0 | `https://example.com/body` |
| Footnote | 157 | 2362 | 163 | `https://example.com/note` |
| Normal header | 213 | 2474 | 326 | `https://example.com/header` |
| First header | 284 | 2616 | 493 | `https://example.com/header` |

The prior parser DOCX has neither hyperlink instructions nor hyperlink
relationships. Its cached text remains visible. Authored and native DOCX have
the body, note and header targets; the binary source has separate normal/first
header occurrences. The fixed parser output contains four locked `HYPERLINK`
fields with exact original targets. A real LibreOfficeDev 26.8 re-export reads
them and writes four corresponding `w:hyperlink` elements with exact external
relationships. No target URL was fetched or visited by the parser or probe.

Pandoc 3.1.11.1 reads **two Link nodes directly from the corrected DOCX** and two
from its native re-export, where the prior parser output had zero. These are the
body and footnote links: Pandoc's AST omits the header stories. The four-field
result is independently checked in the full OPC story parts, not inferred from
the AST count alone. Source cached text is unchanged across the parser fix.

## Reference fields: a separate producer quirk

The reference fixture was independently authored with locked `REF`, internal
`HYPERLINK` and `QUOTE` fields and deliberately distinct cached strings. Its
unchanged native DOC has SHA-256
`20b4e506f40b733cd7d9467ec2e6f2844e0efe319a61e8c4822e371facee0292`.
The source builder, authored DOCX, native DOC, prior parser/native DOCX and source
inspections are retained separately.

The `REF Target_A \\h` marker at CP32/FC2112 points to Data offset0. Its HFD is
117 bytes, but the declared location string (including one NUL) ends at byte115;
the remaining two bytes are zero. The internal HYPERLINK marker at CP79/FC2206
points to offset117 and its 115-byte HFD has no extra word.

The exact source revision of the installed LibreOffice renderer explains this
difference. `sw/source/filter/ww8/ww8atr.cxx`, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, has `InsertSpecialChar` declare
`target.length + 1`, then write a 32-bit zero after the target text. The complete
unmodified source file is retained with SHA-256
`3895da4595a2e5e0f8c6c7fd1a83546c62ecaaf4dc562d27904c8d7bea3a41c3` and
Git blob `9d698fac947da8e5687217d65fff8a7fdc46bb95`. This is an explicitly
qualified producer recovery, not a claim that the format specification defines
an extra HFD field.

The recovery requires a literal REF/PAGEREF/NOTEREF with explicit `\\h`, exact
location-only flags, matching target, exact CP/reference association and either
the standard extent or exactly one additional zero word. Malformed or ambiguous
metadata stays inert. The special padding is not accepted for HYPERLINK.
`binaryReferenceField` evidence distinguishes the change and records
`recoveredNativeTerminator=true` for this source.

The binary bridge had already dropped the authored locks. Direct native export
from that binary recalculated `CACHED-REF` to `ANCHOR-α`; this original native
observation is preserved. Our output retains `CACHED-REF` and the restored locked
REF instruction. Its actual native DOCX re-export retains both. The internal
link and QUOTE remain present with `CACHED-LINK` and `CACHED-QUOTE`.

## Independent source oracle

`source_oracle.py` uses only Python's standard library. It independently reads
the actual CFB FAT/miniFAT and streams, CLX piece CP→FC mapping, CHPX properties,
CFSpec/CFData/CPicLocation, and HFD bytes. It does not import the Dart parser.
It compares raw field delimiters, literal instructions and cached results at
their real global CP positions, then decodes each referenced target from the
actual `Data` bytes. The six binary metadata occurrences (four external, two
reference-fixture occurrences) all agree with the retained observations.

This helper deliberately supports the small version-3 CFB files and uncompressed
CLX pieces used here. It is an evidence decoder for these exact sources, not a
general replacement DOC parser. The source fixtures are never patched by it.

## Targeted acceptance

| Check | Retained result and scope |
| --- | --- |
| External change | Analyzer clear; 69 successful visible Dart tests across five exact suites. |
| Final reference runtime | Analyzer clear; 89 successful visible Dart tests across six exact suites, including all external tests and 20 reference controls. The clean frozen checkout is exact d7e788. |
| Native semantics | Two distinct binary DOC sources. One external re-export plus a preliminary and final reference re-export all completed successfully. Exact commands, requested isolated profiles, stdout/stderr and packages are retained. |
| Open XML SDK | Both corrected parser packages validated with zero errors under Open XML SDK 3.3.0 and .NET 8.0.34, using the previously built SDK8.0.428 validator. The report binds the exact package hashes; validator assembly hashes, original build logs/report and program source are retained. |
| Dart→JavaScript→Node | Both actual retained DOCs, seven fields total, source bytes unchanged, cached results preserved. The strengthened helper at `8eaa15bbe7dc1564692e60427294ae546d177b68` binds targets/results to body, footnote and header owners and rejects an actual same-length body/note target-swap DOC control even though all four global URL fields remain qualified. The production library is unchanged from d7e788. The original d7e788 execution and the new Dart3.13.7/Node24.22.1 compile/execution are retained separately. |
| Evidence controls | 30 resealed semantic corruptions rejected, plus the positive original-artifact control. All checks remain active with optimized Python. |

The preliminary reference measurement predates publication. Its runtime/test
bytes match the final commit except one explanatory comment changed from
"HYPERLINK instruction" to "field instruction". That original successful run is
retained under `reference/`; its raw source snapshots are retained too. The
separate `reference-final/` measurement uses the exact clean published d7e788
source. Both parser packages are byte-identical. Native ZIP identities remain
distinct because these are separate actual saves; no ZIP or pixel equality is
implied. The external source snapshots match the separate published 3c8d22d2
commit exactly.

## Retention and reproduction

`records.tar.xz` is **187,520 bytes** and contains **183 exact files**,
1,397,501 uncompressed bytes. `manifest.json` binds every path, size and SHA-256.
The bundle retains all source/native/parser packages, raw field inspections,
independent source results, complete acceptance command logs, source snapshots,
native producer source, schema results/build receipts, JavaScript entrypoints
and generated output identities. Reproducible compiled JavaScript/maps,
validator binaries and incidental native profile caches are omitted explicitly;
their relevant hashes or initial profile instructions remain recorded.

From the repository root:

```sh
python doc/evidence/hyperlink-fields-20261113/verify.py --repository .
python -m unittest discover -s doc/evidence/hyperlink-fields-20261113 -p test_verifier.py -v
python -O -m unittest discover -s doc/evidence/hyperlink-fields-20261113 -p test_verifier.py -v
```

The Git option checks measured source snapshots against the exact published
commit objects, even when the current checkout is a later integration. The
verifier recomputes the original source/HFD interpretation and OPC observations,
binds exact command arrays/cwd/exit codes/log hashes, required before/after input
receipts and suite event associations,
checks all visible and hidden completions, validates SDK row shape/package
identities, and binds each parser/native/AST target to its actual story and cached
text. JavaScript entrypoints must exactly match the executable generated template,
including the invocation and source payload; a commented-out invocation cannot
stand in for execution. The corruption
controls rebuild the archive and manifest before checking semantic rejection,
so a simple stale outer hash cannot satisfy them. No converter or external link
is activated when verifying this retained evidence.

The primary definitions are linked in the [field contract](../../binary-hyperlink-fields.md).
The independent container/text decoder also follows
[MS-CFB header](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/05060311-bfce-4b12-874d-71fd4ce63aea),
[directory entries](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/60fe8611-66c3-496b-b70d-a504c94c9ace),
[miniFAT](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/c5d235f7-b73c-4ec5-bf8d-5c08306cd023),
[MS-DOC Clx](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/bad26767-b575-44d3-9da3-96378d56ce14)
and [PlcPcd](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1caae71f-35c4-49d7-adf0-af5fc766331c).
