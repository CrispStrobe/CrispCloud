# File Viewer: remaining formats and effective license audit

Audit date: 2026-11-13. Read-only source review of `flyfish-dev/file-viewer` at **`d264009ca6efb3daed79a39d1ae63133e0f25558`** (package version 3.3.3). Scope: CHM, ebooks/comics, PDF, images/DICOM, email, archives, audio/video/MIDI, subtitles, and text. Office, engineering/design/CAD, font inspection, OFD, Typst, GIS, and other data formats belong to the other audit sections.

The requested policy now admits Apache, MIT, BSD and similar permissive licenses plus MPL. The classifications below concern the actual renderer path and its dependencies/assets, rather than the Apache label on File Viewer's own adapter. They are source-review conclusions, not a claim that every renderer was built or exercised in this session. An unresolved exact binary closure is called out rather than inferred from the wrapper's npm license.

## Decisions that matter

1. **CHM and UMD are useful new reading candidates.** CHM has a deliberately permissive Rust/WASM parser and real HTML/topic navigation. UMD uses the Apache parser plus pako under MIT and Zlib. CrispCloud already has EPUB, FB2, and Kindle-family reading, so replacing those readers would give less value.
2. **The Apache comic-book controller is reusable without importing the upstream archive engine.** CBZ/CBR have a real sequential image reader. Port its navigation/page-ordering ideas onto CrispCloud's existing archive and image services.
3. **TIFF and DICOM provide actual pixel rendering.** TIFF is a modest MIT dependency. DICOM is a much larger opt-in Cornerstone stack with BSD/MIT/Apache/IJG/Zlib codecs and an unusually detailed provenance bundle. It remains a limited local single-file viewer.
4. **HEIC/HEIF is outside the admitted license set as currently packaged.** `heic2any` has an MIT wrapper, but its build embeds libheif. The upstream library's LGPL terms do not disappear in the worker. The exact embedded native versions were not recovered, so this is both a stronger-license branch and an unresolved binary provenance branch.
5. **The archive WASM is not cleared merely because `libarchive.js` says MIT.** Its native closure includes libarchive and compression/crypto libraries. The source build recipe and actual WASM version strings differ for bzip2, and File Viewer's vendored directory lacks a full native notice bundle. Reuse existing CrispCloud extraction services where possible.
6. **Several apparent format claims are narrower than a user would expect:** MBOX displays only its first message; MIDI is an inspector, not synthesized playback; AVIF/JXL use browser decoding; `.ipynb` and `.tex` go to source display; no standalone RAW, JPEG 2000, DjVu, PST/OST or subtitle renderer was found.

## Method and common dependencies

The authoritative starting points are the [generated route registry][registry], each package's source implementation, the [locked dependency graph][lock], and retained licenses/provenance. A registered extension is not evidence that every variant of that format decodes correctly. Here, “render” describes a real source path that produces content; it does not promise complete format fidelity.

File Viewer's own code in these renderer packages is Apache-2.0. Its shared [core package][core-package] also brings **DOMPurify 3.4.17**, licensed `MPL-2.0 OR Apache-2.0`; upstream explicitly elects Apache-2.0 in its more detailed notice inventories. Keep the selected license and applicable notices. Sanitized HTML previews should preserve their existing resource/sandbox policy when ported.

A `devDependency` can still be a **distributed runtime**: EPUB.js, PDF.js, and the Cornerstone SDK are bundled during the package build. Conversely, a source-closure inventory may contain build-oriented packages which are absent after bundling. The final delivered JavaScript, WASM and fonts determine the distribution obligation. Emscripten/Rust build executables themselves are not automatically shipped; portions of their standard libraries or generated runtime that are linked into the output need their own notices.

## Format matrix

