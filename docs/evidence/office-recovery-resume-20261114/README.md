# Office recovery publication audit — 14 November 2026

This directory closes the interrupted app evidence-publication step. It links
the existing evidence by immutable commit and records a fresh audit of its
saved bytes. It does not relabel the earlier runs as tests of the current branch.

## Preserved evidence

| Evidence | Measured source | Durable record |
| --- | --- | --- |
| Canonical engine/editor validation | Suite implementation `36e65201`; repeated engine gate `c85c9f0a` | [Suite receipt](https://github.com/CrispStrobe/quds_office_suite/blob/41072ce7fac74eb54cdbc5e3803a45e605533b06/docs/evidence/office-recovery-20261114/suite-validation.json) |
| Native app outputs, schema and independent render comparisons | App `05905b86`; suite `c85c9f0a` | [External receipt](https://github.com/CrispStrobe/quds_office_suite/blob/41072ce7fac74eb54cdbc5e3803a45e605533b06/docs/evidence/office-recovery-20261114/external/external-validation.json), [exact archive](https://github.com/CrispStrobe/quds_office_suite/blob/41072ce7fac74eb54cdbc5e3803a45e605533b06/docs/evidence/office-recovery-20261114/external/external-artifacts.zip) |
| Integrated macOS cohorts, 12-file render and real browser-copy probe | App `455f6d5f`; suite `f9512763` | [Integrated acceptance](https://github.com/CrispStrobe/CrispCloud/blob/2316efe611663e08ebdde8786e9bb3fef280bf40/docs/evidence/office-recovery-20261114/integrated-macos/acceptance.json) |

The native external archive is 1,909,538 bytes and has SHA-256
`ec6911d1ee449e1927d2c1045dd5ff6a81a2b6db181129ce8d0560ac616908cc`.
It remains in its original canonical repository; this directory does not create
a competing copy.

## Freshly executed audit

[archive-audit.json](archive-audit.json) is produced by [verify.py](verify.py).
The verifier reads evidence from the pinned Git commits, so a later branch
checkout cannot silently change the measurement being audited. It verified:

- All 11 canonical supporting-file hashes, five external report hashes,
  the ZIP CRC, and all 235 archived entry lengths and SHA-256 hashes.
- All 149 host inventory entries against the exact archived packages. The
  historical schema reports bind to those 149 files plus four namespace files.
  Every bound report entry records zero schema errors.
- All 16 saved render inputs, decoded PNG fingerprints and saved page text.
  Four groups of three saves match their independent reference in page count,
  text and pixels. This recomputes comparisons of preserved outputs; it does
  not perform new LibreOffice conversions or extract text anew from PDFs.
- All 4,727 tracked inputs against the measured app commit. The remaining five
  of 4,732 input hashes describe generated package-resolution files whose raw
  contents were not retained. The sole collected/restored source difference,
  the SQLite test hook in `pubspec.yaml`, is reconstructed exactly.
- Both integrated macOS report hashes and all three browser source hashes
  against their declared host checkpoint.

Six verifier controls exercise valid archives, altered content, missing files,
unexpected files, duplicate names and incorrect byte lengths.

## Reproduce

Requires Python 3, Pillow, and local Git checkouts containing the pinned commits.
From the CrispCloud repository:

```sh
python3 docs/evidence/office-recovery-resume-20261114/verify.py --suite-root ../quds_office_suite
python3 -m unittest discover -s docs/evidence/office-recovery-resume-20261114 -p 'test_*.py'
```

## Limits of recovered evidence

The external archive retains the successful host collection receipt, commands,
4,732 input hashes and an LCOV hash. It does **not** contain the raw LCOV file or
the complete host test log. The earlier 241-test and 65.4% coverage totals remain
historical recorded results; this audit cannot recalculate them. No new Flutter
test, OpenXML validator, LibreOffice conversion or Chrome execution occurred in
this audit. The integrated browser receipt is preserved separately from the
native schema/render archive and retains its own source identity.

Current-source validation, live-provider/device journeys and authentic signed
Office fixtures require their own acceptance results. The four namespace files
are already part of the suite's 350-file schema scope; they are not four more
unique engine cases. Overlapping native and macOS cohorts must not be added.
