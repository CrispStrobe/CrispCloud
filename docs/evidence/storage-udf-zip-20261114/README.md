# UDF and ZIP recovery qualification

This continuation implements read-only physical UDF browsing and reviewed ZIP
recovery to a new file on `integration/storage-capabilities-20261114`, reviewed
in [draft PR #101](https://github.com/CrispStrobe/CrispCloud/pull/101).

The final runtime revision is
**`20798b39a0c792e533a5c785294417f26db03272`**. The combined regression gate is
bound to **`b07b7b738a261cc79bffe5f47c3881e2412da2cd`**; the targeted follow-up
qualifies the two implementation changes after that gate: an aggregate UDF
full-path text limit and display of queue completion warnings in the ZIP dialog.
The [transition receipt](runtime-qualification-transition.json) identifies all
changed implementation and test files. Counts below overlap and are not additive.

## Implemented behavior

- UDF-only and ISO/UDF bridge images enter the UDF namespace for listing,
  preview and extraction. The admitted profile covers revisions 1.02, 1.50,
  2.00 and 2.01, 2048-byte blocks, physical Type 1 maps, FE/EFE, embedded and
  short/long allocations, bounded continuations, ordered multiple extents and
  sparse regular files. UDF-bearing images remain read-only. Supported UDF
  filesystems inside DMGs expose their files alongside the raw partition.
- **Recover ZIP to new file…** is available for a selected native local ZIP/CBZ
  in the context menu, Tools menu and command palette. It captures a bounded
  immutable snapshot and reviews locally verified stored/deflate records,
  including measured 32-bit deflate data descriptors. The user selects records
  and a new output name. Uncertain boundaries stop discovery; the report does
  not claim that a verified prefix is the complete original archive.
- The shared Operations queue owns an admitted recovery job. The workflow
  independently reopens its candidate, rehashes the original and staged output,
  repeats publication proofs after a pause, and installs a new file without
  replacing an existing destination. Completed publication stays successful if
  Stop or an observer error arrives afterward. Durable recipes contain source
  identities, digests, selected offsets and receipts, not captured payloads;
  restarting requires a fresh scan and explicit review.

The [UDF profile](../../archive-udf-profile.md) and
[ZIP recovery profile](../../archive-zip-recovery.md) define the complete
supported and excluded structures, resource limits and ownership contracts.
The earlier [LZFSE and GPT/MBR receipts](../storage-runtime-20261114) retain
their own qualified revisions; this continuation does not relabel those runs.

## Completed checks

| Check | Result | Source and receipt |
| --- | --- | --- |
| Combined native regression gate | **526 passed, 0 failed, 0 skipped**, 20 files | `b07b7b73`; [summary](udf-zip-final-gate-summary.json), [50-file binding](native-gate-source-binding.json) |
| Final targeted native gate | **96 passed, 0 failed, 0 skipped**, 4 files | `20798b39`; [summary](udf-zip-hardening-gate-summary.json), [binding](hardening-gate-source-binding.json) |
| Final UDF VM and actual compiled JavaScript | **26 groups / 500 checks** in each target, identical results | `20798b39`; [portable receipt](udf-path-budget-portable-receipt.json) |
| ZIP VM and actual compiled JavaScript | **15 groups / 131 checks** in each target over 12 independent inputs | Unchanged ZIP service; [portable receipt](portable-validation-receipt.json) |
| Final strict analysis | **38 changed Dart files, zero issues** | `20798b39`; [analysis receipt](udf-zip-hardening-analysis-receipt.json) |
| Production JavaScript release | **Passed** with original manifests, version `1.2.9+22` and full `20798b39…` source stamp verified in the compiled app | [Release receipt](udf-zip-web-release-receipt.json), [raw build log](udf-zip-web-release.log) |
| Independent UDF extraction | **3 images / 12 payloads** reproduced exactly by 7-Zip 26.06 | [Oracle receipt](udf-sevenzip-oracle.json) |
| Independent UDF descriptor checks | **3 images / 93 tag and CRC checks** | [Python receipt](udf-python-fixture-oracle.json) |
| Independent recovered ZIP readback | **8 candidates / 14 member CRC and SHA-256 checks** | [Python receipt](zip-python-candidate-oracle.json), [actual candidates](zip-recovery-candidates.json) |
| Fixture reproduction | **4 generated fixture/manifest files match byte-for-byte** | [Reproduction receipt](fixture-reproduction-receipt.json) |

The native follow-up contains 62 UDF core tests, 8 independent-review tests,
15 integration tests and 11 recovery-dialog tests. The broad gate also covers
the ZIP service, workflow and queue, all 26 container-viewer cases, existing
job recovery, format dispatch, menu layout, ISO reading/streaming/multiple
extents, and DMG reading/rewriting. Failure-path checks cover source changes,
staged corruption, output collisions, cancellation, pause/revalidation,
provider failures and post-install completion authority.

The production `main.dart.js` is 27,607,886 bytes, SHA-256
`a308d6341dd73477addda31aec855df7fc39116f78cebcdc6853e337787c309b`.
The existing Apple LZFSE license asset is present in the built application.
This is a compiled release qualification, not deployment or browser interaction
acceptance.

The earlier supplemental 60-case UDF SDK/Node receipt is preserved as historical
evidence. It adapted only the test-framework import to execute the same test
bodies outside Flutter; the later 62-case native suite and 26-group portable
driver qualify the final path-budget implementation. It is not an additional
set of distinct covered behaviors.

See [qualification.md](qualification.md) for commands, source identities,
analysis and release-build records. [Independent fixture notes](independent-fixtures.md)
explain external tooling, normalized images, derivative fixtures and the
limits of synthetic large-offset tests. Raw logs are preserved verbatim;
their hashes are part of the evidence inventory.

## Preservation and licensing

Main's native metadata catalogue and Rust CAF interchange at
`14e022eb51c417803a1913131e78912a8a19b3be` were merged before this continuation
through `e49c874653f38becf0018d868c6767c264306e3f`. The
[reconciliation receipt](reconciliation.json) records every fetched branch and
PR head and verifies reachability from the indicated checkpoint. Existing
branches and historical receipts remain available.

| Checkpoint | Preserved work |
| --- | --- |
| `e49c8746` | Merge main's native metadata/CAF work |
| `672c0dcc` | UDF reader, integration and independent images |
| `f618ca2d` | ZIP recovery core and independent fixtures |
| `b07b7b73` | Complete Commander/Operations integration and initial hardening |
| `74c6d43f` | Source-bound combined, portable and independent validation |
| `20798b39` | Aggregate UDF path budget and ZIP completion-warning display |

The new readers/workflow are original MIT code using the existing locked
dependencies. No new Pub or native runtime dependency was added. External
genisoimage and 7-Zip executables were used only as fixture/oracle tools and
are not bundled with the app. Existing project licensing is unchanged.

## Qualification boundaries

- UDF writing/repair, UDF 2.50/2.60, VAT, sparable and metadata maps, backup-anchor
  reconstruction and unsupported stream/record forms remain outside this
  profile. Direct UDF listings report open-volume state; the existing DMG
  wrapper does not forward child filesystem notices. Listing does not establish
  filesystem consistency or payload authenticity.
- The UDF reader requests at most 64 KiB at its `ByteSource` boundary; an F3
  cache fill or DMG chunk decode may be larger within its own bound. Decoded
  name components and retained full-path text each have a separate 16 MiB
  accounting limit. These are not total-process memory claims.
- ZIP recovery has separate 64 MiB source, member, expanded-data and output
  ceilings, and a 4,096-record ceiling. ZIP64, encryption, recognized split
  sets, arbitrary prefixes/self-extractors and stored data descriptors are
  excluded. The first publication UI supports native local storage; browser
  and cloud publication are not enabled by portable parser acceptance.
- External UDF images qualify revision 1.02. Other admitted revisions and
  unusual allocation forms use synthetic fixtures. The 8 GiB logical sparse
  prefix and 6.144 TB physical offset cases test exact addressing and bounded
  prefix reads, not complete extraction of physical files of those sizes.
- Native host tests use the documented temporary optional-ebook-hook profile
  in an isolated validation copy. Original production manifest and lock bytes
  are restored and checked. Device/native release builds, browser interaction
  tests and WebAssembly are not established by these local runs.
- GitHub-hosted checks are recorded separately from completed local
  qualification. Queued checks are not counted as passes.
