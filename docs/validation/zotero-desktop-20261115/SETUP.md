# Zotero desktop follow-up validation

This focused validation uses official Dart 3.13.7 and genuine Pub dependencies.
It runs 34 canonical core-client tests and 16 host transport tests. All 50 passed,
and `dart analyze --fatal-infos .` reported no issues.

## Source scope

The validation package is named `quds_office_engine`, preserving production
package imports. Its `lib/src/zotero/zotero_client.dart`,
`lib/src/zotero/zotero_models.dart`, and `test/zotero_client_test.dart` are exact
copies of the canonical Quds files. `lib/host_transport.dart` is an exact copy of
CrispCloud's `lib/services/office_zotero_transport.dart`.

The host test harness retains the production test's complete transport group and
its `_Client`/request helpers verbatim. Only harness imports and the surrounding
entrypoint are supplied separately, using `package:test` instead of
`flutter_test`. `host-transport-extraction.json` records the canonical source,
harness, and section hashes. `extract-host-transport.py` reproduces that harness
from the canonical CrispCloud checkout; its `--check` mode verifies the staged
bytes without changing them. No production source was replaced or stubbed.

The validation does not compile Flutter widgets, the complete provider graph,
native applications, or host credential/controller tests outside the extracted
transport group. It uses synthetic transports and fixtures; it does not claim
live desktop/private-account acceptance.

## Runtime

The official Linux x64 Dart 3.13.7 archive is:

https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.7/sdk/dartsdk-linux-x64-release.zip

Disk space required selective extraction. The installed runtime contains the
official CLI, VM, AOT runtime, dartdev, frontend compiler, analyzer, SDK source
libraries and VM platform kernels. Unrelated web compilers, developer UI assets,
debug symbols, sanitizer runtimes and other unused components were omitted.
The 55 MB kernel-service snapshot was also omitted. The two byte-identical VM
platform kernels share one inode without changing their contents.

Every extracted file's local ZIP header, byte count, and CRC32 was checked.
`dart-sdk-subset-provenance.json` records the complete installed subset and each
file's SHA-256. Only selected ZIP ranges were downloaded, so the complete ZIP's
SHA-256 was not checked. No SDK code was edited.

## Commands

`pubspec.yaml`, `pubspec.lock`, and `pub-get.log` preserve the actual resolution:
`test` 1.33.0, `http` 1.6.0, and their genuine dependencies. TMPDIR, PUB_CACHE and
XDG_CONFIG_HOME point to writable scratch directories.

The tests were compiled directly by the SDK's
`frontend_server_aot.dart.snapshot`, using
`lib/_internal/vm_platform_strong.dill`, and run by the SDK's `dartvm` with
assertions enabled. This runs the unchanged tests through real `package:test`
without requiring the omitted kernel-service snapshot. It is not a substitute
implementation of Dart or of the tests.

Use `run-focused.sh` after staging the exact files listed above. Set
`ZOTERO_VALIDATION_SDK` to an official Dart 3.13.7 SDK directory if its location
differs from the adjacent runtime directory. The script uses the same compiler,
VM and analyzer path as the recorded checks. It suppresses the compiler's
dependency listing for shorter reproduction logs; compilation semantics are
unchanged.

`validation-receipt.json` contains the exact originally executed commands and
exit codes. `core-tests.log` records 34 passing tests; `host-tests.log` records
16 passing tests. `analysis.log` records the clean focused static analysis.
Generated kernels were hashed and removed after successful execution to recover
space for the analyzer; their hashes remain in `compiled-kernel-receipt.json`.

GitHub Actions was neither queried nor awaited for these checks.
