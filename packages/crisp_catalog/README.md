# Crisp metadata catalogue

A Flutter-independent Dart API over a Rust/SQLite desktop backend. Native scans
stream metadata to a staged database; cached ranking/search queries return
bounded JSON summaries through FFI on a worker isolate. No file contents,
credentials, network connections or GUI grants are read. Existing databases
are replaced only after scan/import, aggregation, commit and flush succeed.
Use `CrispCatalog.execute` with `scan`, `query`, `info`, `import` or `export`.
The CLI and GUI catalogue library use the same engine and database schema.

The independent MIT-licensed `crates/crispcat-format` crate from CrispSorter is
vendored under `native/vendor/crispcat-format`. The parent repository's AGPL
application, Tauri, LanceDB, duplicate hashing and Python runtimes are not
imported. See its `UPSTREAM.json`, modification notices and MIT licence.
The canonical codec retains empty directory entries and timestamps and exposes legacy
unknown-size provenance. Its source and manifest now match the standalone upstream crate exactly. Classic compatibility export deliberately rejects
non-Latin-1 names even though the upstream codec supports a UTF-8 extension.

Current limits: metadata is an observation, not an atomic filesystem snapshot;
symlinks below the chosen canonical root are skipped; hard links count per
path; byte totals are logical and must fit 2^53−1. Scan budgets are opt-in.
SQLite scan rows and queries avoid loading the full tree into Dart. CAF
import/export still materialize Rust's format model; they are not constant-memory
streaming. Refresh rebuilds the catalogue. Desktop macOS/Linux/Windows target
mappings exist. Native mobile hooks are also supplied; this integration was qualified on macOS.
The browser facade reports unsupported, and incremental watchers remain pending.
Do not treat an imported catalogue as an access grant or source identity.

```sh
cargo test --locked --manifest-path native/Cargo.toml
cargo test --locked --manifest-path native/vendor/crispcat-format/Cargo.toml
cargo test --locked --release --manifest-path native/Cargo.toml -- --ignored --nocapture
```

The last command checks 1,000,005 synthetic SQLite rows. It measures catalogue
processing, not disk-enumeration performance. Actual Dart/native-boundary and
CLI tests live in `../../cli/test/catalog_command_test.dart`.

The app now uses this engine for the catalogue library; see [GUI and CLI usage](../../docs/catalogues.md). Native calls run off the UI isolate, support job progress/cancellation, and validate catalogue identity before dependent actions. Schema 2 adds a persistent identity; schema 1 is still readable. Platform hooks include desktop/iOS/Android; the browser facade reports unsupported. Bundled third-party notices cover the locked supported-target graph.
