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
