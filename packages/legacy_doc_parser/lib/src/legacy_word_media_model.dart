// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'legacy_word_officeart_model.dart';
import 'legacy_word_revision_model.dart';
export 'legacy_word_officeart_model.dart';
export 'legacy_word_revision_model.dart';

/// Resolved visibility and tracked-change state at a media reference's CP.
/// Keeping this separate from the binary asset prevents reuse of a picture's
/// bytes from accepting a deletion or revealing a hidden occurrence.
class LegacyWordMediaPresentation {
  const LegacyWordMediaPresentation({
    this.hidden = false,
    this.inserted = false,
    this.deleted = false,
    this.revisionAuthor,
    this.revisionTime,
    this.insertionRevision,
    this.deletionRevision,
  });
  final bool hidden;
  final bool inserted;
  final bool deleted;
  final String? revisionAuthor;
  final DateTime? revisionTime;

  /// Separate provenance for insertion and deletion of this occurrence.
  /// Neither a shared asset nor the legacy compatibility author/date may
  /// replace the independently recorded metadata of overlapping revisions.
  final LegacyWordRevisionInfo? insertionRevision;
  final LegacyWordRevisionInfo? deletionRevision;
}

/// Resolved character-property span. CPs are document-global UTF-16 positions.
class LegacyWordMediaRun {
  const LegacyWordMediaRun({
    required this.startCp,
    required this.endCp,
    this.pictureLocation,
    this.special = false,
    this.object = false,
    this.ole2 = false,
    this.data = false,
    this.presentation = const LegacyWordMediaPresentation(),
  });
  final int startCp;
  final int endCp;
  final int? pictureLocation;
  final bool special;
  final bool object;
  final bool ole2;
  final bool data;
  final LegacyWordMediaPresentation presentation;
}

/// A precise location in an original compound-file stream. Offsets and lengths
/// identify stored bytes; a reconstructed compound payload has its own length.
class LegacyWordSourceReference {
  const LegacyWordSourceReference({
    required this.streamPath,
    required this.offset,
    required this.length,
    required this.structure,
    this.cp,
  });
  final String streamPath;
  final int offset;
  final int length;
  final String structure;
  final int? cp;
}

enum LegacyWordImageFormat { png, jpeg, tiff, dib, emf, wmf, pict, unknown }

/// Bounded structural inspection, not a claim that every GDI record was drawn.
class LegacyWordMetafileInfo {
  LegacyWordMetafileInfo({
    required this.bounds,
    required this.recordCount,
    required this.nativeEmbeddingAllowed,
    this.widthEmu,
    this.heightEmu,
    this.officeArtBounds,
    this.previewSvg,
    List<int> unsupportedPreviewRecords = const [],
  }) : unsupportedPreviewRecords = List.unmodifiable(unsupportedPreviewRecords);

  /// Device-coordinate canvas used for portable playback. This is distinct
  /// from OfficeArt's producer-dependent clipping/presentation rectangle.
  final LegacyWordVectorBounds bounds;
  final LegacyWordVectorBounds? officeArtBounds;
  final int recordCount;
  final int? widthEmu, heightEmu;

  /// Escape records stay inert; they are never forwarded to native rendering.
  final bool nativeEmbeddingAllowed;

  /// Generated fixed-tag SVG only when the bounded renderer supports every
  /// relevant record. Original XML, scripts, links and fonts are never copied.
  final String? previewSvg;
  final List<int> unsupportedPreviewRecords;
  bool get hasCompletePreview => previewSvg != null;
}

