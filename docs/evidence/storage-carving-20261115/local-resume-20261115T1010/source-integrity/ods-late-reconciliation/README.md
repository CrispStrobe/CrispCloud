# Canonical bounded ODS reconciliation

This development checkpoint combines saved canonical integration
`1c1b0af8e20bb02f7d18b4e6cb116328f4342332` with
`fbe879e811b57805583d658523b73320c7149d04` from
`integration/storage-odf-qualification-20261115`. The incoming production
commit is `fe500e2bf50aae3098040ee0308221db2ae0d9f6`; its evidence commit and
all 27 incoming evidence files remain preserved unchanged.

The union retains incoming namespace recognition, row/column groups, named
style inheritance, vertical spans, text handling and workbook-wide resource
budgets. It also preserves saved compatibility for omitted/consecutive merge
placeholders, quoted sheet identifiers, and sparse styled trailing row runs.
Function-prefix conversion retains its identifier boundary, so an unrelated
function such as `MYCOM.MICROSOFT.FUNC` is not renamed.

Meaningful data beyond the supported grid now explicitly declines, matching
the stronger incoming bounded profile. The two former clipping regressions
retain their in-range assertions and additionally require refusal of excess
data; no coverage was removed to make the combined reader pass.

## Observed development results

The combined suite has 35 tests: 19 incoming tests, 14 distinct prior tests,
and two new reconciliation controls for bounded styled padding and function
identifier boundaries.

The incoming reader, before compatibility reconciliation, produced 29 passing
tests, five assertion failures and one execution error. Those raw machine
events and exact test inputs remain under `incoming-baseline-tests.*` and
`baseline-union-test.dart.gz`.

The reconciled reader passes all 35 visible tests, with zero failures, errors
or skips. Strict scoped analysis of the reader and test also passes with no
issues. Both commands confirm unchanged source and resolved dependency graph
hashes before and after execution. These are development runs within an
uncommitted merge; final clean-source qualification follows remote saving and
guarded host synchronization.

`reader-reconciliation.patch` records the changes relative to the incoming
bounded implementation. `tested-inputs.json` records exact tested source
identities. `observed-cutoff.json` separately records the later discovered
`ddaca09c88895c56480dae5b506dc4f0b4cf120f` production head, whose unique
additions are intentionally handled in the next distinct checkpoint.
