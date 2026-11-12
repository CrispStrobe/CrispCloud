# Vendored Rust provider clients — upstream pin

| Crate | Source | License |
| --- | --- | --- |
| `crisp_filen` (package `crisp-filen`) | [CrispSorter `crates/crisp-filen-native`](https://github.com/CrispStrobe/CrispSorter/tree/45c748d4/crates/crisp-filen-native) | MPL-2.0 (`LICENSE`) |
| `crisp_internxt` (package `crisp-internxt`) | [CrispSorter `crates/crisp-internxt-native`](https://github.com/CrispStrobe/CrispSorter/tree/45c748d4/crates/crisp-internxt-native) | MPL-2.0 (`LICENSE`) |

Pinned commit: CrispSorter `45c748d4` (merge of PR #45, 11 November 2026),
exported with `git archive 45c748d4 crates/crisp-<provider>-native`.

## CrispCloud integration patches

1. `Cargo.toml`: `clap` is optional behind a new `cli` feature and the
   test binary has `required-features = ["cli"]`, so the app bridge does not
   resolve the CLI. Build the upstream CLI with `cargo build --features cli`.
2. `Cargo.toml`: an empty `[workspace]` table keeps each crate standalone.
3. `crisp_internxt`: CrispSorter's test-only `internxt-core` dev-dependency is
   not vendored. The single conformance test that used it is compiled only with
   `RUSTFLAGS="--cfg crisp_internxt_core_reference"` (declared in
   `[lints.rust]`), which is how CrispSorter keeps running it.

The historical export also has maintained host transport/proxy integration patches; these directories are an app consumer fork. They are not claimed to be a byte-identical copy of the latest standalone repository. To advance the baseline,
re-export both directories at the new commit, re-apply the three patches,
then run `cargo test --locked` here, the bridge tests in `../../rust_cloud`,
`python3 tool/check_rust_licenses.py --bridge cloud` and the live suites.

MPL-2.0 is file-level copyleft: these files stay under MPL-2.0 inside
CrispCloud, their notices must be retained, and modified MPL files must be
made available in source form. See `docs/STORAGE_ENGINE_ARCHITECTURE.md`.

## Reviewed trash-name backport

The gateway trash-name correction from `CrispStrobe/crisp-cloud-rs` commit `6b61faa8228e3be2eb71d0710975babbc03e5f8e` and its endpoint regressions are applied to the app consumer. Files retain their extension and exact UUID across pagination; folders and extensionless files preserve their names. Existing host transport and dependency patches are retained. This is a protocol metadata backport beyond the historical manifest-only patch list above.
