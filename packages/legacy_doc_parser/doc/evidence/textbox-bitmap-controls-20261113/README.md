# Embedded bitmap textbox controls

Four completed runs retain **831 archived files**, **64 lossless RGB raster
pages**, **10 initial observations** and **12 repeat cycles**.
Repeated controls across runs are observations, not additional independent
designs. The final run measures clean remote runtime
`237509e6d752229b2dbca10f23d19d19c30a07a8`, tree
`2a73ab5c933157c77a0b5018dc85e0ea72ae202d`. Earlier runs retain their original
dirty-worktree identities based on `9c02110`, including the pre-fix picture
result. Every build input was snapshotted at measurement time and is bound by
its original hash.

## Results and source controls

| Final control | Candidate vs authored OOXML | Candidate vs source DOC | Three repeats |
| --- | --- | --- | --- |
| Picture | Exact | Exact | Exact against first import and regenerated DOC |
| Texture | Exact | Tile raster differs; zero word drift | Stable against first import; same native DOC tiling difference |
| DIB pattern, 96 DPI | Exact | Tile raster differs; zero word drift | Native first export changes pattern to colored texture; later parser output stable |
| DIB pattern, 75 DPI | Exact | Tile raster differs; zero word drift | Native first export changes pattern to colored texture; later parser output stable |

All **12 cycles have zero word drift** against the previous parser import and
their regenerated binary. Three cycles are raster-exact against regenerated
DOC, ten against the previous import, and six against the first import. The
uncorrected parser loses bitmap paint and displaces words by 1 point in these
qualified explicit-border controls.

`probe-1` retains the pre-fix picture observation. `probe-2` measures picture,
texture and an independently authored PNG pattern. Native DOC export changes
that pattern to a colored type-2 texture, so that observation does not qualify
type-1 pattern support. `probe-3` introduces real type-1 DIB controls at two
densities. `probe-4` repeats the qualified controls three times on the clean
published runtime.

The DIB controls are independently declared 8-by-8, one-bit, two-color source
images. The source helper preserves the original DOC export, creates a new
copy with the explicit type-1 foreground/background operands, replaces exactly
one global BLIP slot and appends the DIB BLIP to `WordDocument`. Record lengths,
the FIB OfficeArt extent and appended stream length are updated. Source FSPA
coordinates and original table bytes stay unchanged. The retained source
control records bind the declared operands, DIB, UID producer and both binary
files. The helper uses the compound-file reader/writer; it never calls the DOC
conversion writer.

The native binary and VML importers take different text-frame bitmap paths.
This evidence establishes source image/paint preservation and exact agreement
with independently authored VML, with the native tiling difference separately
retained. It does not establish RGB equality between those native paths or
certify all Word14 layout. See [the runtime contract and primary sources](../../textbox-paint.md#embedded-picture-texture-and-monochrome-pattern-fills).
Original fixtures, failures and reviewed goldens are unchanged.

## Verification and portable checks

The manifest binds every archive member, summary and support file. The archive
contains source DOCX packages, original and controlled native DOCs, parser
outputs, PDFs, lossless compressed 72-DPI RGB pages, execution logs, source and
tool receipts, and exact build inputs. Native profiles and reproducible
converter executables are excluded; executable hashes and compiler logs remain.
`native-artifacts.tar.xz` is **453,652 bytes**, SHA-256
`2ad79d0fcc27aea32ac3a62241677503afd98c88564d862b9f2ac3c3dc4dd25a`.

Run from the repository root using normal Python:

```sh
python doc/evidence/textbox-bitmap-controls-20261113/verify.py
```

The verifier refuses optimized Python, verifies every retained byte and raw
raster, checks source-control and repeat binary/DOCX identities, and recomputes
the reported render comparisons. The schema corpus contains eight required
`textbox-fills/` controls, each with zero Open XML SDK validation errors. Their
exact source/output packages and reports are retained here. The first direct
validator attempt omitted the environment's `TMPDIR` and failed to find `/tmp`;
that original observation is retained beside the successful configured run.
The focused regression log records **74 passing tests**.

Sealed native tools are LibreOfficeDev 26.8.0.0.alpha0 at
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, `pdftoppm` and `pdfinfo` 26.05.0,
and `pdftotext` 25.03.0. Reports retain compiler/font identities and original
source snapshots. `seal.py` records deterministic packing without rerunning
native tools or replacing any observation.