class LegacyWordImageAsset {
  LegacyWordImageAsset({
    required this.id,
    required this.format,
    required Uint8List bytes,
    required this.source,
    required this.officeArtArtifactId,
    this.metafile,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String id;
  final LegacyWordImageFormat format;
  final Uint8List bytes;
  final LegacyWordSourceReference source;
  final String officeArtArtifactId;
  final LegacyWordMetafileInfo? metafile;

  /// Reusable raster bytes or a structurally validated, escape-free EMF/WMF.
  /// This is native Office reuse; [LegacyWordMetafileInfo.previewSvg] records
  /// the separate, deliberately narrower portable rendering capability.
  bool get isRenderable =>
      format == LegacyWordImageFormat.png ||
      format == LegacyWordImageFormat.jpeg ||
      format == LegacyWordImageFormat.tiff ||
      ((format == LegacyWordImageFormat.emf ||
              format == LegacyWordImageFormat.wmf) &&
          metafile?.nativeEmbeddingAllowed == true);
  String get contentType => switch (format) {
    LegacyWordImageFormat.png => 'image/png',
    LegacyWordImageFormat.jpeg => 'image/jpeg',
    LegacyWordImageFormat.tiff => 'image/tiff',
    LegacyWordImageFormat.emf => 'image/x-emf',
    LegacyWordImageFormat.wmf => 'image/x-wmf',
    _ => 'application/octet-stream',
  };
  String get extension => switch (format) {
    LegacyWordImageFormat.png => 'png',
    LegacyWordImageFormat.jpeg => 'jpg',
    LegacyWordImageFormat.tiff => 'tif',
    LegacyWordImageFormat.emf => 'emf',
    LegacyWordImageFormat.wmf => 'wmf',
    _ => 'bin',
  };
}

/// An inline picture tied to U+0001 and CPicLocation, never image-carving order.
class LegacyWordPicture {
  const LegacyWordPicture({
    required this.id,
    required this.cp,
    required this.source,
    required this.officeArtArtifactId,
    this.imageId,
    this.widthTwips,
    this.heightTwips,
    this.cropTopFixed16 = 0,
    this.cropBottomFixed16 = 0,
    this.cropLeftFixed16 = 0,
    this.cropRightFixed16 = 0,
    this.storedExternalName,
    this.presentation = const LegacyWordMediaPresentation(),
    this.shapeDeleted = false,
    this.shape,
  });
  final String id;
  final int cp;
  final LegacyWordSourceReference source;
  final String officeArtArtifactId;
  final String? imageId;
  final int? widthTwips;
  final int? heightTwips;
  final int cropTopFixed16;
  final int cropBottomFixed16;
  final int cropLeftFixed16;
  final int cropRightFixed16;

  /// Descriptive source metadata only. It is never resolved or fetched.
  final String? storedExternalName;
  final LegacyWordMediaPresentation presentation;

  /// OfficeArt's deleted-shape bit, distinct from a tracked text deletion.
  /// The stored payload remains evidence and must not become an active shape.
  final bool shapeDeleted;
  final LegacyWordOfficeArtShape? shape;
}

class LegacyWordDrawing {
  const LegacyWordDrawing({
    required this.shapeId,
    required this.anchorCp,
    required this.headerStory,
    required this.leftTwips,
    required this.topTwips,
    required this.rightTwips,
    required this.bottomTwips,
    required this.horizontalOrigin,
    required this.verticalOrigin,
    required this.wrapMode,
    required this.wrapSide,
    required this.behindText,
    required this.anchorLocked,
    required this.source,
    this.officeArtArtifactId,
    this.imageId,
    this.textboxId,
    this.nextTextboxShapeId,
    this.presentation = const LegacyWordMediaPresentation(),
    this.shapeDeleted = false,
    this.cropTopFixed16 = 0,
    this.cropBottomFixed16 = 0,
    this.cropLeftFixed16 = 0,
    this.cropRightFixed16 = 0,
    this.shape,
  });
  final int shapeId;
  final int anchorCp;
  final bool headerStory;
  final int leftTwips;
  final int topTwips;
  final int rightTwips;
  final int bottomTwips;
  final int horizontalOrigin;
  final int verticalOrigin;
  final int wrapMode;
  final int wrapSide;
  final bool behindText;
  final bool anchorLocked;
  final LegacyWordSourceReference source;
  final String? officeArtArtifactId;
  final String? imageId;
  final int? textboxId;
  final int? nextTextboxShapeId;
  final LegacyWordMediaPresentation presentation;
  final bool shapeDeleted;
  final int cropTopFixed16;
  final int cropBottomFixed16;
  final int cropLeftFixed16;
  final int cropRightFixed16;
  final LegacyWordOfficeArtShape? shape;
}

class LegacyWordPreservedStream {
  LegacyWordPreservedStream({
    required this.path,
    required Uint8List bytes,
    this.metadata,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  /// Path relative to the preserved storage's root.
  final String path;
  final Uint8List bytes;
  final LegacyWordStorageMetadata? metadata;
}

class LegacyWordStorageMetadata {
  LegacyWordStorageMetadata({
    required this.path,
    required Uint8List clsid,
    required this.stateBits,
    this.created,
    this.modified,
    Uint8List? createdFiletime,
    Uint8List? modifiedFiletime,
  }) : clsid = Uint8List.fromList(clsid).asUnmodifiableView(),
       createdFiletime = createdFiletime == null
           ? null
           : Uint8List.fromList(createdFiletime).asUnmodifiableView(),
       modifiedFiletime = modifiedFiletime == null
           ? null
           : Uint8List.fromList(modifiedFiletime).asUnmodifiableView();

  /// Empty for the preserved root; otherwise relative to that root.
  final String path;
  final Uint8List clsid;
  final int stateBits;
  final DateTime? created;
  final DateTime? modified;
  final Uint8List? createdFiletime;
  final Uint8List? modifiedFiletime;
}

/// Original stream bytes plus a reconstructed CFB container. Reconstruction
/// changes allocation/directory layout; it is not the original container bytes.
class LegacyWordCompoundStorage {
  LegacyWordCompoundStorage({
    required this.sourcePath,
    required Uint8List bytes,
    required List<LegacyWordPreservedStream> streams,
    required List<LegacyWordStorageMetadata> storages,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       streams = List.unmodifiable(streams),
       storages = List.unmodifiable(storages);
  final String sourcePath;
  final Uint8List bytes;
  final List<LegacyWordPreservedStream> streams;
  final List<LegacyWordStorageMetadata> storages;
}

class LegacyWordEmbeddedObject {
  const LegacyWordEmbeddedObject({
    required this.id,
    required this.cp,
    required this.storage,
    this.progId,
    this.linked,
    this.canEmbed = false,
    this.presentation = const LegacyWordMediaPresentation(),
  });
  final String id;
  final int cp;
  final LegacyWordCompoundStorage storage;

  /// The original CompObj ProgID, when a bounded recognized record supplies it.
  final String? progId;

  /// Null means the original Ole record did not establish this information.
  final bool? linked;

  /// The field end is present and not a zombie, and the Ole record explicitly
  /// identifies an embedded object. Other stored objects remain inert evidence.
  final bool canEmbed;
  final LegacyWordMediaPresentation presentation;
}

class LegacyWordVbaProject {
  LegacyWordVbaProject({
    required this.id,
    required this.storage,
    required this.hasRequiredStreams,
    List<String> signatureArtifactIds = const [],
  }) : signatureArtifactIds = List.unmodifiable(signatureArtifactIds);
  final String id;
  final LegacyWordCompoundStorage storage;

  /// PROJECT plus VBA/dir and VBA/_VBA_PROJECT are present. This is structural
  /// completeness, not verification that macros compile or are safe to execute.
  final bool hasRequiredStreams;
  final List<String> signatureArtifactIds;
}

enum LegacyWordArtifactKind {
  officeArt,
  binaryData,
  documentSignature,
  vbaSignature,
  unreferencedObjectStorage,
}

class LegacyWordOpaqueArtifact {
  LegacyWordOpaqueArtifact({
    required this.id,
    required this.kind,
    required Uint8List bytes,
    required this.source,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String id;
  final LegacyWordArtifactKind kind;
  final Uint8List bytes;
  final LegacyWordSourceReference source;

  /// Signature artifacts are retained as evidence. No cryptographic validation
  /// or assertion that a copied signature authenticates converted output occurs.
  bool get signatureVerified => false;
}

enum LegacyWordMediaIssue {
  unsupportedImage,
  externalPictureNotFetched,
  missingDrawingShape,
  unsupportedDrawing,
  unreferencedObjectStorage,
  incompleteVbaProject,
  oleFieldMetadataIncomplete,

  /// pVertices.op omitted its six-byte IMsoArray header; exact counts proved it.
  recoveredVertexArrayLength,

  /// A constant one-entry BStore header covered multiple validated FBSEs.
  recoveredBlipStoreCount,
}

class LegacyWordMediaNotice {
  const LegacyWordMediaNotice(this.issue, this.source);
  final LegacyWordMediaIssue issue;
  final LegacyWordSourceReference source;
}

class LegacyWordMediaCatalog {
  const LegacyWordMediaCatalog()
    : assets = const [],
      pictures = const [],
      drawings = const [],
      embeddedObjects = const [],
      vbaProjects = const [],
      artifacts = const [],
      notices = const [];

  LegacyWordMediaCatalog.from({
    List<LegacyWordImageAsset> assets = const [],
    List<LegacyWordPicture> pictures = const [],
    List<LegacyWordDrawing> drawings = const [],
    List<LegacyWordEmbeddedObject> embeddedObjects = const [],
    List<LegacyWordVbaProject> vbaProjects = const [],
    List<LegacyWordOpaqueArtifact> artifacts = const [],
    List<LegacyWordMediaNotice> notices = const [],
  }) : assets = List.unmodifiable(assets),
       pictures = List.unmodifiable(pictures),
       drawings = List.unmodifiable(drawings),
       embeddedObjects = List.unmodifiable(embeddedObjects),
       vbaProjects = List.unmodifiable(vbaProjects),
       artifacts = List.unmodifiable(artifacts),
       notices = List.unmodifiable(notices);
  final List<LegacyWordImageAsset> assets;
  final List<LegacyWordPicture> pictures;
  final List<LegacyWordDrawing> drawings;
  final List<LegacyWordEmbeddedObject> embeddedObjects;
  final List<LegacyWordVbaProject> vbaProjects;
  final List<LegacyWordOpaqueArtifact> artifacts;
  final List<LegacyWordMediaNotice> notices;
}
