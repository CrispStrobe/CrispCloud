# FUSE components and license audit

App Store/default builds omit the native helper. Compile with
`python3 tool/macos_distribution.py build --profile github --fuse` to enable
the optional integration in the unsandboxed macOS build. The wrapper sets
`CRISP_ENABLE_FUSE=true` for both the UI and Xcode helper phase; App Store
profiles reject that flag. See [distribution profiles](distribution-profiles.md). The existing rclone NFS
option remains available independently. The runtimes are never bundled.

As of this audit the macOS bridge is CrispCloud source (`macos/fuse_bridge.c`).
`macos/vendor/fuse` contains libfuse 2 header files copied from macFUSE, with
their LGPLv2 notices and `COPYING.LIB`. The bridge loads either the separately
installed FUSE-T or macFUSE runtime dynamically. Neither runtime is bundled
by this build script. The rclone option invokes a separately installed binary;
it does not bundle rclone. FUSE-T is only selected explicitly after the user
confirms non-commercial use.

The repository's `LICENSE.txt` is AGPL-3.0. Its mention of non-commercial
activity concerns one optional source-distribution mechanism; it is not a
general non-commercial-use restriction. The checked-in Filen client is MPL-2.0;
the checked-in Quds Office packages are MIT. The `unorm_dart` Unicode
normalization dependency used by the mount bridge is MIT-licensed. The default SMB transport now uses the permissively licensed Rust engine;
libsmb2 and its downloader are removed. Fonts and their notices are checked in.

The optional build retains the exact header notices and publishes their complete
licence in About. Default builds omit the helper and its choices. The rclone NFS
path is independent; no paid runtime licence is purchased by compiling this app.

Runtime license terms are independent of CrispCloud's source license. See the
[FUSE-T license](https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt)
and [macFUSE licensing information](https://github.com/macfuse/macfuse/wiki/Open-Source-Status).

## Read limits

The experimental built-in mount remains read-only. Azure Blob now supports
files larger than 64 MiB through validated HTTP byte-range reads. Its read
cache holds at most 256 KiB per open file handle; the server must honor the
requested range, and ignored, oversized or truncated responses fail with EIO.
IPC read requests are capped at 32 MiB, matching the native helper's existing
reply limit, and assembled from bounded windows. A response temporarily uses
memory proportional to its requested size (up to that cap).
Random reads fetch only the requested windows; no whole-file download or local
spool is needed. Each open handle has its own cache, so total cache memory
still scales with the number of open files.

Other providers, including encrypted wrappers, retain the 64 MiB whole-file
fallback limit. The explicit `CloudStorageRangeReader` capability is required
to bypass it: `supportsStreaming` is insufficient because several adapters
inherit a buffered stream implementation. The fallback checks known sizes
before opening and downloaded sizes afterward; an unknown or inaccurate size
can still cause its existing whole-file download to exceed that memory limit.
This is not an all-provider large-file guarantee. Provider changes during an
open file are not a snapshot, and separate range requests may observe changes.

## IPC input limits

The Dart bridge rejects request payload lengths above 32 MiB plus the 16-byte
write header as soon as it receives the frame header. It returns EINVAL and
closes that connection, since the rejected frame body cannot safely be treated
as a subsequent request. Path strings with truncated lengths, invalid UTF-8,
or embedded NUL bytes also return EINVAL. These limits do not cap the number
of concurrent requests, directory cache entries, or open handles; total bridge
memory can still grow with those resources. The private IPC socket directory
continues to restrict access to the current user.
