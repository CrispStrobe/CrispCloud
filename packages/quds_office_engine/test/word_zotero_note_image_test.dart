import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note_image.dart';
import 'package:test/test.dart';

final _png = image.encodePng(
  image.Image(width: 8, height: 4, numChannels: 4)
    ..setPixelRgba(0, 0, 255, 0, 0, 127)
    ..setPixelRgba(7, 3, 0, 255, 0, 255),
);
final _jpeg = image.encodeJpg(image.Image(width: 8, height: 4, numChannels: 3));
const _placeholder = '<a href="https://www.zotero.org/?ABC123">(Author)</a>';

String _data(Uint8List bytes, [String mime = 'png']) =>
    'data:image/$mime;base64,${base64.encode(bytes)}';
String _tag({Uint8List? bytes, String mime = 'png', String attributes = ''}) =>
    '<img src="${_data(bytes ?? _png, mime)}" $attributes>';
List<WmlRun> _pictures(WordZoteroNoteText note) => [
  for (final paragraph in note.paragraphs)
    for (final run in paragraph.inlines.whereType<WmlRun>())
      if (run.inlineVisual != null) run,
];
void _reject(String html) => expect(
  () => WordZoteroNoteText.fromHtml(html),
  throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
);

Uint8List _chunk(String type, List<int> data) {
  final bytes = Uint8List(data.length + 12);
  ByteData.sublistView(bytes).setUint32(0, data.length);
  bytes.setRange(4, 8, ascii.encode(type));
  bytes.setRange(8, 8 + data.length, data);
  ByteData.sublistView(bytes).setUint32(
    bytes.length - 4,
    Crc32.compute(Uint8List.sublistView(bytes, 4, bytes.length - 4)),
  );
  return bytes;
}

Uint8List _rewrite(
  Uint8List bytes,
  List<Uint8List> Function(String type, Uint8List data) replace,
) {
  final out = BytesBuilder()..add(bytes.sublist(0, 8));
  var position = 8;
  while (position + 12 <= bytes.length) {
    final count = ByteData.sublistView(bytes).getUint32(position);
    final type = ascii.decode(bytes.sublist(position + 4, position + 8));
    final data = Uint8List.sublistView(
      bytes,
      position + 8,
      position + 8 + count,
    );
    for (final chunk in replace(type, data)) {
      out.add(chunk);
    }
    position += count + 12;
  }
  return out.toBytes();
}

Uint8List _header({int? width, int? height, int? depth, int? color}) =>
    _rewrite(_png, (type, data) {
      final copy = Uint8List.fromList(data);
      if (type == 'IHDR') {
        final view = ByteData.sublistView(copy);
        if (width != null) view.setUint32(0, width);
        if (height != null) view.setUint32(4, height);
        if (depth != null) copy[8] = depth;
        if (color != null) copy[9] = color;
      }
      return [_chunk(type, copy)];
    });

Uint8List _pixelStream(List<int> pixels) {
  var written = false;
  return _rewrite(_png, (type, data) {
    if (type != 'IDAT') return [_chunk(type, data)];
    if (written) return [];
    written = true;
    return [_chunk('IDAT', archive.ZLibEncoder().encode(pixels))];
  });
}

Uint8List _exifJpeg(int orientation) {
  final data = Uint8List(32);
  data.setRange(0, 6, [69, 120, 105, 102, 0, 0]);
  final tiff = ByteData.sublistView(data, 6);
  tiff
    ..setUint16(0, 0x4949)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, 8, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 0x112, Endian.little)
    ..setUint16(12, 3, Endian.little)
    ..setUint32(14, 1, Endian.little)
    ..setUint16(18, orientation, Endian.little);
  final segment = Uint8List(data.length + 4)
    ..setRange(0, 2, [255, 225])
    ..setRange(4, data.length + 4, data);
  ByteData.sublistView(segment).setUint16(2, data.length + 2);
  return (BytesBuilder()
        ..add(_jpeg.sublist(0, 2))
        ..add(segment)
        ..add(_jpeg.sublist(2)))
      .toBytes();
}

