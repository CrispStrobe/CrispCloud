# CrispCloud development handover

This file is a starting point, not a live status dashboard. Inspect the current
branch, open issues and tests before changing code. `PLAN.md` and `HISTORY.md`
contain historical plans and progress notes; their completion markers are not
proof that a feature works in the current build.

## Repository and workflow

CrispCloud is a Flutter cloud file manager. Provider adapters implement
`CloudStorageClient` in `lib/services/cloud_storage_interface.dart`; Riverpod
providers coordinate application state. Read `README.md` and the relevant
files in `docs/` before modifying a feature.

Multiple agents may work in parallel. Use a separate Git worktree when asked,
inspect its status before changing files, and leave other worktrees untouched.
Use the Flutter version in `.fvmrc` and run focused tests for the change. Do
not commit credentials or assume live provider credentials are available.

## Mounts

macOS mounting is experimental and read-only. The FUSE bridge uses a
separately installed macFUSE or FUSE-T runtime; FUSE-T requires explicit
selection and non-commercial-use acknowledgement. The separate rclone NFS
option uses the user's rclone configuration, not CrispCloud credentials.
Linux and Windows mounting is not implemented. See
[the user guide](docs/USER_GUIDE.md#fuse-mounted-drives),
[macOS test instructions](docs/macos_mount_testing.md), and
[the FUSE and license audit](docs/fuse_and_license_audit.md).

macFUSE FSKit and rclone NFS have passed local-fixture tests. FUSE-T NFS,
Finder, actual cloud providers and the signed sandboxed application still need
end-to-end verification. File Provider is a future project; see
[the implementation plan](docs/macos_file_provider_plan.md).

## Verification and release

Run `flutter pub get` when dependencies change and `flutter test` for the
relevant suites. Native mount tests are opt-in because they create temporary
mounts. macOS signing requires appropriate identities and provisioning profiles;
a successful build or signature check is not proof that runtime integration
works. Do not publish, deploy, or alter unrelated machine security settings
unless the task authorizes it.
