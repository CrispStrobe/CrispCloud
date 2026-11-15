## Why

Advance Stage 6 of the storage roadmap with reviewed recovery of complete supported PNG images from a bounded damaged file or image. This continuation also reconciles the observed Office and parser work and replaces stale qualification claims with source-bound local receipts. The earlier disk-capacity blocker is resolved.

## Resulting behavior

- **Recover PNG images to ZIP…** accepts one native local regular file of at most 64 MiB through the context menu, Tools menu or command palette. Review shows candidate ranges, dimensions and findings before selection.
- Only validated noninterlaced 8-bit grayscale, RGB, gray-alpha and RGBA PNGs are selectable. CRCs, chunk order, complete zlib framing and Adler-32, exact scanline lengths and filter bytes must pass.
- Selected images and `recovery-report.json` go into a separately verified new ZIP. The report retains source offsets, hashes, classifications and coverage; recovered names do not claim original filesystem names.
- The shared queue owns admitted work. Publication rehashes source and staged output after the durable committing checkpoint. The exclusive-publication guard checks captured authority and cancellation synchronously after the final asynchronous path probe; pause epochs require fresh proofs, including transient pause/resume.
- Existing destinations and source files are retained. A completed installation remains successful when Stop or a completion observer arrives afterward. Restart requires fresh scanning and review; the journal retains digests and receipts, not source bytes.
- The PNG feature adds no runtime dependency. Its original code is MIT; the source inventory records SHA-256 integrity use without changing encryption or distribution decisions.

## Reconciled source and fixes

The final application-source checkpoint is **[`4c2b6ddd`](https://github.com/CrispStrobe/CrispCloud/commit/4c2b6ddd87c854525b075dfda8783ad209565d5e)**. It mirrors canonical Quds **`47e44e0ae35adcc406eee2a2ae2118dd2a4a082a`** and parser **`08296edbee08da013a8ff718798972552ccd03f7`**. Raw final gate receipts are saved through **[`f43eb775`](https://github.com/CrispStrobe/CrispCloud/commit/f43eb7752f3c98505600a4b7d919537602dfb790)**.

The original finite inventory closes 53 relevant heads: 49 ancestors and four proved supersessions. Main/PR #120, document workspace, worksheet navigation, inline pictures, wrap-text and storage histories remain preserved. Subsequent observed advances are audited separately, ending at integration input **`3e9560c9`**. That input adds real comment serialization source, so its predecessor receipts retain their original scope. This does not claim an additional rolling upstream refresh.

Concrete integration corrections include:

- **ODS geometry and coverage:** preserve native default/base column widths after reproducing an 81px → 64px copy-save failure. Restore the exact three deleted currency-symbol, inherited styled-padding and native-geometry regressions without relaxing covered-cell or comment limits.
- **ODS dates and annotations:** preserve authored literals/component order and keep namespace-aware notes separate from cell values, with bounded expansion and explicit refusal of ambiguous structures. Author IDs retain first-seen order using indexed lookup.
- **Comment ownership:** capture existing worksheet ownership before package mutation. New sheets cannot delete, overwrite or adopt unrelated legacy-named parts. A distinct empty authority survives save/reopen/add/clear while orphan XML, content type and outgoing relationships remain unchanged. Four reproduced failures preceded the fix; 28 focused comment tests and strict analysis passed afterward.
- **Underline controls:** both ribbon and Font dialog support all 18 styles, with complete labels in eight translated locale maps. Regression coverage selects each option, applies Font unchanged, then saves and reopens DOCX.
- **Legacy Word recovery:** handle the specific damaged-directory `CfbfException` through the existing opt-in, bounded text-only DOCX fallback. Strict/default, DOCM, encryption and input/work refusals remain. The host keeps unknown source inventory unknown, requires loss review, preserves prepared bytes on retry and saves a separate create-only copy.

## Completed local qualification

All 13 required local gates have accepted passing receipts. Flutter/Dart runs used the pinned Flutter 3.47.8 / Dart 3.13.7 toolchain with native hooks enabled.

| Scope | Recorded result |
| --- | --- |
| Application | **903 tests / 65 suites** |
| Office engine | **275 tests / 23 suites** |
| Office editor | **105 tests / 11 suites** |
| Strict host analysis | **102 files**: 76 app, 19 engine, 6 editor, 1 CLI; no issues |
| Standalone parser | **4,132 tests / all 144 suites**, plus clean strict analysis of 18 files |
| Generic Office oracle | **12 actual DOCX/XLSX/PPTX outputs** and **17 controls** |
| Comments oracle | **9 XLSX outputs + 2 authored manifests**, **1,154 independent checks** |
| Source integrity | **2,336 managed files** match canonical identities; **85 controls** pass |
| Portable PNG | Each of Dart VM and actual compiled JavaScript passes **8 cases / 248 assertions**; independent readers verify **8 ZIPs and 10 PNGs per runtime**, with matching outputs |
| Navigation | **12 separate capture tests**, six workbooks and two font-backed host PNGs; both previews visually reviewed |

The primary host total is **1,283 tests across 99 suites**. Navigation, focused reruns and historical results are not added. The existing complete parser run at **`09a4a531`** was independently audited against exact source `08296edb`; a new full parser run was not executed in this workspace. Hidden loader events and earlier overlapping parser runs are excluded. Its standalone dependency graph remains a separate scope from host acceptance. Linux goldens retain exact comparisons and bundled fonts, with no relaxed tolerance or reference regeneration.

The first final PNG attempt failed on launcher execution permission and was saved at **`44a7339`**. **`6e556b34`** restores the launcher's executable mode, with script/application contents unchanged and plan metadata updated; the passing retry is saved at **`9e3594`**. The failure remains excluded from acceptance.

**The independent final audit passed on its first attempt.** It verified all 13 accepted gates against 8,621 source/resolution inputs and 49 recorded tool inputs, complete raw event counts, exact artifact inventories, canonical source identities and generated-output bindings. The foreign parser environment script retains only its stable recorded hash; that evidence limit is explicit in the audit. Each completed gate, including failures, was saved remotely before proceeding. Checkpoints use `[skip ci]`; **no GitHub Actions run was polled, awaited or restarted**. This PR remains a draft.

[Final evidence and review](https://github.com/CrispStrobe/CrispCloud/blob/10891b06a6da9f2502960cdbfe34b30eed271665/docs/evidence/storage-carving-20261115/local-gates-20261115T124645/README.md) · [Acceptance index](https://github.com/CrispStrobe/CrispCloud/blob/10891b06a6da9f2502960cdbfe34b30eed271665/docs/evidence/storage-carving-20261115/local-gates-20261115T124645/final-acceptance.json) · [PNG profile and limits](https://github.com/CrispStrobe/CrispCloud/blob/4c2b6ddd87c854525b075dfda8783ad209565d5e/docs/archive-png-carving.md)

## Boundaries

Input/output limits are 64 MiB, with separate parser-work and expansion bounds. Indexed/interlaced/animated PNGs, other bit depths, unknown/compressed ancillary chunks and smaller zlib windows explicitly decline. Fragment reconstruction, original names/directories, physical devices, rescue imaging, undelete and JPEG/PDF carving remain outside this profile.

Portable-core acceptance does not enable browser/cloud publication or establish other-platform execution. Native verify/rename is not atomic compare-and-swap against arbitrary external writers. Before/after snapshots are not hermetic cache proofs. Optional private corpus scans remain excluded. Independent output checks do not certify broad Open XML schemas, rich/VML comment geometry or external Office rendering. This is draft implementation review, not a signed release.