| Format / actual route | What upstream actually provides | Effective license boundary / exact main versions | Value and decision for CrispCloud |
| --- | --- | --- | --- |
| **CHM** | ITSF v2/v3; uncompressed and LZX-compressed topics; HTML, contents/index/search and local resource navigation. | Apache adapter/WASM work; MIT RustChm/FastChm source; permissive Rust crates with BSD/Unicode components. See detailed CHM ledger below. | **Strong candidate.** No CHM route found in the current CrispCloud viewer inventory. Preserve the bounded worker and HTML policy. |
| **EPUB 2/3** | Real chapter rendering, navigation/TOC, scrolling, reading progress and search. | EPUB.js **0.3.93 BSD-2-Clause**, XML DOM **0.9.12 MIT**, JSZip **3.10.2 MIT option**, associated MIT/Apache/Zlib code; final emitted bundle has its own generated manifest. | Compatible in principle, but **existing coverage overlaps heavily**. Reuse a specific missing behavior rather than replace the current reader. |
| **FB2** | XML-derived book metadata, sections, images and links/notes rendered as a semantic book. | Apache parser and browser XML facilities; shared sanitizer closure. | Existing CrispCloud FB2/FBZ coverage. This is not a fixed-page reproduction engine. |
| **UMD** | Decoded structured chapters and book metadata. | Apache parser + **pako 2.2.0, MIT AND Zlib**. | **Useful small new format candidate.** Bounds, encoding and inflation checks should survive a Dart port. |
| **MOBI / AZW / AZW3** | **No renderer route in this checkout.** | No upstream implementation to approve here. | CrispCloud already recognizes these through its ebook reader; do not advertise them as a contribution from File Viewer. |
| **CBZ / CBR** | Sequential comic page reader with natural sorting, navigation, keyboard/swipe and page count. | Controller Apache; archive and image decoders have separate closures. Upstream CBR goes through libarchive. | **Useful UI/controller port on existing CrispCloud archive stack.** Avoid acquiring an unnecessary second archive WASM closure. |
| **PDF** | PDF.js page rendering, outline, search, zoom and print/export; optional font repair. | **PDF.js 5.4.624 Apache**, optional **pdf-lib 1.17.1 MIT**, BSD CMaps/codecs/Foxit fonts, OFL Liberation/Noto fonts, MIT qcms. | Permitted code families, with font/asset notices. Already covered in CrispCloud; selectively borrow behavior. |
| **XPS** | Routed to the **CAD package**, not this PDF.js renderer. | CAD engine's own closure; see engineering audit. | **Do not apply PDF.js's Apache classification to XPS.** |
| **EML** | Parsed message headers/body, sanitized HTML and attachments. | **postal-mime 4.1.4 MIT-0**, Apache adapter/core. | Existing CrispCloud EML support; targeted robustness/UI comparison may help. |
| **MSG** | Structured headers/body/attachments; RTF body resolution can invoke the host RTF renderer. | **@kenjiuno/msgreader 1.29.0 Apache**, **decompressrtf 0.1.4 BSD-2**, buffer/iconv support MIT. Nested RTF/attachments add their selected renderer licenses. | Existing CrispCloud MSG support; no obvious wholesale replacement need. |
| **MBOX** | Counts separators and previews **only the first message**. | Same postal-mime MIT-0 + Apache path. | Small extraction candidate, but a complete mailbox browser needs additional implementation. |
| **PST / OST** | **No route/parser found.** | Unknown/not implemented here. | Do not claim support. |
| **ZIP/ZIPX, 7Z, RAR, TAR and compressed/archive families** | File listing, extraction, password handling and nested previews through a worker; ZIP/TAR/GZIP fallback. | **libarchive.js 2.0.2 MIT** + **libarchive 3.7.2 BSD-2** and native compression/crypto closure; **JSZip 3.10.2 MIT option**. Prebuilt WASM's complete linked licenses/versions remain unresolved. | Existing CrispCloud archive stack already covers many. **Do not vendor the upstream WASM solely on MIT wrapper metadata.** |
| **TIFF / TIF** | Real bounded multi-page decode, page navigation and rotation. | **UTIF 3.1.0 MIT**, **pako 1.0.5 MIT AND Zlib**, Apache viewer. | **Useful candidate for multi-page UI or missing decoding cases**, after comparing with existing TIFF behavior. |
| **PNG/JPEG/GIF/BMP/WebP/ICO/SVG** | Browser image rendering; own view controls. | Apache controller; browser codec supplied by host rather than copied into the JS package. SVG/core sanitization has its separate DOMPurify license. | Existing coverage. Reuse UI behavior only where beneficial. |
| **AVIF / JPEG XL (`.jxl`)** | Blob/image element rendering **only if the browser can decode it**. | Apache controller; **no bundled AVIF/JXL decoder in this image path**. | Does not create reliable cross-platform decoding support by itself. DICOM's codecs are a separate path. |
| **HEIC / HEIF** | `heic2any` converts to PNG; a returned array is reduced to its first image. | **heic2any 0.0.4 MIT wrapper** embeds **libheif LGPL**, with further codec/version provenance not fully recovered. | **Exclude this fallback under the stated license policy.** Existing OS/native handling can be assessed independently. |
| **Camera RAW, standalone JP2/J2K/JPX, DjVu** | **No standalone routes found** for RAW/CR2/CR3/NEF/ARW/RAF/RW2/DNG, JPEG 2000 files or DjVu. | Embedded JPEG 2000 decoding in PDF/DICOM does not establish a standalone image renderer. | Do not market these as supported imports. |
| **DICOM (`.dcm`, `.dicom`)** | Experimental single local Part 10 file and multiframe pixel stack; zoom/windowing/frame navigation. | **Cornerstone 5.13.2 MIT**, **vtk.js 36.4.1 BSD-3**, native codec wrappers plus BSD/IJG/Zlib/MIT/Apache native implementations. Full details below. | **Larger specialized candidate.** Do not call it a PACS, volume viewer or full diagnostic workstation. |
| **MP4 / WebM** | Browser playback; narrow `mp4v` software decoder fallback when native MP4 decoding fails. | Apache controller and AOSP PacketVideo MPEG-4 Part 2 decoder; linked runtime has MIT/NCSA, musl MIT, compiler-rt Apache/LLVM exception, allocator public-domain/CC0 notices. | Existing CrispCloud media coverage is broader. The fallback is useful chiefly for a web gap, not general FFmpeg replacement. |
| **MP3/MPEG/WAV/OGG/OGA/OPUS/M4A/AAC/FLAC/WEBA** | Native HTML audio playback, contingent on browser codecs. | Apache adapter; no general decoder library bundled for these routes. | Existing coverage; extension recognition is not universal codec support. |
| **HLS / M3U8** | Optional streaming-media capability. | **hls.js 1.7.3 Apache-2.0** plus Apache adapter. | Permitted optional capability; local/remote source behavior must fit CrispCloud's existing provider model. |
| **MID / MIDI** | Optional track/note/tempo metadata inspection. | **@tonejs/midi 2.0.28 MIT**, **midi-file 1.2.4 MIT**, **array-flatten 3.0.0 MIT**. | A reasonable new **inspector**, not an audio synthesizer. |
| **LRC** | Parsed lyrics/metadata/timestamps and enhanced word timing inspection. | Apache parser/controller. | Already ported in this branch with source/hex preservation; no new work needed for this row. |
| **SRT / VTT / ASS / SSA / SUB** | **No dedicated subtitle renderer found.** Generic text display may still open text. | No subtitle-specific runtime to approve. | Do not describe text fallback as timed subtitle playback or conversion. |
| **Source/text, JSON/YAML/XML, diff/patch, Git bundle** | Syntax display, formatting; optional patch comparison and bundle inspection; XML-specific tools. | Apache; **highlight.js 11.12.0 BSD-3**, **marked 18.1.2 MIT**, **Prettier 3.9.10 MIT**, XML plugin **3.4.2 MIT**; optional diff/pako and XML WASM closures below. | Existing plain/code viewing overlaps. XML schema/transformation and specialized diff/bundle tools are the more differentiated pieces. |
| **Markdown** | Sanitized rendered Markdown with navigation/link handling. | **marked 18.1.2 MIT** plus DOMPurify **3.4.17 Apache OR MPL**. | Existing coverage; retain source/HTML safety and link routing if porting enhancements. |
| **IPYNB / TeX** | Registered to the **code/source renderer**. | Text dependency closure above. | **Not** a notebook execution/output engine or TeX typesetting implementation. |

