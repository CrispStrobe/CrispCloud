// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

extension _WordMedia on _StructuredWordParser {
  LegacyWordMediaCatalog _readMediaCatalog(List<LegacyWordMediaRun> runs) =>
      _WordMediaReader(source).read(runs);
}

/// Follows documented references only: CPicLocation/PICF, FIB OfficeArt and
/// FSPA, ObjectPool names, the Macros project root and named signature stores.
class _WordMediaReader {
  _WordMediaReader(this.source);
  static const _byteLimit = 64 * 1024 * 1024;
  static const _itemLimit = 4096;
  final _BinarySource source;
  final assets = <LegacyWordImageAsset>[];
  final pictures = <LegacyWordPicture>[];
  final drawings = <LegacyWordDrawing>[];
  final objects = <LegacyWordEmbeddedObject>[];
  final projects = <LegacyWordVbaProject>[];
  final artifacts = <LegacyWordOpaqueArtifact>[];
  final notices = <LegacyWordMediaNotice>[];
  final _artifactIds = <String, String>{};
  final _pictures = <int, _PictureData>{};
  final _storageCache = <int, LegacyWordCompoundStorage>{};
  final _streamCache = <int, Uint8List>{};
  final _referencedObjects = <int>{};
  final _shapes = <(bool, int), _DrawingShape>{};
  final _blipStore = <_ArtRecord>[];
  final _blipAssets = <int, String?>{};
  final _drawingDefaults = _OfficeArtProperties();
  var _geometryPoints = 0;
  var _geometryCommands = 0;
  final _fieldEligibility = <int, bool>{};
  var _fieldTablesRead = false;
  var _retainedBytes = 0;
  var _items = 0;
  var _records = 0;
  String? _drawingArtifact;
  late final List<LegacyWordMediaRun> _mediaRuns;

  String get _tablePath =>
      (source.word.u16(10) & 0x0200) != 0 ? '1Table' : '0Table';

  LegacyWordMediaCatalog read(List<LegacyWordMediaRun> runs) {
    _mediaRuns = List.of(runs)..sort((a, b) => a.startCp.compareTo(b.startCp));
    var previousEnd = 0;
    for (final run in _mediaRuns) {
      if (run.startCp < previousEnd ||
          run.endCp < run.startCp ||
          run.endCp > source.totalLength) {
        throw const FormatException('Invalid Word media character range.');
      }
      previousEnd = run.endCp;
    }
    _readOfficeArt();
    _readAnchors(header: false);
    _readAnchors(header: true);
    var examined = 0;
    for (final run in _mediaRuns) {
      if (!run.special) continue;
      for (var cp = run.startCp; cp < run.endCp; cp++) {
        if (++examined > 8 * 1024 * 1024) {
          throw const FormatException(
            'Word media references exceed their limit.',
          );
        }
        final unit = source.unitAt(cp);
        if (unit == 1 && run.pictureLocation != null) {
          if (run.data) {
            _readBinaryData(cp, run.pictureLocation!);
          } else {
            _readPicture(cp, run.pictureLocation!, run.presentation);
          }
        } else if (unit == 0x14 && run.ole2 && run.pictureLocation != null) {
          _readObject(cp, run.pictureLocation!, run.presentation);
        }
      }
    }
    _readSignatures();
    _readProjects();
    _preserveUnreferencedObjects();
    return LegacyWordMediaCatalog.from(
      assets: assets,
      pictures: pictures,
      drawings: drawings,
      embeddedObjects: objects,
      vbaProjects: projects,
      artifacts: artifacts,
      notices: notices,
    );
  }

