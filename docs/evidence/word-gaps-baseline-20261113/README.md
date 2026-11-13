# Current-main Word baseline — 13 November 2026

This receipt establishes the current CrispCloud baseline before another parser
roll. It preserves main's archive, Android release-packaging and release-evidence
work. No parser runtime, app version, dependency lock, policy decision, technical
fingerprint or source plist changed in this checkpoint.

## Measured source

| Component | Exact identity |
| --- | --- |
| Clean app source | [`794bde82693e07a6e04ed1490bfa228f154e6e5c`](https://github.com/CrispStrobe/CrispCloud/commit/794bde82693e07a6e04ed1490bfa228f154e6e5c) |
| App tree | `7a3465b8d6128acea60fd905143b01b657be68d9` |
| Existing parser pin | `fee9b84bdca8ae25a1839f7ef29690150115abe7` |
| Existing Quds pin | `5b3256522e0b504766c70dea42e27f666abc2d5d` |
| Managed Office files | 1,074: 653 parser files and 421 other files |
| Root lockfile SHA-256 | `135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5` |

The baseline ran on the exact clean main commit above after creating
`feature/office-fidelity-gaps-20261113`. The new evidence commit is separate from
that measured source. The source snapshot and every existing reviewed path
remained unchanged throughout preparation and acceptance. The mirror has no
app-local parser patch and matches the pinned Git bytes and executable modes.

## Completed checks

| Check | Result and boundary |
| --- | --- |
| Existing data-only Word cohort | 107 tests across eight suites; no failures or skips |
| Cohort input identity | All 1,176 captured source, dependency, fixture, runner and configuration hashes unchanged |
| Source synchronization controls | 24 passed; all 1,074 managed Office files independently verified |
| Production DOC/RTF/PPT/MSG JavaScript smoke | Passed using the genuine app package configuration |
| Actual installed-Office acceptance | All 13 existing LibreOffice/Poppler assertions passed on the authored formatting fixture |
| Apple preflight controls | 38 passed |
| Crypto release-evidence controls | 40 passed, with two expected macOS-only `plutil` skips |
| Ebook source controls | 22 passed |
| Actual CrisperBooks verification | All 279 pinned files verified at `32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52` |
| Existing release-input checker | Passed after genuine dependency resolution |
| Existing reviewed-source binding | Reproduced exactly across all 413 bound paths; no fingerprint refresh |

The original 107 assertions use the retained data-only adapter: it changes only
the test-framework import in copied suites and uses its separately captured
dependency configuration. Its 13 fake-process converter tests are separate from
the 13 actual native assertions. JavaScript and native acceptance use the real
production app configuration.

The native result retains `partialFormatting`. It checks source/prepared-byte
preservation, tables, basic character formatting, page definitions, referenced
stories, an image and independent PDF structure/text/image presence. The app
creates distinct temporary probe/conversion profiles and explicitly passes
`-env:UserInstallation`, avoiding shared LibreOffice profiles. Its existing tool
deletes the temporary PDF; this receipt does not claim retained full-page
artifacts, exact pixels/glyphs, arbitrary pagination or Microsoft Word execution.

## Genuine dependency and SDK restoration

Direct Dart 3.13.7 restored the current main lockfile with `--enforce-lockfile`,
then repeated resolution successfully with `--offline --enforce-lockfile`.
The lock contains 272 packages; the production configuration contains those
packages plus the app itself. All 238 hosted package archive hashes match the
authoritative lock. The five Git packages, 21 path packages and eight SDK
packages retain their declared sources. The root manifest and lockfile remained
byte-identical.

Flutter source is the official `3.47.8` Git tag at
`737ba8f885dc774b53b442759999a312c9461e4e`. The generated version metadata and
`sky_engine` package were copied unchanged from the official release archive,
whose published SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The retained release index, source/cache receipts and download records bind that
identity. No version metadata was synthesized and the Flutter launcher was not
invoked. Full engine/build artifacts were unnecessary for this baseline.

The first two Flutter download URLs included an extra `/flutter/` path segment
and returned HTTP 404. The corrected official `/flutter_infra_release/releases/`
URLs succeeded and the checksum matched. The original error records remain.
The first release-input check also correctly rejected the missing production
`package_config.json` before resolution; its original log is retained beside
the later passing check. Neither condition required an app configuration change.

The environment receipt records each native executable separately:
LibreOfficeDev 26.8.0.0.alpha0 build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, `pdfinfo`/`pdftoppm` 26.05.0, and
`pdftotext`/`pdfimages` 25.03.0. Temporary files use the explicit workspace
directory because the system `/tmp` directory is absent.

## Retained records

The [receipt](receipt.json) binds 51 lossless compressed records, including full
test events/logs, exact command arguments, before/after identities, production
and cohort manifests/configurations, dependency restoration, existing policy
and inventory bytes, runtime identities, and the SDK provenance records.
It contains no SDK binaries, dependency archives or duplicated native corpora.

```sh
python3 docs/evidence/word-gaps-baseline-20261113/verify_evidence.py
```

The verifier checks compressed and original hashes, completed tests, source
identity and immutability, source controls, production configuration, native
assertions, the existing reviewed binding and the official Flutter checksum
relationship. The retained command recorder and receipt builder document the
collection process. The earlier
[cohort helper](../word-continuation-7308125/run_word_cohort.py) remains unchanged.

This baseline does not run Flutter widgets, native ebook hooks or a full app
build. It does not qualify a release or automatically validate a later parser
pin. Earlier acceptance receipts keep their original source identities.