## Detailed license boundaries and exact evidence

### 1. CHM: a deliberately permissive native implementation

The [CHM viewer][chm-code], [security adapter][chm-security] and worker load a local Rust/WASM parser. [Third-party notices][chm-notices] explicitly distinguish this work from CHMLib/libmspack-derived implementations. The retained [Rust provenance notice][chm-rust-notice] identifies:

| Source/component | Exact version or commit | Terms / relevance |
| --- | --- | --- |
| RustChm | `5418439a40812079b479acec40719cddedcb583c` (crate 0.1.2 lineage) | MIT source adaptations. |
| FastChm | `2c22935ba0a1fc7a5a3d3d9785c970058c4d00f0` | MIT format/parser research adaptations. |
| encoding_rs | 0.8.35 | `(Apache-2.0 OR MIT) AND BSD-3-Clause`. |
| serde / serde_core / serde_derive | 1.0.229 | MIT OR Apache-2.0. Proc-macro/build code is not automatically runtime. |
| serde-wasm-bindgen | 0.6.5 | MIT. |
| wasm-bindgen / js-sys | 0.2.127 / 0.3.104 | MIT OR Apache-2.0. |
| slab | 0.4.12 | MIT. |
| thiserror | 2.0.20 | MIT OR Apache-2.0. |
| unicode-ident | 1.0.24 | `(MIT OR Apache-2.0) AND Unicode-3.0`; commonly a procedural/build dependency. |

The [full Rust inventory][chm-rust-ledger] includes conservative source/build dependencies and elects Apache for dual grants. The [native runtime profile][chm-profile] covers Rust 1.94.1 standard-library material with retained original notices; it is a source profile, not a post-link assertion that every listed item survives optimization. The own code and MIT inputs can be combined under the broadened policy, keeping each required notice.

This is a genuine CHM topic renderer, not just an ITSF metadata inspector. Its embedded HTML is sanitized, external network/script/ActiveX execution is blocked, and local relative resources are resolved inside the archive. Merged CHM collections still require their constituent files separately. Porting the parser alone and retaining CrispCloud's local-source boundary is a tractable integration; adopting its browser UI would instead require a webview bridge.

### 2. Ebook readers: account for the emitted EPUB engine

The [ebook dispatcher][ebook-index] only registers EPUB, FB2 and UMD. The [EPUB adapter][epub-code] lazily loads a bundled browser engine. The [build script][epub-build] and [source policy][epub-policy] matter because `epubjs` is not merely an unused build dependency.

