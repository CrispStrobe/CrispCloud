# SMB storage review — 11 November 2026

## Current implementation
`packages/crisp_storage` pins `dart_smb2 0.2.1` (BSD wrapper) and therefore
uses LGPL-2.1 libsmb2. `SmbSession` uses one worker isolate per pool, signing,
SMB3 encryption by default, 256 KiB reads and size/mtime/change-time resume
validators. `SmbClientAdapter` adds file-manager writes and secure credentials.
CrisperPlayer consumes an older immutable revision of this package.

## Priorities
1. Remove the extra IOSink flush round trip after every download chunk while
   retaining awaited, bounded disk writes, resume safety and prompt cancellation.
2. Allow a session to retry a failed initial connection instead of caching a
   failed future forever; concurrent initial callers must still share one open.
3. Qualify session reuse/concurrency at the adapter boundary before increasing
   worker counts. Large-folder paging and server-side copies require explicit
   backend support and should not silently weaken existing limits.

## Permissive replacement decision
SMB3 encryption and signing are existing product requirements. smb_connect
(Apache-2.0, advertised through SMB2.1) and Swift SMBClient (MIT, advertised
SMB2.0) are not equivalent replacements. SMBJ (Apache-2.0) only solves the
Java/Android side. A shared Go or Rust SMB2/3 engine is a candidate, not an
approved dependency: validate exact releases, transitive licenses, all target
ABIs, authentication, required signing/encryption, cancellation, validated resume
and malicious-path cases before switching. Preserve current native notices.

No LGPL-removal or throughput claim is made by this review. Real SMB3
interoperability and performance measurements require suitable servers/devices.

## Implemented and validated on this branch
- Awaited RandomAccessFile writes replace per-chunk IOSink add/flush pairs.
  Each progress callback runs after the chunk write; memory remains bounded by
  the read chunk, and interruption closes the local handle before returning.
- Failed initial pool opens are cleared while concurrent callers share the
  same in-flight future. Closed sessions still cannot reopen.
- `dart test` in `packages/crisp_storage`: 15 tests passed with the opt-in
  impacket fixture enabled, including initial failure/retry, concurrent browse,
  partial-write resume, changed-source restart and size-limit rejection.
- `dart analyze`: no errors/warnings; eight existing style informational
  diagnostics. No full Flutter app or physical SMB3 server test was run here.
- Updated the package README, which incorrectly said direct SMB was absent.

CrisperPlayer's existing immutable pin is deliberately unchanged in its sibling
branch. Adopting these shared changes there also requires regenerating its
dependency and native-license evidence; this commit is not silently propagated.
