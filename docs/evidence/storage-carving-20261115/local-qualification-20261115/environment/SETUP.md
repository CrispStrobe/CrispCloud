# Local qualification toolchain

Use `/workspace/scratch/1f80e59755df/toolchains/run.py` before `flutter`, `dart`, or the Python gate recorder. The launcher supplies task-specific caches/temp directories and real native tools without changing HOME or repository source.

- Flutter 3.47.8, framework 737ba8f885dc774b53b442759999a312c9461e4e, engine cf636b1dfb818dd6a3ff16e390e93b1a036969c8.
- Dart 3.13.7; Rust/Cargo 1.100.0; verified Debian Clang 19.1.7.
- Root Flutter resolution passed `pub get --enforce-lockfile` with both tracked manifests unchanged. Engine/editor had no committed locks; normal resolution created local locks, then both passed `--enforce-lockfile --offline`.
- Native bootstrap passed 63 actual PNG service tests with default hooks and actual Kindling, catalogue, SMB2 and bundled SQLite assets. This was a development build while integration source was being edited, not final source-bound qualification.

`setup-receipt.json` records versions, hashes, resolution files, default native assets, and completed setup commands. `versions/`, `resolution/`, and `logs/native-bootstrap.*` retain the raw receipts. No further optional build checks are required before root's final frozen-source qualification.
