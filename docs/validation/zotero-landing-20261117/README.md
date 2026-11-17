# Final CrispCloud host qualification report

**Qualification is complete and independently reviewed** for CrispCloud implementation [`58a7e60b7a8b44d7809b6cf7c27541f41a3168dc`](https://github.com/CrispStrobe/CrispCloud/commit/58a7e60b7a8b44d7809b6cf7c27541f41a3168dc), tree `a6fd4865300febb0bc44cb294c84aa61bdd86750`, pinned to canonical Quds [`b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc`](https://github.com/CrispStrobe/quds_office_suite/commit/b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc), tree `642436fb32d73cb73706a4dd1c1fce32d0f2fb8b`.

Canonical [Quds PR #102](https://github.com/CrispStrobe/quds_office_suite/pull/102) has merged to main at [`518fb28b1cff7aeefad446cbf41c2832673c4d33`](https://github.com/CrispStrobe/quds_office_suite/commit/518fb28b1cff7aeefad446cbf41c2832673c4d33); the [canonical landing receipt](canonical-main-landed.json) records that result. [CrispCloud PR #220](https://github.com/CrispStrobe/CrispCloud/pull/220) is the host landing PR. Its qualification is complete; the host merge outcome will be recorded after landing. The [incoming-main baseline source review](landing-source-review.json) binds the combined source before the four-line note fix; the [final independent review](host-note-independent-review.json) binds the qualified final source.

## Separate, source-bound validation stages

| Qualified host / canonical source | Accepted local results | Evidence |
| --- | --- | --- |
| `96c514eb98f7ba596a385c8f60496bc6c5994307` / `837d06edbde08a2465e99cbbb15927ee4c87d8ac` | All 12 required gates; **108 required passes**: 41 host + 39 service + 28 Python. **2 supplemental writer-reader passes** recorded separately. | [Full run](host-full-run.md), [evidence archive](host-evidence.tar.xz), [artifact index](artifact-index.json) |
| `a8cc440260369214fce5cbae8b0230f425a46829` / `f510060e35d580cbc361985a123927705c92ddc4` | All 10 bounded gates; **40 service passes + 4 probes**: 2 existing ODT writer-reader probes and 2 list/Zotero-list probes. | [ODF amendment](host-odf-amendment.md), [evidence archive](host-odf-evidence.tar.xz), [index](host-odf-index.json), [independent review](host-odf-independent-review.json) |
| `58a7e60b7a8b44d7809b6cf7c27541f41a3168dc` / `b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc` | All 9 bounded gates; **12 focused ODT/ODF service passes + 2 note writer-reader probes**. | [Note amendment](host-note-amendment.md), [evidence archive](host-note-evidence.tar.xz), [index](host-note-index.json), [independent review](host-note-independent-review.json), [receipt summary](host-note-receipt-summary.json) |

All accepted test cohorts completed with zero skips. These stages overlap and must not be summed as unique coverage. Earlier receipts retain their original source identities. The final 12-service selection includes all ten preexisting ODT service tests, the accepted ODF nested-cell regression, and the new covered-note regression. Unchanged broad host/Python cohorts and other document formats were not rerun for the ODT-only note amendment.

## Two confirmed reader defects corrected

**Nested covered cells in ordinary tables.** An isolated negative control on `96c514eb` showed that recursive paragraph collection inside an ordinary table cell exposed retained covered-cell text, including a deeper nested story. The minimal reader change excludes paragraphs with a namespace-exact ODF covered-cell ancestor below that ordinary cell. Its committed regression checks ODT and ODS, preserves visible nested content and foreign elements with the same local name, and confirms hidden payload remains in raw XML. It passed in the 40-test service cohort and remains covered in the final focused run.

**Covered cells inside note bodies.** After the incoming footnote/endnote writer was synchronized, a separate negative control on published host `c66a84fcf5ce9016d8cc5b31b6d44f775d5a1149` exposed `HIDDEN COVERED NOTE` and `HIDDEN DEEP NOTE` through the note preview's inline traversal. A four-line ODT-only switch case now stops traversal at namespace-exact covered cells. The new committed regression checks a nondefault ODF namespace prefix, visible surrounding content, deeper hidden descendants, and a foreign namespace lookalike. The exact writer-reader probe that failed before the fix passed on `58a7e60b`.

Both negative controls retain their original logs, baseline commits, source/dependency maps and expected assertion failures in their respective archives. They are **not accepted passes**. Neither failure arose from compilation or disk pressure.

The final note probes also verify footnote/endnote lookup with equal native IDs, visible cached Zotero citation results, suppression of hidden instruction payload, unchanged original field data, and exact authored spaces/tabs/newlines in emitted note XML. Body whitespace remains visible; the host's existing note preview intentionally normalizes each displayed note to one line. The field-boundary suppression branch and authored whitespace encoder remain unchanged from the preceding qualified canonical source.

## Preservation and input integrity

The final source and independent review confirm:

- **2,559 managed paths:** 702 canonical paths and 1,857 standalone parser paths, with exact source and tracked-file guards passing.
- **20 host customizations** preserved byte-for-byte with their modes, **six original notices** preserved, and the standalone parser subtree/pin unchanged.
- **12 inherited executable-mode differences**, with zero newly introduced differences. The former eight-item inventory was limited: four additional differences already existed at the immutable baseline pins. Complete paths and before/after identities are retained in the preservation evidence; the original limited failed audit remains archived.
- **All 298 captured refs preserved** through the accepted integration ancestry and verified exact-tree aliases. The final note source retains that reviewed base; no additional all-ref scan was performed for the note amendment.
- Incoming host main `d4524de90dd403c9ce350a1d271ac70ce511256b` remains included. Its documentation and TestFlight evidence outside this work's evidence directory were preserved, along with application version `1.3.4+29`, production lock, macOS release workflow and Apple policy/inventory metadata.

The final run fingerprints **3,792 source files** and **6,002 dependency entries**, plus runtime binaries, graph/config inputs, wrapper declarations and probe hashes. Before/after maps are identical; tracked inputs still match the qualified source; the temporary analyzer config was restored. The focused harness has **107 packages**, including **97 hosted packages** whose exact versions and archive hashes match the production lock. Production dependency declarations and lock are unchanged, and no dependency resolution was rerun during the bounded amendments.

Strict analysis with fatal infos and no-change formatting passed for the changed reader and service test. Vendor guards, preservation checks, committed-diff whitespace checks and final integrity checks passed. Each archive contains exact commands, raw logs, source/graph maps, setup inputs, probe sources and concrete reproduction instructions. Independent reviews are published separately beside the archives.

## Scope

These are focused local source qualifications. They do not establish a full application/native build, complete viewer or export-dialog workflow, native/Wasm Harper, live Zotero/desktop integration, or Word/LibreOffice interoperability. Canonical suites and their counts are recorded separately. Flat list grouping and the stated note behavior are covered; native note numbering formats, restarts, custom marks, repeated references and malformed recursive note models are outside the note assertions. Host note preview coverage does not establish canonical note-body search coverage.

Release metadata and workflow source were preserved and fingerprinted; no workflow, signing or release execution was performed. **No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited.**
