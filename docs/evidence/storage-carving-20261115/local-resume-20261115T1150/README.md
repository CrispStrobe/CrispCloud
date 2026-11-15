# Latest integration continuation

## Saved source scope

All **53 relevant heads** in the finite incoming inventories are accounted for:
49 are ancestors and four have explicit supersession proofs. Current main through
`4933ffc2`, app PR 120 through `c8fd8d76`, canonical ODS dates/comments through
`9cc8c6e9`, parser main `7df906d2`, and the earlier parallel qualification
histories remain preserved. See `incoming/incoming-closure.json`; subsequent
correction commits descend from that audited source. No later upstream refresh
is included.

The app mirrors canonical Office **c17098d65fe5f6e2bdf9999389deb2a6b508d928** and
standalone parser **9bdcc7eba3f1ce80b7d834d7740895774eeca615**. All **2,303 managed
files** match these source pins.

## Defects reproduced and corrected

- ODS copy-save lost native default width: 81px became 64px. The canonical
  correction preserves default/base geometry through direct and isolate saves.
- Incoming ODS dates and annotations preserve authored order and literals, and
  keep comments separate from cell values under shared text, grid and work
  bounds. Author serialization retains first-seen IDs with indexed lookup.
- Parser recovery work and input bounds, declared encodings, authoritative
  stream bounds and half-open story cleanup retain their earlier fixes.
- The first complete app run exposed 18 suite-loading errors from the expanded
  underline enum and two errors from typed malformed-compound exceptions. The
  raw 742-case failed run is saved at `f7295806`, with every error classified.
- Both ribbon and Font controls now expose all 18 underline styles with complete
  localized labels. A regression selects each style, applies Font unchanged,
  and saves/reopens DOCX. Imported and mixed-font fidelity is also included.
- Typed `CfbfException` reaches only the existing opt-in bounded DOCX text
  recovery. Nine new canonical tests cover both recovery entry points and the
  strict/default, DOCM, encryption, FIB, size, source and private-tail boundaries.

## Qualification status

Final host cohorts contain **65 app / 9 editor / 22 engine suites**. Strict
analysis covers **76 app / 16 engine / 4 editor / 1 CLI files**. The standalone
parser passes all **4,131 tests in 144 suites**, its 18-file strict analysis and
all nine new admission/refusal controls. Raw final receipts are saved at
`57442c79239fb4d483e274e0ebb04f34686beb6c`; the source pin stays fixed. See
`canonical-parser-current-qualification.json` for exact raw summaries and proof
that later parser commits only add evidence.

Host gates are rerun after the combined underline and parser corrections.
Earlier passing checks and every failure remain predecessor evidence and do not
inflate current acceptance totals. `host-runtime-corrections.json` binds the
corrections and expanded scope. App and CLI locked offline resolution passes
with committed locks unchanged. Five real ELF native assets were built by the
first app run; their manifest and identities are retained in
`native-build-receipt.json`.

Each completed gate is saved remotely before the next. Source, tool and resolved
input identities are checked before and after execution. Generated Office and
navigation outputs are bound to their generator receipts. Checkpoint commits
use `[skip ci]`. No GitHub Actions run is awaited, polled or restarted.

## Evidence boundaries

The independently revalidated predecessor 996-case milestone retains its exact
old source scope. External Office applications, other operating systems and
broad Open XML schema certification remain separate scopes. Two optional
HOME-scanning corpus harnesses are retained without execution or vacuous counts.
