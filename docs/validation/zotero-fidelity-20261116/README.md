# Zotero catalog and document fidelity continuation

This continuation adds local saved-search browsing, native small capitals, and
bibliography entries with paragraph layout to the existing Zotero document
workflow. The shared implementation is pinned through
[the Office fidelity manifest](../../../tool/office_fidelity_manifest.json).
See [the user guide](../../zotero.md) for the exact controls and boundaries.

## What changed

- The desktop catalog can list and execute existing personal/group saved
  searches, filter within their results, and retain selected references for
  insertion. Conditions are evaluated by Zotero.
- Supported CSL small capitals survive editing, native refresh, DOCX and PDF
  export. Native DOCX retains `w:smallCaps`; the application uses a documented
  synthetic rendering with authored source text preserved.
- The native bibliography remains one linked field across real entry
  paragraphs. Hanging/first-line indents, entry spacing, line spacing and tab
  stops survive refresh and DOCX reopening. Unsafe mixed or ambiguous ranges
  remain refused or explicitly reviewed.
- The actual CrispCloud transport has new saved-search route and request-boundary
  regressions. Its existing direct localhost policy needed no production change.

Canonical implementation, engine/editor qualification and the actual Zotero
desktop evidence are in
[Quds' companion overview](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-support-20261116/docs/validation/zotero-fidelity-20261116).
That live acceptance uses synthetic data, two German styles and four refresh
transactions, including a second refresh after DOCX reopen. It verifies local
saved-search execution, `Ebd.` / `Ebd., 34.`, italics, small capitals and one
bibliography spanning two entry paragraphs.

## Saved source and incoming work

[Initial reconciliation](initial-integration.json) preceded feature changes.
The bounded [final source snapshot](final-integration.json), captured at
**2026-11-16T07:29:09.211Z**, covers 62 branch heads and 201 PR heads across both
repositories. All 263 heads are included by actual ancestry.

The initial newer terminal head was `ce386fd6`. The final snapshot found three
additional commits on PR #160, through
`6e11d2d6fda1486dc6968e01137ba7466356398f`. Those commits were merged as
`de1259080074ca7918122d4790e9255269944b25`, preserving both parent histories.
The new native tmux work is therefore part of this delivered branch. The audit
does not claim to include commits created after its cutoff.

Every checkpoint created for this continuation includes `[skip ci]`. No GitHub
Actions runs, queues, logs, statuses or jobs were queried, awaited or rerun.

## Executed local qualification

| Selection | Result | Evidence |
| --- | ---: | --- |
| Shared Quds engine, catalog, fields and notes | 617 passed | Companion canonical receipt |
| Shared editor, controller and dialogs | 223 passed | Companion canonical receipt |
| Actual Quds Studio native transport | 18 passed | Companion canonical receipt |
| Additional typography, layout and PDF checks | 70 passed | Companion canonical receipt |
| Actual CrispCloud Zotero service, transport, credentials and ribbon | 39 passed | [Host receipt](final/host-validation-receipt.json) |
| Current terminal, SSH agent, forwarding, profiles and tmux core | 402 passed | [Terminal receipt](terminal-integration/receipt.json) |
| **Distinct selected unit/widget tests** | **1,369 passed** | No development or pre-merge rerun totals added |
| Real OpenSSH loopback and agent-protocol fixture | 17 passed; 2 explicit skips | [Loopback receipt](terminal-integration/loopback/receipt.json) |
| Bash/Zsh smoke scenarios | 3 passed | Terminal receipt |

The two live skips are the optional PTY case and an actual disposable Unix
ssh-agent socket fixture. The in-memory local-agent protocol tests use real
OpenSSH connections; they do not claim a working system-agent socket.

The final host run measures 1,611 source inputs after the tmux merge. The current
terminal run measures 221 source inputs and uses a genuine locked focused
graph, including reviewed vendored dartssh2. All measured inputs stayed
unchanged during their respective executions. Strict analysis and formatting
passed for 33 changed canonical Dart targets and eight actual host targets.

The [host runner](run-host-checks.py) uses a genuine resolved dependency graph,
offline `--enforce-lockfile`, actual source imports, temporary canonical
analysis configuration, both vendor guards and before/after fingerprints.
The original source's manifest constraints and lockfile are unchanged.

### Build scope

Quds Studio's complete actual Dart/assets bundle compiled successfully with
unchanged sources. CrispCloud's complete production dependency graph resolved
with its unchanged lockfile, and Flutter completed its full application Dart
kernel target. CrispCloud's overall bundle failed at the required
`crisp_catalog` native-assets hook because Cargo is absent. No hook was disabled
and no production source, dependency constraint or build setting was changed.
See [the full app build evidence](full-app-build/README.md).

Neither result claims a complete native desktop executable, full application
GUI acceptance, Microsoft Word/LibreOffice interoperability or real OS-keychain
acceptance.

## Retained attempts and precise limits

The evidence retains initial failures and setup corrections rather than
overwriting them:

- [The prior host cohort runner](attempt-1-prior-host-count/) ran all 39 tests
  successfully but still expected the previous 37-test count.
- [The host format attempt](attempt-2-host-format/) passed tests and analysis
  and identified one new test file requiring CrispCloud's Dart 3.13 formatting.
  The formatted source was checkpointed before final host qualification.
- [The host run before the tmux merge](pre-tmux-qualified-host/) passed and is
  retained separately; the final run qualifies the newer merged inputs.
- Terminal development and pre-tmux runs remain under the terminal evidence.
  Missing focused-harness dependencies were repaired with exact production
  lock entries; production declarations were not relaxed.
- Five additional full-graph terminal UI/transport suites were blocked by the
  same required Cargo hook before any tests started. Their unchanged source and
  dependency receipts are retained in
  [the supplemental attempt](terminal-integration/supplemental/receipt.json).
  They contribute no passes or skips to the totals above.
- Native Zotero's earlier cold-profile CSL readiness timeouts remain in the
  companion evidence. Final live qualification passed with the isolated
  desktop profile ready; cold-profile first-use readiness is not established.

Native locator-popup editing, active ODT citation transfer, page-based note
restarts and unsupported numbering formats retain the documented limitations.
Small capitals use a synthetic 0.8 scale and default Unicode casing rather
than font-designed glyphs or locale-specific casing. Unsupported variants and
arbitrary bibliography CSS/column layout still require review.

The final [delivery source proof](delivery-source-proof.json) compares the
actual delivered inputs with the independently qualified maps, checks the
2,409 managed Office files and unchanged standalone parser source, and verifies
the final exact Quds pin. Source hashes establish the link between
documentation/pin checkpoints and the executed implementation.
