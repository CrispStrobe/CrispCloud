# Font and viewer audit evidence

Audit runtime baseline: `087b73a14b64c445c5eb717f187925b5472ed9b3`.
Documentation-only checkpoint: `b3b03807bcbde5f77fd842e8eb9918807be64376`.
Source hashes and baseline fields distinguish that checkpoint from a code change.

This evidence supports [the assessment](../../document-fonts-and-viewer-policy.md).
No production font/renderer/packaging optimization or application rebuild was
performed by these probes.

## Files and scope

| Files | What they establish |
| --- | --- |
| `footprint.json`, `measure_footprint.py`, `footprint-methodology.md` | Existing release web asset bytes/hashes; selected built assets match source; static engine partition and standalone font inventory. |
| `minify-estimate.json`, `minify_estimate.mjs` | In-memory minification estimate of 32 generated JS outputs, preserving legal comments; selected compression comparisons. Not an optimized production build. |
| `font_widget_probe_test.dart`, `font_widget_probe.log` | Real Flutter HtmlWidget preserves plain Arial but retains CSS hex escapes as a literal family name. Bold and size survive. One diagnostic test passed. |
| `font_css_parser_probe.dart`, `font_css_parser_probe.log` | CSS parsing/string unquoting underlying the widget result. |
| `font_coverage_probe.dart`, `font_coverage_probe.log` | Actual packaged-font cmap coverage of specified samples. Not full shaping/script validation. |
| `font-probe-provenance.json` | Flutter/Dart/package versions and source/font hashes. |
| `inspect-postscript-fonts.py`, `postscript-font-inventory.json` | Exact pinned Stet; 37 verified native resources, 35 fonts, mapping and source hashes. Not a WASM rebuild or arbitrary document-font qualification. |

The complete size inventory contains 133 selected files. The earlier continuation's
131-file check covered 42 runtime files, 86 original notices, manifest, index and
aggregate; this audit additionally inventories two already-present host notices.
Both checks describe the same built content.

Raw, gzip and Brotli numbers have different meanings. Python/Node use different
recorded zlib versions; compare within the same series. None is an APK/IPA/store
download size or network waterfall. Stet fonts are inside WASM and must not be
added twice to package size.

## Reproduction

From the repository root with pinned dependencies and existing release `build/web`:

```sh
python3 docs/evidence/document-fonts-20261113/measure_footprint.py --repo .
node docs/evidence/document-fonts-20261113/minify_estimate.mjs .
flutter test --no-pub --reporter expanded docs/evidence/document-fonts-20261113/font_widget_probe_test.dart
dart --packages=.dart_tool/package_config.json docs/evidence/document-fonts-20261113/font_css_parser_probe.dart
dart --packages=.dart_tool/package_config.json docs/evidence/document-fonts-20261113/font_coverage_probe.dart
python3 docs/evidence/document-fonts-20261113/inspect-postscript-fonts.py --app . --stet /path/to/stet-at-58c7066817f7939789c6f030515c02e94fb0353b
```

The widget probe intentionally asserts the observed defect. It is an audit
reproducer, not a regression expectation to preserve after fixing fonts. Its
passing result does not establish correct font resolution. Regenerate source
provenance if implementation inputs change.
