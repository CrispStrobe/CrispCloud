# Integrated parser checkpoint at d11fa0e

This checkpoint brings the standalone parser's integrated Word fidelity fixes
into CrispCloud's guarded mirror. It includes floating-table anchors, exact
table-ended notes, independently instantiated header textboxes, bounded binary
internal hyperlinks, and separate script-font slots. Current application,
archive and release work from app main `07a1ce77` is retained.

## Exact source and publication identities

| Component | Identity |
| --- | --- |
| Measured clean local app commit | `6a6e526e6d26689be654b01db6f4adaa67fe0ca9` |
| Remote checkpoint with the same tree | [`5bd46861c892ec1b654e0644e22b4cb87f16f715`](https://github.com/CrispStrobe/CrispCloud/commit/5bd46861c892ec1b654e0644e22b4cb87f16f715) |
| Identical Git tree for both commits | `2b4ae797ad366544c70a1ade33682b875d228e98` |
| Standalone parser | `d11fa0e297f8058c8048c71537f2392457baa624` |
| Quds source, unchanged | `71bb109e81217ed55c534881304a44ae8fa608d5` |
| Guarded Office inventory | 1,045 files: 624 upstream parser files and 421 unchanged non-parser files |

The measured local commit and the remote checkpoint have the same parent and
tree. Publication through GitHub's Git Data API gives the remote commit its own
metadata and SHA. The execution remains attributed to the measured local
commit; it is not relabeled as an execution after publication. The complete
[receipt](receipt.json) records this distinction and binds each retained log.

The parser mirror has no app-local patch. Its byte and executable-mode inventory
matches the exact standalone Git commit. The guarded sync also checked the
complete previous mirror before writing. Every non-parser Office hash and the
Quds source pin remains identical to app main.

## Completed checks

| Check | Result | Scope |
| --- | --- | --- |
| Data-only app Word cohort | 107 tests in eight suites passed; zero failures or skips | Existing assertions, with only the test-framework import changed in copied suites. |
| Captured inputs | 1,176 before/after hashes identical | App and package imports, fixtures, copied and original tests, dependency/configuration and runner inputs. |
| Guarded synchronization | 24 controls passed | Existing source/mode/inventory/drift guards. |
| Production portable JavaScript smoke | DOC, RTF, PPT and MSG passed | Exact smoke template and real source fixtures compiled with the cohort's resolved package configuration. |
| Installed native acceptance | 13 checks passed | Built-in DOC-to-DOCX output rendered by LibreOffice and inspected by Poppler. |

The cohort ran on clean source using Dart 3.13.7. It includes 13 fake-process
installed-converter tests, which are separate from the 13 actual native checks.
The native result retains `partialFormatting`; it checks tables, formatting,
page definitions, headers, footers, notes, an image, PDF structure/text/images,
and unchanged source/prepared bytes for the authored `formatting.doc` fixture.
The existing native acceptance tool deletes its temporary PDF, so this receipt
does not claim retained full-page native artifacts or exact rendering equality.

## Retained records and reproduction

All 20 execution records are retained losslessly with original and compressed
byte counts and SHA-256 hashes. They include complete events/logs, before/after
input inventories, adapter transformations, exact package configuration and
lockfile, the captured cohort runner, sync plans, and native/JavaScript output.
Run:

```sh
python3 docs/evidence/word-continuation-d11fa0e/verify_evidence.py
```

The verifier checks every compressed and decoded record, completed test events,
input immutability, native checks, source pin and the matching-tree publication
record. The earlier [cohort reproduction helper](../word-continuation-7308125/run_word_cohort.py)
accepts explicit app, new workspace, Dart executable and cached-dependency
paths. It is also retained in this receipt as `cohort-word_cohort.py.gz`.

Flutter widgets, native ebook hooks and a full application build were not run.
A routine Flutter version probe was rejected by automatic approval review
because it unexpectedly targeted the cloud metadata endpoint `169.254.169.254`.
That probe was not retried. The existing Dart binary and data-only adapter ran
independently; no application manifest, test assertions or release configuration
were altered to perform them.

This checkpoint does not establish Microsoft Word execution, full editing
semantics or arbitrary pagination. Release versions, policy decisions and
historical validation receipts retain their existing meaning.
