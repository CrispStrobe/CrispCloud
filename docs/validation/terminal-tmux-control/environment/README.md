# Local toolchain restoration and prerequisites

These records describe environment preparation for the tmux continuation. They are separate from feature acceptance. Flutter 3.47.8 source revision `737ba8f885dc774b53b442759999a312c9461e4e` and Dart 3.13.7 match the existing application pins. The 322 official hosted archives used to prepare the SDK/application caches were verified against their lockfile SHA-256 entries. Native Debian and Rust component download identities are retained.

The production dependency graph resolved with `flutter pub get --enforce-lockfile --offline`; production manifests and native hooks were unchanged. An initial online SDK bootstrap could not create `/tmp`; the retained scratch runners supply a writable temporary directory. The online application resolver warmed its exact Git mirrors before offline lockfile enforcement completed. The standard Flutter tool snapshot was compiled using the SDK launcher arguments; a scratch direct launcher avoids collisions between isolated process namespaces.

Normal native hooks compiled the catalogue, SMB and PTY assets. The environment bootstrap ran `test/terminal_process_test.dart`: **6 passed, 1 explicit Windows platform skip, 0 failed**. Actual POSIX TTY allocation, resize, fragmented UTF-8, and Ctrl+C passed. C and Rust compile/link/execute probes also passed in both ordinary and filtered environments.

Official Debian tmux **3.5a** runs its version command. An unmodified native server attempt using a scratch socket path exited 1 with `Operation not permitted`; the Unix socket probe independently records EPERM. No workaround was used. Native live tmux acceptance is blocked on this environment prerequisite. TCP loopback is available.

The compiler resource preflight verified the three pinned SDK binary/snapshot hashes, compiled and executed a tiny O4/minified JavaScript probe with a 3,072 MB compiler heap cap, and left all SDK files unchanged. This preflight is not the full application build or browser runtime acceptance.

No GitHub Actions were queried or awaited. `copy-manifest.json` records exact original and retained paths and hashes; logs and receipts preserve their original paths verbatim.