  LegacyWordMediaRun? _runAt(int cp) {
    var low = 0, high = _mediaRuns.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_mediaRuns[middle].endCp <= cp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == _mediaRuns.length || _mediaRuns[low].startCp > cp) return null;
    return _mediaRuns[low];
  }

  void _item() {
    if (++_items > _itemLimit) {
      throw const FormatException('Word media exceeds the item limit.');
    }
  }

  void _retain(int count) {
    if (count < 0 || count > _byteLimit - _retainedBytes) {
      throw const FormatException(
        'Word media exceeds the preserved-byte limit.',
      );
    }
    _retainedBytes += count;
  }

  LegacyWordSourceReference _reference(
    String path,
    int offset,
    int length,
    String structure, {
    int? cp,
  }) => LegacyWordSourceReference(
    streamPath: path,
    offset: offset,
    length: length,
    structure: structure,
    cp: cp,
  );

  String _artifact(
    LegacyWordArtifactKind kind,
    Uint8List bytes,
    LegacyWordSourceReference reference,
  ) {
    final key =
        '${kind.name}:${reference.streamPath}:'
        '${reference.offset}:${reference.length}:${reference.structure}';
    final old = _artifactIds[key];
    if (old != null) return old;
    _item();
    _retain(bytes.length);
    final id = 'artifact-${artifacts.length + 1}';
    artifacts.add(
      LegacyWordOpaqueArtifact(
        id: id,
        kind: kind,
        bytes: bytes,
        source: reference,
      ),
    );
    return _artifactIds[key] = id;
  }

  void _notice(
    LegacyWordMediaIssue issue,
    LegacyWordSourceReference reference,
  ) {
    _item();
    notices.add(LegacyWordMediaNotice(issue, reference));
  }

  _ArtRecord _record(
    _Bytes input,
    int start,
    int end,
    String path,
    int base, [
    int depth = 0,
  ]) {
    if (++_records > 50000 || depth > 32) {
      throw const FormatException(
        'OfficeArt records exceed their complexity limit.',
      );
    }
    if (start < 0 || end > input.length || start > end - 8) {
      throw const FormatException('Truncated OfficeArt record header.');
    }
    final flags = input.u16(start);
    final size = input.u32(start + 4);
    if (size > end - start - 8) {
      throw const FormatException(
        'OfficeArt record exceeds its referenced extent.',
      );
    }
    final recordEnd = start + 8 + size;
    final children = <_ArtRecord>[];
    if ((flags & 15) == 15) {
      var cursor = start + 8;
      while (cursor < recordEnd) {
        final child = _record(input, cursor, recordEnd, path, base, depth + 1);
        children.add(child);
        cursor = child.end;
      }
    }
    return _ArtRecord(
      input,
      start,
      recordEnd,
      flags & 15,
      flags >> 4,
      input.u16(start + 2),
      path,
      base,
      children,
    );
  }

  _OfficeArtProperties _properties(_ArtRecord node) {
    if (node.type != 0xf00b && node.type != 0xf121 && node.type != 0xf122) {
      return _OfficeArtProperties();
    }
    final count = node.instance;
    final fixed = count * 6;
    final input = node.data;
    input.require(0, fixed);
    var extra = fixed;
    final result = _OfficeArtProperties();
    final ids = <int>{};
    for (var i = 0; i < count; i++) {
      final opid = input.u16(i * 6), value = input.u32(i * 6 + 2);
      final id = opid & 0x3fff;
      if (!ids.add(id)) {
        throw const FormatException('Duplicate OfficeArt property identifier.');
      }
      if (id >= 0x0384 && id <= 0x0387 && (opid & 0x4000) != 0) {
        throw const FormatException(
          'OfficeArt wrap distance cannot reference a BLIP.',
        );
      }
      if (id == 0x01cd && (opid & 0x4000) != 0) {
        throw const FormatException(
          'OfficeArt line style cannot reference a BLIP.',
        );
      }
      if ((opid & 0x8000) != 0) {
        var size = value;
        if (id == 0x0145 && value != 0) {
          // LibreOffice's native DOC writer stores pVertices.op excluding the
          // six-byte IMsoArray header, unlike its other complex properties.
          // Recognize only an exact element-size/count match within this FOPT.
          input.require(extra, 6);
          final count = input.u16(extra), element = input.u16(extra + 4);
          final width = element == 0xfff0 ? 4 : element;
          if ((element == 8 || element == 0xfff0) && count * width == value) {
            size += 6;
            _notice(
              LegacyWordMediaIssue.recoveredVertexArrayLength,
              node.reference('OfficeArtFOPT/pVertices'),
            );
          }
        }
        result.complex[id] = input.slice(extra, size);
        extra += size;
      } else {
        result.values[id] = value;
      }
    }
    if (extra != input.length) {
      throw const FormatException('Unexpected OfficeArt property data.');
    }
    return result;
  }

  _DrawingShape _shape(_ArtRecord node, String artifactId) {
    if (node.type != 0xf004 || node.version != 15) {
      throw const FormatException('Expected an OfficeArt shape container.');
    }
    final props = _OfficeArtProperties()..addAll(_drawingDefaults);
    int? shapeId;
    int? textbox;
    var flags = 0;
    var type = 0;
    for (final child in node.children) {
      if (child.type == 0xf00a) {
        if (shapeId != null || child.data.length != 8 || child.version != 2) {
          throw const FormatException(
            'Invalid or duplicate OfficeArt shape identifier.',
          );
        }
        shapeId = child.data.u32(0);
        flags = child.data.u32(4);
        type = child.instance;
      } else if (child.type == 0xf00b ||
          child.type == 0xf121 ||
          child.type == 0xf122) {
        props.addAll(_properties(child));
      } else if (child.type == 0xf00d) {
        if (child.data.length != 4 || textbox != null) {
          throw const FormatException('Invalid OfficeArt textbox identifier.');
        }
        textbox = child.data.u32(0);
      }
    }
    if (shapeId == null) {
      throw const FormatException('OfficeArt shape has no identifier.');
    }
    final propertyTextbox = props.values[0x0080];
    if (textbox != null &&
        propertyTextbox != null &&
        textbox != propertyTextbox) {
      throw const FormatException('Conflicting OfficeArt textbox identifiers.');
    }
    final reader = _OfficeArtShapeReader(props, type, flags);
    // Validate and budget the unwrapped ink before its immutable model copy.
    // The original OfficeArt artifact is separately included in this budget.
    _retain(reader.inkByteLength);
    final model = reader.read();
    _geometryPoints += reader.pointCount;
    _geometryCommands +=
        (model.geometry?.path.length ?? 0) +
        (model.geometry?.editingHints.length ?? 0);
    if (_geometryPoints > 100000 || _geometryCommands > 100000) {
      throw const FormatException(
        'OfficeArt geometry exceeds its complexity limit.',
      );
    }
    if ((flags & 8) != 0 ||
        model.unsupportedProperties.isNotEmpty ||
        (model.geometry == null && type != 75 && (flags & 1) == 0)) {
      _notice(
        LegacyWordMediaIssue.unsupportedDrawing,
        node.reference('OfficeArtSpContainer'),
      );
    }
    return _DrawingShape(
      shapeId,
      props.values,
      textbox,
      artifactId,
      flags,
      model,
    );
  }

  void _readOfficeArt() {
    final (offset, length) = source.pair(50);
    if (length == 0) return;
    final bytes = source.table.slice(offset, length);
    final input = _Bytes(bytes);
    final group = _record(input, 0, length, _tablePath, offset);
    if (group.type != 0xf000 || group.version != 15) {
      throw const FormatException('Invalid OfficeArt drawing-group container.');
    }
    final artifact = _drawingArtifact = _artifact(
      LegacyWordArtifactKind.officeArt,
      bytes,
      _reference(_tablePath, offset, length, 'OfficeArtContent'),
    );
    var hasStore = false;
    for (final child in group.children) {
      if (child.type == 0xf001) {
        final countMismatch = child.children.length != child.instance;
        // LibreOffice's WriteBlibStoreContainer writes recInstance=1 even
        // when it writes multiple FBSEs. Recover only its bounded delayed
        // entry form, after the entire record array has validated by length.
        final recoverCount =
            countMismatch &&
            child.version == 15 &&
            child.instance == 1 &&
            child.children.length >= 2 &&
            child.children.length <= 4095 &&
            child.children.every(
              (entry) =>
                  entry.type == 0xf007 &&
                  entry.version == 2 &&
                  entry.data.length == 36 &&
                  entry.data.u8(33) == 0 &&
                  entry.data.u32(24) > 0 &&
                  entry.data.u32(28) != 0xffffffff &&
                  (entry.instance == entry.data.u8(0) ||
                      entry.instance == entry.data.u8(1)),
            );
        if (hasStore ||
            child.version != 15 ||
            (countMismatch && !recoverCount)) {
          throw const FormatException('Invalid OfficeArt BLIP store.');
        }
        hasStore = true;
        _blipStore.addAll(child.children);
        if (recoverCount) {
          // Prevalidate every recovered entry, including any unreferenced
          // slot, through the ordinary delayed-BLIP size, offset and payload
          // reader. Cached results retain the existing media byte budgets.
          for (var index = 1; index <= _blipStore.length; index++) {
            _globalImage(index);
          }
          _notice(
            LegacyWordMediaIssue.recoveredBlipStoreCount,
            child.reference('OfficeArtBStoreContainer/recInstance'),
          );
        }
      } else {
        _drawingDefaults.addAll(_properties(child));
      }
    }
    var cursor = group.end;
    final seenDrawing = <int>{};
    while (cursor < length) {
      final label = input.u8(cursor++);
      if (label > 1 || !seenDrawing.add(label)) {
        throw const FormatException('Invalid or duplicate Word drawing story.');
      }
      final drawing = _record(input, cursor, length, _tablePath, offset);
      if (drawing.type != 0xf002 || drawing.version != 15) {
        throw const FormatException('Invalid OfficeArt drawing container.');
      }
      void visit(_ArtRecord node) {
        if (node.type == 0xf004) {
          final shape = _shape(node, artifact);
          if (_shapes.containsKey((label == 1, shape.id))) {
            throw const FormatException(
              'Duplicate OfficeArt shape identifier.',
            );
          }
          _shapes[(label == 1, shape.id)] = shape;
        } else {
          for (final child in node.children) {
            visit(child);
          }
        }
      }

      visit(drawing);
      cursor = drawing.end;
    }
  }

  void _readAnchors({required bool header}) {
    final (offset, length) = source.pair(header ? 41 : 40);
    if (length == 0) return;
    if (length < 34 || (length - 4) % 30 != 0) {
      throw const FormatException('Invalid Word drawing-anchor table.');
    }
    final count = (length - 4) ~/ 30;
    if (count > _itemLimit) {
      throw const FormatException('Word drawing anchors exceed their limit.');
    }
    final raw = source.table.slice(offset, length);
    final input = _Bytes(raw);
    _artifact(
      LegacyWordArtifactKind.officeArt,
      raw,
      _reference(
        _tablePath,
        offset,
        length,
        header ? 'PlcfSpaHdr' : 'PlcfSpaMom',
      ),
    );
    final storyLength = header ? source.storyLengths[1] : source.bodyLength;
    final globalStart = header ? source.bodyLength + source.storyLengths[0] : 0;
    final records = (count + 1) * 4;
    var lastCp = -1;
    for (var i = 0; i < count; i++) {
      _item();
      final cp = input.u32(i * 4);
      final run = _runAt(globalStart + cp);
      if (cp <= lastCp ||
          cp >= storyLength ||
          run?.special != true ||
          source.unitAt(globalStart + cp) != 8) {
        throw const FormatException('Invalid Word drawing-anchor character.');
      }
      lastCp = cp;
      final record = records + i * 26;
      final shapeId = input.u32(record);
      final flags = input.u16(record + 20);
      final bx = (flags >> 1) & 3, by = (flags >> 3) & 3;
      final wrap = (flags >> 5) & 15, side = (flags >> 9) & 15;
      if (bx > 2 ||
          by > 2 ||
          wrap > 5 ||
          ((wrap != 1 && wrap != 3) && side > 3) ||
          (flags & 0x2000) != 0) {
        throw const FormatException('Invalid Word drawing-anchor layout.');
      }
      final reference = _reference(
        _tablePath,
        offset + record,
        26,
        'Spa',
        cp: globalStart + cp,
      );
      final shape = _shapes[(header, shapeId)];
      if (shape == null) {
        _notice(LegacyWordMediaIssue.missingDrawingShape, reference);
      }
      final imageIndex = shape?.properties[0x0104];
      drawings.add(
        LegacyWordDrawing(
          shapeId: shapeId,
          anchorCp: globalStart + cp,
          headerStory: header,
          leftTwips: input.i32(record + 4),
          topTwips: input.i32(record + 8),
          rightTwips: input.i32(record + 12),
          bottomTwips: input.i32(record + 16),
          horizontalOrigin: bx,
          verticalOrigin: by,
          wrapMode: wrap,
          wrapSide: wrap == 1 || wrap == 3 ? 0 : side,
          behindText: wrap == 3 && (flags & 0x4000) != 0,
          anchorLocked: (flags & 0x8000) != 0,
          source: reference,
          officeArtArtifactId: shape?.artifactId,
          imageId: imageIndex == null || imageIndex == 0
              ? null
              : _globalImage(imageIndex),
          textboxId: shape?.textboxId ?? shape?.properties[0x0080],
          nextTextboxShapeId: shape?.properties[0x008a],
          presentation: run!.presentation,
          shapeDeleted: shape?.deleted ?? false,
          shape: shape?.model,
          cropTopFixed16: (shape?.properties[0x0100] ?? 0).toSigned(32),
          cropBottomFixed16: (shape?.properties[0x0101] ?? 0).toSigned(32),
          cropLeftFixed16: (shape?.properties[0x0102] ?? 0).toSigned(32),
          cropRightFixed16: (shape?.properties[0x0103] ?? 0).toSigned(32),
        ),
      );
    }
    if (input.u32(count * 4) <= lastCp) {
      throw const FormatException(
        'Invalid final Word drawing-anchor position.',
      );
    }
  }

  String? _globalImage(int oneBased) {
    if (oneBased < 1 || oneBased > _blipStore.length) {
      throw const FormatException('Word drawing references a missing BLIP.');
    }
    if (_blipAssets.containsKey(oneBased)) return _blipAssets[oneBased];
    return _blipAssets[oneBased] = _fileBlock(
      _blipStore[oneBased - 1],
      _drawingArtifact!,
    );
  }

  void _readPicture(
    int cp,
    int offset,
    LegacyWordMediaPresentation presentation,
  ) {
    _item();
    var picture = _pictures[offset];
    if (picture == null) {
      final data = source.data;
      final length = data.i32(offset);
      if (length < 68 || data.u16(offset + 4) != 68) {
        throw const FormatException('Invalid Word picture header.');
      }
      final raw = data.slice(offset, length);
      final input = _Bytes(raw);
      final reference = _reference(
        'Data',
        offset,
        length,
        'PICFAndOfficeArtData',
        cp: cp,
      );
      final artifact = _artifact(
        LegacyWordArtifactKind.officeArt,
        raw,
        reference,
      );
      final width = input.i16(28), height = input.i16(30);
      if (width <= 0 || height <= 0) {
        throw const FormatException('Invalid Word picture dimensions.');
      }
      final scaledWidth = width * input.u16(32);
      final scaledHeight = height * input.u16(34);
      // PICMID gives a scale in tenths of a percent. Check the exact ratio
      // before quantizing, so rounding cannot admit an out-of-range size.
      if (scaledWidth < 15000 ||
          scaledWidth > 31680000 ||
          scaledHeight < 15000 ||
          scaledHeight > 31680000) {
        throw const FormatException(
          'Word picture dimensions exceed their limits.',
        );
      }
      // Word binary picture layout is represented in integer twips. The
      // independently measured native PICMID controls truncate positive
      // fractional twips, including exact halves; nearest rounding grows
      // common scaled EMF frames by one twip. See doc/picture-scaling.md.
      final displayWidth = scaledWidth ~/ 1000;
      final displayHeight = scaledHeight ~/ 1000;
      var cursor = 68;
      String? externalName;
      final mappingMode = input.u16(6);
      if (mappingMode != 0x64 && mappingMode != 0x66) {
        throw const FormatException('Unsupported Word picture mapping mode.');
      }
      if (mappingMode == 0x66) {
        final count = input.u8(cursor++);
        externalName = String.fromCharCodes(input.slice(cursor, count));
        cursor += count;
        _notice(LegacyWordMediaIssue.externalPictureNotFetched, reference);
      }
      final shapeRecord = _record(input, cursor, input.length, 'Data', offset);
      final shape = _shape(shapeRecord, artifact);
      cursor = shapeRecord.end;
      final blocks = <_ArtRecord>[];
      while (cursor < input.length) {
        final block = _record(input, cursor, input.length, 'Data', offset);
        if (block.type != 0xf007 &&
            (block.type < 0xf018 || block.type > 0xf117)) {
          throw const FormatException('Unexpected inline Word picture record.');
        }
        blocks.add(block);
        cursor = block.end;
      }
      // Multiple inline BLIPs can supply picture/fill/line properties. Until
      // every such property is mapped, preserve the exact record rather than
      // silently picking the first file as the displayed picture.
      final image = blocks.length == 1 && shape.properties.containsKey(0x0104)
          ? _fileBlock(blocks.single, artifact)
          : null;
      if (image == null) {
        _notice(LegacyWordMediaIssue.unsupportedImage, reference);
      }
      picture = _PictureData(
        reference,
        artifact,
        image,
        displayWidth,
        displayHeight,
        shape.properties,
        externalName,
        shape.deleted,
        shape.model,
      );
      _pictures[offset] = picture;
    }
    pictures.add(
      LegacyWordPicture(
        id: 'picture-$cp',
        cp: cp,
        source: _reference(
          picture.source.streamPath,
          picture.source.offset,
          picture.source.length,
          picture.source.structure,
          cp: cp,
        ),
        officeArtArtifactId: picture.artifactId,
        imageId: picture.imageId,
        widthTwips: picture.width,
        heightTwips: picture.height,
        cropTopFixed16: (picture.properties[0x0100] ?? 0).toSigned(32),
        cropBottomFixed16: (picture.properties[0x0101] ?? 0).toSigned(32),
        cropLeftFixed16: (picture.properties[0x0102] ?? 0).toSigned(32),
        cropRightFixed16: (picture.properties[0x0103] ?? 0).toSigned(32),
        storedExternalName: picture.externalName,
        presentation: presentation,
        shapeDeleted: picture.deleted,
        shape: picture.shape,
      ),
    );
  }

  String? _fileBlock(_ArtRecord node, String artifact) {
    if (node.type != 0xf007) return _blip(node, artifact);
    final input = node.data;
    input.require(0, 36);
    if (node.version != 2) {
      throw const FormatException('Invalid OfficeArt BLIP entry version.');
    }
    final nameSize = input.u8(33), size = input.u32(20);
    if (nameSize.isOdd || nameSize > 254) {
      throw const FormatException('Invalid OfficeArt BLIP name size.');
    }
    final content = 36 + nameSize;
    input.require(0, content);
    if (content < input.length) {
      final embedded = _record(
        input,
        content,
        input.length,
        node.path,
        node.absoluteStart + 8,
      );
      if (embedded.end != input.length ||
          embedded.end - embedded.start != size) {
        throw const FormatException(
          'Inconsistent embedded OfficeArt BLIP size.',
        );
      }
      return _blip(embedded, artifact);
    }
    if (input.u32(24) == 0) return null;
    final offset = input.u32(28);
    if (offset == 0xffffffff || size < 8) {
      throw const FormatException('Invalid delayed OfficeArt BLIP reference.');
    }
    source.word.require(offset, size);
    final delayed = _record(
      source.word,
      offset,
      offset + size,
      'WordDocument',
      0,
    );
    if (delayed.end != offset + size) {
      throw const FormatException('Inconsistent delayed OfficeArt BLIP size.');
    }
    final delayedArtifact = _artifact(
      LegacyWordArtifactKind.officeArt,
      source.word.slice(offset, size),
      delayed.reference('OfficeArtBlip'),
    );
    return _blip(delayed, delayedArtifact);
  }

  String? _blip(_ArtRecord node, String artifact) {
    _item();
    var format = switch (node.type) {
      0xf01a => LegacyWordImageFormat.emf,
      0xf01b => LegacyWordImageFormat.wmf,
      0xf01c => LegacyWordImageFormat.pict,
      0xf01d || 0xf02a => LegacyWordImageFormat.jpeg,
      0xf01e => LegacyWordImageFormat.png,
      0xf01f => LegacyWordImageFormat.dib,
      0xf029 => LegacyWordImageFormat.tiff,
      _ => LegacyWordImageFormat.unknown,
    };
    final twoUids = switch (format) {
      LegacyWordImageFormat.jpeg => const {
        0x46b,
        0x6e3,
      }.contains(node.instance),
      LegacyWordImageFormat.png => node.instance == 0x6e1,
      LegacyWordImageFormat.tiff => node.instance == 0x6e5,
      LegacyWordImageFormat.emf => node.instance == 0x3d5,
      LegacyWordImageFormat.wmf => node.instance == 0x217,
      _ => false,
    };
    final raster =
        format == LegacyWordImageFormat.jpeg ||
        format == LegacyWordImageFormat.png ||
        format == LegacyWordImageFormat.tiff;
    final validInstance = switch (format) {
      LegacyWordImageFormat.jpeg => const {
        0x46a,
        0x46b,
        0x6e2,
        0x6e3,
      }.contains(node.instance),
      LegacyWordImageFormat.png => const {0x6e0, 0x6e1}.contains(node.instance),
      LegacyWordImageFormat.tiff => const {
        0x6e4,
        0x6e5,
      }.contains(node.instance),
      LegacyWordImageFormat.emf => const {0x3d4, 0x3d5}.contains(node.instance),
      LegacyWordImageFormat.wmf => const {0x216, 0x217}.contains(node.instance),
      _ => true,
    };
    Uint8List bytes;
    LegacyWordSourceReference reference;
    LegacyWordMetafileInfo? metafile;
    if ((format == LegacyWordImageFormat.emf ||
            format == LegacyWordImageFormat.wmf) &&
        node.version == 0 &&
        validInstance) {
      final decoded = decodeOfficeArtMetafile(
        node.data.slice(0, node.data.length),
        format: format,
        twoUids: twoUids,
        maxDecodedBytes: _byteLimit - _retainedBytes,
      );
      bytes = decoded.bytes;
      metafile = decoded.info;
      reference = _reference(
        node.path,
        node.absoluteStart + 8 + decoded.dataOffset,
        decoded.encodedLength,
        'OfficeArtMetafileData',
      );
    } else if (raster && node.version == 0 && validInstance) {
      final skip = (twoUids ? 32 : 16) + 1;
      bytes = node.data.slice(skip, node.data.length - skip);
      reference = _reference(
        node.path,
        node.absoluteStart + 8 + skip,
        bytes.length,
        'BLIPFileData',
      );
      final validMagic = switch (format) {
        LegacyWordImageFormat.png =>
          bytes.length >= 24 &&
              _starts(bytes, [137, 80, 78, 71, 13, 10, 26, 10]) &&
              _starts(Uint8List.sublistView(bytes, 12), [73, 72, 68, 82]),
        LegacyWordImageFormat.jpeg =>
          bytes.length >= 4 && _starts(bytes, [255, 216, 255]),
        LegacyWordImageFormat.tiff =>
          bytes.length >= 8 &&
              (_starts(bytes, [73, 73, 42, 0]) ||
                  _starts(bytes, [77, 77, 0, 42])),
        _ => false,
      };
      if (!validMagic) format = LegacyWordImageFormat.unknown;
    } else {
      bytes = node.input.slice(node.start, node.end - node.start);
      reference = node.reference('OfficeArtBlip');
      if (raster) format = LegacyWordImageFormat.unknown;
    }
    _retain(bytes.length + (metafile?.previewSvg?.length ?? 0));
    final id = 'image-${assets.length + 1}';
    final asset = LegacyWordImageAsset(
      id: id,
      format: format,
      bytes: bytes,
      source: reference,
      officeArtArtifactId: artifact,
      metafile: metafile,
    );
    assets.add(asset);
    if (!asset.isRenderable) {
      _notice(LegacyWordMediaIssue.unsupportedImage, reference);
    }
    return id;
  }

  static bool _starts(Uint8List input, List<int> prefix) {
    if (input.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (input[i] != prefix[i]) return false;
    }
    return true;
  }

  void _readBinaryData(int cp, int offset) {
    final input = source.data;
    final length = input.i32(offset);
    if (length < 68 || input.u16(offset + 4) != 68) {
      throw const FormatException('Invalid Word binary-data header.');
    }
    _artifact(
      LegacyWordArtifactKind.binaryData,
      input.slice(offset, length),
      _reference('Data', offset, length, 'NilPICFAndBinData', cp: cp),
    );
  }

  void _readFields() {
    if (_fieldTablesRead) return;
    _fieldTablesRead = true;
    final lengths = [source.bodyLength, ...source.storyLengths];
    const pairs = [16, 18, 17, 19, 48, 57, 59];
    var global = 0;
    for (var story = 0; story < lengths.length; story++) {
      final (offset, length) = source.pair(pairs[story]);
      if (length > 0) {
        if (length < 10 || (length - 4) % 6 != 0) {
          throw const FormatException('Invalid Word object field table.');
        }
        final input = _Bytes(source.table.slice(offset, length));
        final count = (length - 4) ~/ 6;
        if (count > 50000) {
          throw const FormatException('Word fields exceed their limit.');
        }
        final records = (count + 1) * 4;
        final separators = <int?>[];
        var last = -1;
        for (var i = 0; i < count; i++) {
          final cp = input.u32(i * 4), ch = input.u8(records + i * 2) & 31;
          if (cp <= last ||
              cp >= lengths[story] ||
              source.unitAt(global + cp) != ch) {
            throw const FormatException('Invalid Word object field character.');
          }
          last = cp;
          if (ch == 0x13) {
            if (separators.length >= 64) {
              throw const FormatException('Word fields are nested too deeply.');
            }
            separators.add(null);
          } else if (ch == 0x14) {
            if (separators.isEmpty || separators.last != null) {
              throw const FormatException('Invalid Word field separator.');
            }
            separators[separators.length - 1] = global + cp;
          } else if (ch == 0x15) {
            if (separators.isEmpty) {
              throw const FormatException('Invalid Word field end.');
            }
            final separator = separators.removeLast();
            if (separator != null) {
              final flags = input.u8(records + i * 2 + 1);
              _fieldEligibility[separator] =
                  (flags & 0x22) == 0 && (flags & 0x80) != 0;
            }
          } else {
            throw const FormatException('Invalid Word field marker.');
          }
        }
        if (separators.isNotEmpty) {
          throw const FormatException('Unclosed Word object field.');
        }
      }
      global += lengths[story];
    }
  }

  void _readObject(
    int cp,
    int location,
    LegacyWordMediaPresentation presentation,
  ) {
    _readFields();
    if (_fieldEligibility[cp] == false) {
      // MS-DOC says CPicLocation is unused for zombie OLE fields. Do not turn
      // that stale value into a new active reference. ObjectPool preservation
      // below still retains any stored payload as unreferenced evidence.
      _notice(
        LegacyWordMediaIssue.oleFieldMetadataIncomplete,
        _reference(
          'WordDocument',
          source.pieceAt(cp).fc(cp),
          0,
          'InactiveOLEField',
          cp: cp,
        ),
      );
      return;
    }
    final pool = source.compound.child(source.compound.root, 'ObjectPool');
    final name = '_${location.toSigned(32)}';
    if (pool == null || !pool.isStorage) {
      throw const FormatException('Referenced Word object pool is missing.');
    }
    final storage = source.compound.child(pool, name);
    if (storage == null || !storage.isStorage) {
      throw const FormatException('Referenced Word object storage is missing.');
    }
    final reference = _reference(
      'ObjectPool/${storage.name}',
      0,
      0,
      'OLEObjectStorage',
      cp: cp,
    );
    final eligible = _fieldEligibility[cp];
    if (eligible != true) {
      _notice(LegacyWordMediaIssue.oleFieldMetadataIncomplete, reference);
    }
    _referencedObjects.add(storage.index);
    final preserved = _preserveStorage(storage, 'ObjectPool/${storage.name}');
    bool? linked;
    for (final stream in preserved.streams) {
      if (stream.path.toUpperCase() == '\x01OLE' && stream.bytes.length >= 20) {
        final ole = _Bytes(stream.bytes);
        final flags = ole.u32(4);
        final monikerSize = ole.u32(16);
        final monikerBytes = monikerSize == 0 ? 0 : monikerSize - 4;
        if (ole.u32(0) == 0x02000001 &&
            (flags & ~0x1001) == 0 &&
            ole.u32(12) == 0 &&
            monikerBytes >= 0 &&
            monikerBytes <= stream.bytes.length - 20) {
          final isLink = (flags & 1) != 0;
          if (isLink || stream.bytes.length == 20 + monikerBytes) {
            linked = isLink;
          }
        }
      }
    }
    _item();
    objects.add(
      LegacyWordEmbeddedObject(
        id: 'object-$cp',
        cp: cp,
        storage: preserved,
        linked: linked,
        canEmbed: eligible == true && linked == false,
        presentation: presentation,
      ),
    );
  }

  LegacyWordStorageMetadata _metadata(CfbfDirectoryEntry entry, String path) =>
      LegacyWordStorageMetadata(
        path: path,
        clsid: entry.clsid,
        stateBits: entry.stateBits,
        created: entry.created,
        modified: entry.modified,
        createdFiletime: entry.createdFiletime,
        modifiedFiletime: entry.modifiedFiletime,
      );

  Uint8List _stream(CfbfDirectoryEntry entry) => _streamCache.putIfAbsent(
    entry.index,
    () => source.compound.readEntry(entry),
  );

  LegacyWordCompoundStorage _preserveStorage(
    CfbfDirectoryEntry entry,
    String path,
  ) {
    final existing = _storageCache[entry.index];
    if (existing != null) return existing;
    _item();
    final metadata = <LegacyWordStorageMetadata>[_metadata(entry, '')];
    final streams = <LegacyWordPreservedStream>[];
    final writer = CfbfWriter(
      clsid: entry.clsid,
      stateBits: entry.stateBits,
      createdFiletime: entry.createdFiletime,
      modifiedFiletime: entry.modifiedFiletime,
    );
    void visit(CfbfDirectoryEntry parent, String prefix, int depth) {
      if (depth > 32) {
        throw const FormatException(
          'Word embedded storage is nested too deeply.',
        );
      }
      for (final child in source.compound.childrenOf(parent)) {
        _item();
        if (child.name.contains('/') ||
            child.name.contains('\\') ||
            child.name == '.' ||
            child.name == '..') {
          throw const FormatException(
            'Unsupported path-like compound entry name.',
          );
        }
        final relative = prefix.isEmpty ? child.name : '$prefix/${child.name}';
        final meta = _metadata(child, relative);
        if (child.isStorage) {
          metadata.add(meta);
          writer.addStorage(
            relative,
            clsid: child.clsid,
            stateBits: child.stateBits,
            createdFiletime: child.createdFiletime,
            modifiedFiletime: child.modifiedFiletime,
          );
          visit(child, relative, depth + 1);
        } else {
          final bytes = _stream(child);
          _retain(bytes.length);
          streams.add(
            LegacyWordPreservedStream(
              path: relative,
              bytes: bytes,
              metadata: meta,
            ),
          );
          writer.addStream(
            relative,
            bytes,
            clsid: child.clsid,
            stateBits: child.stateBits,
            createdFiletime: child.createdFiletime,
            modifiedFiletime: child.modifiedFiletime,
          );
        }
      }
    }

    visit(entry, '', 0);
    final bytes = writer.build();
    _retain(bytes.length);
    return _storageCache[entry.index] = LegacyWordCompoundStorage(
      sourcePath: path,
      bytes: bytes,
      streams: streams,
      storages: metadata,
    );
  }

  void _preserveUnreferencedObjects() {
    final pool = source.compound.child(source.compound.root, 'ObjectPool');
    if (pool == null || !pool.isStorage) return;
    for (final entry in source.compound.childrenOf(pool)) {
      if (_referencedObjects.contains(entry.index)) continue;
      final path = 'ObjectPool/${entry.name}';
      final reference = _reference(
        path,
        0,
        0,
        entry.isStorage ? 'ReconstructedCompoundStorage' : 'CompoundStream',
      );
      final bytes = entry.isStorage
          ? _preserveStorage(entry, path).bytes
          : _stream(entry);
      _artifact(
        LegacyWordArtifactKind.unreferencedObjectStorage,
        bytes,
        reference,
      );
      _notice(LegacyWordMediaIssue.unreferencedObjectStorage, reference);
    }
  }

  void _readProjects() {
    for (final name in ['Macros', '_VBA_PROJECT_CUR', 'VBA']) {
      final entry = source.compound.child(source.compound.root, name);
      if (entry == null || !entry.isStorage) continue;
      final storage = _preserveStorage(entry, entry.name);
      final paths = storage.streams
          .map((stream) => stream.path.toUpperCase())
          .toSet();
      final complete = paths.containsAll({
        'PROJECT',
        'VBA/DIR',
        'VBA/_VBA_PROJECT',
      });
      if (!complete) {
        _notice(
          LegacyWordMediaIssue.incompleteVbaProject,
          _reference(entry.name, 0, 0, 'ProjectRootStorage'),
        );
      }
      projects.add(
        LegacyWordVbaProject(
          id: 'vba-${projects.length + 1}',
          storage: storage,
          hasRequiredStreams: complete,
          signatureArtifactIds: artifacts
              .where((a) => a.kind == LegacyWordArtifactKind.vbaSignature)
              .map((a) => a.id)
              .toList(),
        ),
      );
    }
  }

  void _readSignatures() {
    for (final name in ['_signatures', '_xmlsignatures']) {
      final entry = source.compound.child(source.compound.root, name);
      if (entry == null) continue;
      final bytes = entry.isStorage
          ? _preserveStorage(entry, entry.name).bytes
          : _stream(entry);
      _artifact(
        LegacyWordArtifactKind.documentSignature,
        bytes,
        _reference(
          entry.name,
          0,
          entry.isStorage ? 0 : bytes.length,
          entry.isStorage
              ? 'ReconstructedSignatureStorage'
              : 'DocumentSignatureStream',
        ),
      );
    }
    final (offset, length) = source.pair(60);
    if (length == 0) return;
    final input = _Bytes(source.table.slice(offset, length));
    if (input.u16(0) != 0xffff || input.u16(4) != 4) {
      throw const FormatException('Invalid Word user-variable table.');
    }
    final count = input.u16(2);
    if (count > 4096) {
      throw const FormatException('Word user variables exceed their limit.');
    }
    var cursor = 6;
    final names = <String>[];
    final distinct = <String>{};
    for (var i = 0; i < count; i++) {
      final units = input.u16(cursor);
      cursor += 2;
      if (units > 4096) {
        throw const FormatException('Word variable name exceeds its limit.');
      }
      input.require(cursor, units * 2 + 4);
      final nameUnits = [
        for (var j = 0; j < units; j++) input.u16(cursor + j * 2),
      ];
      _validateUnicode(nameUnits);
      final name = String.fromCharCodes(nameUnits);
      if (!distinct.add(name)) {
        throw const FormatException('Duplicate Word user-variable name.');
      }
      names.add(name);
      cursor += units * 2 + 4;
    }
    for (final name in names) {
      final size = 2 + input.u16(cursor) * 2;
      input.require(cursor, size);
      if (const {'Sign', 'SigAgile', 'SigV3'}.contains(name)) {
        _artifact(
          LegacyWordArtifactKind.vbaSignature,
          input.slice(cursor, size),
          _reference(
            _tablePath,
            offset + cursor,
            size,
            'StwUser/$name/WordSigBlob',
          ),
        );
      }
      cursor += size;
    }
    if (cursor != input.length) {
      throw const FormatException('Unexpected Word user-variable data.');
    }
  }
}