**EPUB.js 0.3.93** has BSD-2-Clause terms. Its exact npm release points to source commit `0963efe979e34d53507fee1dc10827ecb07fdc75`. The locked source graph includes **@xmldom/xmldom 0.9.12 MIT**, **core-js 3.50.0 MIT**, **event-emitter 0.3.5 MIT**, **JSZip 3.10.2 MIT OR GPL-3.0-or-later** (select MIT), **localforage 1.10.0 Apache-2.0**, and **lodash 4.18.1 MIT**. JSZip's support graph includes lie, pako, readable-stream and setimmediate under permissive terms, including Zlib notices for pako.

The package deliberately removes unused `marks-pane` and `path-webpack` from the emitted graph and substitutes a reviewed Node POSIX path implementation under MIT. The build rejects unexpected source paths. Generated `dist/vendor/epubjs.manifest.json` and `epubjs.NOTICE.txt` are intended to record the exact inlined packages and retained notices. **Those generated files were not rebuilt in this read-only audit**; use the generated graph, not the complete install graph, for final distribution attribution.

The [UMD parser][umd-parser] uses **pako 2.2.0, MIT AND Zlib**. The [FB2 parser][fb2-parser] is own Apache XML-processing code. Their formats are structurally rendered chapters; they do not reconstruct original fixed-page layouts.

CrispCloud's `lib/services/ebook_file_store.dart` already lists `epub`, `mobi`, `azw`, `azw3`, `fb2`, `fbz`, and `cbz`. UMD and CHM therefore offer a clearer net expansion than another EPUB reader. This comparison is to local current source, not a claim that every variant of those existing formats has passed fidelity testing.

### 3. Email: MBOX's first-message limitation is explicit

The [email implementation][email-code] parses EML and MBOX through **postal-mime 4.1.4, MIT-0**. In `parseMbox`, it finds `From ` separator lines, counts messages, slices from the first separator to the second, and parses that one segment. Its result is a first-message preview plus a count summary. There is no full message list/selection UI hidden behind that path.

The [MSG implementation][msg-code] imports **@kenjiuno/msgreader 1.29.0, Apache-2.0**. Its dependency **@kenjiuno/decompressrtf 0.1.4** is **BSD-2-Clause**. Supporting `iconv-lite 0.6.3`, `buffer 6.0.3` and small buffer/base64 helpers have permissive MIT-family terms. Rendering a compressed RTF body is distinct from decompressing it: the code can resolve a host RTF renderer, so importing that richer branch also imports the chosen RTF engine's license. The same applies to nested attachment preview.

Official release-source identities found in npm metadata:

- [postal-mime 4.1.4 source][postal-source]: `d96e2014e4caa72cf3424517cb89776d1bda8a2b`, MIT-0.
- [msgreader 1.29.0 source][msg-source]: `77b6ee07b2f96f39f8757525ae6f9f2ce1152458`, Apache-2.0.
- [decompressrtf 0.1.4 source][rtf-source]: `305aacbf1ea514436a1a5f078cdde2d03264e215`, BSD-2-Clause.

CrispCloud already has local EML/MSG parsing in `lib/services/email_message_service.dart`, including decoded headers/body, bounded attachment parsing, and embedded Outlook handling. MBOX would be additional scope, but upstream's implementation should not be presented as a complete mailbox reader. No PST/OST route was found.

### 4. Archives and comics: distinguish a wrapper from its native binary

The [archive implementation][archive-code] and [package manifest][archive-package] use **libarchive.js 2.0.2**, a worker and `libarchive.wasm`. Declared archive suffixes in the [registry][registry] include ZIP/ZIPX, 7Z, RAR, TAR, GZ/GZIP/TGZ, BZ2/BZIP2/TBZ/TBZ2, XZ/TXZ, LZMA, ZST/TZST, CAB, AR, CPIO, ISO, XAR, LHA/LZH, JAR/WAR/EAR/APK and CBZ/CBR. This is a route inventory, not a verified per-codec decoder matrix. In particular, Zstandard support in the actual committed WASM was not established here.

The [fallback implementation][archive-fallback] covers the narrower ZIP/TAR/GZIP family using **JSZip 3.10.2** and local TAR/native decompression paths. Its ZIP fallback also serves legacy encoding behavior. It does not prove all libarchive formats work without the worker.

The exact libarchive.js npm release gitHead is `0989c1a6db20d030d793b1763e20d880068091bd`. Its [native build script][libarchive-build] links **libarchive**, **liblzma**, **libssl**, **libcrypto**, and Emscripten zlib/bzip2 ports. Its [Dockerfile][libarchive-docker] declares:

| Build recipe component | Declared recipe version | License boundary |
| --- | --- | --- |
| libarchive | 3.7.2 | BSD-2-Clause project, with source-specific notices retained. |
| zlib | 1.3 | Zlib. |
| xz/liblzma | 5.2.11 | liblzma's main implementation is public domain; review linked source-specific terms. The xz utility's other licenses do not automatically apply to liblzma alone. |
| bzip2 | 1.0.8 | Permissive bzip2 license. |
| OpenSSL | 1.0.2s | **Original OpenSSL and SSLeay licenses**, not the later Apache-2.0 OpenSSL license. |
| Emscripten base image | unversioned `emscripten/emsdk` | Exact toolchain and linked port versions are not pinned by this recipe. |

