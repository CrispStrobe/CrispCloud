# Visible fallback for embedded objects

Measured runtime: `d08627583500063f6cf67a1a1d756dae3f9594f4`, tree
`4281243b63a2bb07655f15bfe5fe1a5e50a8dfcd`. The native measurement required
that exact clean commit and checked 909 source/configuration inputs before
and after. This checkpoint adds evidence only.

The former VML textbox label produced a blank native rectangle. The new
fallback embeds one fixed, reviewed PNG containing “Embedded object” and
“Preview unavailable” and uses a self-contained VML picture type. Each
occurrence keeps its own object identity, original embedded bytes and
owning-part relationships. Generated pixels are explicitly reported as a
placeholder, never as a recovered source preview or source image.

## Results and scope

| Check | Result |
| --- | --- |
| Focused Dart checks | 36 passed; analysis clean |
| Independent main/header/footer relationship control | Three distinct object identities and payloads, one shared image; hidden insertion/deletion wrappers retained |
| Independent Open XML SDK 3.3.0, Office 2019 | 26 DOCX files, zero errors |
| Native reviewed insertion | Exact 288 × 144 reviewed RGB pixels present |
| Native accepted insertion | Exact reviewed RGB pixels present |
| Native rejected insertion | No image displayed |
| Original embedded payload | Byte-identical in all retained packages |
| Native input mutation | None |

The native renderer was LibreOfficeDev `26.8.0.0.alpha0`, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. Isolated native profiles disabled
macros and link updates; no object handler was activated. The accepted and
rejected control packages change only `word/document.xml`; all other ZIP
members remain byte-identical. All three native documents contain the same
source body text and one page. The label is image content, not searchable
PDF text.

This establishes fallback visibility and source-payload preservation. It
does not establish original preview recovery, exact source object placement,
Microsoft Word activation, or universal OLE interoperability. The picture
type's native placement differs from the former broken rectangle, so no
source-layout equivalence is claimed. The converter continues to report
partial formatting for unsupported original presentations.

## Portable evidence

`artifacts.tar.xz` contains 110 files (1,819,874 uncompressed bytes): every
final source and converted document, all three native PDFs and raster
outputs, exact SDK reports, execution logs, measurement and review scripts,
relevant runtime sources, and the deterministic image recipe. It also
retains the original blank-image prototype and the successful picture-type
experiments, separately labeled under `prototypes/`. The first focused test
attempt failed because the temporary directory was missing; that setup
failure remains distinct from the passing rerun. Disposable native user
profiles are the only final-run output omission.

```sh
python3 doc/evidence/ole-visible-placeholder-20261113/verify.py
python3 -O doc/evidence/ole-visible-placeholder-20261113/verify.py
```

The verifier requires Pillow and PyMuPDF. It checks exact archive inventory,
sizes and hashes; binds reports to actual source, DOCX and PDF bytes;
recomputes native image pixels and bounds; verifies review projection scope;
and checks complete SDK input coverage. Its checks use explicit errors and
remain active under optimized Python. This archived measurement is specific
to the pinned runtime; combined acceptance is recorded separately.
