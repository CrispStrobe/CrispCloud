# CrispCloud security and parser-robustness gaps (November 2026)

Status: 24 November 2026. This is the host-side register for untrusted files,
archives, mail bodies, previews and documents. The shared Office/PDF engine
register is in the Quds repository at `docs/security-gaps-2026-11.md`.

This register records what is actually bounded today. It does not turn a local
test into hosted, installed, live-provider or App Store evidence.

## Source pins

| Component | Revision | Notes |
| --- | --- | --- |
| CrispCloud | `ae968f74` plus this register's follow-up commit | Audit branch `audit/security-gaps-20261124` |
| Quds Office engine | `f13e934d2` plus the shared security follow-up | Vendored/pinned copies must be reconciled before an integrated build |
| `covfuzz` | `715a0cd` | Blind fuzzing and minimized reproducers |

## Severity scale

| Level | Meaning |
| --- | --- |
| **S0 Critical** | Code execution, sandbox escape, credential disclosure, or path escape from extraction. |
| **S1 High** | Small untrusted input can exhaust memory/CPU or crash the app; a preview can silently misrepresent trust. |
| **S2 Medium** | Reliable UI freeze, wrong output or a subset gap with a bounded workaround. |
| **S3 Low** | Cosmetic or rare fidelity gap. |

## Register

| ID | Severity | Area | Finding and evidence | Status |
| --- | --- | --- | --- | --- |
| CC-SEC-001 | S1 | Archive decompression | Most archive readers cap **actual produced bytes**, not just headers: PNG carving (`archive_png_carving_service.dart:844-906`), ZIP recovery (`:901-946`), CAB MSZIP (`:366-404`), DMG (`:381-432`), gzip (`archive_streamed_reader.dart:401-471`), 7z Deflate (`:352-470`) and XAR (`archive_package_readers.dart:346-351,524-548`). Keep these as regression boundaries. | **Verified** |
| CC-SEC-002 | S2 | Archive CPU/isolation | Several readers and `decompressSingleFile` run on the main/UI isolate up to the 64 MiB viewer limit (`archive_viewer_service.dart:1561`, `internal_viewer_dialog.dart:829`). Memory is bounded; a slow crafted archive can still freeze the UI. | **Open** — move preview/work to an isolate or cooperative worker. |
| CC-SEC-003 | S2 | Archive path safety | Extraction normalizes entry names, rejects absolute/parent traversal and duplicate destinations (`archive_service.dart:267-300`). Keep a regression test for every new writer/reader profile. | **Verified** — add a fuzz case for names. |
| CC-SEC-004 | S2 | CAB folder allocation | `Uint8List(folder.size)` is bounded by `maxFolderBytes` (default 64 MiB) and block sizes are checked before allocation (`archive_cab_reader.dart:204-225,269`). | **Verified** — no 2 GiB header-only allocation. |
| CC-SEC-005 | S1 | Office engine pin | CrispCloud embeds/pins Quds. DEFLATE, PDF and OPC limits only protect the host after the pin includes this audit wave. | **Partially closed**: CFB sector bounds, glyph-outline bounds, aggregate ZIP-recovery budgets and inline-JPEG framing are synced into the vendored engine with regressions. A full source-pin diff against the latest Quds main remains open. |
| CC-SEC-006 | S1 | PDF page errors | The shared engine now exposes `PdfDisplayList.error`, but the preview/editor must show a visible page error instead of a blank-looking page. | **Open** — host UI follow-up. |
| CC-SEC-007 | S1 | PDF signatures | The shared engine now distinguishes digest match from signature/trust; CrispCloud must not label any PDF as “verified” or “signed by a trusted party” until PKIX verification lands. | **Open** — no trust UI claim. |
| CC-SEC-008 | S1 | Saved mail HTML | Remote images and active HTML stay inert until an explicit action; remote image loading is bounded by bytes, pixels, request count and time. | **Verified** — Mail reader tests. |
| CC-SEC-009 | S2 | Legacy Office preview | Legacy `.doc`/`.xls` preview is explicitly text/limited; macros and ActiveX are inert. Never present preview as full fidelity. | **By design** |
| CC-SEC-010 | S2 | Archive coverage | ZIP/7z/RAR/DMG/ISO/UDF/CAB/CPIO/AR/XAR profiles have documented limits; unsupported methods refuse rather than guess. | **By design** — see `docs/archive-format-coverage.md`. |
| CC-SEC-011 | S1 | Fuzz coverage | No committed, reproducible fuzz job covers archive readers, saved EML/MBOX, MSG and the viewer parser surface at each revision. | **Verified locally**: `fuzz_archive_codecs.dart`, `fuzz_internal_viewer.dart` and `fuzz_mail.dart` are committed; the bounded workflow runs them. Mail fuzzing found the CFBF escape below. |
| CC-SEC-012 | S1 | Outlook CFB sectors | The vendored `CfbfFile` used untrusted stream-start/FAT/DIFAT sectors before checking the container, so a mutated MSG escaped `RangeError` through CFB preview. | **Closed** in the vendored engine: sector and size checks now return typed `CfbfException`; `fuzz_mail.dart` is clean over 50,003 runs and the engine regression covers both start-sector and DIFAT cases. |