The actual File Viewer WASM contains a **libarchive 3.7.2** string and a **bzip2 1.0.6** string. That differs from the recipe's bzip2 1.0.8, plausibly because of the Emscripten port used. The discrepancy means the source recipe is not sufficient evidence for the exact delivered native closure. File Viewer's committed libarchive vendor directory has worker/WASM assets but no comprehensive linked-library license inventory.

Consequently, this branch is **not classified as forbidden merely because it handles RAR**, and it is **not classified as MIT-only merely because its wrapper is MIT**. A release would need the actual binary's linked dependencies, matching notices and reproducible or publisher-proven artifact evidence. The known recipe has permissive-style licenses, including the older OpenSSL/SSLeay conditions, but the exact artifact remains unresolved.

The [comic-book controller][comic-code] is own Apache code: it naturally sorts image entries, opens the first image, supports previous/next, keyboard/swipe and page-count display. It delegates all decoding/extraction. CrispCloud's `lib/services/archive_format_registry.dart` already maps CBZ to ZIP and CBR to RAR; its ebook reader also recognizes CBZ. **A port of just the controller/navigation logic avoids this native-closure problem.** Image formats embedded in comics retain the selected image decoder's terms; a HEIC page would not magically become permissive by residing in a CBZ.

### 5. Image routes: TIFF is an actual decoder, AVIF/JXL are browser dependent

The [image implementation][image-code] routes ordinary images to a browser image element. AVIF and JPEG XL are included among recognized suffixes, but there is no standalone AVIF/JXL decoder import in this path. Decode failure produces an error rather than silently proving support. The host's browser codecs determine success.

The [TIFF implementation][tiff-code] loads **UTIF 3.1.0 MIT**, whose release points to `27f1098a67c3cfd4348c9b8fd887fcd8cd171095`, and **pako 1.0.5 MIT AND Zlib**. It decodes page pixels and provides multi-page controls. Its defaults bound input to 32 MiB, pages to 64, dimensions to 16,384, each page to 32 million pixels and cumulative pixels to 128 million. These are useful engineering protections to retain if ported. The [image notices][image-notices] acknowledge UTIF but do not provide a native HEIC closure.

**HEIC/HEIF requires separate exclusion.** The source always invokes `heic2any` for these suffixes, converts to PNG, and selects the first output image if conversion produces multiple images. `heic2any 0.0.4` is declared MIT, with official release gitHead `3222e591896ce72cf293a37f5a083cde5fc348c7`. Its immutable [build source][heic-build] reads `src/libheif.js` and concatenates it into the worker/browser artifact; [that decoder source][heic-libheif] contains libheif API calls. The upstream [libheif licensing statement][libheif-license] distinguishes the **LGPL library** from MIT sample applications/wrappers. The library terms are LGPL version 3 family, beyond the user-approved permissive/MPL set. The HEVC backend commonly uses libde265, itself LGPL-3.0, but **the exact decoder versions and complete embedded codec closure in this particular heic2any bundle were not recovered**. Do not assert a particular libde265 version or a complete native inventory from the wrapper metadata.

No standalone routes were found for camera RAW variants (`raw`, `cr2`, `cr3`, `nef`, `arw`, `raf`, `rw2`, `dng`), JPEG 2000 (`jp2`, `j2k`, `jpx`), or DjVu. OpenJPEG bundled inside PDF/DICOM is not a standalone image viewer.

CrispCloud already lists TIFF, AVIF and HEIC/HEIF alongside normal images in `lib/services/internal_viewer_service.dart`; `lib/services/gallery_image_decoder.dart` mediates decoding. That existing extension list is not evidence of identical per-platform codec behavior, so any TIFF improvement should be compared against actual current behavior before adding a new decoder.

### 6. DICOM: a substantial opt-in stack with reviewed native notices

The [DICOM entry point][dicom-index] and [viewer implementation][dicom-code] provide actual local pixel rendering for a **single Part 10 file**, including multiframe stacks. It is experimental and opt-in, absent from standard/full presets. Documented/tested transfer syntaxes include Implicit VR Little Endian, Explicit VR Little Endian, Deflated Explicit VR Little Endian, JPEG Lossless Process 14 SV1, JPEG-LS Lossless and JPEG 2000 Lossless. Do not infer all possible transfer syntaxes from the available codec packages alone.

Defaults bound encoded input to 64 MiB, frames to 256, each frame to 16 million pixels and aggregate pixels to 48 million. The UI has frame navigation, zoom and window/level controls. There is no implemented series assembly, PACS/DICOMweb service, multiplanar reconstruction, segmentation or measurement workstation claim.

The [reviewed notice file][dicom-notices], [JavaScript/SDK ledger][dicom-ledger] and [native artifact provenance][dicom-native] are the source of the following closure:

