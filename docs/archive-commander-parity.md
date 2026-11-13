# Commander archive acceptance matrix

Research date: **13 November 2026**. CrispCloud baseline:
`27362f1980d0062f168b874f013a8962909b3e30`.
Continuation branch: `feature/archive-commander-parity-20261113`.

This document turns the requested Total Commander / Double Commander archive
parity into bounded, independently testable capabilities. It records the baseline
before this continuation; a planned row is not a delivered feature. The exact
CrispCloud format profiles remain in [format coverage](archive-format-coverage.md),
[creation](archive-creation.md), [endpoints](archive-endpoints.md) and the
[G18–G24 gap register](file-manager-gaps/03-archives-and-containers.md).

## Implemented continuation

The baseline and acceptance rows below remain a historical comparison. The
current branch adds the following bounded capabilities; their controls, limits,
runtime evidence and remaining work are recorded in the
[Commander workflow guide](archive-commander-workflows.md).

| Rows | Delivered continuation | Remaining boundary |
| --- | --- | --- |
| A06 | Shared Operations queue for native creation and workspace saves; cooperative workers, pause/resume/stop, priority/scheduling, password-free recipes and reviewed restart recovery | Canonical queue behavior is in [archive operation queue](archive-operation-queue.md); no arbitrary compressed-byte resume; existing protected/nested and platform limits remain |
| A07 | Pane/context/palette batch integrity with immutable snapshots, per-file results and copyable member reports | Reader-specific decode and integrity limits remain explicit |
| A08 | Captured extraction plan with masks, separate/shared/smart folders, flattening and complete collision preview | Native local destinations; partial results retain completed files; no overwrite or source deletion |
| A09 | Complete separate-per-selection output plan; live dispatch waits for every job's durable save | History writes are per job; interrupted admission may retain review-only partial records. Sources stay intact and outputs have independent results |
| A10 | Read-only complete numbered 7z sets through panes, F3 and extraction | No split creation/update, RAR volumes or ZIP split sets |
| A11 | Bounded unsigned PE ZIP/7z/RAR payload browsing; executable F3 default retained | No signed/installer-specific overlay rewriting or SFX generation |
| A13 | Checked installed-7z profiles: dictionary 1/4/16 MiB, threads 1/2/4, solid off/16/32 MiB | No arbitrary CLI options; buffered external limits remain |
| A15 | Independently verified installed 7-Zip ZIP/7z and RAR RAR5 creation with owned processes/staging | Broader external actions and WCX hosting remain separate work |

This is substantial archive-workflow progress, not a claim of full feature or
plugin parity with either Commander application.