### Saved-mail and compound-file hardening

- `fuzz_mail.dart` found a `RangeError` escape in CFBF stream-sector reads
  reached by Outlook MSG preview. The vendored engine now validates stream
  size, FAT/DIFAT and mini-FAT indices before every sector view and returns a
  typed `CfbfException`.
- `bounded_cfb_reader_test.dart` pins the start-sector and DIFAT repros at the
  engine boundary; `email_message_service_test.dart` pins the host MSG path.
- The same fuzz harness covers EML MIME nesting, transfer encodings, MBOX
  indexing and per-message decoding. It completed **50,003 runs clean** after
  the fix.

## Fuzz targets

High-value pure-Dart/IO surfaces:

| Target | Entry point | Seed | Notes |
| --- | --- | --- | --- |
| ZIP metadata | `openViewerArchive` | small ZIP | names, sizes, duplicate/traversal |
| ZIP recovery | recovery service | truncated ZIP | actual-output and time budgets |
| PNG carving | `ArchivePngCarvingService` | valid PNG | chunk lengths, zlib/Adler |
| CAB | `openCabArchive` | small CAB | folder sizes/checksums/MSZIP |
| DMG | `openDmgArchive` | small DMG | chunk headers/zlib |
| 7z | `openSevenZipArchive` | small 7z | folder/dictionary limits |
| Mail HTML | safe HTML projection | transactional mail | deep nesting, CRLF, remote URLs |
| Saved EML/MBOX/MSG | `parseEmailMessage`, `parseMboxDocument` | MIME, mbox and CFBF seeds | header/body/MIME/CFBF limits; committed `fuzz_mail.dart` |

Prefer `covfuzz` for blind campaigns and minimized reproducers. Use
`package:fuzz` only for a specific deep precondition where its libFuzzer
feedback is measurably better; do not add two permanent fuzz frameworks without
a measured reason.

## Closure order

1. **S1:** reconcile the Quds pin with the shared DEFLATE/PDF/OPC limits and
   verify the host actually uses it.
2. **S1:** add the committed archive/mail fuzz harness and a bounded CI job.
3. **S2:** move synchronous archive preview work off the UI isolate.
4. **S2:** surface PDF page errors and never present digest-only signatures as
   verified.
5. **S2:** keep extraction path and archive-profile regressions in every
   writer/reader change.

## Verification commands

```bash
flutter analyze
flutter test

# focused archive/security suites (names may vary by branch)
flutter test test/archive_*test.dart test/email_message_service_test.dart

# bounded blind fuzzing
dart run tool/fuzz_mail.dart 5000
dart run tool/fuzz_archive_codecs.dart 5000
dart run tool/fuzz_internal_viewer.dart
```

Local runs are not hosted CI or installed-app acceptance. Native release claims
still require the signed build and launch checks in `AGENTS.md`.
