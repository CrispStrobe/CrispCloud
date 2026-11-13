# Textbox paint controls, 13 November 2026

This archive retains the independently authored paint controls supporting
runtime checkpoint `33240acea1927a93a8c6022c507e7be26290f8b5` and the original
Word14 source inspection. It contains **1,194 files**, including **108 lossless
72-DPI RGB raster pages**, **15 initial case observations**, and **24 repeat
cycles** across three completed native runs. One rejected setup run is retained
separately. The observations include repeated controls across candidate
versions; they are not 15 distinct test designs.

The completed builds were exploratory worktrees based on
`4518f43c4eae84c5495a95068c0343f077d67ea0`. Their original reports preserve the
dirty-worktree identities and exact source-file hashes. The archive includes
the corresponding source bytes, deduplicated by SHA-256, and does not relabel
these executions as clean builds of the subsequently published checkpoint.

## Results and limits

| Run | Initial cases | Repeat cycles | Scope |
| --- | ---: | ---: | --- |
| `probe-1` | 0 | 0 | Rejected before native measurement because Dart created the baseline's missing package configuration during compilation |
| `probe-2` | 7 | 0 | Initial paint serialization; dashed-border frame correction was not yet applied |
| `probe-3` | 7 | 21 | Paint and dashed-border frame correction, with plain, opacity, dash, translucent-shadow, and disabled-shadow controls |
| `probe-4` | 1 | 3 | Independently authored opaque simple shadow with the completed runtime changes |

The 50% and 0% solid fill controls resolve prior raster differences. The dashed
2-point border and opaque simple shadow resolve prior 1-point word
displacement and raster differences. Each corrected control renders exactly
against its own native binary source, including all three repeats. Fill opacity
and dash also remain exact to the first parser import. The opaque shadow has a
first-repeat native raster change with zero word drift; later repeats are
stable against their predecessor. Plain, disabled-shadow, and line-opacity
controls retain their prior exact result. The native line-opacity control does
not establish that the bridge retained border opacity; model tests separately
protect the emitted property.

The old `shadow-enabled` cases in `probe-2` and `probe-3` used 50% opacity. They
remain unresolved: the native bridge writes color `0x7F665544`, outside the
resolved OfficeArt RGB operand, and normalizes unequal x/y offsets. `probe-4`
uses an opaque shadow. Original names and observations have not been rewritten.
See [the runtime contract](../../textbox-paint.md) for supported components and
the retained limitations.

`word14-source-model.json` is a read-only inspection of the original fixture,
whose SHA-256 is
`cab742e55b62e7a638ada283e877144a574e0412032ac5d797c1eb8cfedcfb9a`.
Its pattern, texture, picture, scaled-gradient, absent-width, and other unresolved
properties are outside these resolved-paint controls. The original native
failures and reviewed goldens remain unchanged.

## Retained evidence and verification

`paint-diagnostics.tar.xz` is 429,392 bytes, SHA-256
`68cc48bdd1d52e5ac9d46fae0579c4fcb4dd1036bdc77a8ca69636632d358825`.
`manifest.json` binds every member's path, length, and SHA-256 and binds the
summary and comparison helper. Original DOCX/DOC/PDF files, raw compressed RGB
pages, native and compiler logs, source receipts, and reports are retained.
Temporary native profiles and rebuildable converter executables are excluded;
their build identities, source bytes, compiler logs, and executable hashes are
retained. `seal_paint.py` records how the original scratch runs were packed.

Run from the repository root with normal Python:

```sh
python doc/evidence/textbox-next-20261113/verify_paint.py
```

The verifier checks every archive member, decompresses and hashes all raw
raster pages, verifies their PDF bindings, checks the exact recorded build
sources, and recomputes the render comparisons. It refuses optimized Python
because the inherited comparison helpers use assertions. The sealed native
tool identities are LibreOfficeDev 26.8.0.0.alpha0 at
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, `pdftoppm` and `pdfinfo` 26.05.0,
and `pdftotext` 25.03.0. Font and compiler identities remain in each report.
