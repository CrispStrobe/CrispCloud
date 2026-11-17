import 'dart:typed_data';

import '../io/byte_source.dart';
import 'sfnt_parser.dart';

/// Result of subsetting a TrueType font to the glyphs actually used.
class FontSubset {
  /// FontSubset API.
  FontSubset({
    required this.bytes,
    required this.oldToNewGlyph,
    required this.unicodeToNewGlyph,
    required this.numGlyphs,
  });

  /// bytes API.
  final Uint8List bytes;

  /// oldToNewGlyph API.
  final Map<int, int> oldToNewGlyph;

  /// unicodeToNewGlyph API.
  final Map<int, int> unicodeToNewGlyph;

  /// numGlyphs API.
  final int numGlyphs;
}

/// Builds a minimal TrueType containing only the requested code points.
class FontSubsetter {
  /// FontSubsetter API.
  FontSubsetter(this.font);

  /// font API.
  final SfntFont font;

  /// Retains the requested Unicode scalars and their composite components.
  ///
  /// Invalid scalar values, absent glyphs and out-of-range [extraGlyphIds] are
  /// ignored. Supplementary characters retain their mappings in a
  /// full-repertoire format 12 cmap. Invalid composite references or cycles
  /// throw [SfntException].
  FontSubset subset(
    Iterable<int> codePoints, {
    Iterable<int> extraGlyphIds = const <int>[],
  }) {
    final Set<int> wanted = <int>{0};
    final Map<int, int> unicodeToOld = <int, int>{};
    for (final int gid in extraGlyphIds) {
      if (gid > 0 && gid < font.numGlyphs) {
        wanted.add(gid);
      }
    }
    for (final int cp in codePoints) {
      if (!_isUnicodeScalar(cp)) {
        continue;
      }
      final int gid = font.glyphIdFor(cp);
      if (gid <= 0 || gid >= font.numGlyphs) {
        continue;
      }
      wanted.add(gid);
      unicodeToOld[cp] = gid;
    }
    final Uint8List? glyfSrc = font.hasTable('glyf')
        ? font.tableBytes('glyf')
        : null;
    final glyphs = <int, Uint8List>{};
    final components = <int, List<_GlyphReference>>{};
    final List<int> pending = List<int>.from(wanted);
    while (pending.isNotEmpty) {
      final int gid = pending.removeLast();
      if (glyfSrc == null) {
        continue;
      }
      // Dependency discovery only needs component records, not decoded paths.
      // Avoid recursively expanding outlines before the visited set can stop
      // repeated dependencies (or a malformed composite cycle).
      final glyph = _glyphBytes(gid, glyfSrc);
      glyphs[gid] = glyph;
      final references = _compositeReferences(glyph);
      components[gid] = references;
      for (final reference in references) {
        final child = reference.glyphId;
        if (child >= font.numGlyphs) {
          throw SfntException(
            'Composite glyph $gid refers to absent glyph $child',
          );
        }
        if (wanted.add(child)) {
          pending.add(child);
        }
      }
    }
    _checkCompositeCycles(components);
    final List<int> oldIds = wanted.toList()..sort();
    final Map<int, int> oldToNew = <int, int>{
      for (int i = 0; i < oldIds.length; i++) oldIds[i]: i,
    };
    final Map<int, int> unicodeToNew = <int, int>{
      for (final MapEntry<int, int> e in unicodeToOld.entries)
        e.key: oldToNew[e.value] ?? 0,
    };

    final BytesBuilder glyfOut = BytesBuilder(copy: false);
    final List<int> loca = <int>[0];
    for (final int oldId in oldIds) {
      if (glyfSrc == null) {
        loca.add(0);
        continue;
      }
      final glyph = glyphs[oldId]!;
      if (glyph.isNotEmpty) {
        glyfOut.add(_remapComposite(glyph, components[oldId]!, oldToNew));
      }
      // Long loca can represent odd offsets. Short loca stores offset / 2,
      // so every retained glyph must be aligned before selecting that format.
      if (glyfOut.length.isOdd) glyfOut.addByte(0);
      loca.add(glyfOut.length);
    }

    final bool longLoca = loca.last > 0x1FFFE;
    final ByteSink locaSink = ByteSink(capacity: loca.length * 4);
    if (longLoca) {
      for (final int off in loca) {
        locaSink.u32be(off);
      }
    } else {
      for (final int off in loca) {
        locaSink.u16be((off / 2).floor());
      }
    }

    final ByteSink hmtx = ByteSink(capacity: oldIds.length * 4);
    for (final int oldId in oldIds) {
      hmtx.u16be(font.advanceWidth(oldId));
      final int lsb = oldId < font.leftSideBearings.length
          ? font.leftSideBearings[oldId]
          : 0;
      hmtx.u16be(lsb & 0xFFFF);
    }

    final Map<String, Uint8List> outTables = <String, Uint8List>{
      'head': _patchedHead(longLoca),
      'hhea': _patchedHhea(oldIds.length),
      'maxp': _patchedMaxp(oldIds.length),
      'hmtx': hmtx.takeBytes(),
      'cmap': _buildCmap(unicodeToNew),
      'name': font.hasTable('name')
          ? font.tableBytes('name')
          : _minimalName(font.familyName),
    };
    if (glyfSrc != null) {
      outTables['glyf'] = glyfOut.takeBytes();
      outTables['loca'] = locaSink.takeBytes();
    }
    // These tables contain font-wide data, independent of remapped glyph IDs.
    for (final String tag in <String>['cvt ', 'fpgm', 'prep', 'gasp']) {
      if (font.hasTable(tag)) {
        outTables[tag] = font.tableBytes(tag);
      }
    }
    if (font.hasTable('OS/2')) outTables['OS/2'] = _subsetOs2(unicodeToNew);
    if (font.hasTable('post')) outTables['post'] = _subsetPost();

    return FontSubset(
      bytes: _wrapSfnt(outTables),
      oldToNewGlyph: oldToNew,
      unicodeToNewGlyph: unicodeToNew,
      numGlyphs: oldIds.length,
    );
  }

