# German hyphenation provenance

Only `hyph-de-1996.tex` is imported from **tex-hyphen**, pinned at commit
`5684c0f51c0b81133db2efbe60a408b4155a3ff5`:

https://github.com/hyphenation/tex-hyphen/blob/5684c0f51c0b81133db2efbe60a408b4155a3ff5/hyph-utf8/tex/generic/hyph-utf8/patterns/tex/hyph-de-1996.tex

The unchanged source contains the complete copyright and **MIT** license grant.
Its version is `2024-02-28`; its SHA-256 is
`374ad1ce3263f8a2791ec070ef9b516c532dae64456f3fb656e617e8ae53a9d3`.
The source also records the underlying Wortliste revision
`304aaa2188a75e57afe36bad0443d90a9c715b8e`.

Regenerate the 36,709 embedded patterns from the checked-in source with:

```
python packages/quds_office_engine/tool/proofing/generate_hyphenation.py
```

The generator checks the exact digest before reading patterns and includes the
original notice in the generated Dart file. No LibreOffice-converted dictionary,
GPL/LGPL pattern set, or third-party pattern engine is used. The small Liang
trie implementation in `german_hyphenator.dart` is authored in this fork.

Patterns cover reformed German (2006); the same modern pattern set serves
`de`, `de-DE`, `de-AT` and `de-CH`. Minimum fragment sizes are two letters.
No spelling reform substitutions are performed. Offsets always refer to the
unchanged source, including decomposed umlauts. Other languages return no
automatic candidates. Explicit source soft hyphens are handled by layout
independently of the automatic language setting.
