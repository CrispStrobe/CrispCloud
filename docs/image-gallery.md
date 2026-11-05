# Image gallery and tiles

CrispCloud's image workspace extends its existing file panels. It uses the
same local folders, browser folder handles, cloud connections and archive
inventory, with an image viewer and non-destructive batch exports.

## Open a view

Use **View** in the top toolbar, the per-panel menu's **Image gallery** or
**Tiles** command, or the native View menu. Each panel remembers its layout.

| Layout | Contents |
| --- | --- |
| List | Existing detailed or brief file list. |
| Icons | Mixed files and folders with adjustable image previews. |
| Tiles | Larger thumbnail alongside filename, type, size, date and catalog marks. |
| Gallery | Image candidates and navigable folders; documents and other files are hidden. |
| Columns | Existing column browser. |

The size slider changes thumbnail density. Fit preserves the entire image;
Fill crops only its on-screen thumbnail. The More menu controls filenames and
details. Folders, including the parent entry, stay available while filtering.
No directory scan or whole-library indexing is triggered by switching views.

## Find and select images

Search matches filename and catalog tags, with all entered words required.
Filters combine image format, minimum rating, color label, favorite status
and an inclusive **file modification date** range. This date is not an EXIF
capture-date filter. Sort supports natural filename order (`photo2` before
`photo10`), extension, modified date, file size and rating, in either direction.

Click a tile to select it. Ctrl/Cmd-click toggles a selection; Shift-click
selects a range in the visible sort order. Checkboxes are available for touch.
Select all and invert apply only to visible entries, excluding the parent
folder. Filtering clears selection marks on hidden entries, so subsequent
batch actions cannot silently affect hidden photographs.

| Gallery shortcut | Action |
| --- | --- |
| Arrow keys | Move horizontally or vertically through the tile grid. |
| Shift + arrows | Extend the visible range selection. |
| Ctrl/Cmd + arrows | Move the cursor without replacing marked selections. |
| Home / End | First / last visible item. |
| Page Up / Page Down | Move approximately one viewport. |
| Ctrl/Cmd + A | Select all visible entries. |
| Ctrl/Cmd + F | Focus gallery search. |
| Space / Insert | Toggle the cursor item's selection. |
| Enter / double-click | Open an image in the gallery viewer or navigate a folder. |
| 0–5 | Set the selected images' rating; 0 clears it. |
| F | Toggle favorites for the current image selection. |
| Escape | Clear marked selection. |

Typing in search and dialog inputs remains normal text input.

## Catalog annotations

**Catalog annotations** edits a single image or a selected batch. It supports
0–5 stars, six colors, favorites and up to 50 tags per image. Batch changes can
leave fields unchanged, append tags or replace the tag set.

These annotations are a **CrispCloud catalog on this device**. They do not
modify EXIF, IPTC or XMP in the original image, and they do not synchronize to
other devices. Export catalog creates JSON for the selected images, or all
visible images when nothing is marked.

Keys include storage identity so annotations from different accounts do not
share a filename-only key. Native local files use their paths. Cloud files use
their provider ID when available, otherwise their path. A path-based annotation
does not automatically follow a rename or move. Browser-granted folders and
connections without a complete stable account/endpoint identity are scoped to
the current session to avoid reusing another source's annotations or previews.
The settings database persists their records, but such records are not
automatically rebound to a later, unverifiable session.

## Viewer, slideshow and comparison

Open an image to use the fullscreen dialog with previous/next navigation,
filmstrip, fit, actual size, zoom and pan, an information sidebar, original-copy
export and display rotation/flips. Rotation and flips here change the view;
use **Edit image** for a saved pixel edit through CrispCloud's existing image
editor and its conflict checks.

The slideshow has a configurable interval and playback controls. Images load
with an error state if the original is unavailable; closing the viewer cancels
its playback timers. Select **two to four images** and choose Compare to view
them together, with linked pan/zoom or independent inspection.

| Viewer shortcut | Action |
| --- | --- |
| Left / Right, Home / End | Navigate the image sequence. |
| Space | Play/pause slideshow. |
| + / − | Zoom. |
| 0 / 1 | Fit / actual size. |
| R | Rotate the displayed image. |
| I | Show/hide image information. |
| F | Show/hide filmstrip. |
| Ctrl/Cmd + S | Save an original copy. |
| F4 | Hand off supported files to the existing editor. |
| Escape | Close the viewer. |

Image information includes dimensions, size, format, timestamps and inspected
EXIF fields where available. Catalog annotations are shown separately from
embedded metadata. Original-copy export retains original bytes, including
metadata; it does not export the rotated on-screen view.

## Batch conversion and contact sheets