  Uint8List _patchedHead(bool longLoca) {
    final Uint8List head = Uint8List.fromList(font.tableBytes('head'));
    final ByteData data = ByteData.sublistView(head);
    data.setUint32(8, 0); // checksumAdjustment cleared
    data.setInt16(50, longLoca ? 1 : 0);
    return head;
  }

  Uint8List _patchedHhea(int numMetrics) {
    final Uint8List hhea = Uint8List.fromList(font.tableBytes('hhea'));
    ByteData.sublistView(hhea).setUint16(34, numMetrics);
    return hhea;
  }

  Uint8List _patchedMaxp(int numGlyphs) {
    final Uint8List maxp = Uint8List.fromList(font.tableBytes('maxp'));
    ByteData.sublistView(maxp).setUint16(4, numGlyphs);
    return maxp;
  }

  Uint8List _subsetOs2(Map<int, int> unicodeToNew) {
    final os2 = Uint8List.fromList(font.tableBytes('OS/2'));
    if (os2.length < 68) {
      throw const SfntException('Truncated SFNT OS/2 character coverage');
    }
    final data = ByteData.sublistView(os2);
    var first = 0xffff;
    var last = 0;
    final ranges = <int>[0, 0, 0, 0];
    for (final cp in unicodeToNew.keys) {
      final bmp = cp < 0xffff ? cp : 0xffff;
      if (bmp < first) first = bmp;
      if (bmp > last) last = bmp;
      if (cp > 0xffff) ranges[1] |= 1 << (57 - 32);
      final bit = _unicodeRangeBit(cp);
      if (bit != null) ranges[bit ~/ 32] |= 1 << (bit % 32);
    }
    for (var i = 0; i < ranges.length; i++) {
      data.setUint32(42 + i * 4, ranges[i]);
    }
    data.setUint16(64, unicodeToNew.isEmpty ? 0 : first);
    data.setUint16(66, last);
    if (data.getUint16(0) >= 1 && os2.length >= 86) {
      final partial = font.cmap.mappings.any(
        (entry) =>
            _isUnicodeScalar(entry.key) &&
            entry.value > 0 &&
            entry.value < font.numGlyphs &&
            !unicodeToNew.containsKey(entry.key),
      );
      // A reduced font cannot inherit the full face's code-page claims.
      // Clear these compatibility hints conservatively for partial subsets;
      // the cmap and Unicode-range fields describe the retained repertoire.
      if (partial) {
        data.setUint32(78, 0);
        data.setUint32(82, 0);
      }
    }
    // Preserve typography metrics, weight/style and embedding-rights data.
    return os2;
  }