| Component | Exact version / source | Effective terms |
| --- | --- | --- |
| Cornerstone core, metadata, utils, dicom-image-loader | 5.13.2 | MIT SDK/runtime; SDK build dependencies are bundled into the consumer package. |
| dicom-parser | 1.8.21 | MIT. |
| vtk.js | 36.4.1 | BSD-3-Clause. |
| pako / events | 2.2.0 / 3.3.0 | MIT AND Zlib / MIT. |
| codec-charls | 1.2.7; native `9930a2a2fa75f516c4a08708180c9907fa501a97` | Wrapper MIT; CharLS BSD-3-Clause. |
| codec-libjpeg-turbo-8bit | 1.2.7; native `dc4a93fab38b42d29b89a533409e012570180e28` | Wrapper npm metadata ISC, retained root source MIT; native **IJG AND BSD-3-Clause AND Zlib**. Retain IJG acknowledgment. |
| codec-openjpeg | 1.3.6; native `6c4a29b00211eb0430fa0e5e890f1ce5c80f409f` | Wrapper MIT; OpenJPEG BSD-2-Clause. |
| codec-openjph | 2.4.11; native `4a68609b55034a14fac23f95afc60e239a9e809e` | Wrapper MIT; OpenJPH BSD-2-Clause. |
| codec-libjxl | 1.1.1; native `794a5dcf0d54f9f0b20d288a12e87afb91d20dfc` | Wrapper metadata BSD-3, root source MIT; native libjxl BSD-3, with PATENTS/AUTHORS. |
| Brotli / Highway / skcms linked with libjxl | Native commits recorded in PROVENANCE.json | MIT / Apache-2.0 selection (both dual texts retained) / BSD-3-Clause. |
| JPEG lossless JavaScript decoder | 2.2.1 | MIT. |

The wrapper metadata discrepancies are expressly recorded upstream, not silently replaced with an easier label. Missing npm wrapper license files are repaired by retaining exact upstream source notices tied to release and publisher-build commits. Native source gitlinks and official tarball inventories are recorded, while the notice correctly declines to claim an independent bit-for-bit rebuild.

The conservative SDK source inventory also includes MIT/ISC/Apache packages, **argparse 2.0.1 Python-2.0**, and **caniuse-lite CC-BY-4.0 data**. It is not a list of everything shipped after tree-shaking. Generated `dist/bundled-runtime.json` records actual inputs/output/WASM hashes, and `dist/THIRD_PARTY_LICENSES.txt` holds their texts; verify those in the chosen build. A small attribution inconsistency exists: the notice's introductory caniuse bullet names `1.0.30001810`, whereas its later inventory names `1.0.30001819`. Reconcile the exact shipped version rather than copying both claims unchanged.

This is a candidate under the broadened policy once the delivered manifest/notices are carried with it. It is substantially more integration work and download size than a pure parser. No DICOM route was found in CrispCloud's current internal-viewer extension inventory.

### 7. PDF: Apache engine plus distinct fonts, color and image codecs

The [PDF package][pdf-package] builds and stages **pdfjs-dist 5.4.624** (Apache-2.0). The [staging/provenance scripts][pdf-stage] copy runtime support files rather than assuming the primary npm license covers all assets. Optional font repair uses **pdf-lib 1.17.1 MIT**.

| Distributed asset/runtime | Terms retained in the repository |
| --- | --- |
| PDF.js worker and own adapter | Apache-2.0. |
| Adobe CMaps | BSD-3-Clause in `vendor/pdf/cmaps/LICENSE`. |
| Foxit/PDFium standard fonts | BSD-3-Clause in `standard_fonts/LICENSE_FOXIT`. |
| Liberation Sans standard fonts | OFL-1.1 in `standard_fonts/LICENSE_LIBERATION`. |
| Noto Sans SC fallback font | OFL-1.1 in the font assets. |
| OpenJPEG JPEG 2000 decoder | BSD-2-Clause; PDF.js glue notice retained separately. |
| JBIG2 decoder | BSD-3-Clause and Apache-2.0 portions/glue notices. |
| qcms color conversion | MIT native library; PDF.js glue has a separate BSD-style notice. |

See [vendored PDF asset tree][pdf-assets] and the [global asset ledger][assets-ledger]. There is a version-attribution mismatch: the package pins `@fontsource-variable/noto-sans-sc` **5.3.1**, while the committed asset ledger describes **5.3.0**. Both use OFL, but the exact redistributed version should be reconciled before transferring the notices. The fonts are not Apache code; retain their notices and reserved-name/modification conditions if changing them.

No MuPDF/AGPL engine is involved in this PDF path. XPS is separately registered to the CAD package. CrispCloud already has PDF support, so the relevant decision is whether a particular search, rendering, range-loading or font-repair improvement fills a real gap.

### 8. Audio/video: browser playback and a narrow permissive MP4V fallback

