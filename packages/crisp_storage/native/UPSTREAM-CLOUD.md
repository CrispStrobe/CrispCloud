# Vendored Rust provider clients — upstream pin

| Crate | Source | License |
| --- | --- | --- |
| `crisp_filen` (package `crisp-filen`) | [CrispSorter `crates/crisp-filen-native`](https://github.com/CrispStrobe/CrispSorter/tree/45c748d4/crates/crisp-filen-native) | MPL-2.0 (`LICENSE`) |
| `crisp_internxt` (package `crisp-internxt`) | [CrispSorter `crates/crisp-internxt-native`](https://github.com/CrispStrobe/CrispSorter/tree/45c748d4/crates/crisp-internxt-native) | MPL-2.0 (`LICENSE`) |

Pinned commit: CrispSorter `45c748d4` (merge of PR #45, 11 November 2026),
exported with `git archive 45c748d4 crates/crisp-<provider>-native`.

## CrispCloud patches (manifest/test only, no protocol code changes)

1. `Cargo.toml`: `clap` is optional behind a new `cli` feature and the
   test binary has `required-features = ["cli"]`, so the app bridge does not
   resolve the CLI. Build the upstream CLI with `cargo build --features cli`.
2. `Cargo.toml`: an empty `[workspace]` table keeps each crate standalone.
3. `crisp_internxt`: CrispSorter's test-only `internxt-core` dev-dependency is
   not vendored. The single conformance test that used it is compiled only with
   `RUSTFLAGS="--cfg crisp_internxt_core_reference"` (declared in
   `[lints.rust]`), which is how CrispSorter keeps running it.

Every other file is byte-identical to the pinned export. To advance the pin,
re-export both directories at the new commit, re-apply the three patches,
then run `cargo test --locked` here, the bridge tests in `../../rust_cloud`,
`python3 tool/check_rust_licenses.py --bridge cloud` and the live suites.

MPL-2.0 is file-level copyleft: these files stay under MPL-2.0 inside
CrispCloud, their notices must be retained, and modified MPL files must be
made available in source form. See `docs/STORAGE_ENGINE_ARCHITECTURE.md`.
