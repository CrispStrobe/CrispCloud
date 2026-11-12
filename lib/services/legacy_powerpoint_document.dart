import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart' show BoundedCfbReader, CfbfDirectoryEntry;

enum LegacyPowerPointErrorCode {
  malformed,
  unsupportedVersion,
  encrypted,
  resourceLimit,
}

class LegacyPowerPointException implements Exception {
  const LegacyPowerPointException(this.code);
  final LegacyPowerPointErrorCode code;
  @override
  String toString() => 'LegacyPowerPointException(${code.name})';
}

class LegacyPowerPointSlide {
  const LegacyPowerPointSlide({required this.slideId, required this.text});
  final int slideId;
  final String text;
}

class LegacyPowerPointDocument {
  LegacyPowerPointDocument(List<LegacyPowerPointSlide> slides)
    : slides = List.unmodifiable(slides);
  final List<LegacyPowerPointSlide> slides;
  String get plainText => slides.map((slide) => slide.text).join('\n\n');
}

const kLegacyPowerPointInputLimit = 64 * 1024 * 1024;
const kLegacyPowerPointTextLimit = 4 * 1024 * 1024;

/// Reads PowerPoint 97–2003 text from the current persist-object directory and
/// current slide drawing references, following [MS-PPT] and [MS-ODRAW]. It never
/// scans arbitrary stream bytes for text: old saves, deleted slides, masters,
/// notes, embedded documents, media and macros are not part of this preview.
LegacyPowerPointDocument extractLegacyPowerPoint(Uint8List bytes) {
  if (bytes.length > kLegacyPowerPointInputLimit) {
    throw const LegacyPowerPointException(
      LegacyPowerPointErrorCode.resourceLimit,
    );
  }
  try {
    final cfb = BoundedCfbReader(
      bytes,
      maxStreamBytes: kLegacyPowerPointInputLimit,
      maxTotalReadBytes: kLegacyPowerPointInputLimit,
    );
    final current = cfb.readPath('Current User');
    final document = cfb.readPath('PowerPoint Document');
    if (current == null || document == null) {
      throw const LegacyPowerPointException(
        LegacyPowerPointErrorCode.unsupportedVersion,
      );
    }
    return _PowerPointParser(document).parse(current);
  } on LegacyPowerPointException {
    rethrow;
  } on FormatException {
    throw const LegacyPowerPointException(LegacyPowerPointErrorCode.malformed);
  } on RangeError {
    throw const LegacyPowerPointException(LegacyPowerPointErrorCode.malformed);
  }
}

class _Record {
  const _Record(this.start, this.end, this.type, this.version, this.instance);
  final int start;
  final int end;
  final int type;
  final int version;
  final int instance;
  int get payload => start + 8;
  int get length => end - payload;
}

class _SlideReference {
  _SlideReference(this.persistId, this.slideId, this.expectedTextCount);
  final int persistId;
  final int slideId;
  final int expectedTextCount;
  final placeholders = <String>[];
}

