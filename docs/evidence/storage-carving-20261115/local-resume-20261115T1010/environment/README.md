# Local qualification environment

This directory records setup of a genuine pinned local toolchain. These are environment receipts, not application test results.

## Tools

- Flutter 3.47.8, commit `737ba8f885dc774b53b442759999a312c9461e4e`; Dart 3.13.7.
- Rust and Cargo 1.100.0, downloaded from the official release manifest with component SHA-256 checks.
- Debian trixie Clang 19.1.7, CMake 3.31.6 and Ninja 1.12.1, extracted into the workspace after package SHA-256 checks against the official package index.
- C and Rust compile/link/run probes passed both normally and with only PATH inherited. The saved launchers supply workspace temporary/cache paths and loader search paths to real tool binaries, including for filtered native hooks.
- The official Flutter archive SHA-256 matches its release metadata. Flutter's bundled package preload cache initialized its own development dependencies offline. The final Linux precache succeeded.

## Use

The installation exists at `/workspace/scratch/aed049b7e8bd/toolchains`. Source its `env.sh`, then use `flutter --no-version-check --suppress-analytics` to avoid unrelated update checks. The captured environment file and launchers are path-bound receipts; relocate the toolchain root consistently when reproducing elsewhere.

No application dependencies were resolved during the setup captured here, and no repository source or production dependency was changed. Native hooks remain enabled. The setup receipt distinguishes the cancelled cache-initialization attempts and the initial temporary-directory probe failure from the final successful setup.

Resolve the locked root app graph and needed package development graphs before beginning source-bound gates. The recorder includes their lock/config/graph files, so do not resolve dependencies concurrently with recording. Keep navigation capture review separate from machine-event test acceptance.

The JSON files retain versions, upstream download identities, hash checks and native probe results. Setup logs are gzip-compressed without timestamps. `artifacts-sha256.json` covers this evidence directory.

## Completed dependency resolution

All five setup attempts completed successfully. The root app and CLI used `--enforce-lockfile`; both committed lockfiles and their pubspec declarations remained byte-for-byte unchanged. Office engine/editor and standalone parser packages had no pre-existing development lockfiles; their normal package-local resolution created locks/configurations without changing dependency declarations. Exact commands, source heads, selected environment variables, logs and before/after lock/config/graph bytes are retained under `resolution/`.

The application source changed concurrently during this explicitly setup-only phase. These receipts do not qualify those source edits. No dependency resolution remains active. Complete and commit source changes before beginning recorder gates.

`record_gate.py` already snapshots root and Office engine/editor/parser package graphs. For a CLI-focused analysis gate, also pass `--tool cli/.dart_tool/package_config.json --tool cli/.dart_tool/package_graph.json` so the CLI resolution inputs are bound without changing the recorder. The tracked CLI lock is already included in its source snapshot.
