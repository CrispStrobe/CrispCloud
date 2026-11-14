# Production JavaScript release build — 2026-11-14

The complete CrispCloud web application built successfully with Flutter **3.47.8 / Dart 3.13.7** in **137.9 seconds** of compilation, using the original production manifest. The generated JavaScript contains app version **1.2.9+22** and the explicit source stamp **`fb57e8abb22e1a2fe588c1a22d9ac0326e7358ee`**. The source stamp comes from the primary published checkpoint rather than the older Git HEAD of the isolated validation checkout.

The command was:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=APP_VERSION=1.2.9+22 \
  --dart-define=GIT_HASH=fb57e8abb22e1a2fe588c1a22d9ac0326e7358ee
```

No native-test hook override was present. Both `pubspec.yaml` and `pubspec.lock` remained byte-for-byte unchanged:

| File | SHA-256 |
| --- | --- |
| `pubspec.yaml` | `f10ba24448b047cf379dac0efeb11f8f60d9ae089022a831b12a6b32b8fa564f` |
| `pubspec.lock` | `2a0b95288cf41be9087af0c01ea57afcc4a2f138876d15709bff2f866060ccb4` |

The bundled `assets/packages/apple_lzfse/LICENSE` is **1,514 bytes** and exactly matches the reviewed source license, SHA-256 `2a20082c2219edbbdb2e862a0566ba4f762a564ade7c04b09250ae4464bc4b32`. Its presence was checked in the actual release output. The generated `main.dart.js` is **27,570,755 bytes**, SHA-256 `84f5571fc1698b4347db220d96df68ad8eecf068b6703924cc2013536ab1db20`.

`web-release-build-receipt.json` records the exact command, production manifest hashes, source synchronization hashes, compile stamp checks, and output checksums. `web-release-build.log` preserves compiler output; `web-release-build-helper.py` is the historical wrapper used from the scratch runtime directory. This qualifies the standard JavaScript release build. It does not claim a WebAssembly build, a browser end-to-end session, or a native/device release build.
