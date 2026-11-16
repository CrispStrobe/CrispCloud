# Final pre-acceptance remote cutoff

This separate audit was requested immediately before source freeze so that
newly published work could be integrated before the full local acceptance run.
No GitHub Actions were queried or awaited. This audit did not change source,
the Git index, or commits.

## Integrated result

The root agent integrated the incoming head after its final tmux fixes and
published **`60bc3a4155c3c1e1b7107cc087647ac79938b0d6`**, tree
`0874a6271d01922565d5edbe96b0b83d1f7879c4`. At **07:47:28.669794 UTC**, all
**189** heads from the cutoff below were explicitly verified as ancestors of
that published commit; **none were missing**. See
`postmerge-remote-ancestry.json`. This check reused the existing advertisement
and fetched no new references.

Both local provenance guards passed with `--require-tracked` at that same
published checkpoint: **2,409 Office files** at Quds pin
`ca4011de0e17783f12bcff07336e318adc1db99c`, and **96 dartssh2 4.1.0 upstream
files with four reviewed patches**. See `postmerge-vendor-verification.json`
and its two logs. The earlier clean merge-tree result below was computed
against `359e3997`; the final published tree also contains the root's finished
tmux fixes from parent `e61256c2`.

## Snapshot

The remote advertisement completed on **16 November 2026 at
07:44:13.637994 UTC**. It contained **38 branch heads and 151 available
pull-request heads, 189 references total**. The subsequent fetch completed at
07:44:19.106955 UTC. See `remote-audit.json`, `advertised-refs.stdout.log`, and
the fetch logs for exact commands, timings, and every advertised SHA.

Against root checkpoint `359e399757e4f0b74ab8b190a3119cef841d3c7d`, only two
references were not yet ancestors:

| Reference | Incoming SHA |
| --- | --- |
| `refs/heads/codex/zotero-support-20261116` | `fc09d3f5e0ecb74ca91f3c416b401b0897dc04da` |
| `refs/pull/161/head` | `fc09d3f5e0ecb74ca91f3c416b401b0897dc04da` |

The remaining 187 references were contained. The new head was reported to the
root agent immediately for integration. This initial receipt preserves the
state before that integration; it does not claim that the two references were
already merged at the snapshot time.

## Incoming-only review

The branches have **two merge bases**:
`6e11d2d6fda1486dc6968e01137ba7466356398f` and
`e980293cc7446899f1404372ee6296bb65710358`. Using just the first merge base
includes Office changes already incorporated by the root branch. For an exact
incoming effect, this audit compared the root HEAD tree with the clean
prospective merge tree.

```sh
git merge-tree --write-tree \
  359e399757e4f0b74ab8b190a3119cef841d3c7d \
  fc09d3f5e0ecb74ca91f3c416b401b0897dc04da
```

The command exited zero, with no conflicts, and produced tree
`48a90a486b1f819c7b9d43648752ae57a9ee0970`. It did not touch the working tree or
index. `incoming-merge-tree.json` records the result.

The effective incoming delta comprises **58 files**: 48 documentation and
validation-evidence files, eight managed Office source/test files, the Office
transport test, and the Office provenance manifest. No application or package
dependency manifest or lockfile changes. No terminal source, terminal tests,
workflow, or terminal validation-runner changes.

`effective-incoming-review.json` is the authoritative incoming-scope receipt.
`incoming-review.json` preserves the earlier single-merge-base view for
transparency. Four incoming commits were not yet ancestors of the root HEAD:

- `769b087c8b8fa78fbdfb9da1faaeb6d28b69ecca`: hardened bibliography and Unicode
  typography at the new Quds source pin.
- `0b1646f9fe64ac8f88ae24034a672c138647e50e`: formatting of the saved-search
  transport tests.
- `de1259080074ca7918122d4790e9255269944b25`: merge of the earlier native tmux
  work into the Zotero branch.
- `fc09d3f5e0ecb74ca91f3c416b401b0897dc04da`: host qualification and incoming
  tmux source-audit evidence.

The runtime changes add Unicode full-uppercase expansion data, preserve Greek
iota-subscript mark ordering, retain display offsets through replacement glyph
objects, and avoid treating an identical plain-text bibliography response as
new paragraph-boundary evidence. The application transport-test delta is
formatting only.

## Incoming provenance

The Office manifest advances from Quds pin
`9b31295bbf705b7aff8a732c16f9d010edbb4e3a` to
`ca4011de0e17783f12bcff07336e318adc1db99c`, with **2,407 to 2,409 entries**.
There are two added entries, six changed hashes, and no removals. All eight
added/changed entries were hashed directly from the prospective merge's Git
blobs and match the incoming manifest. Independent legacy-parser source
declarations are unchanged.

This is the final requested pre-acceptance remote cutoff. Later acceptance and
postmerge ancestry reference this immutable advertisement without
fetching again unless a new remote refresh is requested.

## Incoming Office acceptance compared with integrated source

The incoming branch carries
`docs/validation/zotero-fidelity-20261116/final/host-validation-receipt.json`.
That receipt reports **39 passed tests** across the citing transport, Office
Zotero service, and Office ribbon suites, completed at **07:33:38.561867 UTC**.
Its eight host analysis/format targets and all recorded steps passed. It used
Flutter 3.47.8 / Dart 3.13.7 with a focused **96-package host dependency
graph**, rather than the complete production application dependency graph.

`incoming-office-acceptance-comparison.json` independently checks the imported
receipt and the current source at `60bc3a41` without rerunning an SDK command:

- All seven recorded step logs match their declared SHA-256 hashes.
- The before/after inventories are identical; their counts and aggregate
  hashes match the receipt. Dependency-input and qualification-script hashes
  also match.
- The receipt, source inventories, dependency inputs, and logs match the exact
  imported Git blobs at `fc09d3f5`.
- All **417 archived Office package source/configuration files** match the
  currently integrated files, as do all **eight host analysis/test targets**.
- The complete current **2,409-entry Office manifest**, source pin, independent
  parser declarations, and every managed file hash match the incoming
  acceptance evidence.

The broader incoming inventory covers 1,611 files. Its only four differences
from the current integration are later tmux changes in
`lib/l10n/tmux_control_strings.dart`,
`lib/services/ssh_tmux_control_output.dart`,
`lib/services/tmux_control_client.dart`, and
`lib/widgets/tmux_control_workspace.dart`. There are no missing inventory
files. The incoming Office qualification therefore matches the integrated
Office source; it does not establish acceptance of the later tmux changes.

The incoming receipt explicitly limits its claim to mocked host tests. It does
not establish live Zotero desktop/account, real OS keychain, native Word
refresh, a full application build, or a new execution of canonical engine and
editor suites.

Our separate earlier transport run in `../audit-final/office-transport/`
passed **16 tests** at `4316f7fc` with the production dependency graph and
normal native hooks, before this final Office integration. Its count overlaps
the incoming 39-test host qualification and must not be added to that number
as unique tests. The final local production acceptance begins separately at
`60bc3a41`.
