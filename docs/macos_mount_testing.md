# macOS mount testing

The macOS mount is experimental and read-only. It currently downloads whole
files into memory and refuses files larger than 64 MiB. Run the native tests
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

Repeat with `CRISPCLOUD_FUSE_TEST_BACKEND=fuse-t` after installing FUSE-T. The
test checks listing, Unicode names, reading, rejection of writes, and unmount.
It is skipped in ordinary test runs. A passing helper test does not establish
that the signed, sandboxed application can start the helper or load the FUSE
runtime. Validate those separately in the signed app, including Finder access,
network disconnection, remounting, and the actual cloud providers to be shipped.