The integration preserves the canonical shared queue from `main` at
`07928e070135d422fbd136fccd1bf53d0d2d47b6`. The combined source at
[`6fe58ec5fa531c0437aafa9606ff9f0885327306`](https://github.com/CrispStrobe/CrispCloud/commit/6fe58ec5fa531c0437aafa9606ff9f0885327306) passed **2,789 normal regressions** with
**zero failures and 13 explicit >2 GiB opt-in skips**, strict analysis,
portable JavaScript codec readback, offline-help validation and a versioned
release web build. The [retained local receipt](evidence/archive-commander-acceptance-6fe58ec5.json) records its exact inputs,
tools, commands, skip names and build identity. Native macOS/Windows and the
earlier large-case hosted runs retain their separate qualification boundaries.

## Comparison scope

The official release pages currently identify **Total Commander 11.58.1** and
**Double Commander 1.2.11**. The DC source references below are pinned to
`v1.2.11`; the documentation sites can change independently of releases.
[TC release][tc-release] · [DC releases][dc-releases]

There are three distinct delivery models:

- **Built in / bundled:** functionality shipped with the program, including a
  bundled codec DLL or bundled WCX plugin. These are different implementation
  arrangements but comparable out-of-box workflows on a supported platform.
- **Optional plugin:** an additional WCX module, with its own version, native
  architecture, dependencies, supported operations and license.
- **External tool:** an installed command-line packer and an adapter describing
  how to invoke it. The tool determines the available codecs and write support.

TC has bundled internal 7z compression since **11.50**. Its older feature and
packing-FAQ pages must therefore be read together with current release history,
not used to describe all 7z writes as external. DC supplies several archive
engines as WCX plugins; its SevenZip plugin is documented for Windows and Linux,
and many formats handled by that engine are read-only.
[TC newsletter][tc-newsletter] · [DC bundled plugins][dc-plugins]

The target is an explicit set of format/operation/engine/platform combinations.
“Every WCX plugin” is not a finite acceptance scope: the TC catalog includes
image tools, catalog generators and application-specific storage adapters as
well as conventional archives. Compatibility with one plugin or an external
packer does not establish compatibility with the entire ecosystem.
[TC plugin catalog][tc-plugins]

## CrispCloud baseline already delivered

The baseline has shared pane/F3/search/extraction routing; 35 creation choices;
reviewed add, edit, rename, delete and folder operations; archive-to-archive
copies; ordered native top-level two-container moves; grouped moves within one
workspace; one-way folder-to-archive synchronization; and a cancellable F3
integrity/readability report. Original identity, protection and supported
metadata are checked before verified publication and recovery.

Eligible native common-format and ISO/RAR5 Store/canonical DMG workflows use
bounded streams and private spools. Their documented 8 GiB budgets are profile
limits, not a claim that every format, option, platform or maximum-size case was
qualified. Protected and nested workflows retain smaller bounds; fresh plain
TAR creation retains its separately documented 2 GiB bound. The latest integrated
ISO/RAR/DMG record reports **1,856 normal archive tests and nine explicitly
enabled cases above 2 GiB**. Those gates do not close native device acceptance,
durable packing jobs, or all Commander workflows.
[Runtime evidence](archive-containers-runtime-verification.md) ·
[ISO/RAR/DMG profiles](archive-iso-rar-dmg.md)

## Workflow acceptance matrix

**Priority:** P0 = shared infrastructure or a broad workflow gap; P1 = the next
user-visible compatibility layer; P2 = a separate engine/platform project.
“Delivered within profile” retains every boundary in the linked baseline docs.
Acceptance criteria below are CrispCloud requirements; they are not claims that
the competitors provide transactional recovery or identical safety guarantees.

| ID / priority | Official competitor evidence | CrispCloud at baseline | Concrete remaining acceptance |
| --- | --- | --- | --- |
| A01 · P1 · Open, browse, preview | TC treats archives as folders; DC routes through WCX or external engines. [TC][tc-features] [DC][dc-archives] | Delivered within profile, including supported images/packages, signature-prioritized routing and nested previews. | Record browse, preview, extraction and test separately per codec. Test misleading suffixes, extensionless inputs, Unicode, malformed metadata, limits and source closure. Add explicit SFX discovery under A11. |
| A02 · P1 · Copy into/out of an archive | TC documents copying into/out of archives. [TC][tc-features] | Reviewed native imports and extraction; captured sources, conflicts, hierarchy and empty folders. | Qualify remaining remote/browser endpoints independently; retain source identity and metadata/protection policy through delayed work. A recognized archive is not automatically writable. |
| A03 · P1 · Archive-to-archive transfer | TC explicitly documents direct archive-to-archive copying. [TC][tc-features] | Copy is delivered; native top-level moves verify both candidates and publish the destination before source removal. | Close G20 nested cross-container moves and grouped operations across independently opened inner routes. Cover alias/hard-link endpoints, separate passwords, overlap, late source changes and interruption between publications. |
| A04 · P1 · Member edit and repack | DC temporarily extracts F3/F4 files and can repack changed edits when the engine supports it. [DC][dc-archives] | In-app reviewed member edits and nested propagation are delivered within policy. | Inventory arbitrary external-editor handoff separately from the in-app editor. Any added handoff must detect completion, associate the exact member/version, revalidate the container and retain a recoverable edit on failure. |
| A05 · P1 · Same-container changes | TC's internal 7z implementation includes deletion and renaming; unsupported format actions remain engine-specific. [TC history][tc-history1150] | Add/remove/rename/folders and grouped same-workspace moves are delivered. | Preserve one transaction per physical container across aliases and nested routes. Verify retained entries, order and supported metadata; avoid decompression/recompression when a proven metadata-only path is available. |
| A06 · P0 · Background jobs | TC documents background packing. DC exposes queued operations and bundled Zip/SevenZip background flags. [TC][tc-features] [DC queues][dc-copy] [Zip][dc-zip-source] [7z][dc-seven-source] | Foreground streaming, progress, cancellation and publication recovery exist. Durable packing drafts/queue lifecycle remain G21. | Queue packing independently of dialog lifetime; show scan/read/pack/verify/commit phases, reorder pending work, stop safely and retain explicit terminal results. After restart, revalidate captured sources/destination and restart or resume only a proven safe phase. Measure actual UI responsiveness and memory. Never persist passwords in ordinary records. |
| A07 · P1 · Test archives | DC provides a selected-archive integrity command whose coverage follows its engines. [DC][dc-help] | F3 reports checked/failed/skipped/unprocessed members and SHA-256; default 64 MiB/member and 256 MiB work limits. | Add pane/batch invocation and streamed testing for eligible large readers. A checksumless, skipped, password-blocked, corrupt or cancelled member must not produce an unqualified pass. Retain per-member diagnostics and a copyable report. |
| A08 · P1 · Batch extraction | DC offers masks, one folder per archive, smart extraction and retained/flattened paths. [DC][dc-help] | Safe extraction is delivered; this full Commander-style batch option set is not qualified by the baseline. | Add a captured multi-archive plan with masks and explicit folder mode. Preview flattening collisions, directory/file conflicts and overwrite policy; extraction must stay within the approved destination. Verify independent archives cannot overwrite each other's output silently. |
| A09 · P1 · Batch creation and move-to-archive | DC's pack dialog has separate-per-selection and move-to-archive controls. [DC source][dc-pack-dialog] | One reviewed creation output and reviewed native import/move workflows exist. | Add one-output-per-selected-file/folder planning where useful. Capture every output name before work, verify each output independently, and remove a source only after its own successful verified publication. Clearly report partial batches. |
| A10 · P1 · Split volumes | TC's bundled 7z supports multipart output. DC's generic volume-size control is enabled by an external adapter's `%V`; its WCX path disables that control. [TC history][tc-history1150] [DC source][dc-pack-source] | Archive volume sets are not an enabled write profile. Generic file split/join is a separate capability. | First define exact read/write profiles, such as 7z byte volumes or ZIP split archives. Capture ordered sibling identities; report missing/wrong/replaced volumes; enforce total limits. Publish or recover the whole volume set, including late collisions and cancellation. Do not advertise generic chunking as format-aware volume support. |
| A11 · P1 · Browse SFX | TC documents Ctrl+PageDown to inspect self-extracting archives. DC supports content recognition with configurable signatures/offset ranges. [TC FAQ][tc-packing] [DC][dc-archives] | Ordinary signature dispatch exists; explicit executable-overlay/SFX coverage is not established. | Add a bounded, read-only ZIP/7z/RAR SFX profile after auditing pinned readers. Validate executable and archive boundaries; distinguish an appended payload from a coincidental embedded signature; preserve ownership and limits. Browsing must not execute the stub. Add independent real SFX, corrupt, ambiguous and oversized-prefix fixtures. |
| A12 · P2 · Create SFX | TC's internal 7z history includes multipart SFX. DC enables an external SFX command when configured. [TC history][tc-history1150] [DC][dc-archives] | No SFX creation workflow. | Use a named, versioned, redistributable stub/engine profile. Verify the embedded archive independently, retain reviewed output identities and handle signatures explicitly. Stub execution is a separate user action and is not a prerequisite for validating an archive. |
| A13 · P1 · Compression options | DC's SevenZip options include method, level, dictionary, word/solid-block sizes, threads and memory estimates. [DC dialog][dc-seven-options] | Real supported codec/method/level controls; no general Commander-style advanced engine settings. | Expose only effective options for the selected engine/version. Validate combinations before scanning, estimate resource use, preserve appropriate existing compression policy, and record requested/actual options in the review. Test generated output with an independent decoder. |
| A14 · P1 · Passwords and hidden names | 7-Zip supports AES-256 for 7z/ZIP. TC 11.58 adds protections against leaking encrypted filenames in tabs/history/logs. [7-Zip][sevenzip] [TC][tc-newsletter] | ZIP AES-256 content encryption and 7z AES/header protection; independent nested passwords and wrong-password handling. Larger protected paths remain bounded. | Qualify large encrypted reads/writes, password retry and cancellation, empty/protected archives and policy-preserving rewrites. Audit logs/history/job records/temp paths for passwords and protected names. Credential persistence, if added, needs an explicit secure-store policy. |
| A15 · P0 · External packers | DC provides List/Extract/Add/Delete/Test/SFX actions and password/options/volume variables. TC supports external packers and Multi-Arc. [DC][dc-archives] [TC][tc-packing] | G24 scoped; no archive packer runtime bundled. | Deliver a native manifest/adapter boundary with discovered exact tool identity/version and separately proven actions. Stage outputs privately, pass paths safely, bound output, kill the child tree on cancellation, classify exit codes and verify output before publication. Tool availability must not imply every codec or action. |
| A16 · P2 · WCX plugins | TC publishes WCX interfaces; DC can use many compatible TC plugins on Windows. [TC][tc-plugins] [DC][dc-help] | No WCX ABI host. | Define a tested plugin allowlist and OS/architecture matrix. Isolate native crashes in a helper process; implement required callbacks, Unicode/large sizes, progress, passwords, content detection and declared background behavior. Expose only per-plugin proven operations. Native ABI compatibility does not imply browser support. |
| A17 · P1 · Folder/archive synchronization | TC documents directory↔ZIP sync. DC supports local↔virtual sync with directional actions; its docs exclude empty directories and limit content comparison for a virtual second side. [TC][tc-features] [DC][dc-sync] | G19 native one-way content-hashed folder→archive sync includes empty entries and reviewed optional removals. | Add reviewed reverse-direction and two-way conflict/deletion semantics with reliable baseline state. Test changed equal/unselected members, type conflicts, stale plans and partial publication. Extend nested/remote destinations only with their own authority and recovery contract. |
| A18 · P1 · Nested archives | Commander archive-as-folder workflows depend on the selected engines; arbitrary nesting is not an all-engine guarantee. [DC][dc-archives] | Independent passwords/generations and eligible inner repacks; buffered nesting and cross-route limits remain explicit. | Exercise edits/transfers through every supported layer, ancestor generation changes, combined limits and password failure at different levels. Group updates to a shared outer container once. Display the repacking cost and retain every original until the outer publication verifies. |
| A19 · P1 · Remote/browser publication | Competitor archive and filesystem plugins are different extension types; their existence is not evidence of CrispCloud provider semantics. [TC][tc-plugins] [DC][dc-plugins] | G18/G23 browsing is broader than publication; no remote backend currently provides the required archive access-policy contract. | Enable each provider only after captured account/object identity, exclusive staging, access-policy preservation, collisions, revocation and recovery are proven. Browser downloads and writing a granted destination must remain distinct outcomes. |
| A20 · P1 · Archive search | TC documents text search inside archives; DC's search coverage depends on installed packer plugins. [TC][tc-features] [DC][dc-search] | Shared archive routing/search is delivered within existing reader limits. | Qualify newly added engines, SFX and volume sets for names/content search. Report skipped encrypted, oversized and unsupported members; do not turn a partial search into an exhaustive-result claim. |

## Format and engine boundaries

This table is a family-level comparison, not a promise that every method,
metadata record, version or plugin in a family works. **R** = browse/extract;
**W** = a documented writer exists for at least the named profile. W does not
establish a signed-package builder, a bootable filesystem editor, or preservation
of every producer-specific record.

| Family | Total Commander delivery | Double Commander delivery | CrispCloud baseline / remaining compatibility |
| --- | --- | --- | --- |
| ZIP and ordinary ZIP aliases | Bundled ZIP R/W. [TC][tc-features] | Bundled Zip WCX; codec libraries can be required. [DC][dc-plugins] | R/W for inspected ZIP/CBZ and eligible unsigned Java/KMZ; ZIP64 native streams. Extra methods, split/SFX and broader protection profiles need individual gates. |
| 7z | Bundled R/W since 11.50; optional plugins also exist. [TC][tc-newsletter] | Bundled SevenZip WCX. [DC][dc-plugins] | R/W with the documented Store/Deflate/LZMA2 and protection profiles. Advanced tuning, split/SFX and large encrypted writes remain separate. |
| TAR and compressed streams | TAR/GZ support plus optional bzip2/LZMA/XZ plugins. [TC features][tc-features] [TC catalog][tc-plugins] | Zip WCX handles TAR and several stream/wrapper families. [DC][dc-plugins] | TAR plus gzip/bzip2/XZ/Zstandard/LZ4/LZMA/UNIX compress R/W. Lzip remains R. Preserve inspected TAR metadata; do not silently drop unknown extensions. |
| Compressed RAR | Internal R; RAR packing is an external-tool integration. [TC FAQ][tc-packing] | UnRAR library for R; configured WinRAR/rar for W. [DC][dc-plugins] | Existing compressed/password R plus independent unencrypted single-volume RAR5 Store W. Actual RAR compression, solid/protected writes, volumes and recovery records need a separately licensed tool/profile. |
| ARJ, LHA/LZH | Internal readers; external packers for W. [TC][tc-features] [TC FAQ][tc-packing] | SevenZip offers R for these families; 7-Zip lists them as unpack-only. [DC][dc-plugins] [7-Zip][sevenzip] | Remaining readers; external-engine route can supply a first compatible implementation. No inferred writer. |
| CAB | Internal R. [TC][tc-features] | SevenZip R; upstream unpack-only. [DC][dc-plugins] [7-Zip][sevenzip] | Stored/MSZIP single-cabinet R. LZX/Quantum, split cabinets and CAB creation require separate work. InstallShield CAB is a different format. |
| ACE / UC2 | Legacy internal/external handling is listed; exact installed engine must be qualified. [TC][tc-features] | No bundled support established by the cited plugin list; external/plugin route is separate. [DC][dc-plugins] | Not enabled. License/tool availability and precise version/method fixtures precede support. |
| ISO / UDF | Optional ISO reader; optional TotalISO fronts separately installed image-building tools. [TC][tc-plugins] | SevenZip ISO R; current upstream also lists UDF R, both unpack-only. [DC][dc-plugins] [7-Zip][sevenzip] | ISO9660/Joliet/Rock Ridge R and inspected data ISO W. UDF, boot/hybrid/multisession writing and broader image layouts remain separate. |
| DMG / HFS / APFS and other filesystems | Optional Total7zip/image plugins broaden R. [TC][tc-plugins] | SevenZip DMG/HFS R; upstream APFS and many disk formats are unpack-only. [DC][dc-plugins] [7-Zip][sevenzip] | Supported UDIF/HFS R; fresh HFSX and verified canonical HFSX DMG W. APFS and arbitrary filesystem rewrites are not implemented. |
| CPIO / RPM / DEB | Optional package readers. [TC][tc-plugins] | Bundled CPIO/RPM/DEB readers, with platform-specific routing. [DC][dc-plugins] | More CPIO W profiles plus a narrow paired-prebuilt DEB replacement workflow. RPM remains R. None of these generic views validates a complete installable/signed package. |
| AR / XAR / PKG / XIP | Optional engines; no generic package rebuild claim in the cited catalog. [TC][tc-plugins] | Relevant SevenZip formats are unpack-only upstream. [7-Zip][sevenzip] | Inspected flat AR and unsigned XAR W; indexed `.a`, PKG/XIP and signed structures remain R. Dedicated symbol-index/package/signature rebuilds are separate capabilities. |
| WIM, VHD/VHDX, VMDK, NTFS, SquashFS, CHM, MSI, etc. | Optional plugin coverage varies. [TC][tc-plugins] | Some are registered with SevenZip; upstream lists a broader readable set and WIM among packable formats. [DC][dc-plugins] [7-Zip][sevenzip] | Not established by existing ISO/DMG support. Add individual reader/engine profiles; do not label the entire upstream list as bundled, writable or tested. |

Upstream 7-Zip's current format list is useful to identify candidate backend
capabilities, but it is **not** evidence that a Commander installation ships
that exact library version or registers every upstream format. Plugin capability
flags are also broader than a particular opened archive: each operation still
needs format- and file-specific validation.

## Plugin contract acceptance

DC's pinned WCX header distinguishes new archives, modification, multiple
members, deletion, options, in-memory packing, content detection, text search,
hidden handling and encryption. `PK_CAPS_MULTIPLE` means multiple **members**,
not multiple volumes. Testing is a separate `ProcessFile` operation; background
packing/unpacking have separate declarations in the bundled plugin sources.
[WCX header][dc-wcx] · [Zip implementation][dc-zip-source] ·
[SevenZip implementation][dc-seven-source]

A CrispCloud adapter must preserve those distinctions. Registration should
explain engine identity, version, platform, supported actions and reasons for
unavailable controls. Reading must not accidentally grant write access; a
successful external command must not bypass candidate verification. An ABI host
and a command-line adapter are separate deliverables with separate tests.

## Original implementation order

This sequence records the planning baseline. The delivered rows above describe
the current integration; unfinished portions retain their own acceptance gates.

1. **A06 / G21:** durable native creation jobs and a queue whose owner survives
   the creation dialog. Preserve captured inputs/options, revalidation and
   verified publication. Add packing-draft recovery before declaring G21 closed.
2. **A15 / G24:** a constrained external-engine foundation, with one explicit
   first engine/profile, independently decoded output and failed-tool coverage.
   Broad format registration comes only after per-format capability tests.
3. **A11:** bounded read-only SFX recognition/extraction is an independent next
   workflow. Audit pinned reader offset behavior first; retain executable
   overlays as a read-only container and never pass them through a normal
   archive writer that would drop the stub or invalidate a signature.
4. **A07/A08/A09/A13:** streamed/batch testing, extraction/packing plans and
   genuine engine options improve common tasks without claiming new codecs.
5. **A10/A12/A16 and G19/G20/G23:** volume sets, SFX creation, WCX hosting and the
   remaining synchronization/nested/provider paths retain their own acceptance
   milestones. A completed first queue or first external engine does not close
   these rows.

For each completed row, record the exact source revision, OS/architecture,
engine/version, method/protection profile, measured bounds and independent
fixture result. Add malformed/truncated, traversal, collision, wrong-password,
resource-limit, cancellation and changed-source cases relevant to that operation.
Only then update its status from the baseline. These are acceptance requirements
for CrispCloud; the research alone establishes no new runtime capability.

## Primary references

All competitor claims above use official project documentation, official
release history or source maintained in the project's own repository. No
third-party feature summaries are used. Links were checked on the research date.

[tc-release]: https://www.ghisler.com/whatsnew.htm
[tc-newsletter]: https://www.ghisler.com/mailing.htm
[tc-features]: https://www.ghisler.com/featurel.htm
[tc-history1150]: https://www.ghisler.com/history1150.txt
[tc-packing]: https://www.ghisler.com/efaqpack.htm
[tc-plugins]: https://www.ghisler.com/plugins.htm
[dc-releases]: https://sourceforge.net/projects/doublecmd/files/Double%20Commander/
[dc-plugins]: https://doublecmd.github.io/doc/en/plugins.html
[dc-archives]: https://doublecmd.github.io/doc/en/multiarc.html
[dc-help]: https://doublecmd.github.io/doc/en/help.html
[dc-copy]: https://doublecmd.github.io/doc/en/copymove.html
[dc-sync]: https://doublecmd.github.io/doc/en/syncdirs.html
[dc-search]: https://doublecmd.github.io/doc/en/findfiles.html
[dc-pack-dialog]: https://github.com/doublecmd/doublecmd/blob/v1.2.11/src/fpackdlg.lfm
[dc-pack-source]: https://github.com/doublecmd/doublecmd/blob/v1.2.11/src/fpackdlg.pas
[dc-seven-source]: https://github.com/doublecmd/doublecmd/blob/v1.2.11/plugins/wcx/sevenzip/src/SevenZipWcx.dpr
[dc-seven-options]: https://github.com/doublecmd/doublecmd/blob/v1.2.11/plugins/wcx/sevenzip/src/SevenZipDlg.lfm
[dc-zip-source]: https://github.com/doublecmd/doublecmd/blob/v1.2.11/plugins/wcx/zip/src/ZipFunc.pas
[dc-wcx]: https://github.com/doublecmd/doublecmd/blob/v1.2.11/sdk/wcxplugin.h
[sevenzip]: https://www.7-zip.org/
