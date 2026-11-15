# Saved integration and remaining local qualification

## Current state

The source integration is saved at `97e6aa18625e74169c085085ecaecd9adf917283`
(tree `44e273534652889ccb4945709360bb9cf4d2e723`). Documentation-only
navigation checkpoint `d97705da` is also included through `488478cc`.
The remote cutoff is 15 November 2026 at 08:06:34 UTC.

The branch includes current main, the newer worksheet preview/evidence work,
and all six commits from `feature/new-documents-history-20261115`.
All original PNG commands remain alongside New, Recent and Convert. The
incoming branch adds nine test files and changes the browser-menu store test;
the app cohort now contains 41 suites.

**Runtime qualification is still pending.** No Flutter/Dart test suite ran in
this continuation. The local filesystem exhausted its capacity and then
prevented every sandboxed command from starting. The narrowly scoped cleanup
request was rejected because this environment disables sandbox escalation.
The computer-use runtime was also unavailable. Source integration and these
receipts were therefore saved through the repository API.

The user explicitly requires progress without waiting for GitHub Actions.
No Actions run was awaited or restarted. Every new checkpoint uses
`[skip ci]` in its commit message.

## Completed checks

- Verified the complete 10,413-file source union at `97e6aa18`: no missing,
  extra or unintended changed paths.
- Of those files, 10,409 use expected existing blob identities. The four
  combined files were read back and compared with their intended complete
  content.
- For each combined file, incoming hunks reproduce the exact incoming file
  from the common base, match one unique context in the integration source,
  and reverse to the unchanged pre-merge integration file.
- All 2,220 managed Office files match canonical Git blob identity, size and
  mode: 488 Quds files and 1,732 standalone parser files.
- Corrected 41 pre-existing executable flags on Quds Dart files. No source
  bytes or canonical pins changed.
- Verified standalone inventory and agreement among the source manifest,
  parser UPSTREAM declaration and dependency declarations.
- Confirmed current main is an ancestor of the source checkpoint (zero commits
  behind). No upstream feature branch was rewritten or deleted.

The canonical pins remain Quds `b23d033620f07cf2659209eff4c4c8e2d71ee89c`
and standalone parser `d422fa99a3a84830794f0e2dc332d59f923779f7`.
Quds main's newer merge ancestry does not add newer production bytes and
lacks the final Linux golden correction, so it does not replace the pin.

These are committed-source and merge checks. They do not establish runtime,
rendering or schema acceptance. The full manifest SHA-256 rehash was not
executed in this continuation; canonical Git blob identities were compared.
The older 606/607, 71/73, 95, 248 and other counts in historical progress
entries are not new results for the combined source. The final raw receipts
described in the pasted handoff were not present in the recovered branch.

## Saved receipts

- [Remote cutoff and checkpoints](remote-source-audit.json)
- [Merge/source checks](integration-verification.json)
- [Canonical Office identity and mode corrections](office-source-verification.json)
- [Execution blocker and cleanup outcome](execution-blocker.json)

The separately imported
[worksheet-navigation local checkpoint](../../office-worksheet-navigation-20261115/resume/local-preview-20261115/README.md)
records its own analysis and disk-blocked native launch. Its source and scope
remain separate; it does not qualify this combined app.

## Resume with writable capacity

Use a workspace with room for the pinned Flutter/Dart toolchain, locked
dependency cache and real native builds. Follow `.fvmrc` and the repository's
native setup scripts. Flutter is 3.47.8 and Dart is 3.13.7. Resolve the locked
dependency graph before recording gates and retain the resulting tool versions,
package lock and configuration. Do not disable native hooks, fake native
libraries, change production dependencies or weaken tests to fit the runner.

Fetch the integration branch and check out its current saved head. Preserve
any available failed-run evidence before removing temporary build data.
Run gates on a clean source tree. The recorder retains before/after source
and resolution hashes, command, exit status and strict machine-event counts.

For the app cohort, from the repository root:

```bash
source_commit="$(git rev-parse HEAD)"
gate_root="docs/evidence/storage-carving-20261115/local-resume-$(date -u +%Y%m%dT%H%M%SZ)"
suite_manifest="docs/evidence/storage-carving-20261115/app-suites.txt"
mapfile -t app_suites < "$suite_manifest"

python3 docs/evidence/storage-carving-20261115/record_gate.py \
  --repo "$PWD" --head "$source_commit" \
  --output "$gate_root/app" --suites "$suite_manifest" \
  --tool "$(command -v flutter)" -- \
  flutter --suppress-analytics test --no-pub --reporter json \
  "${app_suites[@]}"
```

**Save the resulting gate immediately, including a failed gate:**

```bash
git add "$gate_root/app"
git commit -m "test(storage): preserve local app qualification receipt [skip ci]"
git push origin HEAD:integration/storage-carving-20261115
```

Then run the existing editor and engine manifests in their respective package
directories, strict focused analysis for the combined changed Dart source,
Office inventory/sync controls and the full source verification. Update the
recorded source head after each evidence commit; do not reuse a previous
`--head` with a different checkout.

Run the existing portable driver on the pinned Dart VM and actual compiled
JavaScript, using the independent Python reader for both outputs:

```bash
python3 docs/evidence/storage-carving-20261115/run_portable.py \
  --repo "$PWD" --launcher "$(command -v env)" \
  --output "$gate_root/png-portable"
```

Wrap that command in `record_gate.py` for source-bound recording, and commit
both its recorder output and portable artifacts immediately afterward.
Use `OFFICE_NAVIGATION_PREVIEW=1` for the separate navigation capture run,
inspect the real captures and retain their font/source receipts. Keep that
visual review distinct from ordinary machine-event acceptance.

Update PR #111 with only the freshly observed results once the required local
gates finish. Keep the PR draft while qualification remains incomplete.
