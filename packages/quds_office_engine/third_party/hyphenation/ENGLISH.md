# American and British English hyphenation

The two original TeX files are pinned to tex-hyphen commit
[5684c0f51c0b81133db2efbe60a408b4155a3ff5](https://github.com/hyphenation/tex-hyphen/tree/5684c0f51c0b81133db2efbe60a408b4155a3ff5).
They are separate from the existing modern German MIT patterns.
No package dependency or network service is added.

| Pattern file | Terms stated in the original file | Patterns | Exceptions | Minimum left/right |
| --- | --- | ---: | ---: | --- |
| [hyph-en-us.tex](hyph-en-us.tex) | Kuiken's explicit royalty-free permission to copy and distribute, with or without modification, preserving copyright and permission notices | 4,938 | 14 | 2 / 3 |
| [hyph-en-gb.tex](hyph-en-gb.tex) | MIT | 8,527 | 8 | 2 / 3 |

The US grant is recorded as **LicenseRef-Kuiken-permissive**, not relabeled as
MIT. Its copyright and permission notice remain in the complete original
source and generated Dart preface. The GB file's full MIT notice is retained
in both places. Neither file is taken from LibreOffice's converted resources.

The GB source explains that the underlying Oxford University Press word list
may not be redistributed. This repository ships the licensed pattern file,
not that word list. The original exception lists are reproduced unchanged,
including US entries with **no** allowed break, such as `project` and `present`.

## Runtime scope

- `en` and `en-US` select the American patterns.
- `en-GB` selects the British patterns.
- Other English dialect tags receive no automatic candidates; they are not
  silently redirected to another dialect. This is independent of the broader
  dialect support in the optional Harper spelling/grammar backend.
- Patterns are ASCII Latin data. Accented words, contractions, possessives,
  identifiers, words containing authored U+00AD, and words longer than 128
  source units are conservatively skipped.
- Quotation marks surrounding a word do not turn it into a contraction.
  Explicit hyphen-separated components remain eligible independently.
- Every English break leaves at least two letters before and three after.
  Candidate positions are original UTF-16 offsets; source text is unchanged.
- HTTP(S)/WWW URLs, email addresses and closed backtick code spans receive no
  automatic dictionary breaks. Matching code delimiters may contain one or
  multiple backticks; unmatched delimiters do not hide the rest of a paragraph.
- Fragments adjoining U+200C, U+200D, U+2060 or U+FEFF are skipped; explicit
  U+200B opportunities remain the line breaker's responsibility.
- A word crossing a run dialect boundary is skipped; `en` and `en-US` are
  equivalent American aliases. Mixed paragraphs can
  combine English and German candidates through `OfficeHyphenator`.
- The existing line breaker determines whether a candidate fits, measures the
  visible discretionary hyphen, and preserves selection/copy/PDF source
  ownership. Explicit soft hyphens remain available in any language.

These are fixed upstream pattern sets, not a guarantee that every proposed
linguistic break is ideal. The US source explicitly records a known
`democrat` pattern issue. No exceptions have been invented to disguise upstream
limitations.

## Reproduction

The [manifest](english-manifest.json) records immutable source URLs, source
Git blob IDs, SHA-256 hashes, exact counts and generated output digests.

From the repository root:

```sh
python3 packages/quds_office_engine/tool/proofing/generate_english_hyphenation.py --check
```

Omit `--check` to regenerate the two Dart data files. The generator uses only
Python's standard library and the checked-in sources; it rejects changed
source hashes, unsupported TeX syntax, duplicate keys, count drift and output
digest drift. The existing German generator and German runtime are unchanged.