class _ArtRecord {
  const _ArtRecord(
    this.input,
    this.start,
    this.end,
    this.version,
    this.instance,
    this.type,
    this.path,
    this.base,
    this.children,
  );
  final _Bytes input;
  final int start, end, version, instance, type, base;
  final String path;
  final List<_ArtRecord> children;
  int get absoluteStart => base + start;
  _Bytes get data => _Bytes(input.slice(start + 8, end - start - 8));
  LegacyWordSourceReference reference(String structure) =>
      LegacyWordSourceReference(
        streamPath: path,
        offset: absoluteStart,
        length: end - start,
        structure: structure,
      );
}

class _DrawingShape {
  const _DrawingShape(
    this.id,
    this.properties,
    this.textboxId,
    this.artifactId,
    this.flags,
    this.model,
  );
  final int id;
  final Map<int, int> properties;
  final int? textboxId;
  final String artifactId;
  final int flags;
  final LegacyWordOfficeArtShape model;
  bool get deleted => (flags & 8) != 0;
}

class _PictureData {
  const _PictureData(
    this.source,
    this.artifactId,
    this.imageId,
    this.width,
    this.height,
    this.properties,
    this.externalName,
    this.deleted,
    this.shape,
  );
  final LegacyWordSourceReference source;
  final String artifactId;
  final String? imageId;
  final int width, height;
  final Map<int, int> properties;
  final String? externalName;
  final bool deleted;
  final LegacyWordOfficeArtShape shape;
}
