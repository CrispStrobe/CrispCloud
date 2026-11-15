# Dependency and distribution boundaries

CrispCloud's own AGPL-3.0 licence is unchanged. This cleanup concerns third-party
code and the contents of distributed application/CLI bundles. A GPL keyword in
a retained notice is not, on its own, a dependency licence determination:
dual-licensing choices and explicit exceptions must be read completely.

## SMB

The default native transport is now the existing `crisp_smb` Rust engine backed
by `smb2` 0.43.0. The Dart libsmb2 adapter, native downloader/build recipes and
`dart_smb2` dependency are removed. Existing `libsmb2` and `auto` profile values
migrate to Rust. A missing Rust library produces an actionable failure; there
is no LGPL fallback or automatic second authentication attempt. Signing and the default
SMB3 encryption requirement are preserved. Old resume validators are not reused
under a different transport. A cancelled native download session is retired
after its operation finishes; the facade reconnects lazily on a later explicit
retry, without replaying the failed operation. Device/NAS interoperability still needs testing.

App and CLI pubspecs enable the source-built Rust native asset. The hook maps
iOS, macOS, Linux, Windows and Android targets; Android uses the NDK and 16 KiB
ELF page alignment. A supported target without its build toolchain fails the
build instead of silently dropping native SMB support.

The reviewed Cargo inventory selects permissive grants for all 143 resolved
SMB packages, including platform/build dependencies. A crate offering
`MIT OR Apache-2.0 OR LGPL-2.1-or-later` is distributed under its selected MIT
grant; the optional LGPL grant is not a required runtime licence. The existing
`crisp_storage/NOTICES` contains complete evidence for both storage graphs and
is collected by Flutter. CLI bundles now include it as `STORAGE-NOTICES.txt`.

## Embedded iOS shell

The Bash-derived GPL signal-table generator is replaced before compilation by
an independently authored MIT generator using Darwin SDK/libSystem signal
metadata. Previously generated `signames.c` is removed, forcing regeneration.
The generator is included in build fingerprints. Its output is compiled in
tests; a full native shell test remains the platform acceptance gate.

The GPL Automake `missing`, `compile` and `depcomp` scripts are replaced by
minimal MIT adapters for the pinned clang build. Dependency tracking is
explicitly disabled. Maintainer-tool regeneration fails rather than silently
running an unreviewed tool. The X Consortium `install-sh` script is retained.
These replacements do not relicense any upstream source.

The AWK generated parser retains its Bison larger-work exception. The notice
collector now preserves the adjacent exception block, with a regression test.
It is not labelled plain GPL. Original upstream COPYING text and GPL texts
remain as provenance/exception material; downloaded immutable upstream archives
also contain unused components. This is not a claim that every byte of those
upstream repositories has a permissive licence. The curated framework targets
and command manifest remain the runtime boundary; unused `less` is not enabled.

## Optional macOS mounts

Default builds omit the native macFUSE/FUSE-T bridge and its UI choices.
Use `flutter build macos --dart-define=CRISP_ENABLE_FUSE=true` to opt in.
The Xcode phase reads that same define. An incremental default build removes
an old generated helper, preventing accidental carryover from an opted-in build.
The optional source keeps its LGPL libfuse headers and their complete notices;
this exception is deliberate and does not apply to the removed SMB backend.

Neither runtime is bundled. Opting in does not purchase or grant a runtime
licence. FUSE-T's published terms require a commercial licence for commercial
use/bundling; macFUSE states that commercial bundling or integration requires a
paid licence. Existing noncommercial acknowledgement for FUSE-T is retained.
The rclone NFS option remains independent. App Store restrictions still apply.

Sources: [FUSE-T terms](https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt),
[macFUSE status](https://github.com/macfuse/macfuse/wiki/Open-Source-Status).

## Packaging and media

The CLI packager now copies the actual `LICENSE.txt` unconditionally to
`LICENSE-CRISPCLOUD.txt`; missing licensing fails packaging. The optional RPM
spec declares `AGPL-3.0-only` rather than `Proprietary`.

Platform media encoding remains enabled. FFmpeg/ffprobe are independent test
tools, not the shipped export implementation. Android MP4 export selects H.264.
Copyright licences and codec patent rights are separate: using a platform
encoder does not establish that every distribution/use is covered or royalty
free. No separate fee/reporting obligation for this app has been established.
The remaining review is platform coverage, distribution territories and use;
no blanket patent-clearance claim is made.

Sources: [Via LA AVC programme](https://www.via-la.com/licensing-programs/avc-h-264/),
[Apple platform encoding API](https://developer.apple.com/documentation/avfoundation/recording-movies-in-alternative-formats).

## Product limits

VeraCrypt remains a limited header/format helper, not finished native container
browsing/mounting. AES-XTS/PBKDF2 subsets do not establish support for Argon2id,
custom PIMs, keyfiles or native TrueCrypt headers. Placeholder container listing
must not be advertised as working support. The existing exFAT exclusion stays.

`tool/check_distribution_components.py` guards the removed dependency and can
inspect an extracted app/CLI bundle for libsmb2 and accidental default FUSE
inclusion. This targeted guard supplements source inventories, notices and
platform binary inspection; it is not a universal licence or patent audit.

## Observed checks for this cleanup

- Shared storage policy/profile/notice/target-selection unit tests: 48 passed.
- Host SMB setup plus copy/move, queue and notification regression: 67 passed.
- Distribution/packaging controls: five passed, including actually producing a
  CLI bundle with a compiler fixture and inspecting its copied licence files.
- iOS shell preparation/provenance controls: 28 passed, including compiling and
  executing the replacement signal-table generator and retaining Bison's
  adjacent exception.
- Optional FUSE helper: universal signature verified when enabled; default
  rebuild removes the generated helper. The optional mount suite passed 68
  tests; its notice title assertion was corrected to the original Library GPL
  v2 wording and the focused bundled-notice test passed. No FUSE filesystem
  was mounted.
- Native SMB bridge release compilation passed. Both authenticated shared
  transport tests pass, including cancellation followed by explicit resume,
  source replacement, bounded reads and encryption refusal. The test server
  delays reads so cancellation tests cannot accidentally finish before polling.
- CLI acceptance: 21 tests passed, including real authenticated file operations
  through every legacy setting. JSON distinguishes the effective Rust engine
  from the original saved setting without rewriting configuration while listing.
- Live host acceptance: five tests passed, covering authenticated file-manager
  operations, the default FUSE compile guard and actual bundled notice loading.
- Rebuilt iOS shell: device/simulator compilation and all 379 native assertions
  passed against real ios_system + Dash, including detach/access-lease cases.
- Reviewed SMB Cargo grant/evidence check covers 143 packages. Existing packaged
  storage notices verify 318 dependency versions across both native graphs.
- Crypto release controls: 42 passed. Source checks retain Filen and Internxt
  and refresh fingerprints without changing distribution declarations.
- Scoped storage/CLI analyzers passed. Full application-library analysis has
  zero errors, the same 26 existing warnings as the baseline, and 209 infos.

Final macOS app startup/signing and hosted CI remain separate acceptance gates.
These source and native-shell results do not assert that those gates completed.
