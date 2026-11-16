# Remote integration and local provenance audit

Recorded on 16 November 2026. These checks used Git and local tools. No GitHub
Actions were queried, started, or awaited by this audit.

## Remote snapshot and late integration

The remote advertisement completed at **07:26:39.358987 UTC** and contained
**38 branch heads and 151 available pull-request heads, 189 references total**.
The exact advertisement is `advertised-refs.txt`; command timings and the
original ancestry results are in `remote-audit.json`. The commands were:

```sh
git ls-remote origin 'refs/heads/*' 'refs/pull/*/head'
git fetch --no-tags origin \
  '+refs/heads/*:refs/remotes/origin/*' \
  '+refs/pull/*/head:refs/remotes/audit-pr/*'
```

The first ancestry check against local checkpoint
`013daab50a178bf0392eb8c1109b44662afdbd8e` correctly identified two references
whose new head was not yet included: `codex/zotero-support-20261116` and PR #161,
both at `e980293cc7446899f1404372ee6296bb65710358`. That original finding is
preserved; it is not the final integration result.

The incoming branch already contained the previous continuation checkpoint
`ce386fd6c16268b782088b2e47e32bbab8b4ce43`. The incoming-only delta from that
merge base consisted of two commits and 33 changed files: Office/Zotero source
and tests, the Office provenance manifest, and reconciliation evidence. No
application or package dependency manifests, dependency lockfiles, terminal
code, workflow files, or terminal validation runner changed in this delta.

`git merge-tree --write-tree` against
`6e11d2d6fda1486dc6968e01137ba7466356398f` completed without conflicts and
produced tree `3f854d143c07788ce0b07ad8b0d65bd86c7ea59d`. The root agent then
integrated the incoming head and published checkpoint
`4316f7fc7aca30ecfccfecf318acbdc8e5599ff2` with that exact tree. The locally
observed intermediate merge commit
`10c97e5ad8fe3ba4434831c6708784ba00552f9b` has the same tree; its identity is
retained in the first postmerge guard receipts rather than rewritten.

At **07:30:10.715082 UTC**, every one of the 189 advertised reference heads was
explicitly checked with `git merge-base --is-ancestor` against published
checkpoint `4316f7fc7aca30ecfccfecf318acbdc8e5599ff2`. **No advertised head was
missing from its ancestry.** See `published-remote-ancestry.json`. This is a
snapshot cutoff, not a claim that remote branches cannot advance afterward.

Supporting incoming-change receipts are `late-zotero-review.json`,
`late-zotero-diff-stat.txt`, `late-zotero-merge-tree.json`, and
`late-zotero-manifest-review.json`.

## Vendor provenance

The audit ran both repository guards with the tracked-source requirement:

```sh
python3 tool/verify_office_fidelity.py --require-tracked
python3 tool/verify_dartssh2_vendor.py --require-tracked
```

The premerge receipt `vendor-verification.json` verifies the earlier **2,399**
Office entries at Quds pin `b24718cc1468c34f494805eb7fb433a87f565503`. It is
retained as historical evidence and is superseded for the integrated source by
`postmerge-vendor-verification.json`.

After integration, both guards exited zero:

- **2,407 Office entries** verified at Quds source pin
  `9b31295bbf705b7aff8a732c16f9d010edbb4e3a`.
- The independent legacy parser remained pinned to
  `4895712158127b2fc930d796e17035c3ca0dac62`.
- **96 dartssh2 4.1.0 upstream files and four reviewed agent-channel patches**
  verified unchanged.

The incoming Office manifest adds eight entries and changes 22 hashes, with
none removed. Every added or changed manifest hash was also compared directly
with the incoming Git blob before integration; all 30 matched. Standalone
source declarations and all dependency manifests and lockfiles were unchanged.

## Workflow and local runner registration

`workflow-entrypoints.json` records a local YAML parse of all **33 workflow
files**, using a loader that rejects duplicate mapping keys. It also verifies
that all referenced test paths exist. All six deterministic tmux suites are
registered in each of these `.github/workflows/ci.yml` steps:

| Job | Step | Platform |
| --- | --- | --- |
| `collection-browser` | Terminal input and explicit SSH gateway | Chrome on Ubuntu |
| `build-windows` | Terminal workspace and remote session regressions | Native Windows |
| `build-macos` | macOS regression tests | Native macOS |

The suites are `tmux_control_protocol_test.dart`,
`tmux_control_client_test.dart`, `tmux_control_workspace_test.dart`,
`ssh_native_tmux_persistence_test.dart`, `terminal_input_budget_test.dart`, and
`ssh_tmux_panel_lifecycle_test.dart`, all under `test/`.

The local `tool/run_terminal_validation.py` registration includes all six, with
**75 files** in the assembled native terminal cohort and no missing paths.
The SSH vendor guard is registered in `ci.yml`, `nightly.yml`, and
`release.yml`. `dart_test.yaml` also parsed successfully.

After the Office integration, SHA-256 comparisons confirmed that all 33 parsed
workflow files and the terminal validation runner were unchanged. See
`postmerge-workflow-and-checkpoint-verification.json`. These are syntax,
registration, and local path checks; they do not claim remote workflow execution
or platform acceptance.

## Incoming Office application-boundary test

The requested narrow test used the pinned Flutter 3.47.8 / Dart 3.13.7 runner,
the preexisting enforced production dependency resolution, and normal native
build hooks:

```sh
../toolchain/run flutter test --no-pub --reporter=expanded \
  test/office_zotero_citing_transport_test.dart
```

It completed at **07:30:21.783433 UTC** in **27.915 seconds**, with **16 tests
passed, no skips, and no failures**. It covers local saved-search routing,
refusal of writes and encoded route injection, citing request bounds and
headers, redirects, timeouts, and disposal of pending or streaming responses.

The test started and ended at checkpoint
`4316f7fc7aca30ecfccfecf318acbdc8e5599ff2`. All 35 watched incoming source,
evidence, and dependency-manifest files retained the same SHA-256 hashes during
the run. The full log and receipt are in `office-transport/`. This focused
transport test is separate from the terminal cohort and full web acceptance
performed by the root validation task.
