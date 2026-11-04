import 'dart:typed_data';

import '../io/byte_source.dart';
import 'glyph_outlines.dart';
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

  /// subset API.
  FontSubset subset(Iterable<int> codePoints, {Iterable<int> extraGlyphIds = const <int>[]}) {
    final Set<int> wanted = <int>{0};
    final Map<int, int> unicodeToOld = <int, int>{};
    for (final int gid in extraGlyphIds) {
      if (gid > 0) {
        wanted.add(gid);
      }
    }
    for (final int cp in codePoints) {
      final int gid = font.glyphIdFor(cp);
      if (gid == 0) {
        continue;
      }
      wanted.add(gid);
      unicodeToOld[cp] = gid;
    }
    final GlyphOutlineDecoder decoder = GlyphOutlineDecoder(font);
    final List<int> pending = List<int>.from(wanted);
    while (pending.isNotEmpty) {
      final int gid = pending.removeLast();
      if (!font.hasTable('glyf')) {
        continue;
      }
      final GlyphOutline outline = decoder.decode(gid);
      for (final int child in outline.componentGlyphIds) {
        if (wanted.add(child)) {
          pending.add(child);
        }
      }
    }
    final List<int> oldIds = wanted.toList()..sort();
    final Map<int, int> oldToNew = <int, int>{
      for (int i = 0; i < oldIds.length; i++) oldIds[i]: i,
    };
    final Map<int, int> unicodeToNew = <int, int>{
      for (final MapEntry<int, int> e in unicodeToOld.entries)
        e.key: oldToNew[e.value] ?? 0,
    };

    final Uint8List? glyfSrc = font.hasTable('glyf')
        ? font.tableBytes('glyf')
        : null;
    final BytesBuilder glyfOut = BytesBuilder(copy: false);
    final List<int> loca = <int>[0];
    for (final int oldId in oldIds) {
      if (glyfSrc == null) {
        loca.add(0);
        continue;
      }
      final int start = font.glyphOffsets[oldId];
      final int end = font.glyphOffsets[oldId + 1];
      if (end > start) {
        final Uint8List slice = Uint8List.sublistView(glyfSrc, start, end);
        glyfOut.add(_remapComposite(slice, oldToNew));
      }
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
    for (final String tag in <String>['cvt ', 'fpgm', 'prep', 'gasp']) {
      if (font.hasTable(tag)) {
        outTables[tag] = font.tableBytes(tag);
      }
    }

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

  static Uint8List _remapComposite(Uint8List glyph, Map<int, int> oldToNew) {
    if (glyph.length < 2) {
      return glyph;
    }
    final int contours = ByteData.sublistView(glyph).getInt16(0);
    if (contours >= 0) {
      return glyph;
    }
    final Uint8List copy = Uint8List.fromList(glyph);
    int offset = 10;
    var more = true;
    while (more && offset + 4 <= copy.length) {
      final int flags = (copy[offset] << 8) | copy[offset + 1];
      final int oldGid = (copy[offset + 2] << 8) | copy[offset + 3];
      final int newGid = oldToNew[oldGid] ?? 0;
      copy[offset + 2] = (newGid >> 8) & 0xFF;
      copy[offset + 3] = newGid & 0xFF;
      offset += 4;
      if ((flags & 0x0001) != 0) {
        offset += 4;
      } else {
        offset += 2;
      }
      if ((flags & 0x0008) != 0) {
        offset += 2;
      } else if ((flags & 0x0040) != 0) {
        offset += 4;
      } else if ((flags & 0x0080) != 0) {
        offset += 8;
      }
      if ((flags & 0x0100) != 0 && offset + 2 <= copy.length) {
        final int n = (copy[offset] << 8) | copy[offset + 1];
        offset += 2 + n;
      }
      more = (flags & 0x0020) != 0;
    }
    return copy;
  }

  static Uint8List _buildCmap(Map<int, int> unicodeToNew) {
    final List<MapEntry<int, int>> bmp =
        unicodeToNew.entries
            .where((MapEntry<int, int> e) => e.key <= 0xFFFF)
            .toList()
          ..sort((MapEntry<int, int> a, MapEntry<int, int> b) => a.key - b.key);
    final List<_Seg> segs = <_Seg>[];
    if (bmp.isNotEmpty) {
      int start = bmp.first.key;
      int prev = bmp.first.key;
      int startGid = bmp.first.value;
      for (int i = 1; i < bmp.length; i++) {
        final int cp = bmp[i].key;
        final int gid = bmp[i].value;
        if (cp == prev + 1 && gid == startGid + (cp - start)) {
          prev = cp;
          continue;
        }
        segs.add(_Seg(start, prev, startGid));
        start = prev = cp;
        startGid = gid;
      }
      segs.add(_Seg(start, prev, startGid));
    }
    segs.add(const _Seg(0xFFFF, 0xFFFF, 0));

    final int segCount = segs.length;
    final int searchRange = _pow2le(segCount) * 2;
    final int entrySelector = _log2(_pow2le(segCount));
    final int rangeShift = segCount * 2 - searchRange;
    final int length = 16 + segCount * 8 + 2;
    final ByteSink sink = ByteSink(capacity: 32 + length);
    sink.u16be(0);
    sink.u16be(1);
    sink.u16be(3);
    sink.u16be(1);
    sink.u32be(12);
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

class _Seg {
  const _Seg(this.start, this.end, this.startGid);

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// startGid API.
  final int startGid;
}
