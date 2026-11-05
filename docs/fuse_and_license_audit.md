# FUSE components and license audit

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
normalization dependency used by the mount bridge is MIT-licensed. The SMB dependency includes an
LGPL-2.1-or-later libsmb2 notice in `packages/crisp_storage/NOTICE-LIBSMB2.txt`
and registers the notice in the app. Fonts and their notices are checked in.

A text search of checked-in source and license files found no non-commercial
runtime clause beyond the AGPL passage above. A separate keyword scan of the
license files in the 230 packages then in the local Dart package configuration found
no non-commercial-use restriction; six Flutter SDK packages have no separate
package-level license file and fall under the SDK's licensing. macOS CocoaPods
license files were also searched. These are keyword and file-presence checks,
not a complete review of transitive native artifacts, platform builds, asset
provenance, license compatibility or every distribution obligation. Repeat a
full dependency and binary license review for each shipped build.

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