**Convert / resize copies** prepares a ZIP containing JPEG or PNG copies. It
supports aspect-preserving bounds, optional upscaling, JPEG quality, quarter
turns, horizontal/vertical flips and brightness/contrast/saturation. Transparent
images are flattened on white when exporting JPEG. Exports bake orientation
and strip source metadata. Animated inputs export their first frame, clearly
reported in the result.

**Contact sheet** creates a PNG with configurable columns, thumbnail size and
optional filename captions. It uses marked images, or the visible image set
when nothing is marked. Images that cannot be decoded are reported individually.

Preparation is sequential with a progress indicator and cancellation. The
result lists successes and failures before **Save copy**. A canceled native
save picker keeps the prepared output available. Browser output is reported
as a download, not as a confirmed write to the source folder. No operation in
this export workflow overwrites originals.

### Resource bounds

| Resource | Default limit |
| --- | --- |
| Original image preview read | 64 MiB; SVG: 4 MiB. |
| Preview decoded pixels | 40 million pixels, including embedded SVG rasters. |
| Concurrent media loads | 3, with full-image requests prioritized. |
| Thumbnail memory cache | 32 MiB, also bounded by entry count. |
| Thumbnail disk cache | 256 MiB. |
| Batch conversion/contact sheet | 100 images. |
| Conversion source per image | 32 MiB / 40 million pixels. |
| Conversion aggregate source | 256 MiB / 400 million pixels. |
| Conversion output per image | 32 MiB / 16 million pixels. |
| Retained batch output | 64 MiB; ZIP has a separate final size bound. |
| Device export | 128 MiB. |

Oversized, corrupt, unsupported and disconnected images remain visible with a
clear failure/placeholder. Thumbnail requests use revision-aware cache keys,
deduplicate in-flight reads and prefer provider thumbnails when available.
Every remote original requires a known, acceptable file size before download,
including adapters that advertise streaming. Streaming readers stop at their
byte limit and receive progress guards; these checks do not change legacy
adapters that buffer internally. SVG previews reject linked images and nested
SVG payloads and count embedded raster dimensions toward the pixel limit.

Scrolling uses a lazy grid and bounded concurrent decoding. Thumbnail work
already queued by a tile can finish after that tile scrolls off screen; there
is no visibility-based cancellation of individual queued reads yet.

## File commands and source boundaries

Existing rename, copy, move, delete, context menus and cross-panel dragging are
available when their legacy routing agrees with the current verified file
source. The gallery does not infer storage from a pane's left/right label.
Archive members, unverified search results and source combinations unsupported
by the legacy mutation path remain view/export-only in the gallery. The image
editor independently enforces its stronger write-source and conflict checks.

## Relationship to XnView

The reference was XnView's documented thumbnail/fullscreen/filmstrip/slideshow,
four-image comparison, metadata, batch conversion and contact-sheet workflow:

- <https://www.xnview.com/en/xnview/>
- <https://www.xnview.com/en/faq/>

This is not full XnView format or catalog parity. Common platform raster codecs,
SVG and the existing Dart image library provide previews; supported fallback
decoders include formats such as TIFF, PSD, TGA and PNM. Camera RAW and formats
without a decoder can appear as image candidates and may have provider-supplied
thumbnails, but opening/converting the original is not promised.

Not included: hundreds of native codecs, RAW development, lossless JPEG
transforms, ICC proofing/conversion controls, XMP/IPTC writing or sidecar
round-tripping, hierarchical category indexing, perceptual duplicate search,
scanner integration, printing and a global background photo catalog. Existing
CrispCloud duplicate finding remains separate from this gallery.

Gallery/annotation/export chrome is English and German with the host's English
fallback; the viewer's strings cover all nine app languages.

## Verification

The focused regression suite covers catalog persistence/isolation/concurrent
edits, natural sorting and filters, visible selection and keyboard interaction,
source/account invalidation, bounded thumbnail reads/decoding, viewer controls,
export pixel results, cancellation/partial failures and device-export semantics.
Run with the repository's pinned Flutter SDK:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test test/gallery_models_test.dart test/gallery_catalog_service_test.dart \
  test/gallery_layout_persistence_test.dart \
  test/gallery_media_service_test.dart test/gallery_export_service_test.dart \
  test/gallery_device_export_test.dart test/gallery_viewer_strings_test.dart \
  test/thumbnail_service_test.dart test/archive_viewer_integration_test.dart \
  test/widget/gallery_browser_test.dart \
  test/widget/gallery_media_routing_test.dart test/widget/gallery_thumbnail_test.dart \
  test/widget/gallery_viewer_dialog_test.dart test/widget/gallery_export_dialog_test.dart
```

Use CI for the complete suite and platform builds. A Dart startup failure before
application code (for example, unavailable process stack mappings in a sandbox)
does not count as a successful test run.
