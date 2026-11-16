# German spelling data

`manifest.json` records the exact source revision, source and license hashes,
selected orthography, generated data hashes, and independently authored
supplement. The bundled MIT source is **Werners Wortliste / DANTE**, from the
[hyphenation project mirror](https://github.com/hyphenation/languages-german/tree/4330a0b1254e88615cb4c83e4b3dc2f0810c76d9).
The [canonical project](https://wiki.dante.de/trennmuster/korpora) identifies
Werners Liste as MIT. The complete upstream notice is in `WORTLISTE_LICENSE`;
the Quds supplement's notice is in `QUDS_WORDS_LICENSE`.

This is a pinned **1 May 2016** mirror snapshot. It is not advertised as the
latest canonical word list. The canonical repository could be read through
indexed documentation during recovery, but its download endpoint returned a
bot/access-denied page. This package uses a verifiable authorized mirror, not
an unverified dictionary substitute.

## Selection and scope

The source combines historical and modern orthographies. Its first column is
a key, **not** a modern-orthography allowlist. The generator selects the shared
second field, or otherwise the reformed fourth field. Missing `-N-` fields are
excluded. The seventh field (shared fifth-field fallback) supplies modern
Swiss/no-sharp-s variants. `de-CH` additionally maps accepted modern sharp-s
forms to `ss` and rejects sharp-s tokens. `de-DE` and `de-AT` share the source
vocabulary; this does not provide an exhaustive Austrian regional dictionary.

The source is a hyphenation corpus. It omits many short/common word forms. The
independently authored `tool/proofing/german_common_words.txt` fills a small
reviewable set of basic forms and common inflections. It has no copied external
dictionary definitions or unverified package/example data. No GPL, LGPL,
LanguageTool, nlprule, Hunspell dictionary, or LibreOffice language data is used.

The checker recognizes finite listed word forms. Explicit hyphen compounds may
use known components; it does not perform unrestricted closed-compound or
morphology inference. Unknown proper names, new terms, and unlisted inflections
can produce findings. The message deliberately says a word is absent from the
word list; hosts must offer personal vocabulary and ignore controls. Document
text and dictionary data are never rewritten automatically.

Common decomposed Latin accents and explicit soft hyphens are normalized only
for lookup; findings keep original UTF-16 offsets and text. Case remains
significant for German nouns. Sentence-initial capitalization and all-capitals
are accepted when a corresponding listed form exists. URLs and email addresses
are excluded. Suggestions use bounded candidate generation (distance-one
transpositions, insertions, deletions, substitutions and German accent/sharp-s
variants), not an unbounded dictionary scan. Data decode yields between chunks;
checking yields between token batches, including in JavaScript.

## Reproduction

From the engine package:

```sh
python tool/proofing/generate_german_lexicon.py --download --check
# Or use an already retrieved exact file:
python tool/proofing/generate_german_lexicon.py --source /path/to/wortliste --check
```

Omit `--check` to regenerate. Downloads are pinned and verified before generation.
Only the standard-library Python `zlib` encoder is used. Its version and the
uncompressed logical hashes are recorded in the manifest; another zlib version
could produce different compressed bytes while preserving the logical data.
Generated shards are raw-DEFLATE/base64 Dart constants, with at most 4,096 words
per chunk. The engine uses its existing pure-Dart bounded decoder. Runtime
checking has no network or file-system dependency.

## Personal words

`OfficeProofingVocabulary` belongs to one host-selected `ownerId`. The engine
only mutates its in-memory instance. The host chooses storage/account scope and
can persist `toJson()` or restore `OfficeProofingVocabulary.fromJson(...)`.
Words and ignored words are language-scoped and case-sensitive after canonical
accent composition. `onChanged` and `revision` invalidate proofing caches. An
in-flight result is rejected if the vocabulary changes during its check.
