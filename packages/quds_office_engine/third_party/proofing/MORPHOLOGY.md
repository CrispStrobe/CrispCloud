# German noun morphology

The German grammar provider uses a finite noun morphology resource derived
from Unicode Inflection. It supplies gender, number and alternative case forms
to the existing Dart phrase analyzer. This expands the vocabulary available to
article, noun-case and adjective-ending checks while keeping the runtime
offline on native and web platforms.

The authoritative inventory is [morphology_manifest.json](morphology_manifest.json).
It records the exact upstream inputs, spelling inputs, selection policy,
reviewed additions, statistics, encoding and generated-file hashes. The
[generator](../../tool/proofing/generate_german_morphology.py) and
[runtime](../../lib/src/proofing/german_morphology.dart) implement the format
described here.

## Source and license

The pinned source is
[Unicode Inflection revision `346cf8916249eddc3d5918cfbc27d2b24826ca37`](https://github.com/unicode-org/inflection/tree/346cf8916249eddc3d5918cfbc27d2b24826ca37).
The resource files are under
`resources/org/unicode/inflection/dictionary/` in that repository:

| Input | Purpose | Exact bytes |
| --- | --- | ---: |
| `dictionary_de.lst` | Surface forms, grammatical tags and pattern references | 55,993,784 |
| `inflectional_de.xml` | German inflection patterns | 1,857,558 |
| `LICENSE` | Upstream Unicode License V3 | 2,033 |

The manifest supplies a pinned download URL and SHA-256 for each input. The
generator verifies both the byte count and hash before parsing. The dictionary
and XML downloads must contain the actual Git LFS resource bytes; an LFS pointer
is explicitly rejected. This is a reproducible snapshot, with no claim that it
is the latest upstream revision.

The data is distributed under **Unicode-3.0**. The full upstream text is in
[UNICODE_INFLECTION_LICENSE](UNICODE_INFLECTION_LICENSE), and
[UNICODE_INFLECTION_NOTICE](UNICODE_INFLECTION_NOTICE) retains the revision and
Apple/Unicode attribution. Every generated Dart file also carries that
attribution and the full license text. Redistribution must retain the required
copyright and permission notice with the data/software or its associated
documentation, as specified by the license.

This integration uses the two licensed data resources and an independently
written Python generator and Dart runtime. It adds no GPL or LGPL dependency,
LanguageTool rules, Hunspell dictionary, external NLP model, or required
language server. The separate modern spelling input retains its MIT and Quds
supplement provenance described in [README.md](README.md) and
[manifest.json](manifest.json).

## Generation and linguistic safeguards

### Selecting fixed noun paradigms

The generator first verifies and decodes the existing modern spelling shards.
It selects a lemma only when the exact capitalized spelling is already in the
standard modern vocabulary. Candidates must be single alphabetic words,
tagged as nouns and nominative singular, or explicitly plural-only nominative.
Rows tagged as proper names, adjectives, abbreviations, diminutives, numerals,
or determiner-dependent weak/strong/mixed forms are excluded.

Pattern interpretation is deliberately limited to explicit noun inflections
with case, number and gender attributes and a simple stem plus suffix. A
singular pattern without an explicit recognized gender, or one whose forms
depend on extra grammatical attributes, is marked unresolved. A candidate
lemma referring to such a pattern is omitted rather than assigned a fixed
gender or declension.

Source dictionary tags can combine several analyses of the same surface form.
The generator therefore requires the candidate lemma to equal the pattern's
actual nominative form for its base number and, for singular candidates, to
match a gender present in the source row. A generated case form must also have
an actual dictionary row corroborating its noun tag, case, number and exact
inflection-pattern reference. This prevents a plural surface from seeding an
invented singular paradigm or an unsupported doubled ending.

Each accepted reading has forms for all four cases. An incomplete reading is
omitted. Distinct source patterns remain separate, including plural senses;
they are deduplicated only when their lemma, gender/number and complete case
form sets are identical. Alternative valid forms remain in those sets, and
homographs retain their selected competing readings. Corroboration improves
the evidence but does not establish that every upstream grammatical tag is
correct.

### Keeping unresolved alternatives visible

Simply omitting a context-dependent noun reading can leave a misleading
ordinary-noun reading of the same surface. For example, a capitalized adjective
such as `Armen` can coexist with an inflection of `Arm`.

The generator therefore records unresolved surface keys for source noun rows
that refer to context-dependent or gender-incomplete patterns. It keeps these
signals where the form is already in modern spelling or overlaps an indexed
morphology surface, and adds the corresponding `ss` aliases. A sentinel in the
same surface bucket causes `lookup` to return no fixed readings and
`hasUnresolvedReading` to return true. The phrase analyzer checks this signal
before using its small independently authored fallback noun table. An omitted
analysis consequently cannot make a conflicting fallback correction appear
certain.

The phrase analyzer also preserves a valid nominalized-adjective reading when
its existing adjective stems and endings establish one. This bounded veto
protects phrases such as `für die Junge` and `mit der Jungen`; it does not
attempt general nominalization analysis. `mit dem Junge` still has the unique
supported noun correction `mit dem Jungen`.

### Reviewed additions and corrections

The generator contains a small, explicit set of independently reviewed
grammatical facts. The manifest lists every addition and links the supporting
IDS grammis or Duden reference; no external checker rule table is imported.

| Lemma | Adjustment |
| --- | --- |
| `Herz` | Preserve both `Herz` and optional `Herzen` in dative singular. |
| `Nachbar` | Preserve the accepted strong and weak singular variants, including `Nachbars` and `Nachbarn` in genitive. |
| `Assistent`, `Architekt` | Correct the masculine oblique singular forms to `Assistenten` and `Architekten`. |
| `Teil`, `Stift` | Retain an additional neuter reading alongside the selected masculine reading. |
| `Bonbon` | Retain an additional masculine reading alongside the selected neuter reading. |

These adjustments are part of the generated resource and its hashes. They
must remain reviewable when the upstream revision changes. The generator does
not infer literary dative `-e` merely because a spelling exists. The phrase
analyzer instead has a narrow abstention safeguard for possible literary
singular readings that coincide with a recorded plural; it never proposes a
new literary form.

### Separate spelling permission

Morphological evidence and permission to suggest a spelling are separate.
All retained case alternatives can participate in analysis and suppress an
unwanted correction, including forms that are absent from the modern spelling
vocabulary. A proposed noun replacement must additionally pass
`acceptsSpelling`.

The generator calculates that permission by intersecting generated forms with
the verified modern spelling data. Standard German uses the standard and
reviewed common-word shards. Swiss German uses their `ß`/`ẞ` to `ss`/`SS`
equivalents plus the Swiss shard. Case remains significant. The runtime's
permission sets are finite subsets of those inputs; morphology never inserts
new words into the spelling provider's dictionary. This guard also applies to
noun replacements originating in the fallback grammar table.

The current manifest records 67,492 lemmas, 127,987 readings, 189 deduplicated
patterns and 186,607 distinct case-form spellings. It also records 2,885
unresolved surface keys and 118,075 standard / 118,073 Swiss spellings eligible
as noun replacements. These are resource counts, not measures of grammar
accuracy or the number of sentences the provider can parse.

## Generated schema

Schema version 1 uses a small pattern table and 256 surface buckets. The index
file is `lib/src/proofing/data/german_morphology_data.dart`; the sixteen
`german_morphology_surfaces_00.dart` through
`german_morphology_surfaces_15.dart` files each contain sixteen bucket strings.
Each string is base64-encoded raw DEFLATE containing UTF-8 TSV rows.

### Patterns and reading descriptors

A pattern has five tab-separated fields: a gender/number index, followed by
nominative, accusative, dative and genitive suffix columns. Alternative
suffixes within a case are separated by `|`. An empty suffix represents the
stem itself. Gender/number indices are `0` masculine, `1` feminine, `2` neuter
and `3` plural. The four case indices used by the runtime are `0` nominative,
`1` accusative, `2` dative and `3` genitive.

Each ordinary surface row has exactly seven fields:

| Position | Field | Meaning |
| --- | --- | --- |
| 1 | Surface key | Lowercase lookup form, including an `ss` alias where applicable. |
| 2 | Reading ID | Decimal zero-based identifier shared by all rows for this reading. |
| 3 | Lemma | Original capitalized lemma. |
| 4 | Stem | Common prefix to which the pattern suffixes are appended. |
| 5 | Pattern ID | Decimal zero-based index into the pattern table. |
| 6 | Standard spelling mask | Decimal bit mask of suffixes permitted as standard German replacements. |
| 7 | Swiss spelling mask | Decimal bit mask of suffixes permitted after Swiss sharp-s conversion. |

The two masks enumerate the **sorted distinct suffixes across all four case
columns**, rather than the case columns individually. Bit `i` describes suffix
`i` in that sequence. The generator rejects patterns with more than 30 distinct
suffixes, keeping bitwise operations portable to compiled JavaScript. Reading
IDs are shared within one generated snapshot and must not be persisted as
identities across data regeneration.

An unresolved row uses the same seven-field shape: its reading ID is `-1` and
the remaining five fields are empty. In escaped notation it is
`key\t-1\t\t\t\t\t`. Ordinary and unresolved rows may coexist for a surface;
the unresolved signal vetoes fixed-noun analysis.

### Bucketing and decoding

The surface bucket is a rolling hash over UTF-16 code units, starting at zero:
`h = (h * 31 + unit) & 255`. Both the Python generator and Dart runtime use this
definition. Each bucket contains all descriptors for its surface keys. A
reading that has forms in different buckets is represented there as needed,
then shares one runtime object by reading ID.

The decoder limits inflated output to 1 MiB per bucket. It validates field
counts, bucket hashes, reading and pattern bounds, mask bounds, sentinel
shape, and consistency of repeated descriptors. Parsing takes place in
temporary collections; only a completely validated bucket is published.
Returned reading lists and case-form sets are immutable. The manifest records
the actual maximum bucket size and generated hashes.

The manifest's `logical_sha256` covers the ordered reading descriptors. The
individual generated-file hashes cover the full serialized artifacts,
including surface rows, sentinels, pattern metadata and notices. Retain the
whole manifest when binding a validation result to a source snapshot.

## Lazy loading and performance

`ensureLoaded()` initializes only the pattern metadata. Its completion does
not mean all lexical forms have been decoded. A warm call supplies a newly
completed future in the caller's zone, avoiding a retained initial test/UI
zone. `prepareWords()` normalizes its words, loads only their distinct missing
buckets, and yields to the event loop after each newly loaded bucket.

The grammar provider prewarms noun-phrase candidates using the same structural
helper as the analysis itself: a known determiner, up to two recognized
lowercase adjectives, and an adjacent capitalized noun. The candidate range
must pass the protected-text and grapheme-boundary checks; a qualifying
governing preposition is included in that range. Sentence-start capitals and
unrelated proper names alone do not trigger dictionary loading.

`lookup()` can synchronously load one missing bucket for a later lookup, such
as the stripped base in the literary-dative safeguard. `acceptsSpelling()` can
also load the target bucket when checking a previously unseen replacement.
Readings and decoded buckets are shared for the lifetime of the singleton;
case-form sets are constructed only when inspected. The diagnostic getters
`loadedBucketCount` and `cachedReadingCount` expose the amount loaded.

This layout trades some duplicated compressed descriptors for less decoding
and object construction on a short initial request. All generated constants
still contribute to the application bundle, and the cache can eventually grow
to all 256 buckets during prolonged use. Decoding an individual bucket is
synchronous; yielding between buckets does not guarantee a particular frame
budget. Runtime timings depend on the platform, compiler, document and cache
state. Measure cold and warm requests separately against an identified source
and runtime; an all-bucket format check is not a representative interactive
latency benchmark.

## Grammar scope and remaining limits

The added lexical readings support the existing conservative article and
adjective checks and the stable `de.grammar.noun-case` and
`de.grammar.dative-plural` rules. A governed case must be available before a
noun replacement is proposed. Competing analyses must agree on one target
noun form, no applicable reading may already accept the original, and the
target must pass the modern spelling guard. Article and adjective changes also
require a unique supported target. An ambiguous or missing analysis generally
causes abstention.

The system analyzes bounded determiner phrases. Adjective recognition remains
a finite independently authored stem list, and the existing verb and clause
rules retain their own bounded vocabularies. Unrestricted compounds, arbitrary
proper names, unrestricted nominalizations, long-distance agreement,
dependency parsing and semantic disambiguation are outside this resource's
scope. Upstream omissions, conservative filtering and spelling-vocabulary
gaps leave real mistakes undetected. Passing a phrase does not certify its
grammar.

The integration uses the existing source projection and grapheme checks, so
suggestions retain source offsets and soft-hyphen ownership. URLs, email
addresses and closed backtick-delimited code remain protected. German locale
aliases and Swiss `ss` presentation follow the existing provider behavior.
Findings are suggestions under independently ignorable rule IDs; the resource
does not automatically rewrite document text.

## Reproduction and validation

### Verify or regenerate data

From `packages/quds_office_engine`, with the existing spelling shards matching
their spelling manifest:

```sh
python tool/proofing/generate_german_morphology.py --download --check
```

To use already retrieved and verified source files, place the actual
`dictionary_de.lst`, `inflectional_de.xml` and `LICENSE` in one directory:

```sh
python tool/proofing/generate_german_morphology.py \
  --source-directory /path/to/unicode-inflection-inputs --check
```

`--check` compares every expected output byte, including the manifest and
notices, and rejects stale generated morphology files. Omit `--check` to
regenerate. If the spelling supplement or spelling source changes, regenerate
and verify the spelling data first using [README.md](README.md), then regenerate
morphology. The Python standard-library zlib version is recorded in the
manifest; this snapshot uses zlib 1.3.2. A different encoder version may change
compressed bytes even where the logical reading data is unchanged.

### Focused runtime and grammar tests

From `packages/quds_office_engine`, with the workspace dependencies resolved:

```sh
dart test \
  test/proofing/german_morphology_loading_test.dart \
  test/proofing/german_morphology_grammar_test.dart \
  test/proofing/german_grammar_test.dart \
  --reporter expanded
```

These tests cover lazy metadata initialization, bounded loading, immutable
shared readings, caller-zone completion, spelling guards and conservative
grammar behavior. Wider spelling, locale, editor and hyphenation checks remain
necessary when those integrations change.

### Validate every bucket on VM and JavaScript

From the repository root, after dependency resolution, retain a receipt with
the source commit, dirty-file state, manifest and runtime hashes. Substitute
its identifier for `reviewed-source-receipt` below. The label supplements that
receipt; it does not create one automatically.

```sh
dart --packages=.dart_tool/package_config.json \
  -DQUDS_MORPHOLOGY_SOURCE_BINDING=reviewed-source-receipt \
  tools/proofing/validate_morphology_buckets.dart

mkdir -p .dart_tool/morphology-validation
dart compile js --packages=.dart_tool/package_config.json \
  -DQUDS_MORPHOLOGY_SOURCE_BINDING=reviewed-source-receipt \
  tools/proofing/validate_morphology_buckets.dart \
  -o .dart_tool/morphology-validation/buckets.js
node -e 'globalThis.self=globalThis; require(process.argv[1]);' \
  "$(pwd)/.dart_tool/morphology-validation/buckets.js"
```

The validator loads all 256 buckets, exercises format and descriptor checks,
and requires the cached reading count to match the generated count. Its passed
status establishes resource decoding and coverage, not linguistic accuracy.

### Run the independent sentence corpus

The repository-level qualification harness executes the same provider corpus
on the selected checkout under Dart VM and compiled JavaScript/Node. It emits
source, corpus, harness and runtime hashes, verifies that inputs remain
unchanged, and compares the VM and Node results. From the repository root:

```sh
python tools/proofing/run_morphology_qualification.py \
  --target . \
  --output .dart_tool/morphology-validation/corpus \
  --dart /absolute/path/to/dart \
  --node node
```

The default corpus is `tools/proofing/german_morphology_cases.json`. Use
`--corpus tools/proofing/german_morphology_review_cases.json` for the separate
review set. The harness's operational passed status is distinct from its
diagnostic correction and false-positive scores. Preserve the frozen corpus
and report legitimate ambiguity or disputed expectations separately rather
than changing the corpus to make an implementation appear more accurate.
