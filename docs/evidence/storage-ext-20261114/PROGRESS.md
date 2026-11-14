# ext filesystem continuation — recoverable progress

## Starting state

- Branch: `integration/storage-ext-20261114`.
- Baseline: `a34f7fcab53441da7d1d6c96e9d9e5ba25111907` on current main.
- PR [#101](https://github.com/CrispStrobe/CrispCloud/pull/101) is merged.
  Its FAT implementation, native/JavaScript results and production build were
  saved successfully before the previous agent stalled. The original records
  remain in `../storage-fat-20261114/` with their original source revisions.
- All remote branch heads, PR heads and tags were refreshed. See
  `reconciliation-start.json`; existing references have not been replaced.
- Main's later catalogue, 1.3.0 release and DOC fixes are preserved.

## This increment

Implement an original MIT, bounded, read-only ext-family filesystem adapter
using the existing archive byte-source, preview and extraction contracts.
The exact supported feature profile is documented in
`../../archive-ext-profile.md`. Unsupported layouts and journal recovery are
explicit; there is no filesystem write or repair authority.

Work is divided into the core reader, archive/image integration, independent
fixtures and validation. Checkpoints are saved remotely as each part becomes
concrete. Final local qualification is complete; see `README.md` and
`final-validation.json`. Intermediate checks are preserved with their exact
source hashes and are not presented as later source runs.

## Prior hosted CI follow-up

The previous archive hosted job passed 992 tests then failed downloading the
external FatFs reference archive. The workspace job passed 947 tests then
failed a formatter cleanliness gate. These are separate from the earlier
recorded local qualification and will be assessed during this continuation.

## Resume guidance

1. Fetch this branch and current main before editing.
2. Read this file and the eventual ext profile and validation receipts.
3. Preserve existing evidence and bind every new test result to its source.
4. Push incremental commits; do not rewrite existing branch history.

## Incremental checkpoints

- `71fa70c8`: recovered prior completed FAT qualification and refreshed all refs.
- `3c868b26`: saved fail-closed ext API skeleton, bounded hash-verified external
  FatFs retrieval, and stable generated/UI formatting.
- `eeefe937`: saved functional ext reader, standalone/MBR/GPT integration,
  read-only workspace/F3 tests and first independent reference corpus.

Current follow-up adds the CRC16 external reference, malformed-image tests,
combined-disk budgets, source-length checks, resize/symlink allocation checks,
and VM/JavaScript-stable timestamps. Five complete external images reproduce
exactly and contain 48 regular file instances. Preliminary portable checks pass;
final pinned native, JavaScript, analysis and production results are recorded
below. This paragraph describes the intermediate checkpoint, not the final gate.

The first native core/reference run passed 68 tests and failed one assertion:
the extended timestamp test incorrectly selected a 128-byte inode specimen.
The test now selects the 256-byte inode specimen it requires. Its full original
logs, summary, receipt and source hashes are preserved here (larger records use
lossless gzip). See `intermediate-evidence-index.json`.

## Integration follow-up

- `d5dbff96`: saved allocation/source hardening, five external images,
  malformed-image controls and the initial native evidence.
- Draft review: [PR #102](https://github.com/CrispStrobe/CrispCloud/pull/102).
- The first focused app gate passed 427 and failed four checks: two native
  workspaces rejected metadata-only links; two F3 checks exhausted the native
  fake-clock wait. Complete failed-run evidence is retained.
- Ext/disk-image selectable namespaces now validate all names before omitting
  special metadata. F3 retains disabled metadata rows. Direct whole-image
  extraction uses the same policy. Other archive formats retain strict refusal.
- The targeted integration follow-up passed 138 tests, zero failures/skips,
  including native ext/GPT workspace extraction and F3 preview/mode changes.
- The core follow-up passed 70 tests, zero failures/skips. Tests overlap these
  runs; counts are not additive or attributed to a later source revision.
- Explicit GPT signatures now take priority over an ext marker that can also
  occur in a valid GPT partition name. Native and portable collision regressions
  cover valid and corrupt GPTs, while standalone ext retains MBR precedence.
- The expanded portable smoke run passed 19 groups / 3,360 checks on both VM
  and actual compiled JavaScript with exact output equality. The authoritative
  final gates will run again against the next saved complete source checkpoint.

## Saved qualification source

The complete implementation and test source is saved at
`8bbdc25c7eca7598215bdc1053e8558ef3f5d643`.
Strict analysis passed all 30 changed Dart files with no issues; all 8,075
tracked non-document source/asset paths matched that commit before and after.
The refreshed remote check retains 12 branch heads, 92 PR heads and 21 tags;
all branch and PR heads are ancestors of this source. Main remains `a34f7fca`.
The final native gate and production build ran from separate copies of this
exact revision. Their evidence is preserved in this directory.

## Completed qualification

- `ebec52ec`: saved strict analysis, hosted-check snapshot and refreshed refs.
- Native: **1,007 passed, zero failed, one expected opt-in skip**, 37 files.
- Portable: **19 groups / 3,360 checks per VM and actual dart2js/Node target**;
  complete JSON and serialized stdout match exactly, with no excluded fields.
- Strict analysis: **30 changed Dart files, no issues**.
- Production JavaScript: **1.3.0+23**, original production manifests, full
  `8bbdc25c` source stamp and Apple LZFSE license asset verified.
- Native/build/analysis source checks matched all 8,075 non-document paths;
  portable checks bound 5,032 source/configuration/fixture paths and all 605
  actual compiler inputs. No source drift was found.
- Five complete external images and 48 regular-file instances reproduce
  byte-for-byte; all external consistency and extraction controls passed.
- Complete receipts and logs, including earlier failed and pre-test attempts,
  are being committed as documentation-only descendants of the qualified
  source. The final evidence index includes plain logs excluded by the
  repository's default ignore rules.
- Hosted qualification remains incomplete. `hosted-ci-status.json` records
  its separate timestamped state. PR #102 remains a draft; no merge or
  deployment is claimed.

Future work should start by fetching the latest branch and reading the final
evidence README, the admitted ext profile and current hosted results. Preserve
the existing checkpoints and keep new results tied to their actual source.
