// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

const _evidenceRelationship = 'urn:legacy-doc-parser:relationships:evidence';

extension _WordMedia on _StructuredWordWriter {
  void _prepareMedia() {
    final media = document.media;
    if (media.assets.length > 4096 ||
        media.pictures.length > 20000 ||
        media.drawings.length > 20000 ||
        media.embeddedObjects.length > 4096 ||
        media.vbaProjects.length > 32 ||
        media.artifacts.length > 4096) {
      _tooComplex();
    }
    for (final asset in media.assets) {
      if (_mediaAssets.containsKey(asset.id)) {
        throw const FormatException('Duplicate Word image identity.');
      }
      _mediaAssets[asset.id] = asset;
    }
    for (final picture in media.pictures) {
      final owner = _storyAt(picture.cp);
      _preserveInk(picture.shape, {
        'pictureId': picture.id,
        'cp': picture.cp,
        'story': owner,
        'officeArtArtifactId': picture.officeArtArtifactId,
      });
      final asset = _mediaAssets[picture.imageId];
      if (owner == null ||
          !_displayPosition(picture.cp) ||
          asset == null ||
          !asset.isRenderable ||
          picture.shapeDeleted) {
        limitations.add(LegacyWordConversionLimitation.images);
        _evidenceRecords.add({
          'kind': 'picture',
          'id': picture.id,
          'cp': picture.cp,
          'imageId': picture.imageId,
          'source': _sourceMetadata(picture.source),
          'externalName': picture.storedExternalName,
          'shapeDeleted': picture.shapeDeleted,
          'reason': 'not rendered; no external resources are fetched',
        });
        continue;
      }
      if (picture.storedExternalName != null) {
        _evidenceRecords.add({
          'kind': 'pictureSourceName',
          'id': picture.id,
          'storedName': picture.storedExternalName,
          'source': _sourceMetadata(picture.source),
          'reason':
              'validated stored image used; external name was not fetched',
        });
      }
      _event(owner, picture.cp, 50, () => _picture(picture, asset));
    }
    final shapeIds = <(bool, int)>{};
    final textboxShapes = {
      for (final reference in document.textboxReferences)
        if (reference.shapeId != null)
          (reference.inHeaderFooter, reference.shapeId!),
    };
    final textboxStories = {
      for (final reference in document.textboxReferences)
        (reference.inHeaderFooter, reference.id),
    };
    for (final drawing in media.drawings) {
      if (!shapeIds.add((drawing.headerStory, drawing.shapeId))) {
        throw const FormatException('Duplicate Word drawing identity.');
      }
      final owner = _storyAt(drawing.anchorCp);
      _preserveInk(drawing.shape, {
        'shapeId': drawing.shapeId,
        'cp': drawing.anchorCp,
        'story': owner,
        'officeArtArtifactId': drawing.officeArtArtifactId,
      });
      final asset = _mediaAssets[drawing.imageId];
      if (textboxShapes.contains((drawing.headerStory, drawing.shapeId)) ||
          textboxStories.contains((
            drawing.headerStory,
            (drawing.textboxId ?? 0) >> 16,
          ))) {
        continue; // Emitted with its story below.
      }
      if (drawing.textboxId != null) {
        limitations.add(LegacyWordConversionLimitation.embeddedObjects);
        _evidenceRecords.add(
          _drawingMetadata(drawing)
            ..['reason'] = 'textbox drawing has no resolved text story',
        );
      }
      if (owner != null &&
          _displayPosition(drawing.anchorCp) &&
          drawing.imageId == null &&
          drawing.textboxId == null &&
          !drawing.shapeDeleted &&
          _validDrawing(drawing, allowLine: true) &&
          _canWriteShape(drawing.shape)) {
        _event(owner, drawing.anchorCp, 50, () => _shapeDrawing(drawing));
        continue;
      }
      if (owner == null ||
          !_displayPosition(drawing.anchorCp) ||
          asset == null ||
          !asset.isRenderable ||
          drawing.shapeDeleted ||
          !_validDrawing(drawing)) {
        limitations.add(LegacyWordConversionLimitation.embeddedObjects);
        if (drawing.imageId != null) {
          limitations.add(LegacyWordConversionLimitation.images);
        }
        _evidenceRecords.add(
          _drawingMetadata(drawing)
            ..['reason'] =
                'unrendered drawing; original OfficeArt retained when available',
        );
        continue;
      }
      _event(owner, drawing.anchorCp, 50, () => _drawing(drawing, asset));
    }
    for (final object in media.embeddedObjects) {
      final owner = _storyAt(object.cp);
      if (owner == null ||
          !_displayPosition(object.cp) ||
          !object.canEmbed ||
          object.linked != false) {
        limitations.add(LegacyWordConversionLimitation.embeddedObjects);
        _preserveEvidence('embeddedObject', object.storage.bytes, {
          'id': object.id,
          'cp': object.cp,
          'sourcePath': object.storage.sourcePath,
          'linked': object.linked,
          'canEmbed': object.canEmbed,
          'containerReconstructed': true,
          'reason':
              'inert; embedded-object identity was not positively established',
        });
        continue;
      }
      if (_embeddedParts.containsKey(object.id)) {
        throw const FormatException('Duplicate Word embedded-object identity.');
      }
      final path = 'word/embeddings/oleObject${_embeddedParts.length + 1}.bin';
      _embeddedParts[object.id] = path;
      _package.addBytes(
        path,
        'application/vnd.openxmlformats-officedocument.oleObject',
        object.storage.bytes,
      );
      _event(owner, object.cp, 50, () => _embeddedObject(object, path));
      _count('embeddedObjects');
      // The exact embedded CFB stream content is preserved. Its original visual
      // preview is not asserted to be recoverable from arbitrary OLE storages.
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
    final activateVba =
        format == LegacyWordOutputFormat.docm &&
        media.vbaProjects.length == 1 &&
        media.vbaProjects.single.hasRequiredStreams;
    for (final project in media.vbaProjects) {
      if (activateVba) {
        _package.addBytes(
          'word/vbaProject.bin',
          'application/vnd.ms-office.vbaProject',
          project.storage.bytes,
        );
        _package.relate(
          'word/document.xml',
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
          'vbaProject.bin',
        );
        _count('vbaProjects');
      } else {
        limitations.add(LegacyWordConversionLimitation.macrosSignatures);
        _preserveEvidence('vbaProject', project.storage.bytes, {
          'id': project.id,
          'sourcePath': project.storage.sourcePath,
          'hasRequiredStreams': project.hasRequiredStreams,
          'containerReconstructed': true,
          'reason': format == LegacyWordOutputFormat.docx
              ? 'DOCX does not contain active VBA'
              : 'a single structurally complete VBA project was not available',
        });
      }
    }
    final artifactIds = <String>{};
    for (final artifact in media.artifacts) {
      if (!artifactIds.add(artifact.id)) {
        throw const FormatException('Duplicate Word evidence identity.');
      }
      final signature =
          artifact.kind == LegacyWordArtifactKind.documentSignature ||
          artifact.kind == LegacyWordArtifactKind.vbaSignature;
      _preserveEvidence(artifact.kind.name, artifact.bytes, {
        'id': artifact.id,
        'source': _sourceMetadata(artifact.source),
        if (signature)
          'signatureValidity':
              'not verified; does not authenticate converted output',
      }, signature: signature);
      if (signature) {
        limitations.add(LegacyWordConversionLimitation.macrosSignatures);
      }
      if (artifact.kind == LegacyWordArtifactKind.unreferencedObjectStorage) {
        limitations.add(LegacyWordConversionLimitation.embeddedObjects);
      }
    }
    for (final notice in media.notices) {
      _evidenceRecords.add({
        'kind': 'notice',
        'issue': notice.issue.name,
        'source': _sourceMetadata(notice.source),
      });
      switch (notice.issue) {
        case LegacyWordMediaIssue.recoveredVertexArrayLength:
        case LegacyWordMediaIssue.recoveredBlipStoreCount:
          limitations.add(LegacyWordConversionLimitation.partialFormatting);
        case LegacyWordMediaIssue.unsupportedImage:
          limitations.add(LegacyWordConversionLimitation.images);
        case LegacyWordMediaIssue.externalPictureNotFetched:
          // The stored, positively identified BLIP is still usable. The
          // occurrence loop above reports missing/deleted/unsupported data.
          break;
        case LegacyWordMediaIssue.incompleteVbaProject:
          limitations.add(LegacyWordConversionLimitation.macrosSignatures);
        case LegacyWordMediaIssue.missingDrawingShape:
        case LegacyWordMediaIssue.unsupportedDrawing:
        case LegacyWordMediaIssue.unreferencedObjectStorage:
        case LegacyWordMediaIssue.oleFieldMetadataIncomplete:
          limitations.add(LegacyWordConversionLimitation.embeddedObjects);
      }
    }
  }

  void _preserveInk(
    LegacyWordOfficeArtShape? shape,
    Map<String, Object?> occurrence,
  ) {
    final ink = shape?.ink;
    if (ink == null) return;
    limitations.add(LegacyWordConversionLimitation.embeddedObjects);
    if (ink.annotation == true) {
      limitations.add(LegacyWordConversionLimitation.notesComments);
    }
    final bytes = ink.data;
    final metadata = <String, Object?>{
      ...occurrence,
      'payloadPropertyId': 0x0700,
      'booleanPropertyId': 0x073f,
      'annotation': ink.annotation,
      'hitTestInk': ink.hitTestInk,
      'renderShape': ink.renderShape,
      'renderInk': ink.renderInk,
      'discussionAnchor': shape!.discussionAnchor,
      'hasPayload': bytes != null,
      'format': bytes == null ? null : 'ISF',
      'headerStatus': ink.headerStatus?.name,
      'strokeSemanticsDecoded': false,
      'nativeInkEmitted': false,
      'reason': bytes == null
          ? 'ink properties retained without a stored ink payload'
          : 'inert ISF payload retained; pen-stroke semantics are not reconstructed',
    };
    if (bytes == null) {
      _evidenceRecords.add({'kind': 'officeArtInk', ...metadata});
    } else {
      _preserveEvidence('officeArtInk', bytes, metadata);
      _count('inkPayloads');
    }
  }

  String _imageRelation(LegacyWordImageAsset asset) {
    var path = _mediaParts[asset.id];
    if (path == null) {
      path = 'word/media/image${_mediaParts.length + 1}.${asset.extension}';
      _mediaParts[asset.id] = path;
      _package.addBytes(path, asset.contentType, asset.bytes);
      _count('images');
    }
    return _package.relate(
      _part,
      '$_relationshipNamespace/image',
      path.substring(5),
    );
  }

  void _picture(LegacyWordPicture picture, LegacyWordImageAsset asset) {
    var width = picture.widthTwips, height = picture.heightTwips;
    if (width == null || height == null || width <= 0 || height <= 0) {
      // Raster aspect and intended layout are distinct; do not guess from
      // pixels. A bounded placeholder size is an explicit layout limitation.
      width = height = 1440;
      limitations.add(LegacyWordConversionLimitation.partialFormatting);
    }
    if (width > 2000000 || height > 2000000) _tooComplex();
    final cx = width * 635, cy = height * 635;
    final id = ++_drawingId;
    _mediaStart(picture.presentation);
    _xml.add(
      '<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$id" name="Picture $id"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>',
    );
    _imageGraphic(
      asset,
      id,
      cx,
      cy,
      shape: picture.shape,
      transform: _imageTransform(picture.shape),
      crop: [
        picture.cropLeftFixed16,
        picture.cropTopFixed16,
        picture.cropRightFixed16,
        picture.cropBottomFixed16,
      ],
    );
    _xml.add('</wp:inline></w:drawing>');
    _mediaEnd(picture.presentation);
    _count('pictureReferences');
  }

  bool _validDrawing(LegacyWordDrawing drawing, {bool allowLine = false}) =>
      ((drawing.rightTwips > drawing.leftTwips &&
              drawing.bottomTwips > drawing.topTwips) ||
          (allowLine &&
              drawing.shape?.geometry?.preset == 'line' &&
              drawing.rightTwips >= drawing.leftTwips &&
              drawing.bottomTwips >= drawing.topTwips &&
              (drawing.rightTwips > drawing.leftTwips ||
                  drawing.bottomTwips > drawing.topTwips))) &&
      [
        drawing.leftTwips,
        drawing.topTwips,
        drawing.rightTwips,
        drawing.bottomTwips,
      ].every((value) => value.abs() <= 2000000) &&
      drawing.horizontalOrigin >= 0 &&
      drawing.horizontalOrigin <= 2 &&
      drawing.verticalOrigin >= 0 &&
      drawing.verticalOrigin <= 2 &&
      drawing.wrapMode >= 0 &&
      drawing.wrapMode <= 5 &&
      drawing.wrapSide >= 0 &&
      drawing.wrapSide <= 3;

  void _drawing(LegacyWordDrawing drawing, LegacyWordImageAsset asset) {
    final sourceWidth = (drawing.rightTwips - drawing.leftTwips) * 635;
    final sourceHeight = (drawing.bottomTwips - drawing.topTwips) * 635;
    final position = drawing.shape?.position;
    final transform = _imageTransform(
      drawing.shape,
      floatingAbsolute:
          (position?.horizontalMode ?? 0) == 0 &&
          (position?.verticalMode ?? 0) == 0 &&
          [
            position?.horizontalRelativeTo,
            position?.verticalRelativeTo,
          ].every((value) => value == null || (value >= 0 && value <= 3)),
    );
    final width = transform.swapsAxes ? sourceHeight : sourceWidth;
    final height = transform.swapsAxes ? sourceWidth : sourceHeight;
    final x = drawing.leftTwips * 635 + ((sourceWidth - width) / 2).round();
    final y = drawing.topTwips * 635 + ((sourceHeight - height) / 2).round();
    if (x < -0x80000000 ||
        x > 0x7fffffff ||
        y < -0x80000000 ||
        y > 0x7fffffff) {
      _tooComplex();
    }
    final id = ++_drawingId;
    _mediaStart(drawing.presentation);
    _xml.add(
      '<w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" '
      'simplePos="0" relativeHeight="$id" behindDoc="${drawing.behindText ? 1 : 0}" '
      'locked="${drawing.anchorLocked ? 1 : 0}" '
      'layoutInCell="${drawing.shape?.layoutInCell == false ? 0 : 1}" allowOverlap="1">'
      '<wp:simplePos x="0" y="0"/>',
    );
    _officeArtDrawingPosition(
      drawing,
      horizontalOffsetEmu: x,
      verticalOffsetEmu: y,
    );
    _xml.add('<wp:extent cx="$width" cy="$height"/>');
    if (drawing.wrapMode == 3) {
      _xml.add('<wp:wrapNone/>');
    } else if (drawing.wrapMode == 1) {
      _xml.add('<wp:wrapTopAndBottom/>');
    } else {
      if (drawing.wrapMode == 4 || drawing.wrapMode == 5) {
        // Exact tight/through polygons are preserved in OfficeArt evidence;
        // rectangular wrapping is the declared conversion approximation.
        limitations.add(LegacyWordConversionLimitation.partialFormatting);
      }
      final wrap = ['bothSides', 'left', 'right', 'largest'][drawing.wrapSide];
      _xml.add('<wp:wrapSquare wrapText="$wrap"/>');
    }
    _xml.add(
      '<wp:docPr id="$id" name="Drawing $id"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>',
    );
    _imageGraphic(
      asset,
      id,
      width,
      height,
      shape: drawing.shape,
      transform: transform,
      crop: [
        drawing.cropLeftFixed16,
        drawing.cropTopFixed16,
        drawing.cropRightFixed16,
        drawing.cropBottomFixed16,
      ],
    );
    _xml.add('</wp:anchor></w:drawing>');
    _mediaEnd(drawing.presentation);
    _count('drawingReferences');
  }

  void _imageGraphic(
    LegacyWordImageAsset asset,
    int id,
    int cx,
    int cy, {
    LegacyWordOfficeArtShape? shape,
    _ImageTransform transform = const _ImageTransform(),
    List<int> crop = const [0, 0, 0, 0],
  }) {
    final relation = _imageRelation(asset);
    _xml.add(
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="Image $id"/>'
      '<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$relation"/>',
    );
    if (crop.any((value) => value != 0)) {
      if (crop.any((value) => value.abs() > 655360)) _tooComplex();
      final values = crop
          .map((value) => (value * 100000 / 65536).round())
          .toList();
      _xml.add(
        '<a:srcRect l="${values[0]}" t="${values[1]}" r="${values[2]}" b="${values[3]}"/>',
      );
    }
    _xml.add(
      '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm${transform.attributes}><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>',
    );
    _imageAppearance(shape);
    _xml.add('</pic:spPr></pic:pic></a:graphicData></a:graphic>');
  }

  void _embeddedObject(LegacyWordEmbeddedObject object, String path) {
    final relation = _package.relate(
      _part,
      '$_relationshipNamespace/oleObject',
      path.substring(5),
    );
    final id = ++_drawingId;
    _mediaStart(object.presentation);
    // The source preview is unavailable. Keep a clearly labelled icon rather
    // than claiming a Content snapshot, and give ShapeID a real v:shape target.
    // MS-OI29500 2.1.1834 also limits ObjectID to an underscore plus int32.
    _xml.add(
      '<w:object w:dxaOrig="1440" w:dyaOrig="720">'
      '<v:shape id="_legacyObject$id" style="width:72pt;height:36pt" '
      'coordsize="21600,21600" path="m0,0l21600,0,21600,21600,0,21600xe" '
      'o:ole="t" o:oleicon="t" '
      'alt="Embedded object; original preview unavailable" '
      'fillcolor="#EEEEEE" strokecolor="#808080">'
      '<v:textbox><w:txbxContent><w:p><w:r><w:rPr><w:sz w:val="16"/>'
      '</w:rPr><w:t>Embedded object</w:t><w:br/>'
      '<w:t>Preview unavailable</w:t>'
      '</w:r></w:p></w:txbxContent></v:textbox></v:shape>'
      '<o:OLEObject Type="Embed" DrawAspect="Icon" ShapeID="_legacyObject$id" '
      'ObjectID="_$id" r:id="$relation"',
    );
    if (object.progId != null && object.progId!.isNotEmpty) {
      _xml.add(' ProgID="');
      _xml.text(object.progId!, attribute: true);
      _xml.add('"');
    }
    _xml.add('/></w:object>');
    _mediaEnd(object.presentation);
  }

  void _prepareTextboxes() {
    if (document.textboxReferences.length > 20000) _tooComplex();
    final drawings = <(bool, int), LegacyWordDrawing>{};
    final drawingStories = <(bool, int), LegacyWordDrawing>{};
    for (final drawing in document.media.drawings) {
      drawings[(drawing.headerStory, drawing.shapeId)] = drawing;
      final storyIndex = (drawing.textboxId ?? 0) >> 16;
      if (storyIndex > 0) {
        drawingStories.putIfAbsent((
          drawing.headerStory,
          storyIndex,
        ), () => drawing);
      }
    }
    final ids = <(bool, int)>{};
    WordHeaderTextboxAliases? headerAliases;
    for (final reference in document.textboxReferences) {
      if (!ids.add((reference.inHeaderFooter, reference.id))) {
        throw const FormatException('Duplicate Word textbox identity.');
      }
      final story = _stories[reference.storyId];
      if (story == null ||
          (story.kind != LegacyWordStoryKind.textbox &&
              story.kind != LegacyWordStoryKind.headerTextbox)) {
        throw const FormatException('Invalid Word textbox story.');
      }
      WordHeaderTextboxAliasPair? aliasPair;
      if (reference.headerAliases.isNotEmpty) {
        if (reference.anchors.length != 1 ||
            reference.headerAliases.length != 1) {
          throw const FormatException('Invalid Word header textbox alias.');
        }
        headerAliases ??= WordHeaderTextboxAliases(
          stories: document.stories,
          media: document.media,
          fields: document.fields,
          bookmarks: document.bookmarks,
          notes: document.noteReferences,
          comments: document.commentReferences,
        );
        aliasPair = headerAliases.resolve(reference, [
          ...reference.anchors,
          ...reference.headerAliases,
        ]);
        if (aliasPair == null ||
            aliasPair.primary != reference.anchors.single ||
            aliasPair.alias != reference.headerAliases.single) {
          throw const FormatException('Invalid Word header textbox alias.');
        }
        for (final occurrence in [aliasPair.primary, aliasPair.alias]) {
          final shape = drawings[(true, occurrence.shapeId)]!;
          if (!_displayPosition(occurrence.anchorCp) || !_validDrawing(shape)) {
            throw const FormatException(
              'Unsupported Word header textbox alias placement.',
            );
          }
        }
      }
      final drawing =
          drawings[(reference.inHeaderFooter, reference.shapeId)] ??
          drawingStories[(reference.inHeaderFooter, reference.id)];
      final cp = reference.anchorCp ?? drawing?.anchorCp;
      final owner = cp == null ? null : _storyAt(cp);
      if (owner == null ||
          !_displayPosition(cp!) ||
          drawing == null ||
          drawing.shapeDeleted ||
          !_validDrawing(drawing)) {
        limitations.add(LegacyWordConversionLimitation.embeddedObjects);
        // Serialize after all inline events have been prepared and sorted.
        _unplacedTextboxes.add((reference, story));
        continue;
      }
      final chain = reference.anchors.isEmpty
          ? [
              LegacyWordTextboxAnchor(
                shapeId: drawing.shapeId,
                anchorCp: cp,
                chainIndex: 0,
              ),
            ]
          : reference.anchors;
      if (chain.length > 4096) _tooComplex();
      final resolved = <(LegacyWordDrawing, int, String)>[];
      for (final anchor in chain) {
        final shape = drawings[(reference.inHeaderFooter, anchor.shapeId)];
        final owner = _storyAt(anchor.anchorCp);
        if (shape == null ||
            owner == null ||
            !_displayPosition(anchor.anchorCp) ||
            shape.shapeDeleted ||
            !_validDrawing(shape)) {
          resolved.clear();
          break;
        }
        resolved.add((shape, anchor.anchorCp, owner));
      }
      if (resolved.isEmpty) {
        limitations.add(LegacyWordConversionLimitation.embeddedObjects);
        _unplacedTextboxes.add((reference, story));
        continue;
      }
      for (var i = 0; i < resolved.length; i++) {
        final (shape, anchor, owner) = resolved[i];
        final first = i == 0;
        final nextShape = i + 1 < resolved.length
            ? resolved[i + 1].$1.shapeId
            : null;
        _event(
          owner,
          anchor,
          60,
          () => _textbox(
            reference,
            story,
            shape,
            first: first,
            nextShape: nextShape,
          ),
        );
      }
      if (aliasPair != null) {
        final alias = aliasPair.alias;
        final aliasShape = drawings[(true, alias.shapeId)]!;
        _event(
          aliasPair.aliasOwner.id,
          alias.anchorCp,
          60,
          () => _textbox(reference, story, aliasShape, first: true),
        );
        _evidenceRecords.add({
          'kind': 'headerTextboxAlias',
          'id': reference.id,
          'story': reference.storyId,
          'startCp': story.startCp,
          'endCp': story.endCp,
          'chainLength': reference.chainLength,
          'occurrences': [
            for (final (anchor, owner) in [
              (aliasPair.primary, aliasPair.primaryOwner),
              (aliasPair.alias, aliasPair.aliasOwner),
            ])
              {
                'shapeId': anchor.shapeId,
                'anchorCp': anchor.anchorCp,
                'chainIndex': anchor.chainIndex,
                'headerStory': owner.id,
                'headerType': owner.headerFooterType!.name,
                'sectionIndex': owner.sectionIndex,
              },
          ],
          'reason':
              'recovered separate normal/first header occurrences of one '
              'single-frame source text range; no text-flow link inferred',
        });
      }
      if (reference.chainLength > 1) {
        _evidenceRecords.add({
          'kind': 'textboxChain',
          'id': reference.id,
          'story': reference.storyId,
          'declaredLength':
              reference.declaredChainLength ?? reference.chainLength,
          'resolvedLength': reference.chainLength,
          'anchors': [
            for (final anchor in reference.anchors)
              {
                'shapeId': anchor.shapeId,
                'anchorCp': anchor.anchorCp,
                'chainIndex': anchor.chainIndex,
                'nextShapeId': anchor.nextShapeId,
              },
          ],
          'reason': 'linked editable text retained; exact reflow not claimed',
        });
      }
    }
  }

  void _mediaStart(LegacyWordMediaPresentation presentation) {
    final fallback = LegacyWordRevisionInfo(
      author: presentation.revisionAuthor,
      time: presentation.revisionTime,
    );
    if (presentation.inserted) {
      _revisionElementStart('ins', presentation.insertionRevision ?? fallback);
    }
    if (presentation.deleted) {
      _revisionElementStart('del', presentation.deletionRevision ?? fallback);
    }
    _xml.add('<w:r');
    if (presentation.inserted) {
      _revisionSaveAttribute('rsidR', presentation.insertionRevision?.saveId);
    }
    if (presentation.deleted) {
      _revisionSaveAttribute('rsidDel', presentation.deletionRevision?.saveId);
    }
    _xml.add('>');
    if (presentation.hidden) _xml.add('<w:rPr><w:vanish/></w:rPr>');
  }

  void _mediaEnd(LegacyWordMediaPresentation presentation) {
    _xml.add('</w:r>');
    if (presentation.deleted) _xml.add('</w:del>');
    if (presentation.inserted) _xml.add('</w:ins>');
  }

  void _preserveEvidence(
    String kind,
    Uint8List bytes,
    Map<String, Object?> metadata, {
    bool signature = false,
  }) {
    final path = 'word/evidence/artifact${_evidenceRecords.length + 1}.bin';
    _package.addBytes(path, 'application/octet-stream', bytes);
    _evidenceRecords.add({'kind': kind, 'part': path, ...metadata});
    _count('evidenceArtifacts');
    if (signature) {
      signatureEvidenceParts.add(path);
      _count('signatureEvidence');
    }
  }

  void _writeEvidence() {
    for (final entry in _inertStories.entries) {
      final story = _stories[entry.key]!;
      final evidence = _wordPart('body');
      final path = 'word/inertStoryEvidence${_evidenceRecords.length + 1}.xml';
      _withStory(story, path, evidence, () => _blocks(story.blocks));
      evidence.add('</w:body>');
      _package.addXml(path, 'application/xml', evidence);
      _evidenceRecords.add({
        'kind': 'inertStory',
        'story': story.id,
        'storyKind': story.kind.name,
        'part': path,
        'reason': entry.value,
      });
    }
    for (final (reference, story) in _unplacedTextboxes) {
      final evidence = _wordPart('txbxContent');
      final path = 'word/textboxEvidence${_evidenceRecords.length + 1}.xml';
      _withStory(story, path, evidence, () => _blocks(story.blocks));
      evidence.add('</w:txbxContent>');
      _package.addXml(path, 'application/xml', evidence);
      _evidenceRecords.add({
        'kind': 'textbox',
        'id': reference.id,
        'part': path,
        'story': story.id,
        'nextTextboxId': reference.nextTextboxId,
        'reason': 'source placement not established',
      });
    }
    // Non-renderable/unreferenced assets are never silently discarded, even if
    // a caller supplies a model without the original enclosing OfficeArt blob.
    for (final asset in document.media.assets) {
      if (!_mediaParts.containsKey(asset.id)) {
        _preserveEvidence('imageAsset', asset.bytes, {
          'id': asset.id,
          'format': asset.format.name,
          'source': _sourceMetadata(asset.source),
          'reason': 'asset not rendered at a validated source reference',
        });
      }
    }
    if (_evidenceRecords.isEmpty) return;
    if (_evidenceRecords.length > 20000) _tooComplex();
    final sink = _BoundedEvidenceSink();
    final encoder = JsonUtf8Encoder().startChunkedConversion(sink);
    encoder.add({
      'schema': 'legacy-doc-parser/evidence',
      'version': 1,
      'signatureValidityClaimed': false,
      'notice':
          'Original source evidence. It does not authenticate the converted package. '
          'Opaque objects and macros are not executed by conversion.',
      'records': _evidenceRecords,
    });
    encoder.close();
    final encoded = sink.takeBytes();
    _package.addBytes(
      'word/evidence/manifest.json',
      'application/json',
      encoded,
    );
    _package.relate(
      'word/document.xml',
      _evidenceRelationship,
      'evidence/manifest.json',
    );
    for (final record in _evidenceRecords) {
      final path = record['part'];
      if (path is String) {
        _package.relate(
          'word/document.xml',
          _evidenceRelationship,
          path.substring(5),
        );
      }
    }
  }
}

class _BoundedEvidenceSink implements Sink<List<int>> {
  final _bytes = BytesBuilder(copy: false);
  var _length = 0;
  @override
  void add(List<int> data) {
    _length += data.length;
    if (_length > kLegacyWordDocxXmlLimit) _tooComplex();
    _bytes.add(data);
  }