  static int? _unicodeRangeBit(int cp) {
    var lo = 0;
    var hi = _unicodeRanges.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final range = _unicodeRanges[mid];
      if (cp < range.$1) {
        hi = mid;
      } else if (cp > range.$2) {
        lo = mid + 1;
      } else {
        return range.$3;
      }
    }
    return null;
  }

  Uint8List _subsetPost() {
    final source = font.tableBytes('post');
    if (source.length < 32) {
      throw const SfntException('Truncated SFNT post header');
    }
    // Version 3 retains font-wide italic/underline/fixed-pitch information
    // without copying glyph-name arrays indexed by the original glyph IDs.
    // The original download-memory estimates do not describe the subset.
    final post = Uint8List(32)..setRange(0, 16, source);
    ByteData.sublistView(post).setUint32(0, 0x00030000);
    return post;
  }

  Uint8List _glyphBytes(int gid, Uint8List glyf) {
    if (gid < 0 ||
        gid >= font.numGlyphs ||
        gid + 1 >= font.glyphOffsets.length) {
      throw SfntException('Missing loca entry for glyph $gid');
    }
    final start = font.glyphOffsets[gid];
    final end = font.glyphOffsets[gid + 1];
    if (start < 0 || end < start || end > glyf.length) {
      throw SfntException('Invalid loca range for glyph $gid');
    }
    return Uint8List.sublistView(glyf, start, end);
  }

  static List<_GlyphReference> _compositeReferences(Uint8List glyph) {
    if (glyph.isEmpty) return const [];
    if (glyph.length < 10) {
      throw const SfntException('Truncated TrueType glyph header');
    }
    final data = ByteData.sublistView(glyph);
    final contours = data.getInt16(0);
    if (contours >= 0) {
      _validateSimpleGlyph(glyph, contours);
      return const [];
    }
    final references = <_GlyphReference>[];
    var offset = 10;
    var haveInstructions = false;
    var more = true;
    while (more) {
      if (offset + 4 > glyph.length) {
        throw const SfntException('Truncated composite glyph component');
      }
      final flags = data.getUint16(offset);
      references.add((glyphId: data.getUint16(offset + 2), offset: offset + 2));
      offset += 4 + ((flags & 0x0001) != 0 ? 4 : 2);
      if ((flags & 0x0008) != 0) {
        offset += 2;
      } else if ((flags & 0x0040) != 0) {
        offset += 4;
      } else if ((flags & 0x0080) != 0) {
        offset += 8;
      }
      if (offset > glyph.length) {
        throw const SfntException('Truncated composite glyph transform');
      }
      haveInstructions |= (flags & 0x0100) != 0;
      more = (flags & 0x0020) != 0;
    }
    // WE_HAVE_INSTRUCTIONS may be set on an earlier component, but its
    // instruction stream always follows the final component record.
    if (haveInstructions &&
        (offset + 2 > glyph.length ||
            offset + 2 + data.getUint16(offset) > glyph.length)) {
      throw const SfntException('Truncated composite glyph instructions');
    }
    return references;
  }

  static void _validateSimpleGlyph(Uint8List glyph, int contours) {
    final data = ByteData.sublistView(glyph);
    var offset = 10 + contours * 2;
    if (offset + 2 > glyph.length) {
      throw const SfntException('Truncated simple glyph contour endpoints');
    }
    var lastPoint = -1;
    for (var i = 0; i < contours; i++) {
      final point = data.getUint16(10 + i * 2);
      if (point <= lastPoint) {
        throw const SfntException('Invalid simple glyph contour endpoints');
      }
      lastPoint = point;
    }
    offset += 2 + data.getUint16(offset);
    if (offset > glyph.length) {
      throw const SfntException('Truncated simple glyph instructions');
    }
    var points = 0;
    var coordinateBytes = 0;
    while (points <= lastPoint) {
      if (offset >= glyph.length) {
        throw const SfntException('Truncated simple glyph flags');
      }
      final flag = glyph[offset++];
      var count = 1;
      if ((flag & 0x08) != 0) {
        if (offset >= glyph.length) {
          throw const SfntException('Truncated simple glyph flag repeat');
        }
        count += glyph[offset++];
      }
      points += count;
      if (points > lastPoint + 1) {
        throw const SfntException('Invalid simple glyph flag repeat');
      }
      final xBytes = (flag & 0x02) != 0 ? 1 : ((flag & 0x10) != 0 ? 0 : 2);
      final yBytes = (flag & 0x04) != 0 ? 1 : ((flag & 0x20) != 0 ? 0 : 2);
      coordinateBytes += count * (xBytes + yBytes);
    }
    if (offset + coordinateBytes > glyph.length) {
      throw const SfntException('Truncated simple glyph coordinates');
    }
  }

  static void _checkCompositeCycles(
    Map<int, List<_GlyphReference>> components,
  ) {
    final unresolved = <int, int>{};
    final dependants = <int, List<int>>{};
    final ready = <int>[];
    for (final entry in components.entries) {
      final dependencies = entry.value.map((ref) => ref.glyphId).toSet();
      unresolved[entry.key] = dependencies.length;
      if (dependencies.isEmpty) ready.add(entry.key);
      for (final child in dependencies) {
        (dependants[child] ??= []).add(entry.key);
      }
    }
    var resolved = 0;
    while (ready.isNotEmpty) {
      final gid = ready.removeLast();
      resolved++;
      for (final parent in dependants[gid] ?? const <int>[]) {
        final remaining = unresolved[parent]! - 1;
        unresolved[parent] = remaining;
        if (remaining == 0) ready.add(parent);
      }
    }
    if (resolved != components.length) {
      throw const SfntException('Cyclic composite glyph references');
    }
  }

  static Uint8List _remapComposite(
    Uint8List glyph,
    List<_GlyphReference> references,
    Map<int, int> oldToNew,
  ) {
    if (references.isEmpty) return glyph;
    final Uint8List copy = Uint8List.fromList(glyph);
    final data = ByteData.sublistView(copy);
    for (final reference in references) {
      data.setUint16(reference.offset, oldToNew[reference.glyphId]!);
    }
    return copy;
  }

  static Uint8List _buildCmap(Map<int, int> unicodeToNew) {
    final entries = unicodeToNew.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // U+FFFF is the mandatory format 4 sentinel. A real mapping for it must
    // live in format 12, just like a supplementary character.
    final bmp = _cmapSegments(entries.where((e) => e.key < 0xFFFF))
      ..add(const _Seg(0xFFFF, 0xFFFF, 0));
    final format4Length = 16 + bmp.length * 8;
    final include4 = format4Length <= 0xFFFF;
    final include12 = !include4 || entries.any((e) => e.key >= 0xFFFF);
    final format4 = include4 ? _cmapFormat4(bmp) : null;
    final format12 = include12 ? _cmapFormat12(_cmapSegments(entries)) : null;
    final count = (include4 ? 1 : 0) + (include12 ? 1 : 0);
    final headerLength = 4 + count * 8;
    final sink = ByteSink();
    sink.u16be(0);
    sink.u16be(count);
    if (format4 != null) {
      sink.u16be(3); // Windows, Unicode BMP.
      sink.u16be(1);
      sink.u32be(headerLength);
    }
    if (format12 != null) {
      sink.u16be(3); // Windows, full Unicode repertoire.
      sink.u16be(10);
      sink.u32be(headerLength + (format4?.length ?? 0));
    }
    if (format4 != null) sink.add(format4);
    if (format12 != null) sink.add(format12);
    return sink.takeBytes();
  }

  static List<_Seg> _cmapSegments(Iterable<MapEntry<int, int>> entries) {
    final segments = <_Seg>[];
    int? start;
    var end = 0;
    var firstGid = 0;
    for (final entry in entries) {
      if (start != null &&
          entry.key == end + 1 &&
          entry.value == firstGid + entry.key - start) {
        end = entry.key;
        continue;
      }
      if (start != null) segments.add(_Seg(start, end, firstGid));
      start = end = entry.key;
      firstGid = entry.value;
    }
    if (start != null) segments.add(_Seg(start, end, firstGid));
    return segments;
  }

  static Uint8List _cmapFormat4(List<_Seg> segs) {
    final int segCount = segs.length;
    final int searchRange = _pow2le(segCount) * 2;
    final int entrySelector = _log2(_pow2le(segCount));
    final int rangeShift = segCount * 2 - searchRange;
    // The 16-byte fixed header already includes reservedPad. Never wrap the
    // uint16 length: large sparse mappings use format 12 instead.
    final int length = 16 + segCount * 8;
    final ByteSink sink = ByteSink(capacity: length);
    sink.u16be(4);
    sink.u16be(length);
    sink.u16be(0);
    sink.u16be(segCount * 2);
    sink.u16be(searchRange);
    sink.u16be(entrySelector);
    sink.u16be(rangeShift);
    for (final _Seg s in segs) {
      sink.u16be(s.end);
    }
    sink.u16be(0);
    for (final _Seg s in segs) {
      sink.u16be(s.start);
    }
    for (final _Seg s in segs) {
      if (s.start == 0xFFFF) {
        sink.u16be(1);
      } else {
        sink.u16be((s.startGid - s.start) & 0xFFFF);
      }
    }
    for (int i = 0; i < segCount; i++) {
      sink.u16be(0);
    }
    return sink.takeBytes();
  }

  static Uint8List _cmapFormat12(List<_Seg> groups) {
    final length = 16 + groups.length * 12;
    final sink = ByteSink(capacity: length);
    sink.u16be(12);
    sink.u16be(0); // Reserved.
    sink.u32be(length);
    sink.u32be(0); // Language-neutral Unicode mapping.
    sink.u32be(groups.length);
    for (final group in groups) {
      sink.u32be(group.start);
      sink.u32be(group.end);
      sink.u32be(group.startGid);
    }
    return sink.takeBytes();
  }

  static bool _isUnicodeScalar(int value) =>
      value >= 0 && value <= 0x10FFFF && (value < 0xD800 || value > 0xDFFF);

  static Uint8List _minimalName(String family) {
    final String name = family.isEmpty ? 'Subset' : family;
    final Uint8List utf16 = Uint8List(name.length * 2);
    for (int i = 0; i < name.length; i++) {
      utf16[i * 2] = (name.codeUnitAt(i) >> 8) & 0xFF;
      utf16[i * 2 + 1] = name.codeUnitAt(i) & 0xFF;
    }
    final ByteSink sink = ByteSink();
    sink.u16be(0);
    sink.u16be(1);
    sink.u16be(18);
    sink.u16be(3);
    sink.u16be(1);
    sink.u16be(0x0409);
    sink.u16be(1);
    sink.u16be(utf16.length);
    sink.u16be(0);
    sink.add(utf16);
    return sink.takeBytes();
  }

  static Uint8List _wrapSfnt(Map<String, Uint8List> tables) {
    final List<String> tags = tables.keys.toList()..sort();
    final int numTables = tags.length;
    final int searchRange = _pow2le(numTables) * 16;
    final int entrySelector = _log2(_pow2le(numTables));
    final int rangeShift = numTables * 16 - searchRange;
    var offset = 12 + numTables * 16;
    final List<int> offsets = <int>[];
    final List<Uint8List> padded = <Uint8List>[];
    for (final String tag in tags) {
      offsets.add(offset);
      final Uint8List data = tables[tag]!;
      final int pad = (4 - (data.length % 4)) % 4;
      final Uint8List block = Uint8List(data.length + pad)..setAll(0, data);
      padded.add(block);
      offset += block.length;
    }
    final ByteSink sink = ByteSink(capacity: offset);
    sink.u32be(0x00010000);
    sink.u16be(numTables);
    sink.u16be(searchRange);
    sink.u16be(entrySelector);
    sink.u16be(rangeShift);
    for (int i = 0; i < tags.length; i++) {
      final String tag = tags[i];
      final Uint8List data = tables[tag]!;
      sink.add(tag.codeUnits);
      sink.u32be(_checksum(padded[i]));
      sink.u32be(offsets[i]);
      sink.u32be(data.length);
    }
    for (final Uint8List block in padded) {
      sink.add(block);
    }
    final Uint8List file = sink.takeBytes();
    final int fileSum = _checksum(file);
    final int adjust = (0xB1B0AFBA - fileSum) & 0xFFFFFFFF;
    final int headOffset = offsets[tags.indexOf('head')];
    ByteData.sublistView(file).setUint32(headOffset + 8, adjust);
    return file;
  }

  static int _checksum(Uint8List data) {
    var sum = 0;
    for (int i = 0; i + 3 < data.length; i += 4) {
      sum =
          (sum +
              ((data[i] << 24) |
                  (data[i + 1] << 16) |
                  (data[i + 2] << 8) |
                  data[i + 3])) &
          0xFFFFFFFF;
    }
    return sum;
  }

  static int _pow2le(int n) {
    var p = 1;
    while ((p << 1) <= n) {
      p <<= 1;
    }
    return p;
  }

  static int _log2(int n) {
    var v = 0;
    var x = n;
    while (x > 1) {
      x >>= 1;
      v++;
    }
    return v;
  }
}