The [media entry/source][media-index] recognizes MP4/WebM video and MP3/MPEG/WAV/OGG/OGA/OPUS/M4A/AAC/FLAC/WEBA audio. Native HTML media elements do the main decoding. The package does not provide a universal AVI/MKV/MOV/container or codec stack.

The [MP4V player][mp4v-code] and [native decoder boundary][mp4v-readme] implement a specific MPEG-4 Part 2 Simple Profile fallback when an MP4 has `mp4v` video and native playback fails. It renders decoded frames through modern worker/canvas/video-frame facilities; AAC audio can provide the clock. This is not a generic H.264/HEVC/FFmpeg software fallback.

AOSP PacketVideo source is Apache-2.0, pinned to **`e2f098935447ca4945946de5cb69db843fe3f003`** in [SOURCE.json][mp4v-source]. The [toolchain/native-link ledger][mp4v-ledger] records Emscripten **6.0.6**, reconstructed output matching the frozen JS/WASM, and actual linked archives: `libc.a`, `libclang_rt.builtins.a`, `libdlmalloc.a`. Its status is `verified-exact-artifact-native-link-inputs`.

Keep the AOSP notice plus generated Emscripten runtime MIT/NCSA notices, musl MIT material, compiler-rt Apache-2.0/LLVM exception, and allocator public-domain/CC0 material. Additional conservative SDK source notices in that ledger are explicitly distinguished from the linked archives. The compiler executable's license is not the issue; these linked runtime pieces are. The source expressly excludes FFmpeg/libav/Xvid and LGPL/GPL/AGPL decoder code.

Optional capabilities:

- [HLS streaming][hls-package]: locked **hls.js 1.7.3 Apache-2.0** (manifest range starts at 1.7.2).
- [MIDI inspection][midi-package]: **@tonejs/midi 2.0.28 MIT**, `midi-file 1.2.4 MIT`, `array-flatten 3.0.0 MIT`. It shows track/note/timing data, not synthesized sound.

CrispCloud's existing media stack recognizes many more native container routes. The narrow MP4V fallback or MIDI inspector can still be useful, but should be justified as specific missing behavior, not general media coverage.

### 9. Text, Markdown, XML, patch and Git bundle

The [text package][text-package] and [source code][text-code] cover plain/code display and formatting. Relevant exact locked versions are **highlight.js 11.12.0 BSD-3-Clause** (manifest range starts at 11.11.1), **marked 18.1.2 MIT**, **Prettier 3.9.10 MIT**, **@prettier/plugin-xml 3.4.2 MIT**, and **DOMPurify 3.4.17 MPL OR Apache**. The XML formatter's transitive emitted graph was not independently rebuilt in this audit; carry the actual bundle's retained license inventory rather than only these direct licenses.

Registered source-code suffixes include TXT, LRC, JSON/JSONC/JSON5, JS/MJS/CJS/JSX, CSS, JAVA, PY, HTML/HTM, TS/TSX, XML, LOG, VUE, YAML/YML, INI, SH/BASH, SQL, GO, RS, PHP, C/CPP/CC/H/HPP, CS, DIFF/PATCH, BUNDLE/BDL, IPYNB, TOML, PROTO, HCL, TEX, GV, HTTP, REACT, RB, SWIFT and KT. Markdown has MD/MARKDOWN. This registration does not turn IPYNB into executed notebooks or TEX into page typesetting; those are code/source views.

The optional [text-tools capability][texttools-package] uses **diff2html 3.4.56 MIT** for patch comparison and **pako 2.2.0 MIT AND Zlib** for Git bundle pack inspection. `diff2html`'s locked graph includes `diff 8.0.4 BSD-3-Clause` and a Hogan template dependency; the exact emitted transitive notice bundle was not separately verified here. This is a small remaining attribution task if this capability is selected, not evidence of a discovered copyleft blocker.

The optional XML profile engines have a dedicated [reviewed notice file][xml-notice]:

| Runtime | Version / pinned underlying source | Effective terms |
| --- | --- | --- |
| xslt-polyfill | 1.0.33, source `4c0603c4dc84c17a511816c703c7ce3b936aa56f` | BSD-3-Clause. |
| xmllint-wasm | 5.3.0 | MIT wrapper. |
| XSLT libxml2 | `c34742f3017f6d39f3e4ccae4f70172238160ef8` | MIT-style upstream Copyright. |
| XSD libxml2 | `eb0a2f2b91566384f378d870ffcd69c0a24162cc` | MIT-style upstream Copyright. |
| libxslt/libexslt | `923903c59d668af42e3144bc623c9190a0f65988` | MIT-style upstream Copyright. |
| zlib linked into xmllint | Exact version not identified in published npm metadata | Zlib; upstream notice included conservatively. |

These perform actual XSD validation and XSLT transformation in disposable bounded workers; they are more than generic XML syntax highlighting. External network access is blocked, and the XSLT WASM memory declaration is bounded before compilation. Upstream explicitly says the exact zlib version is not recovered, so do not present that closure as completely version-resolved. No dedicated SRT/VTT/ASS/SSA/SUB path was found; source fallback is not subtitle playback.

