# German proofing and Office release qualification: build 30

CrispCloud 1.3.4 (30) was built and signed locally for the App Store, including the Finder extension. The signed development copy starts, reaches **Credential policy ready**, and remains healthy for 15 seconds. **Apple delivery remains pending:** repeated authenticated API requests and Apple's own `altool` validation return HTTP 500. No upload or external TestFlight availability is claimed. The Mac screen is locked, preventing the remaining signed UI interaction checks.

## Frozen sources and changes

- Built host: `28979cea08a46c9b3beb016ab20b69ee02bea2b0`.
- Canonical Quds: `96e65705ad69f969710d3ff6d2897bd4aa38fbf9`, pinned in the host's 2,627-file source manifest. Both implementation snapshots were pushed to upstream `main` before building. Documentation publication does not change the built snapshot.
- Incoming work includes cached page-field continuation and spreadsheet color scales/data bars. A canonical sync briefly removed the host-only data-bar painter; the painter was promoted into Quds and restored to the host with a failing-then-passing pixel regression.
- Conservative German changes repair bounded dative demonstratives before unambiguous neuter nouns, add finite first-party morphology for *Freundin/Freundinnen* and *Straßenpolizist/Straßenpolizisten*, and regenerate resources from the same pinned licensed inputs. Ambiguous readings continue to abstain.
- An actual LibreOffice round trip exposed lost literal ODS whitespace. The ODS cell/preview decoder now opts into preserving it; the writer explicitly serializes significant whitespace with the shared ODF writer. Word/slide default decoding stays unchanged.
- First-party integration, review, editor lifecycle and safety work around the historical analyzer remains. No incompletely documented AOT/RML/nlp_base runtime, dictionaries or transport was introduced. Native spaCy implementation remains assigned to the separate handoff/session.

## Accepted local checks

| Cohort | Result and source scope |
| --- | --- |
| Engine proofing and Office formats | 1,644 passed at `5cce94a1`; engine unchanged through final canonical source |
| Conditional-format rendering | 8 passed at final canonical source, including actual pixel change for a data bar |
| Broad host workflows | 272 passed at `2d717866`, covering Save As/copy, favorites, ESC, shortcuts, dialog focus, ODS, keychain settings and application launch handling |
| Final affected host Office workflows | 81 passed at exact built host source |
| Terminal units | 1,077 passed, 2 platform skips; terminal source/tests/dependencies unchanged after qualification |
| Live SSH | 25 passed, no skips; real OpenSSH, PTY and Unix agent |
| Live tmux and shell helpers | One actual tmux feature test passed; Bash and Zsh smoke checks passed |
| Native keychain | Disposable Security.framework fixtures passed; existing credential stores/preferences were not modified by that fixture |
| Apple release guards | 38 Python controls; 27 Ruby runs / 146 assertions passed |
| Signed startup | Healthy for 15 seconds; credential policy ready |

These cohorts overlap. They are not a claim that every repository test or every UI workflow passed. Engine analysis has one incoming informational `use_null_aware_elements` lint at `sml_analysis.dart:505`, with no errors or warnings. Earlier disk-exhausted runs are superseded by the accepted reruns. The initial preliminary app was superseded by the final build recorded here.

## German results

VM and compiled JavaScript outputs match for every recorded corpus.

| Corpus | Exact error cases | Flagged valid controls |
| --- | --- | --- |
| Original | 18/18 | 0/12 |
| Context | 21/23 | 0/60 |
| Holdout | 46/46 | 0/58 |
| New release cases | 9/9 | 0/29 |
| Broader morphology | 73/81 | 0/175 |

The morphology run makes 1,280 requests: targeted cases score 70/73 and challenge cases 3/8. No operational, protection, ignore or recheck failures were recorded. This is bounded deterministic coverage, not general linguistic analysis or native spaCy inference.

## Actual LibreOffice interoperability

LibreOffice 26.8.2.2 on macOS ARM64 saved and reopened synthetic files. The retained fixtures verify ODS numeric/formula/date/boolean values, Unicode and literal spaces/newlines, formatting, merges, comments, hidden sheets and hyperlink targets; ODS → XLSX → ODS also passes. Word checks cover ODT → DOCX → ODT and Quds-authored DOCX import, including body/table/header/footer content, comments and bookmarks. The PDF text confirms visible stories and excludes comment text.

The interoperability receipt identifies its actual tested source (`cc716c46`); later field/data-bar integrations have their separate engine/host/render checks. Hyperlink comparison allows LibreOffice's trailing-slash normalization only. The intentionally synthetic document artifacts are in `fixtures/`.

## Delivery and remaining work

The app and Finder extension both carry **1.3.4/build 30**, ARM64. App Store sandbox/profile/component checks and strict nested signatures pass, with no optional FUSE helper. Package SHA-256: `64f88aa1e6a0f2e5cc07b282e94b30e19f7b806fff96b526728ea25d5f156450`.

The existing outside-France release decision, encryption answers, signing identities and reviewed TestFlight groups are retained. No country, tester, public-link or encryption-policy changes were made. Live preflight failed on Apple's API; it was not bypassed. `altool` also logged repeated HTTP 500 errors while resolving the app and returned process status 0 without a successful validation result; that exit code is not counted as acceptance.

Pending external conditions are Apple API recovery for validation/upload/processing/group assignment and an unlocked Mac for live signed UI actions. The package remains locally available as `CrispCloud-1.3.4-30.pkg` in the private release evidence directory. The previous build 29 receipt is historical evidence, not proof of build 30 availability.

## Evidence

[receipt.json](receipt.json) records source identities, package hash and exact qualification boundaries. [evidence-index.json](evidence-index.json) lists hashes for compressed logs, corpus outputs and synthetic interoperability fixtures. User home-directory prefixes are redacted from published textual evidence; both original and published hashes are recorded. Credentials, GUI dumps containing user file names, compiler caches, native binaries and the signed installer are excluded. No GitHub Actions jobs or status endpoints were queried or awaited.
