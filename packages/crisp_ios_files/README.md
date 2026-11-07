# crisp_ios_files

CrispCloud's native iOS folder authorization and coordinated file operations.
It is an in-process Flutter plugin and has no companion-app integration.

## Access model

`UIDocumentPickerViewController` opens folders in place. A successful selection
starts its security scope, creates bookmark data and persists the complete
bookmark snapshot before reporting success. Cancellation does not change the
previous selection. Bookmark records retain multiple selected roots so an
already-open terminal or operation does not lose its root when the user browses
another folder.

Restoring a bookmark checks the resolved directory and refreshes stale data while
access is active. A moved folder is restored at its new path. Acquiring an old
path fails with `directory_moved`, rather than silently executing an existing
callback against a different working directory. Revoked grants fail with an
access error and require a new picker selection. A raw saved path is never
accepted as proof of external access. An iOS app-container path requires no
external scope.

Each `acquireAccess(path)` returns an independent `IosAccessLease`. `release()` is
idempotent, concurrent release calls share one future, and a failed transport
release may be retried. Closing one lease cannot end another lease on the same
folder. Engine teardown drains remaining leases. `withAccess` holds a lease
until its asynchronous callback finishes, including error paths; release errors
do not turn a completed write into an apparent failure.

Native shell commands use `CrispNativeDirectoryLease`, which resolves a fresh
bookmark snapshot through a separate scope manager. The shell owns this lease
until its command tree finishes cleanup. Detaching the Flutter files plugin can
drain that plugin's grants without revoking the native command's access. Stale
bookmark refresh stays inside the native lease's snapshot, preserving any newer
durable selection made by the file picker.

Path checks compare components, resolve symbolic links after starting access,
and recheck coordinated URLs inside accessors. Prefix lookalikes such as
`/folder-copy` do not inherit `/folder` authorization. Writes reject symbolic
link destinations and directories, stage output beside its destination, and
replace only after staging succeeds. Non-overwrite saves use an exclusive move.
Reads, listings, recursive walks, saves, creation, deletion and length queries
use bounded `NSFileCoordinator` accessors. Recursive walks never follow symbolic
links. The lease API itself holds no provider-wide file lock; terminal and media
callbacks keep their independent scope for as long as their native-path work
requires it.

## Dart API

```dart
final files = IosFilesClient();
final selected = await files.pickDirectory(initialDirectory: previousPath);
final restored = await files.restoreLastDirectory();

final lease = await files.acquireAccess(path);
try {
  await runUntilClosed(lease.path);
} finally {
  await lease.release();
}

await files.withAccess(path, (accessiblePath) async {
  // The lease remains active until this future completes.
});
```

Finite operations are `hasAccess`, `listDirectory`, `walkFiles`, `readFile`,
`writeFile`, `createDirectory`, `deleteEntry`, and `fileLength`. Listings return
`IosFileEntry` metadata captured while provider access was held. The app converts
these into display snapshots so its existing post-listing `stat()` calls do not
reopen unscoped paths.

`MobileFileService` uses the plugin only on iOS. It implements
`ScopedLocalFileOperations`, giving local terminals and operation callbacks
independent leases. Android keeps its existing file service path. The legacy
`beginStreamAccess`/`endStreamAccess` API has no consumer token, so all overlapping
stream leases are conservatively kept until that group of consumers has ended.

## Validation

From this package:

```sh
flutter pub get
flutter test
flutter analyze
```

On macOS, from the repository root:

```sh
swift test --package-path packages/crisp_ios_files/ios/ScopeCore
```

The Foundation-only native target tests scoped bookmarks, stale refresh, moved
and revoked roots, persistence failures, overlapping and concurrent leases,
symlink escapes, safe replacement, provider coordination failures, method-channel
argument validation, picker cancellation and teardown. It needs no Flutter or
UIKit dependency. The normal iOS app build compiles the Flutter/UIKit adapter.

The application also tests `test/ios_local_file_service_test.dart`, including
scope lifetime through asynchronous callbacks, metadata snapshots, legacy stream
overlap and Android regression behavior. On-device checks should select a real
Files-provider folder, read/write in it, reopen after relaunch, cancel a second
selection, open overlapping terminals/readers, and verify recovery after the
folder is renamed or provider access is revoked. Simulator and mocked tests
cannot establish a third-party provider's actual grant or background behavior.
