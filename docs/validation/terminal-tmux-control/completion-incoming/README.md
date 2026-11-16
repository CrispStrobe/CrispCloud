# Completion-time integration proof

The completion audit recorded at **07:54:21.308626 UTC on 16 November 2026**
found a newer PR #161 / `codex/zotero-support-20261116` head,
`5efae7732727fc1ae43d6b664922214dd6acfedf`. This follow-up inspected the supplied
Git objects without fetching again, running an SDK, or querying GitHub Actions.

## Final ancestry and provenance

The root agent integrated the reviewed tree and published
**`48775630505eceb784301f1ff630b4a58779cc25`**, tree
`06548945c098b801b8ae4fe3f30b87a6bacf5afc`. The complete immutable advertisement
is `../completion-remote-advertisement.tsv`, with its original audit in
`../completion-remote-audit.json`.

`postmerge-remote-ancestry.json` verifies all **38 branch heads and 151
pull-request heads, 189 references total**, as actual ancestors of that
published checkpoint. **No heads are missing.** The proof records SHA-256
identities for both the original advertisement and audit receipt.

Both local provenance guards passed with `--require-tracked` at the published
checkpoint:

| Guard | Result |
| --- | --- |
| Office | 2,409 managed files; Quds source `428679a33381f943a8ae63117d4207f01dd15462` |
| Independent legacy parser | Source remains `4895712158127b2fc930d796e17035c3ca0dac62` |
| SSH | 96 dartssh2 4.1.0 upstream files and four reviewed patches |

The commands, hashes, output, and zero exit codes are recorded in
`postmerge-vendor-verification.json` and the two guard logs.

## Why the completed cohort remains applicable

The incoming commit changes **196 files** relative to root checkpoint
`b14ba65d6fc18a9b3214a068849a7c9951df44c0`: 195 new files under
`docs/validation/zotero-fidelity-20261116/` and the provenance manifest.

The manifest's **only changed JSON key is `source_commit`**, advancing from
`ca4011de0e17783f12bcff07336e318adc1db99c` to
`428679a33381f943a8ae63117d4207f01dd15462`. Its 2,409 managed-file hashes and
independent source declarations are identical. The incoming delivery plan and
apply receipts also record zero vendor writes and zero deletions.

No application source, test, dependency manifest, lockfile, platform code,
workflow, runner, or bundled asset changes. The new `pubspec.yaml` and lockfiles
in the diff are archived evidence under `docs/validation/`; they do not
participate in the production dependency graph. None of the incoming paths
matches an asset declaration in the application's manifest.

`effective-incoming-review.json` records identical Git object identities for
16 application/source/test/platform/configuration scopes before and after the
merge, and verifies that the published tree is exactly the inspected tree.
This is a documentation and provenance merge. It introduces no runtime change
that requires repeating the already completed exact-source terminal cohort.
The failed optimized web attempt still requires its independent retry; the
merge does not change that retry's runtime inputs.

## Imported qualification and its limits

`incoming-qualification-review.json` inspects the evidence supplied by
`5efae773` and verifies its linked log and receipt hashes. The imported results
remain distinct from this continuation's own final-source acceptance:

| Imported qualification | Recorded result | Scope |
| --- | --- | --- |
| Office host | 39 passed | Three host suites; focused 96-package graph |
| Terminal core | 402 passed | 29 suites; focused 130-package graph including its root |
| OpenSSH loopback | 17 passed, two skips | Three suites; system-agent socket and optional PTY cases skipped |
| Supplemental terminal UI/transport | No tests executed | Required native hook blocked on absent Cargo |
| Full application Dart kernel | Kernel target passed | Recorded kernel stamp, dependency file, input hashes; kernel binary not archived |
| Full application bundle | Failed | Required `crisp_catalog` native-assets hook could not find Cargo |

All checked core/loopback logs, terminal delivery-receipt hashes, and kernel
stamp/depfile/input-map hashes match their recorded values. The imported build
does not establish a complete application bundle, executable, GUI acceptance,
or optimized web release. Its native hooks were enabled.

The imported terminal qualification covers the earlier tmux source through
`6e11d2d6`. Its 221-file source map differs from the current continuation in
`ssh_tmux_control_output.dart`, `tmux_control_client.dart`, and
`tmux_control_client_test.dart`. The broader imported host/full-app maps also
predate the later tmux localization and workspace changes; the full-app map
predates the final metadata-only Office pin. Exact paths and hashes are
recorded in the review. These imported terminal/build results do not replace
the root's final-source validation.

The incoming overview also references canonical Quds engine/editor, typography,
and live Zotero evidence in the companion repository. This audit records those
as referenced upstream claims; it did not fetch or independently reexecute that
separate repository's qualification. The verified unchanged Office bytes link
the previously reviewed Office host acceptance to the final provenance pin.