## Adoption order for these formats

A practical next selection is **CHM, then UMD**, followed by **comic navigation improvements** or **multi-page TIFF behavior** if current CrispCloud testing shows a gap. These provide identifiable user value with relatively contained licenses and implementation boundaries.

**MIDI inspection** and **XML schema/XSLT tools** are narrower optional additions. **DICOM** is a credible larger feature if the product wants a local basic image-stack viewer. **PDF/EPUB/email/general text/media** mostly overlap existing app capabilities, so select concrete enhancements after comparison instead of adding parallel engines.

Keep **HEIC's heic2any/libheif fallback excluded**, and leave the **prebuilt libarchive WASM unapproved pending exact native closure/notices**. Neither prevents importing independent Apache controllers or integrating against existing CrispCloud decoders. No new code, dependencies, remote changes or tests were made for this research.

## Evidence links

All File Viewer links below are immutable at the audited commit. External release-source links use exact npm release gitHead commits where recovered. The libheif license link is a current upstream legal statement, **not** a claimed identity of the unknown embedded libheif release.

[registry]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/core/src/registry/formats.generated.ts
[lock]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/pnpm-lock.yaml
[core-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/core/package.json
[chm-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/src/chm.ts
[chm-security]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/src/security.ts
[chm-notices]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/THIRD_PARTY_NOTICES.md
[chm-rust-notice]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/rust/NOTICE.md
[chm-rust-ledger]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/rust/THIRD_PARTY_LICENSES.md
[chm-profile]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/build-support/licenses/chm-native-profile.json
[ebook-index]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ebook/src/index.ts
[epub-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ebook/src/epub.ts
[epub-build]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ebook/scripts/build-epub-engine.mjs
[epub-policy]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ebook/scripts/epub-source-policy.mjs
[umd-parser]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ebook/src/umd/parser.ts
[fb2-parser]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ebook/src/fb2/parser.ts
[email-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/email/src/email.ts
[msg-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/email/src/msg.ts
[postal-source]: https://github.com/postalsys/postal-mime/tree/d96e2014e4caa72cf3424517cb89776d1bda8a2b
[msg-source]: https://github.com/HiraokaHyperTools/msgreader/tree/77b6ee07b2f96f39f8757525ae6f9f2ce1152458
[rtf-source]: https://github.com/HiraokaHyperTools/DeCompressRTF/tree/305aacbf1ea514436a1a5f078cdde2d03264e215
[archive-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/archive/src/archive.ts
[archive-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/archive/package.json
[archive-fallback]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/archive/src/archiveFallback.ts
[comic-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/archive/src/comicBook.ts
[libarchive-build]: https://github.com/nika-begiashvili/libarchivejs/blob/0989c1a6db20d030d793b1763e20d880068091bd/lib/tools/build.sh
[libarchive-docker]: https://github.com/nika-begiashvili/libarchivejs/blob/0989c1a6db20d030d793b1763e20d880068091bd/lib/tools/docker/Dockerfile
[image-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/image/src/image.ts
[tiff-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/image/src/tiff.ts
[image-notices]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/image/THIRD_PARTY_NOTICES.md
[heic-build]: https://github.com/alexcorvi/heic2any/blob/3222e591896ce72cf293a37f5a083cde5fc348c7/build/build.ts
[heic-libheif]: https://github.com/alexcorvi/heic2any/blob/3222e591896ce72cf293a37f5a083cde5fc348c7/src/libheif.js
[libheif-license]: https://github.com/strukturag/libheif/blob/master/COPYING
[dicom-index]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/dicom/src/index.ts
[dicom-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/dicom/src/dicom.ts
[dicom-notices]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/dicom/THIRD_PARTY_NOTICES.md
[dicom-ledger]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/dicom/THIRD_PARTY_LICENSES.json
[dicom-native]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/dicom/third-party/native-codecs/PROVENANCE.json
[pdf-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/pdf/package.json
[pdf-stage]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/pdf/scripts/stage-pdfjs-runtime.mjs
[pdf-assets]: https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/apps/viewer-demo/public/vendor/pdf
[assets-ledger]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/apps/viewer-demo/public/THIRD_PARTY_LICENSES.assets.json
[media-index]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/media/src/index.ts
[mp4v-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/media/src/mp4vPlayer.ts
[mp4v-readme]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/media/vendor/aosp-mp4v/README.md
[mp4v-source]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/media/vendor/aosp-mp4v/SOURCE.json
[mp4v-ledger]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/media/src/vendor/mp4v/TOOLCHAIN_THIRD_PARTY_LICENSES.json
[hls-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/capabilities/streaming-media/package.json
[midi-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/capabilities/midi/package.json
[text-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/text/package.json
[text-code]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/text/src/code.ts
[texttools-package]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/capabilities/text-tools/package.json
[xml-notice]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/text/licenses/xml-profiles/NOTICE.md
