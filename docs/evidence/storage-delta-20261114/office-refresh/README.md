# Follow-up for the final main and canonical Word refresh

**60 tests passed across six native host suites, with zero failures, skips or
error events**, at source `b98cd70e6dae21ba486a0704e7946cf35ab6575a`, tree
`11329c5e82aa1f86afd48ab0ec366de2bb73a3b1`. All **8,384** captured inputs, HEAD,
tree and clean Git status remained unchanged during execution.

This source includes the final observed main and annotated `v1.3.2` target
`2c373371973b2506fc4fc03e599ef093d14a4be1`. The
[source/ancestry proof](source-refresh.json) identifies exactly four runtime
changes since the earlier 790-case qualification: the canonical Word document,
bookmark, content-control and deserialization files. Application `lib/` and
`test/` files, delta code, bandwidth code and other managed runtime files are
unchanged. All observed branch and 96 PR heads are incorporated. The observation
cutoff is 2026-11-14 20:54:46 UTC; later remote work is not silently attributed
to this run.

## Focused app gate

| Suite | Passed |
| --- | ---: |
| Office editor lifecycle and save/recovery | 25 |
| Native Office host workflows | 9 |
| Word template preservation | 12 |
| Office document services | 9 |
| Office round-trip preservation | 3 |
| Office editor layout fixes | 2 |
| **Total** | **60** |

The same Linux Flutter 3.47.8 / Dart 3.13.7 environment and native hooks were
used. [Exact command](qualification/command.json),
[metadata](qualification/metadata.json), [summary](qualification/summary.json),
[raw events](qualification/stdout.jsonl), and before/after input inventories are
retained. [The review](qualification/review.json) records source stability and
40 host artifacts written inside this run window; their exact bytes are under
`qualification/host-outputs/build/`. ZIP CRC and XML well-formedness checks
passed. This is not external schema validation, external rendering, browser
execution or live-provider acceptance.

## Canonical ownership and qualification

The guarded sync now pins `a379ecc455890032906098b6cf58e17504581ed0`, preserving
the combined sorting/history regression while incorporating current canonical
main. The [dry plan](office-refresh-sync-plan.json) and
[applied receipt](office-refresh-sync-applied.json) list the four Word runtime
and three Word test changes. [Verification](verify-managed.txt) confirms all
**2,187** managed files; the separate legacy-DOC pin is unchanged.

The canonical source independently passed **117 Word tests and 115 editor
tests**, with zero failures or skips, clean strict analysis and 2,955 stable
inputs. [The exact published receipt](canonical-validation.json) links evidence
head `579f2105cf7fca61536f7e3f9b59004929bdb6c5` and
[companion PR #12](https://github.com/CrispStrobe/quds_office_suite/pull/12).

The earlier [790-case app cohort](../qualification/README.md) keeps source
`331981649872e363253aef13f57a638e5747b8e5`; the later run is an explicit scoped
follow-up. These counts are not combined into a claim that 850 distinct tests
ran on one source revision.
