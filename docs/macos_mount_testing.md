# macOS mount testing

The macOS mount options are experimental and read-only. The macFUSE/FUSE-T
bridge downloads whole files into memory and refuses files larger than 64 MiB;
this limit does not apply to the independent rclone NFS option. Run native tests
only with disposable mount points; they use a local fixture and do not need
cloud credentials.

Install FUSE-T or macFUSE separately. For macFUSE FSKit, enable its file system
extension under System Settings → General → Login Items & Extensions →
**By Category** → File System Extensions. The **By Application** switches may
not work on some macOS versions; see [macFUSE issue 1194](https://github.com/macfuse/macfuse/issues/1194).
The macFUSE kernel backend is an explicit option and requires the platform's
kernel-extension approval and, on Apple silicon, Reduced Security.
FUSE-T is selected explicitly and the user confirms non-commercial use at
each mount. Automatic selection uses macFUSE FSKit; it does not select FUSE-T.

The experimental rclone NFS option uses a separately installed `rclone` and
its own configured remote (for example, `work:documents`). It does not reuse
CrispCloud credentials. The mount is read-only, uses a loopback NFS server,
and can be accessed by local processes. A signed sandboxed app's ability to
launch the external binary and mount it remains to be verified. To run its
fixture test with rclone installed at a standard Homebrew path:

```sh
CRISPCLOUD_RCLONE_TEST=1 flutter test --no-pub test/fuse_live_macos_test.dart
```

Build the universal helper and run the opt-in test from the repository root:

```sh
mkdir -p /tmp/crispcloud-fuse-test
SRCROOT="$PWD/macos" TARGET_BUILD_DIR=/tmp/crispcloud-fuse-test \
  UNLOCALIZED_RESOURCES_FOLDER_PATH=Resources sh macos/build_fuse_bridge.sh
CRISPCLOUD_FUSE_TEST_BACKEND=macfuse-fskit \
  CRISPCLOUD_FUSE_TEST_HELPER=/tmp/crispcloud-fuse-test/Resources/crispcloud_fuse_bridge \
  flutter test --no-pub test/fuse_live_macos_test.dart
```

Repeat with `CRISPCLOUD_FUSE_TEST_BACKEND=fuse-t` for FUSE-T NFS, or
`fuse-t-smb` for its SMB backend, after installing FUSE-T. The test checks
listing, Unicode names, reading, rejection of writes, and unmount.
The fixture includes a 1,200-file directory to exercise paged directory reads.
It is skipped in ordinary test runs. A passing helper test does not establish
that the signed, sandboxed application can start the helper or load the FUSE
runtime. Validate those separately in the signed app, including Finder access,
network disconnection, remounting, and the actual cloud providers to be shipped.

## FUSE-T NFS diagnostics

FUSE-T writes runtime diagnostics under `~/Library/Logs/fuse-t/`. If it starts
but the mount command fails, inspect that log and, if present, `/etc/nfs.conf`.
Existing system-wide NFS defaults can affect mounts. On one macOS 26.2 test
machine, FUSE-T 1.2.9 returned mount exit status 22. A controlled probe showed
that the machine's `locallocks` default fails initial NFSv4 validation, whereas
adding `nolocallocks` reaches the server connection attempt. The separate
warning about an unknown `nfssvers` option is not the cause established by that
probe. FUSE-T 1.2.9 rejects `nolocallocks` as a FUSE option. With the user's
authorization, removing `locallocks` temporarily allowed the FUSE-T NFS
fixture test to pass; the original configuration was restored afterward. Do
not silently modify system-wide NFS settings: they can affect other mounts.

FUSE-T SMB is an explicit alternative and passed the fixture tests without an
NFS configuration change. The bridge resolves Unicode-equivalent path names
back to the spelling stored by the provider. If a directory contains two
canonically equivalent names, it returns `EEXIST` rather than risking access to
the wrong object. Finder, cloud-provider and signed-sandbox testing remain open.

The native directory filler can also be tested without a FUSE runtime:

```sh
clang -std=c11 -O2 -Wall -Wextra -Werror -I macos/vendor \
  test/fuse_bridge_readdir_test.c -o /tmp/crispcloud-fuse-readdir-test
/tmp/crispcloud-fuse-readdir-test
```
