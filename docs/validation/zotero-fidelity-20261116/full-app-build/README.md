# Full CrispCloud Dart compilation and native-assets boundary

The complete CrispCloud application's **Dart kernel compilation passed** at
`de1259080074ca7918122d4790e9255269944b25`, which includes the reconciled tmux
work and Quds source pin `ca4011de0e17783f12bcff07336e318adc1db99c`.
The requested Linux debug **bundle failed** because the required
`crisp_catalog` native-assets hook could not launch `cargo`.

These are separate outcomes from the same real Flutter invocation. No native
hook was disabled, no production constraint or build configuration was changed,
and no native toolchain was installed. This is compile evidence, not a runnable
native application or GUI acceptance result.

## Recorded results

| Step | Result |
| --- | --- |
| Initial online dependency restore | Bounded timeout; original log retained |
| Initial diagnostic restore | Bounded timeout; original log retained |
| Initial offline diagnostic | Identified missing exact cached dependencies; original log retained |
| Cache restoration | Official `dart pub cache add` obtained all 76 remaining missing hosted versions; lock unchanged |
| Production dependency graph | `flutter pub get --offline --enforce-lockfile` passed against the exact copied manifest and lock |
| Full application Dart compilation | `kernel_snapshot_program` completed for `lib/main.dart`, Linux x64, debug |
| Kernel output | 241,861,864 bytes; SHA-256 `3e89525d6f2b153d9958de5c3eebe8f5df4dba3b3a24b36977c3b3b0ca73c3d9` |
| Required native-assets hook | Failed to launch `cargo build --release --locked … --target x86_64-unknown-linux-gnu` for `crisp_catalog` |
| Overall Flutter bundle | Failed; no complete asset bundle is claimed |
| Source preservation during the attempt | All 6,981 recorded canonical input hashes unchanged; isolated manifest and lock unchanged |

The [receipt](receipt.json) records commands, exit codes, durations, source
identity, original input scopes and output hashes. The
[bundle log](logs/full-crisp-bundle.log) contains the native-assets failure;
the [locked restore log](logs/full-crisp-locked-restore.log) records successful
production dependency resolution. Earlier unsuccessful attempts are kept in
[initial-attempts](initial-attempts/), and exact-version acquisition receipts
are in [cache](cache/receipt.json). Overlapping attempts are not counted as
additional successes.

## Why the Dart compilation result is independently established

Flutter completed its kernel target concurrently with the native-assets work.
It left a fresh [kernel target stamp](compiler/kernel_snapshot_program.stamp),
the associated [dependency file](compiler/kernel_snapshot_program.d), and a
complete `app.dill` with the Dart kernel header `90abcdef`.

The official Flutter source used in this run is retained for the narrow
completion check. [`KernelSnapshot.build`](environment/flutter-kernel-target.dart)
throws if the compiler returns no output or any errors.
The [build system](environment/flutter-build-system.dart) writes a target's
stamp only after its build completes, and clears the stamp if that target
throws. The receipt records the kernel/stamp timestamps from this invocation,
their content hashes, and the kernel's retained workspace path. No second
compilation or cache-only replay is substituted for this result.

The large, reproducible kernel binary is not committed. Its hash and actual
path permit an independent check while it remains in the workspace. The
recorded sources, locked graph, official runtime, commands and target evidence
support reproduction.

## Isolation and source equivalence

The build project copied the exact production `pubspec.yaml`, `pubspec.lock`,
analysis options and localization configuration. The original `lib` symlink
was replaced with an exact isolated copy before Flutter ran `gen-l10n`, so
generated localization code could not write through into the source checkout.
Declared licence, macOS licence and help-document assets were also supplied.
Package and asset trees remained linked to their genuine source files; no
stand-in implementations or dependency overrides were added.

[Source before](source-before.json) and [source after](source-after.json)
record the 6,981 canonical inputs checked across the attempt. The
[actual compiler-input map](compiler/input-sha256.json) records 8,266 distinct
inputs after compilation, including dependencies and generated compiler
inputs. [Generated localization evidence](compiler/generated-localizations.json)
separately records the ten generated outputs, their current isolated paths and
the canonical ARB input hashes. Copied library files outside those declared
outputs remain equal to their canonical inputs.

The canonical source scope also includes the companion vendor manifest and
declared documentation assets. A later documentation-only vendor repin must be
reported as a changed metadata input if it changes that map. Kernel continuity
can be assessed separately from the actual compiler-input map; the original
before/after maps must not be rewritten to hide a later difference.

## Reproduction and limits

The executed [preparation](scripts/prepare-full-crisp.py),
[cache warming](scripts/warm-crisp-locked-cache.py),
[bounded build runner](scripts/run-full-crisp.py) and
[evidence packaging](scripts/package-full-crisp.py) scripts retain their actual
workspace layout and commands. Restore the recorded official Flutter
3.47.8 / Dart 3.13.7 runtime and exact dependencies before reusing them in a
new workspace. The [input files](inputs/) and Flutter source excerpts preserve
the relevant configuration; original dependency constraints remain unchanged.

The missing Cargo executable prevents qualification of the native-assets
phase. Other native prerequisites may still be required after that point.
No native executable, full CrispCloud launch, private-account/keychain
behavior, or desktop interaction is claimed. GitHub Actions were not queried,
polled, awaited or rerun.