  @override
  void close() {}
  Uint8List takeBytes() => _bytes.takeBytes();
}

Map<String, Object?> _sourceMetadata(LegacyWordSourceReference source) => {
  'streamPath': source.streamPath,
  'offset': source.offset,
  'length': source.length,
  'structure': source.structure,
  'cp': source.cp,
};

Map<String, Object?> _drawingMetadata(LegacyWordDrawing drawing) => {
  'kind': 'drawing',
  'shapeId': drawing.shapeId,
  'anchorCp': drawing.anchorCp,
  'rectTwips': [
    drawing.leftTwips,
    drawing.topTwips,
    drawing.rightTwips,
    drawing.bottomTwips,
  ],
  'horizontalOrigin': drawing.horizontalOrigin,
  'verticalOrigin': drawing.verticalOrigin,
  if (drawing.shape?.groupShapeBooleanProperties case final group?) ...{
    'groupShapeBooleanProperties': group,
    'layoutInCell': drawing.shape!.layoutInCell,
  },
  if (drawing.shape?.position case final position?)
    'officeArtPosition': {
      'horizontalMode': position.horizontalMode,
      'verticalMode': position.verticalMode,
      'horizontalRelativeTo': position.horizontalRelativeTo,
      'verticalRelativeTo': position.verticalRelativeTo,
      'semantics': 'WordFoptZeroBased',
      'unsupportedProperties': drawing.shape!.unsupportedProperties,
    },
  'wrapMode': drawing.wrapMode,
  'wrapSide': drawing.wrapSide,
  'behindText': drawing.behindText,
  'anchorLocked': drawing.anchorLocked,
  'shapeDeleted': drawing.shapeDeleted,
  'cropFixed16': [
    drawing.cropLeftFixed16,
    drawing.cropTopFixed16,
    drawing.cropRightFixed16,
    drawing.cropBottomFixed16,
  ],
  'textboxId': drawing.textboxId,
  'imageId': drawing.imageId,
  'source': _sourceMetadata(drawing.source),
};
