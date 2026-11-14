# External Word regression corpus — 14 November 2026

This corpus contains **88 distinct externally authored files**: **40 DOC and
48 DOCX**, totaling **2,845,581 bytes**. It is a fixed selection from Apache
POI's document regression suite at commit
[`47dcff769bb395034dddfd59c4609659b6dbc6a4`](https://github.com/apache/poi/tree/47dcff769bb395034dddfd59c4609659b6dbc6a4/test-data/document).
The selection was established before running our parsers against it.

The set broadens coverage beyond this project's own generated documents. It
contains 54 filenames associated with issue regressions, four website-named
upstream samples, and thirty named feature fixtures. These categories come
from upstream filenames. Original bug reports and websites were not
independently reconstructed, and not every sample is asserted to be an
unmodified production document.

## Provenance and verification

`manifest.json` records every upstream commit/path/URL, local path, byte
length, SHA-256 and Git blob SHA-1. Each downloaded file matched the pinned
upstream byte length and Git blob identity. All 88 SHA-256 values are distinct;
none matched an existing legacy parser DOC/DOCX fixture at collection time.

The original Apache POI [LICENSE](licenses/poi-LICENSE),
[NOTICE](licenses/poi-NOTICE), and [README](licenses/poi-README.md) are retained
without modification, with their exact source URLs and hashes in the manifest.

To verify all 88 documents and three upstream notice files:

```sh
python3 fetch.py --verify-only
```

To reproduce the downloads into a fresh directory:

```sh
python3 fetch.py --out /path/to/new-corpus
```

The downloader limits each input to its pinned size, verifies both hashes,
and refuses existing mismatched files. No document content or external
relationship is executed or fetched by this script. Explicit fuzzer,
password-protected, macro-named and truncated samples were not selected.

## Observed diversity

The DOCX package inventory includes:

| Feature | Files containing it |
| --- | ---: |
| Tables | 16 |
| Textboxes | 4 |
| Footnote references | 4 |
| Endnote references | 2 |
| Comments | 2 |
| Hyperlinks | 8 |
| Field constructs | 9 |
| Tracked insertions | 2 |
| Tracked deletions | 2 |
| Media parts | 7 |
| Header parts | 12 |
| Footer parts | 11 |
| External relationships | 11 |

Run text includes Latin, Cyrillic, Arabic, Han and Kana characters. Application
metadata names Windows and Macintosh Word, multiple LibreOffice releases and
Outlook. These labels are preserved metadata, not independent proof of which
application authored the document. Normal-note and separator counts are
recorded separately; a note part can exist without a reference in body text.
This initial set contains no footnote/endnote relationship parts.

`format-inventory.json` records the CFB signature and raw WordDocument FIB
header fields for all forty DOC inputs. Twenty-nine have `nFib=0x00C1`, five
have `0x0065`, five have `0x0101`, and one has `0x00C2`. The five `0x0065` files
also use the older `0xA5DC` identifier. None sets the FIB encryption flag.
These recorded values describe the input corpus; they do not claim that every
version or feature is supported by our parser.

The feature inventory uses namespace-specific XML inspection for DOCX and
`olefile 0.47` for CFB metadata. It is independent of our parser, but it is not
a rendering, editing, or semantic-equivalence oracle. Any acceptance report
must record unsupported inputs, conversion failures and oracle disagreements
separately instead of reducing the cohort to passing files.
