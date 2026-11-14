# Validation environment and preliminary attempts

This record describes setup and intermediate work on 2026-11-14. It does not
qualify a later commit. Final source-bound gate receipts are recorded separately
by the parent evidence index.

## Toolchain and original dependencies

The repository-pinned Flutter **3.47.8** / Dart **3.13.7** SDK was downloaded
from the official Flutter release archive. Its SHA-256 matched the release
index. [toolchain.json](toolchain.json) retains that release record, exact
revision and archive digest. Rust/Cargo **1.100.0** and Clang **19.1.7** supplied
the existing native build hooks; Chromium **156.0.8078.79** was available for
browser tests. These are validation tools, not new application dependencies.

`flutter pub get --enforce-lockfile` completed successfully. To reduce setup
time, 232 missing hosted packages were fetched at their exact locked versions
through normal `dart pub cache add` commands; all returned exit code 0. Normal
Pub and Cargo cache/checksum paths remained in use. The original manifest
hashes are retained in [intermediate/manifest-before.json](intermediate/manifest-before.json),
and [environment-validation.json](environment-validation.json) records the
same hashes after dependency resolution, SDK/compiler provenance, and setup
wrapper hashes. Both `pubspec.yaml` and `pubspec.lock` remained byte-identical.
The compressed dependency and Cargo logs, exact-version prefetch results, and
byte hashes are indexed by [intermediate/files.json](intermediate/files.json).

## Native setup corrections

The first native test launch stopped before loading tests while an existing
SMB hook requested its public Linux runtime. Independent read-only inspection
established that the unchanged hook selected a fixed release asset and made a
bodyless, unauthenticated GET without user-file data or custom request headers.
It verifies the bytes before publishing its cache entry:

- Source: `packages/dart_smb2/hook/build.dart`.
- Asset: `https://github.com/ales-drnz/dart_smb2/releases/download/libsmb2-r10/libsmb2_linux-x86_64.so`.
- Required and independently observed SHA-256:
  `4612ed4499f4c066d0db295679469c62545c6252849bfa61eb5f45ec1bbd3577`.

After that diagnosis, an unchanged normal test retry completed the download.
No alternate downloader, hook rewrite, project dependency override, or access
policy change was used. The zero-byte log from the interrupted launch is
preserved; this note summarizes the interruption without including internal
review text.

Two further setup attempts stopped before loading tests. Dart's native-hook
environment did not retain the scratch Rust installation location, so the
Cargo shim could not find a default toolchain. A scratch-local launcher then
selected the installed compiler and cache explicitly. The PTY C hook next
required Clang, which was initially absent. Four official Debian packages were
verified against their published index hashes and extracted into scratch;
a local launcher exposed that compiler and its shared libraries. Package
versions, filenames and checksums appear in the environment record. Application
manifests and native-hook source were not edited. Both original failure logs
are preserved in the intermediate directory.

## Preliminary results and attribution

The subsequent four-suite native comparison run passed **52 tests**, with
zero failures or skips. Its expanded log and JSON events are retained with
their original bytes. It was a working-tree run: `observedRevisionAfterRun`
in the summary identifies an observed HEAD, not a complete frozen source
qualification. The two earlier source inventories belong to their interrupted
or setup-failing attempts and must not be used to bind the later passing run.

The initial widget run passed six tests and failed three expectations because
`pumpAndSettle` waited on intentionally stalled loading UI. The test harness was
corrected without a runtime change, and its retry passed **nine tests**, with
zero failures or skips. Both logs are preserved as working-tree observations;
neither carries a complete pre-run source binding. Final native and browser
qualification must use the separately saved candidate and its own receipts.

The Visual Studio discovery line is a non-fatal compiler-resolver diagnostic
on Linux. Recorded exit codes, test events and explicit success lines govern
each result. All copied logs and records were inspected for credential tokens,
authenticated URLs, and sensitive environment data before inclusion.

## Failed saved candidate

The later saved candidate `542c1c8b97643e5ad2e7c44f35b5417ef95c7d6a` has
separately preserved [source-bound failed gates](intermediate/candidate-542c1c8b/README.md).
The expanded native gate passed 87 tests and failed one reused-provider-buffer
case; strict scoped analysis found one required-braces lint. Both receipts
reported unchanged source and package maps over 8,111 source paths. These
failures are distinct from the earlier setup attempts and from the 52-test
preliminary pass; neither failed receipt is attributed to a subsequent fix.
