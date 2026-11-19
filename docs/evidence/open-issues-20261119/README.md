# Remaining storage issues — 2026-11-19

Base: `40b955c262f980f9745812e6021d9ca30048b764` (Nextcloud #96 fix).
No GitHub Actions runs/status queues were queried or awaited.

## Implementations

- #2: FUSE IPC uses the process-approved temporary directory instead of `/tmp`.
  Private random directories retain mode 0700 and cleanup. Short directory/socket
  names reserve space for macOS container paths and the 104-byte Unix limit.
- #272: cross-storage Google Drive Copy uses exact provider IDs, including fresh
  metadata/version checks and paginated child listings. Portable destination
  names replace forbidden separators/characters; Google-native documents gain
  their exported extension. The preview shows source display names and mapped
  destinations. Mapping collisions fail planning before writes. Same-storage
  operations, relative-path profiles and Move retain their existing behavior. This ID-addressed view
  does not support persistent recovery across app restart; filename mapping
  is unavailable with relative-path profiles. This view never deletes sources. Live Google/Internxt account qualification
  is separate from local HTTP/provider fixtures.
- #273: optional verified, immutable per-directory metadata records and explicit
  restoration UI. See [format and restoration](../../metadata-sidecars.md).
- #99: complete-bundle user-local CLI installer, no-clobber checks, versioned
  updates retaining previous releases, and Settings discovery/download guidance.
  `crispcloud` is canonical; `crisp` remains compatible. Configuration is shared
  by the two CLI names and separate from app credentials.

## Validation

The final focused suite passed 380 tests, with 29 explicit platform/native
capability skips. Installer/packaging Python tests passed 6/6. The signed sandbox
IPC probe passed with an 89-byte container socket path and verified cleanup.
The FUSE-T SMB fixture passed both 1,200-file mount/read/unmount cycles.
Compiled CLI installation, catalogue scanning and offline querying also passed.
Build and final receipts are recorded in acceptance.json. Native
metadata fields unsupported by the Flutter runner remain explicit skips;
sidecar timestamp/content/tamper/symlink tests execute against real local files.
A standalone FUSE mount does not qualify actual Google/Internxt cloud mounts.
The sandbox IPC probe has its own app identity and bypasses production startup,
preferences and credentials. It does not enable FUSE in App Store builds.
