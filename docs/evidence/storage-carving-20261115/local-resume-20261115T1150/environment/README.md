# Reproduced local qualification environment

The pinned Flutter 3.47.8 / Dart 3.13.7 toolchain and genuine Rust 1.100.0, Clang 19.1.7, CMake 3.31.6 and Ninja 1.12.1 are installed at `/workspace/scratch/1e19fe1d39ae/toolchains`. Source `env.sh` from that directory to use them.

All 19 archives were checked against their recorded SHA-256 identities. The selected Flutter release also matches newly fetched official release metadata; the Rust manifest matches its recorded hash; all 15 Debian packages match their exact version, path, size and digest in the newly fetched trixie package index. Raw SDK/Rust metadata, download identities and index-verification details are retained here. Large toolchain archive payloads are reproducible from the recorded URLs and are excluded from the repository.

Flutter's official bundled preload cache initialized the SDK tooling offline. Linux precache completed, the Flutter test executable resolves its shared libraries, and real C/Rust compile, link and execution probes passed both with the full environment and with PATH alone. Launchers restore workspace temporary/cache/loader settings for native hooks; no native hook was disabled and no compiler or native library was substituted.

These are setup receipts, not application qualification. App and CLI dependency resolution use committed lock enforcement. Engine/editor/parser development graphs resolve separately. Resolution receipts will be saved separately after all setup completes. Do not change dependency graphs while acceptance gates execute.

The environment and launchers contain absolute workspace paths. For reproduction, relocate those paths consistently. No GitHub Actions run was awaited or restarted.