class _PowerPointParser {
  _PowerPointParser(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  final persist = <int, int>{};
  int recordCount = 0;
  int decodedLength = 0;
  int outputLength = 0;
  int persistEntryCount = 0;

  Never fail([
    LegacyPowerPointErrorCode code = LegacyPowerPointErrorCode.malformed,
  ]) => throw LegacyPowerPointException(code);

  int u32(int offset) => data.getUint32(offset, Endian.little);
  int i32(int offset) => data.getInt32(offset, Endian.little);

  _Record record(int offset, int limit) {
    if (++recordCount > 250000) fail(LegacyPowerPointErrorCode.resourceLimit);
    if (offset < 0 || offset > limit - 8 || limit > bytes.length) fail();
    final packed = data.getUint16(offset, Endian.little);
    final size = u32(offset + 4);
    if (size > limit - offset - 8) fail();
    return _Record(
      offset,
      offset + 8 + size,
      data.getUint16(offset + 2, Endian.little),
      packed & 15,
      packed >> 4,
    );
  }

  Iterable<_Record> children(_Record parent) sync* {
    var offset = parent.payload;
    while (offset < parent.end) {
      final child = record(offset, parent.end);
      yield child;
      offset = child.end;
    }
  }

  void require(_Record value, int type, int version, {int? length}) {
    if (value.type != type ||
        value.version != version ||
        value.instance != 0 ||
        (length != null && value.length != length)) {
      fail();
    }
  }

  LegacyPowerPointDocument parse(Uint8List current) {
    // Current User contains one CurrentUserAtom, whose fixed portion is 20
    // bytes. The optional Unicode user name is never needed for rendering.
    if (current.length < 32 || current.length > 1024) fail();
    final user = ByteData.sublistView(current);
    int user32(int offset) => user.getUint32(offset, Endian.little);
    if (user.getUint16(0, Endian.little) != 0 ||
        user.getUint16(2, Endian.little) != 0x0ff6 ||
        user32(8) != 20) {
      fail(LegacyPowerPointErrorCode.unsupportedVersion);
    }
    final token = user32(12);
    if (token == 0xf3d1c4df) fail(LegacyPowerPointErrorCode.encrypted);
    if (token != 0xe391c05f) fail();
    if (user.getUint16(22, Endian.little) != 0x03f4 ||
        current[24] != 3 ||
        current[25] != 0) {
      fail(LegacyPowerPointErrorCode.unsupportedVersion);
    }
    final userLength = user.getUint16(20, Endian.little);
    final minimum = 32 + userLength;
    if (userLength > 255 ||
        (current.length != minimum &&
            current.length != minimum + userLength * 2) ||
        user32(4) + 8 != current.length ||
        (user32(28 + userLength) != 8 && user32(28 + userLength) != 9)) {
      fail();
    }

    var editOffset = user32(16);
    var editCount = 0;
    var documentId = 0;
    while (true) {
      if (++editCount > 4096) fail(LegacyPowerPointErrorCode.resourceLimit);
      final edit = record(editOffset, bytes.length);
      require(edit, 0x0ff5, 0);
      if (edit.length != 28 && edit.length != 32) fail();
      if (bytes[edit.payload + 6] != 0 || bytes[edit.payload + 7] != 3) {
        fail(LegacyPowerPointErrorCode.unsupportedVersion);
      }
      if (edit.length == 32 && u32(edit.payload + 28) != 0) {
        fail(LegacyPowerPointErrorCode.encrypted);
      }
      final previous = u32(edit.payload + 8);
      final directoryOffset = u32(edit.payload + 12);
      final docId = u32(edit.payload + 16);
      final seed = u32(edit.payload + 20);
      if (docId != 1 ||
          previous >= editOffset ||
          directoryOffset <= previous ||
          directoryOffset >= editOffset) {
        fail();
      }
      if (editCount == 1) documentId = docId;
      readPersistDirectory(directoryOffset, editOffset, seed);
      if (previous == 0) break;
      editOffset = previous;
    }
    final documentOffset = persist[documentId];
    if (documentOffset == null) fail();
    final document = record(documentOffset, bytes.length);
    require(document, 0x03e8, 15);
    _Record? slideList;
    for (final child in children(document)) {
      if (child.type != 0x0ff0 || child.instance != 0) continue;
      if (slideList != null || child.version != 15) fail();
      slideList = child;
    }
    final references = slideList == null
        ? <_SlideReference>[]
        : readSlideList(slideList);
    final slides = <LegacyPowerPointSlide>[];
    final seenOffsets = <int>{};
    for (final reference in references) {
      final offset = persist[reference.persistId];
      if (offset == null || !seenOffsets.add(offset)) fail();
      final slide = record(offset, bytes.length);
      require(slide, 0x03ee, 15);
      final texts = <String>[];
      final usedPlaceholders = <int>{};
      var drawingCount = 0;
      for (final child in children(slide)) {
        if (child.type != 0x040c) continue;
        require(child, 0x040c, 15);
        if (++drawingCount > 1) fail();
        final drawings = children(child).toList();
        if (drawings.length != 1 || drawings.single.type != 0xf002) fail();
        readDrawing(drawings.single, reference, usedPlaceholders, texts, 0);
      }
      if (drawingCount != 1) fail();
      // Unreferenced outline text is deliberately omitted. It may belong to a
      // deleted placeholder retained in the current drawing's data.
      final text = texts.where((text) => text.isNotEmpty).join('\n');
      outputLength += text.length + (slides.isEmpty ? 0 : 2);
      if (outputLength > kLegacyPowerPointTextLimit) {
        fail(LegacyPowerPointErrorCode.resourceLimit);
      }
      slides.add(LegacyPowerPointSlide(slideId: reference.slideId, text: text));
    }
    return LegacyPowerPointDocument(slides);
  }

  void readPersistDirectory(int offset, int editOffset, int seed) {
    final directory = record(offset, editOffset);
    require(directory, 0x1772, 0);
    final seen = <int>{};
    var cursor = directory.payload;
    while (cursor < directory.end) {
      if (directory.end - cursor < 4) fail();
      final packed = u32(cursor);
      cursor += 4;
      final id = packed & 0x000fffff;
      final count = packed >>> 20;
      if (id == 0 ||
          count == 0 ||
          id + count - 1 > 0x000fffff ||
          id + count - 1 > seed ||
          count > (directory.end - cursor) ~/ 4) {
        fail();
      }
      persistEntryCount += count;
      if (persistEntryCount > 100000) {
        fail(LegacyPowerPointErrorCode.resourceLimit);
      }
      for (var index = 0; index < count; index++) {
        final target = u32(cursor);
        cursor += 4;
        if (target > offset - 8 || !seen.add(id + index)) fail();
        // Walking newest-to-oldest is essential: earlier saves may contain
        // superseded slides and text under the same persist identifier.
        persist.putIfAbsent(id + index, () => target);
      }
    }
  }

  List<_SlideReference> readSlideList(_Record list) {
    final slides = <_SlideReference>[];
    final ids = <int>{};
    final references = <int>{};
    _SlideReference? current;
    var hasHeader = false;
    var hasText = false;
    for (final child in children(list)) {
      if (child.type == 0x03f3) {
        require(child, 0x03f3, 0, length: 20);
        if (current != null &&
            current.placeholders.length != current.expectedTextCount) {
          fail();
        }
        final id = u32(child.payload);
        final count = i32(child.payload + 8);
        final slideId = u32(child.payload + 12);
        if (count < 0 ||
            count > 8 ||
            !references.add(id) ||
            !ids.add(slideId)) {
          fail();
        }
        if (slides.length >= 10000) {
          fail(LegacyPowerPointErrorCode.resourceLimit);
        }
        current = _SlideReference(id, slideId, count);
        slides.add(current);
        hasHeader = hasText = false;
      } else if (child.type == 0x0f9f) {
        if (current == null ||
            child.version != 0 ||
            child.length != 4 ||
            child.instance > 5 ||
            current.placeholders.length >= current.expectedTextCount) {
          fail();
        }
        current.placeholders.add('');
        hasHeader = true;
        hasText = false;
      } else if (child.type == 0x0fa0 || child.type == 0x0fa8) {
        if (current == null || !hasHeader || hasText) fail();
        current.placeholders[current.placeholders.length - 1] = readText(child);
        hasText = true;
      }
    }
    if (current != null &&
        current.placeholders.length != current.expectedTextCount) {
      fail();
    }
    return slides;
  }

  void readDrawing(
    _Record drawing,
    _SlideReference slide,
    Set<int> used,
    List<String> texts,
    int depth,
  ) {
    if (depth > 64) fail(LegacyPowerPointErrorCode.resourceLimit);
    if (drawing.version != 15) fail();
    final parts = children(drawing).toList();
    if (drawing.type == 0xf004) {
      final shape = parts.where((part) => part.type == 0xf00a).toList();
      if (shape.length != 1 ||
          shape.single.version != 2 ||
          shape.single.length != 8) {
        fail();
      }
      if ((u32(shape.single.payload + 4) & 8) != 0) return;
    }
    if (drawing.type == 0xf003 &&
        parts.isNotEmpty &&
        parts.first.type == 0xf004) {
      // A deleted group's patriarch makes all its descendants non-current.
      for (final prop in children(parts.first)) {
        if (prop.type == 0xf00a) {
          if (prop.version != 2 || prop.length != 8) fail();
          if ((u32(prop.payload + 4) & 9) == 9) return;
        }
      }
    }
    var textboxes = 0;
    for (final child in parts) {
      // Descend only actual OfficeArt drawing/group/shape containers. Text
      // hidden in client data, metadata, media or embedded objects is ignored.
      if ((drawing.type == 0xf002 &&
              (child.type == 0xf003 || child.type == 0xf004)) ||
          (drawing.type == 0xf003 &&
              (child.type == 0xf003 || child.type == 0xf004))) {
        readDrawing(child, slide, used, texts, depth + 1);
      } else if (drawing.type == 0xf004 && child.type == 0xf00d) {
        if (++textboxes > 1) fail();
        readTextBox(child, slide, used, texts);
      }
    }
  }

  void readTextBox(
    _Record box,
    _SlideReference slide,
    Set<int> used,
    List<String> texts,
  ) {
    require(box, 0xf00d, 15);
    var hasHeader = false;
    var hasText = false;
    var hasReference = false;
    for (final child in children(box)) {
      if (child.type == 0x0f9e) {
        require(child, 0x0f9e, 0, length: 4);
        if (hasHeader || hasReference) fail();
        final index = i32(child.payload);
        if (index < 0 ||
            index >= slide.placeholders.length ||
            !used.add(index)) {
          fail();
        }
        texts.add(slide.placeholders[index]);
        hasReference = true;
      } else if (child.type == 0x0f9f) {
        require(child, 0x0f9f, 0, length: 4);
        if (hasReference || hasHeader) fail();
        hasHeader = true;
      } else if (child.type == 0x0fa0 || child.type == 0x0fa8) {
        if (!hasHeader || hasReference || hasText) fail();
        texts.add(readText(child));
        hasText = true;
      }
    }
  }

  String readText(_Record text) {
    if (text.version != 0 || text.instance != 0) fail();
    final unicode = text.type == 0x0fa0;
    if (unicode && text.length.isOdd) fail();
    final count = text.length ~/ (unicode ? 2 : 1);
    decodedLength += count;
    if (decodedLength > kLegacyPowerPointTextLimit) {
      fail(LegacyPowerPointErrorCode.resourceLimit);
    }
    final result = StringBuffer();
    var highSurrogate = false;
    for (var index = 0; index < count; index++) {
      final unit = unicode
          ? data.getUint16(text.payload + index * 2, Endian.little)
          : bytes[text.payload + index];
      if (unit == 0 || (unit < 32 && unit != 9 && unit != 11 && unit != 13)) {
        fail();
      }
      if (unit >= 0xdc00 && unit <= 0xdfff) {
        if (!highSurrogate) fail();
        highSurrogate = false;
      } else {
        if (highSurrogate) fail();
        highSurrogate = unit >= 0xd800 && unit <= 0xdbff;
      }
      result.writeCharCode(unit == 13 || unit == 11 ? 10 : unit);
    }
    if (highSurrogate) fail();
    return result.toString();
  }
}