void main() {
  test(
    'native image annotation retains raster, source locator placeholder, and comment',
    () {
      // Shape emitted by Zotero EditorInstanceUtilities.serializeAnnotations and
      // Notes.getExportableNote, then sent by integration.js:_processNote.
      final note = WordZoteroNoteText.fromHtml(
        '<html><body><div data-schema-version="9" data-citation-items="%5B%5D">'
        '<p>${_tag(attributes: 'class="image" width="160" height="80" '
            'data-annotation="%7B%22pageLabel%22%3A%224%22%7D"')}'
        '<br>$_placeholder My comment</p></div></body></html>',
      );
      expect(note.plainText, '\uFFFC\n(Author) My comment');
      final run = _pictures(note).single;
      expect(run.text, '\uFFFC');
      expect(run.isAtomic, isTrue);
      expect(run.inlineVisual!.visual.imageBytes, _png);
      expect(run.inlineVisual!.visual.width, 120);
      expect(run.inlineVisual!.visual.height, 60);
      final placeholder = note.placeholders['ABC123']!;
      expect(placeholder.paragraphIndex, 0);
      expect(placeholder.start, 2);
      expect(placeholder.end, 10);
    },
  );

  test(
    'picture-only note accepts HTML void img and quoted greater-than attributes',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<p>${_tag(attributes: 'alt="Diagram &gt; text &amp; context" '
            'title=\'A > B "title"\'')}</p>',
      );
      expect(note.paragraphs.single.text, '\uFFFC');
      final visual = _pictures(note).single.inlineVisual!.visual;
      expect(visual.width, 6);
      expect(visual.height, 3);
      expect(visual.picture.altDescription, 'Diagram > text & context');
      expect(visual.picture.altTitle, 'A > B "title"');
      expect(visual.title, 'A > B "title"');
      expect(note.placeholders, isEmpty);
    },
  );

  test(
    'self-closing image and ink class preserve explicitly authored dimensions',
    () {
      final note = WordZoteroNoteText.fromHtml(
        _tag(attributes: 'class="ink" width="100" height="100"/'),
      );
      final visual = _pictures(note).single.inlineVisual!.visual;
      expect(visual.width, 75);
      expect(visual.height, 75);
      expect(visual.imageBytes, _png);
    },
  );

  test(
    'image markers retain surrounding rich text and one-character offsets',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<p>Before <b>${_tag()}bold</b> $_placeholder ${_tag()} after</p>',
      );
      expect(note.plainText, 'Before \uFFFCbold (Author) \uFFFC after');
      final pictures = _pictures(note);
      expect(pictures, hasLength(2));
      expect(pictures.first.properties.bold, isTrue);
      expect(pictures.last.properties.bold, isFalse);
      final placeholder = note.placeholders['ABC123']!;
      expect(
        note.paragraphs.single.text.substring(
          placeholder.start,
          placeholder.end,
        ),
        '(Author)',
      );
      expect(placeholder.start, 13);
    },
  );

  test(
    'images retain normal hyperlink membership without absorbing adjacent text',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<p>Before <a href="https://example.org/research">${_tag()} link</a> after</p>',
      );
      final picture = _pictures(note).single;
      expect(picture.hyperlink!.url, 'https://example.org/research');
      expect(
        note.paragraphs.single.inlines.whereType<WmlRun>().last.hyperlink,
        isNull,
      );
      final onlyImageLink = WordZoteroNoteText.fromHtml(
        '<a href="zotero://open-pdf/library/items/ABCD1234?page=4">${_tag()}</a>',
      );
      expect(
        _pictures(onlyImageLink).single.hyperlink!.url,
        contains('page=4'),
      );
    },
  );

  test(
    'images inside active citation placeholders refuse the complete note',
    () {
      _reject(
        '<p>Keep me <a href="https://www.zotero.org/?ABC123">${_tag()}</a></p>',
      );
      _reject(
        '<p><a href="https://www.zotero.org/?ABC123">text ${_tag()}</a></p>',
      );
    },
  );

  test(
    'image headings, flat lists, and image-only list items keep structure',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<h2>${_tag()} Heading</h2><ul><li>${_tag()}</li>'
        '<li><p>Item ${_tag()} $_placeholder</p></li></ul>',
      );
      expect(note.paragraphs.map((p) => p.text), [
        '\uFFFC Heading',
        '\uFFFC',
        'Item \uFFFC (Author)',
      ]);
      expect(note.paragraphs.first.properties.headingLevel, 2);
      expect(note.listItems.keys, [1, 2]);
      expect(note.placeholders['ABC123']!.paragraphIndex, 2);
      expect(_pictures(note), hasLength(3));
    },
  );

  test(
    'uppercase HTML void tags and markup-looking comments do not create pictures',
    () {
      final note = WordZoteroNoteText.fromHtml(
        '<!-- <img src="https://example.org/never" title=">"> -->'
        '<P><IMG SRC="${_data(_png)}"><BR>after</P>',
      );
      expect(note.plainText, '\uFFFC\nafter');
      expect(_pictures(note), hasLength(1));
    },
  );

  test(
    'JPEG data uses genuine intrinsic dimensions and retains original bytes',
    () {
      final note = WordZoteroNoteText.fromHtml(
        _tag(bytes: _jpeg, mime: 'jpeg'),
      );
      final visual = _pictures(note).single.inlineVisual!.visual;
      expect(visual.imageBytes, _jpeg);
      expect(visual.width, 6);
      expect(visual.height, 3);
    },
  );

  test(
    'missing width or height derives the other dimension from the raster ratio',
    () {
      final byWidth = _pictures(
        WordZoteroNoteText.fromHtml(_tag(attributes: 'width="160"')),
      ).single.inlineVisual!.visual;
      expect((byWidth.width, byWidth.height), (120, 60));
      final byHeight = _pictures(
        WordZoteroNoteText.fromHtml(
          _tag(bytes: _jpeg, mime: 'jpeg', attributes: 'height="80"'),
        ),
      ).single.inlineVisual!.visual;
      expect((byHeight.width, byHeight.height), (120, 60));
    },
  );

  test(
    'upright EXIF JPEG is accepted and rotated or flipped variants are refused',
    () {
      final upright = _exifJpeg(1);
      expect(
        _pictures(
          WordZoteroNoteText.fromHtml(_tag(bytes: upright, mime: 'jpeg')),
        ).single.inlineVisual!.visual.imageBytes,
        upright,
      );
      for (final orientation in [2, 3, 4, 5, 6, 7, 8]) {
        _reject(_tag(bytes: _exifJpeg(orientation), mime: 'jpeg'));
      }
    },
  );

  test('non-RGB JPEG component layouts are refused before rendering', () {
    final bytes = Uint8List.fromList(_jpeg);
    var offset = 2;
    while (bytes[offset + 1] != 0xc0) {
      offset += 2 + ByteData.sublistView(bytes).getUint16(offset + 2);
    }
    bytes[offset + 9] = 1;
    _reject(_tag(bytes: bytes, mime: 'jpeg'));
    bytes[offset + 9] = 4;
    _reject(_tag(bytes: bytes, mime: 'jpeg'));
  });

  test('external or unsupported source formats never become images', () {
    for (final src in [
      'https://example.org/image.png',
      'http://localhost/image.png',
      'file:///tmp/image.png',
      'blob:https://example.org/id',
      'javascript:alert(1)',
      'zotero://attachment/ABCD1234',
      'data:image/svg+xml;base64,PHN2Zy8+',
      'data:image/gif;base64,R0lGODlh',
      'data:image/png,not-base64',
      'data:image/jpg;base64,AAAA',
      'data:application/octet-stream;base64,AAAA',
    ]) {
      _reject('<p>Before<img src="$src">After</p>');
    }
    _reject('<img data-attachment-key="ABCD1234">');
    _reject('<img>');
  });

  test(
    'custom styling, image handlers, and unresolved attachment data refuse',
    () {
      for (final attributes in [
        'style="width:120px"',
        'style="display:none"',
        'class="custom-image"',
        'onload="anything"',
        'srcset="image.png 2x"',
        'data-attachment-key="ABCD1234"',
        'width="100" WIDTH="100"',
      ]) {
        _reject(_tag(attributes: attributes));
      }
      expect(
        _pictures(
          WordZoteroNoteText.fromHtml(
            _tag(attributes: 'style=" " class="image ink" alt=""'),
          ),
        ),
        hasLength(1),
      );
    },
  );

  test('malformed base64 and MIME mismatches refuse before insertion', () {
    for (final src in [
      'data:image/png;base64,',
      'data:image/png;base64,====',
      'data:image/png;base64,AAAA===',
      'data:image/png;base64,AA_A',
      'data:image/png;base64,AA%2BA',
      'data:image/png;base64,AA\nAA',
      _data(_jpeg),
      _data(_png, 'jpeg'),
    ]) {
      _reject('<img src="$src">');
    }
  });

  test(
    'image marker spoofing through text or decoded attributes is refused',
    () {
      for (final marker in [
        '\uE000i0\uE001',
        '&#57344;i0&#57345;',
        '&#xE000;i0&#xE001;',
      ]) {
        _reject('<p>$marker${_tag()}</p>');
        _reject(_tag(attributes: 'alt="$marker"'));
        _reject(_tag(attributes: 'data-annotation="$marker"'));
      }
    },
  );

  test('alternative image text cannot introduce invalid XML characters', () {
    for (final value in ['\u0000', '\u0001', '\uFFFE', '&#0;']) {
      _reject(_tag(attributes: 'alt="$value"'));
      _reject(_tag(attributes: 'title="$value"'));
    }
  });

  test('ordinary Zotero note keeps fractional aspect-ratio dimensions', () {
    // Upstream note-editor bdf61e0c275e483c3068ce4fcb86b44691b22afc:
    // node-views/image.js sends naturalHeight * width / naturalWidth unchanged
    // through editor-core.js and commands.js into schema/nodes.js serialization.
    const source =
        'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
    final note = WordZoteroNoteText.fromHtml(
      '<p>Before <img src="data:image/png;base64,$source" '
      'width="53" height="35.333333333333336" alt="Sample"> '
      '$_placeholder after</p>',
    );
    final visual = _pictures(note).single.inlineVisual!.visual;
    expect(visual.imageBytes, base64.decode(source));
    expect(visual.width, 39.75);
    expect(visual.height, closeTo(26.5, 0.000000001));
    expect(note.plainText, 'Before \uFFFC (Author) after');
    expect(note.placeholders['ABC123']!.start, 9);
    expect(note.placeholders['ABC123']!.end, 17);
    expect(
      _pictures(
        WordZoteroNoteText.fromHtml(
          _tag(attributes: 'width="80.5" height="40.25"'),
        ),
      ).single.inlineVisual!.visual.width,
      60.375,
    );
  });

  test(
    'invalid or unrepresentable authored dimensions are refused explicitly',
    () {
      for (final dimension in [
        '0',
        '-1',
        '2,5',
        '2..5',
        '+2',
        'Infinity',
        '1' * 33,
        '1e2',
        'NaN',
        '100%',
        '999999',
      ]) {
        _reject(_tag(attributes: 'width="$dimension"'));
        _reject(_tag(attributes: 'height="$dimension"'));
      }
      final tiny = image.encodePng(image.Image(width: 1, height: 1));
      _reject(_tag(bytes: tiny));
      final accepted = _pictures(
        WordZoteroNoteText.fromHtml(
          _tag(bytes: tiny, attributes: 'width="2" height="2"'),
        ),
      ).single.inlineVisual!.visual;
      expect((accepted.width, accepted.height), (1.5, 1.5));
    },
  );

  test('corrupt and truncated PNG chunks are refused', () {
    final checksum = Uint8List.fromList(_png)..[30] ^= 1;
    _reject(_tag(bytes: checksum));
    _reject(_tag(bytes: Uint8List.fromList(_png.sublist(0, _png.length - 1))));
    _reject(_tag(bytes: Uint8List.fromList([..._png, 0])));
    _reject(
      _tag(
        bytes: _rewrite(
          _png,
          (type, data) => type == 'IEND' ? [] : [_chunk(type, data)],
        ),
      ),
    );
    _reject(
      _tag(
        bytes: _rewrite(
          _png,
          (type, data) => type == 'IHDR'
              ? [_chunk(type, data), _chunk(type, data)]
              : [_chunk(type, data)],
        ),
      ),
    );
  });

  test(
    'PNG pixels require exact bounded scanline data and valid filter bytes',
    () {
      const expected = (8 * 4 + 1) * 4;
      _reject(_tag(bytes: _pixelStream(List.filled(expected - 1, 0))));
      _reject(_tag(bytes: _pixelStream(List.filled(expected + 1, 0))));
      _reject(_tag(bytes: _pixelStream(List.filled(expected, 0)..[0] = 5)));
      final accepted = _pixelStream(List.filled(expected, 0));
      expect(
        _pictures(WordZoteroNoteText.fromHtml(_tag(bytes: accepted))),
        hasLength(1),
      );
    },
  );

  test('bad PNG zlib checksums are refused even when chunk CRC is valid', () {
    final corrupted = _rewrite(_png, (type, data) {
      final copy = Uint8List.fromList(data);
      if (type == 'IDAT') copy[copy.length - 1] ^= 1;
      return [_chunk(type, copy)];
    });
    _reject(_tag(bytes: corrupted));
  });

  test('animated PNG control chunks are refused without flattening frames', () {
    for (final type in ['acTL', 'fcTL', 'fdAT']) {
      final animated = _rewrite(
        _png,
        (name, data) => [
          _chunk(name, data),
          if (name == 'IHDR') _chunk(type, List.filled(8, 0)),
        ],
      );
      _reject(_tag(bytes: animated));
    }
  });

  test(
    'PNG dimension and expanded-byte limits are checked before pixel inflation',
    () {
      for (final bytes in [
        _header(width: 0),
        _header(height: 0),
        _header(width: 8193),
        _header(width: 8192, height: 4096),
        _header(width: 8192, height: 2048, depth: 16),
        _header(color: 7),
        _header(depth: 3),
      ]) {
        _reject(_tag(bytes: bytes, attributes: 'width="80" height="40"'));
      }
    },
  );

  test(
    'compressed PNG metadata is bounded before native display or PDF decoding',
    () {
      final metadata = archive.ZLibEncoder().encode(
        List.filled(WordZoteroNoteImageReader.maxMetadataBytes + 1, 0),
      );
      final expanded = _rewrite(
        _png,
        (type, data) => [
          _chunk(type, data),
          if (type == 'IHDR') _chunk('zTXt', [75, 0, 0, ...metadata]),
        ],
      );
      _reject(_tag(bytes: expanded));
      final small = _rewrite(
        _png,
        (type, data) => [
          _chunk(type, data),
          if (type == 'IHDR')
            _chunk('zTXt', [
              75,
              0,
              0,
              ...archive.ZLibEncoder().encode(utf8.encode('caption')),
            ]),
        ],
      );
      expect(
        _pictures(WordZoteroNoteText.fromHtml(_tag(bytes: small))),
        hasLength(1),
      );
    },
  );

  test(
    'JPEG truncation, non-image bytes, and trailing payloads are refused',
    () {
      _reject(
        _tag(bytes: Uint8List.fromList([255, 216, 255, 217]), mime: 'jpeg'),
      );
      _reject(
        _tag(
          bytes: Uint8List.fromList(_jpeg.sublist(0, _jpeg.length - 2)),
          mime: 'jpeg',
        ),
      );
      _reject(_tag(bytes: Uint8List.fromList([..._jpeg, 1]), mime: 'jpeg'));
      final large = Uint8List.fromList(_jpeg);
      var offset = 2;
      while (large[offset + 1] != 0xc0) {
        offset += 2 + ByteData.sublistView(large).getUint16(offset + 2);
      }
      ByteData.sublistView(large).setUint16(offset + 5, 8193);
      _reject(_tag(bytes: large, mime: 'jpeg'));
    },
  );

  test('image count is bounded across the complete note', () {
    final tag = _tag();
    expect(
      _pictures(
        WordZoteroNoteText.fromHtml('<p>${List.filled(32, tag).join()}</p>'),
      ),
      hasLength(32),
    );
    _reject('<p>${List.filled(33, tag).join()}</p>');
  });

  test(
    'encoded image size refuses before attempting to decode invented pixels',
    () {
      _reject(
        _tag(bytes: Uint8List(WordZoteroNoteImageReader.maxImageBytes + 1)),
      );
    },
  );

  test(
    'total compressed image bytes are bounded independently of individual size',
    () {
      final large = _rewrite(
        _png,
        (type, data) => [
          _chunk(type, data),
          if (type == 'IHDR') _chunk('raNd', Uint8List(2 * 1024 * 1024)),
        ],
      );
      expect(
        _pictures(WordZoteroNoteText.fromHtml(_tag(bytes: large))),
        hasLength(1),
      );
      _reject('<p>${_tag(bytes: large)}${_tag(bytes: large)}</p>');
    },
  );

  test(
    'malformed image tag nesting or unfinished quotes refuse rather than swallowing prose',
    () {
      _reject('${_tag()}not-image-content</img>');
      _reject('<p><img src="${_data(_png)}" alt="unfinished></p>');
      _reject('<p>${_tag()}<img src="bad"></p>');
    },
  );
}