// OpenType OS/2 Unicode-range bit assignments (v4 and later), sorted by
// scalar value for binary lookup. Bit 57 describes all supplementary scalars
// and is handled separately. Unassigned bits remain clear.
// Numeric transcription via FontTools 4.61.1 OS2_UNICODE_RANGES (MIT).
// Attribution and license: third_party/fonttools/LICENSE in this package.
// https://learn.microsoft.com/en-us/typography/opentype/spec/os2#ulunicoderange1
const _unicodeRanges = <(int, int, int)>[
  (0x0000, 0x007f, 0),
  (0x0080, 0x00ff, 1),
  (0x0100, 0x017f, 2),
  (0x0180, 0x024f, 3),
  (0x0250, 0x02af, 4),
  (0x02b0, 0x02ff, 5),
  (0x0300, 0x036f, 6),
  (0x0370, 0x03ff, 7),
  (0x0400, 0x04ff, 9),
  (0x0500, 0x052f, 9),
  (0x0530, 0x058f, 10),
  (0x0590, 0x05ff, 11),
  (0x0600, 0x06ff, 13),
  (0x0700, 0x074f, 71),
  (0x0750, 0x077f, 13),
  (0x0780, 0x07bf, 72),
  (0x07c0, 0x07ff, 14),
  (0x0900, 0x097f, 15),
  (0x0980, 0x09ff, 16),
  (0x0a00, 0x0a7f, 17),
  (0x0a80, 0x0aff, 18),
  (0x0b00, 0x0b7f, 19),
  (0x0b80, 0x0bff, 20),
  (0x0c00, 0x0c7f, 21),
  (0x0c80, 0x0cff, 22),
  (0x0d00, 0x0d7f, 23),
  (0x0d80, 0x0dff, 73),
  (0x0e00, 0x0e7f, 24),
  (0x0e80, 0x0eff, 25),
  (0x0f00, 0x0fff, 70),
  (0x1000, 0x109f, 74),
  (0x10a0, 0x10ff, 26),
  (0x1100, 0x11ff, 28),
  (0x1200, 0x137f, 75),
  (0x1380, 0x139f, 75),
  (0x13a0, 0x13ff, 76),
  (0x1400, 0x167f, 77),
  (0x1680, 0x169f, 78),
  (0x16a0, 0x16ff, 79),
  (0x1700, 0x171f, 84),
  (0x1720, 0x173f, 84),
  (0x1740, 0x175f, 84),
  (0x1760, 0x177f, 84),
  (0x1780, 0x17ff, 80),
  (0x1800, 0x18af, 81),
  (0x1900, 0x194f, 93),
  (0x1950, 0x197f, 94),
  (0x1980, 0x19df, 95),
  (0x19e0, 0x19ff, 80),
  (0x1a00, 0x1a1f, 96),
  (0x1b00, 0x1b7f, 27),
  (0x1b80, 0x1bbf, 112),
  (0x1c00, 0x1c4f, 113),
  (0x1c50, 0x1c7f, 114),
  (0x1d00, 0x1d7f, 4),
  (0x1d80, 0x1dbf, 4),
  (0x1dc0, 0x1dff, 6),
  (0x1e00, 0x1eff, 29),
  (0x1f00, 0x1fff, 30),
  (0x2000, 0x206f, 31),
  (0x2070, 0x209f, 32),
  (0x20a0, 0x20cf, 33),
  (0x20d0, 0x20ff, 34),
  (0x2100, 0x214f, 35),
  (0x2150, 0x218f, 36),
  (0x2190, 0x21ff, 37),
  (0x2200, 0x22ff, 38),
  (0x2300, 0x23ff, 39),
  (0x2400, 0x243f, 40),
  (0x2440, 0x245f, 41),
  (0x2460, 0x24ff, 42),
  (0x2500, 0x257f, 43),
  (0x2580, 0x259f, 44),
  (0x25a0, 0x25ff, 45),
  (0x2600, 0x26ff, 46),
  (0x2700, 0x27bf, 47),
  (0x27c0, 0x27ef, 38),
  (0x27f0, 0x27ff, 37),
  (0x2800, 0x28ff, 82),
  (0x2900, 0x297f, 37),
  (0x2980, 0x29ff, 38),
  (0x2a00, 0x2aff, 38),
  (0x2b00, 0x2bff, 37),
  (0x2c00, 0x2c5f, 97),
  (0x2c60, 0x2c7f, 29),
  (0x2c80, 0x2cff, 8),
  (0x2d00, 0x2d2f, 26),
  (0x2d30, 0x2d7f, 98),
  (0x2d80, 0x2ddf, 75),
  (0x2de0, 0x2dff, 9),
  (0x2e00, 0x2e7f, 31),
  (0x2e80, 0x2eff, 59),
  (0x2f00, 0x2fdf, 59),
  (0x2ff0, 0x2fff, 59),
  (0x3000, 0x303f, 48),
  (0x3040, 0x309f, 49),
  (0x30a0, 0x30ff, 50),
  (0x3100, 0x312f, 51),
  (0x3130, 0x318f, 52),
  (0x3190, 0x319f, 59),
  (0x31a0, 0x31bf, 51),
  (0x31c0, 0x31ef, 61),
  (0x31f0, 0x31ff, 50),
  (0x3200, 0x32ff, 54),
  (0x3300, 0x33ff, 55),
  (0x3400, 0x4dbf, 59),
  (0x4dc0, 0x4dff, 99),
  (0x4e00, 0x9fff, 59),
  (0xa000, 0xa48f, 83),
  (0xa490, 0xa4cf, 83),
  (0xa500, 0xa63f, 12),
  (0xa640, 0xa69f, 9),
  (0xa700, 0xa71f, 5),
  (0xa720, 0xa7ff, 29),
  (0xa800, 0xa82f, 100),
  (0xa840, 0xa87f, 53),
  (0xa880, 0xa8df, 115),
  (0xa900, 0xa92f, 116),
  (0xa930, 0xa95f, 117),
  (0xaa00, 0xaa5f, 118),
  (0xac00, 0xd7af, 56),
  (0xe000, 0xf8ff, 60),
  (0xf900, 0xfaff, 61),
  (0xfb00, 0xfb4f, 62),
  (0xfb50, 0xfdff, 63),
  (0xfe00, 0xfe0f, 91),
  (0xfe10, 0xfe1f, 65),
  (0xfe20, 0xfe2f, 64),
  (0xfe30, 0xfe4f, 65),
  (0xfe50, 0xfe6f, 66),
  (0xfe70, 0xfeff, 67),
  (0xff00, 0xffef, 68),
  (0xfff0, 0xffff, 69),
  (0x10000, 0x1007f, 101),
  (0x10080, 0x100ff, 101),
  (0x10100, 0x1013f, 101),
  (0x10140, 0x1018f, 102),
  (0x10190, 0x101cf, 119),
  (0x101d0, 0x101ff, 120),
  (0x10280, 0x1029f, 121),
  (0x102a0, 0x102df, 121),
  (0x10300, 0x1032f, 85),
  (0x10330, 0x1034f, 86),
  (0x10380, 0x1039f, 103),
  (0x103a0, 0x103df, 104),
  (0x10400, 0x1044f, 87),
  (0x10450, 0x1047f, 105),
  (0x10480, 0x104af, 106),
  (0x10800, 0x1083f, 107),
  (0x10900, 0x1091f, 58),
  (0x10920, 0x1093f, 121),
  (0x10a00, 0x10a5f, 108),
  (0x12000, 0x123ff, 110),
  (0x12400, 0x1247f, 110),
  (0x1d000, 0x1d0ff, 88),
  (0x1d100, 0x1d1ff, 88),
  (0x1d200, 0x1d24f, 88),
  (0x1d300, 0x1d35f, 109),
  (0x1d360, 0x1d37f, 111),
  (0x1d400, 0x1d7ff, 89),
  (0x1f000, 0x1f02f, 122),
  (0x1f030, 0x1f09f, 122),
  (0x20000, 0x2a6df, 59),
  (0x2f800, 0x2fa1f, 61),
  (0xe0000, 0xe007f, 92),
  (0xe0100, 0xe01ef, 91),
  (0xf0000, 0xffffd, 90),
  (0x100000, 0x10fffd, 90),
];

typedef _GlyphReference = ({int glyphId, int offset});

class _Seg {
  const _Seg(this.start, this.end, this.startGid);

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// startGid API.
  final int startGid;
}
