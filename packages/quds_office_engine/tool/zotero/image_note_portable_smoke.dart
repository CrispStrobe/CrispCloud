import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_zotero_note.dart';

// Fixed synthetic 3 x 2 images generated with Pillow: RGBA PNG, 2-bit palette
// PNG with transparency, and three-component JPEG. Keeping the encoded bytes
// fixed makes this a decoder/parser equivalence check, independent of encoder
// floating-point choices. No filesystem, network, Flutter, or clock is used.
const _transparent =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAGklEQVR42gXBAQEAAAjDIJ7c6BNEcmSlSeMBhKQJevvojIYAAAAASUVORK5CYII=';
const _indexed =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACAgMAAADgGo6JAAAADFBMVEX/AAAA/wAAAP8AAAD7vkbkAAAAA3RSTlMAf/9/005qAAAADElEQVR42mOQYJgAAADcAKlSGhOPAAAAAElFTkSuQmCC';
const _jpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAMDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAT/xAAcEAEAAwACAwAAAAAAAAAAAAABAAIEAwYFITH/xAAVAQEBAAAAAAAAAAAAAAAAAAAFB//EAB4RAAAEBwAAAAAAAAAAAAAAAAABAgQFMzVxcrGy/9oADAMBAAIRAxEAPwCbtPjcB2bdUxZgrcqBxV9BUA+RESmQenN8EckH2shFi0P/2Q==';
const _citation = '<a href="https://www.zotero.org/?ABC123">(Author)</a>';

void main() {
  final results = <Map<String, Object?>>[];
  void check(String name, Map<String, Object?> Function() operation) {
    try {
      results.add({'behavior': name, 'passed': true, 'observed': operation()});
    } on Object catch (error) {
      results.add({'behavior': name, 'passed': false, 'error': '$error'});
    }
  }

  check('transparent_png_fractional_dimensions', () {
    final note = _read(
      _tag(
        _transparent,
        attributes:
            'width="53" height="35.333333333333336" '
            'alt="Red &gt; green" title="Sample"',
      ),
    );
    final visual = _pictures(note).single.inlineVisual!.visual;
    final decoded = image.decodePng(visual.imageBytes!)!;
    final alpha = [
      for (var x = 0; x < 3; x++) decoded.getPixel(x, 0).a.toInt(),
    ];
    _require(
      _sameBytes(visual.imageBytes!, base64.decode(_transparent)),
      'PNG bytes changed',
    );
    _require(alpha.join(',') == '255,127,0', 'Transparent PNG pixels changed');
    _require(
      _emu(visual.width) == 504825 && _emu(visual.height) == 336550,
      'Fractional image dimensions changed',
    );
    _require(
      visual.picture.altDescription == 'Red > green' &&
          visual.picture.altTitle == 'Sample',
      'Alternative image text changed',
    );
    return {
      ..._raster(visual),
      'first_row_alpha': alpha,
      'alternative_text': visual.picture.altDescription,
      'title': visual.picture.altTitle,
    };
  });

  check('indexed_png_palette_alpha', () {
    final visual = _pictures(_read(_tag(_indexed))).single.inlineVisual!.visual;
    final decoded = image.decodePng(visual.imageBytes!)!;
    final pixels = [
      for (var x = 0; x < 3; x++)
        [
          decoded.getPixel(x, 0).r.toInt(),
          decoded.getPixel(x, 0).g.toInt(),
          decoded.getPixel(x, 0).b.toInt(),
          decoded.getPixel(x, 0).a.toInt(),
        ],
    ];
    _require(
      jsonEncode(pixels) == '[[255,0,0,0],[0,255,0,127],[0,0,255,255]]',
      'Indexed PNG palette or alpha changed',
    );
    _require(
      _sameBytes(visual.imageBytes!, base64.decode(_indexed)),
      'Indexed PNG bytes changed',
    );
    return {..._raster(visual), 'first_row_rgba': pixels};
  });

  check('jpeg_original_payload_and_intrinsic_ratio', () {
    final visual = _pictures(
      _read(_tag(_jpeg, mime: 'jpeg', attributes: 'width="96"')),
    ).single.inlineVisual!.visual;
    _require(
      _sameBytes(visual.imageBytes!, base64.decode(_jpeg)),
      'JPEG bytes changed',
    );
    _require(
      _emu(visual.width) == 914400 && _emu(visual.height) == 609600,
      'JPEG ratio or CSS pixel conversion changed',
    );
    return _raster(visual);
  });

  check('unicode_and_image_citation_offsets', () {
    final note = _read(
      '<p>Before 🧭 ${_tag(_transparent)} $_citation after</p>',
    );
    final placeholder = note.placeholders['ABC123']!;
    _require(
      note.plainText == 'Before 🧭 \uFFFC (Author) after',
      'Note text order changed',
    );
    _require(
      placeholder.start == 12 && placeholder.end == 20,
      'UTF-16 citation offsets changed',
    );
    _require(
      _pictures(note).single.isAtomic,
      'The image is not an atomic inline',
    );
    return {
      'text': note.plainText,
      'citation_start': placeholder.start,
      'citation_end': placeholder.end,
      'picture_atomic': true,
    };
  });

  check('ordinary_image_hyperlink', () {
    final note = _read(
      '<p>Before <a href="https://example.org/?a=1&amp;b=2">'
      '${_tag(_transparent)} linked</a> after</p>',
    );
    final picture = _pictures(note).single;
    _require(
      picture.hyperlink?.url == 'https://example.org/?a=1&b=2',
      'Image hyperlink changed',
    );
    _require(
      note.paragraphs.single.inlines.whereType<WmlRun>().last.hyperlink == null,
      'Image link absorbed following prose',
    );
    return {
      'text': note.plainText,
      'image_link': picture.hyperlink!.url,
      'following_text_linked': false,
    };
  });

  check('image_only_list_structure', () {
    final note = _read('<h2>Research</h2><ul><li>${_tag(_indexed)}</li></ul>');
    _require(
      note.paragraphs.length == 2 && note.paragraphs[1].text == '\uFFFC',
      'Image-only list item changed',
    );
    _require(
      note.paragraphs.first.properties.headingLevel == 2 &&
          note.listItems.containsKey(1),
      'Research note structure changed',
    );
    return {
      'paragraphs': note.paragraphs.map((p) => p.text).toList(),
      'heading_level': 2,
      'list_paragraph': 1,
      'pictures': _pictures(note).length,
    };
  });

  check('png_crc_and_adler_rejection', () {
    final corruptCrc = base64.decode(_transparent)..[30] ^= 1;
    final corruptAdler = _rewritePng(base64.decode(_transparent), (type, data) {
      if (type == 'IDAT') data[data.length - 1] ^= 1;
    });
    final outcomes = [
      _reject(_tag(base64.encode(corruptCrc))),
      _reject(_tag(base64.encode(corruptAdler))),
    ];
    _require(
      outcomes.every((kind) => kind == 'FormatException'),
      'Invalid PNG checksum accepted',
    );
    return {'rejections': outcomes};
  });

  check('raster_bounds_before_pixel_decoding', () {
    final dimension = _rewritePng(base64.decode(_transparent), (type, data) {
      if (type == 'IHDR') ByteData.sublistView(data).setUint32(0, 8193);
    });
    final scanlines = _rewritePng(base64.decode(_transparent), (type, data) {
      if (type == 'IHDR') {
        ByteData.sublistView(data)
          ..setUint32(0, 4096)
          ..setUint32(4, 4096);
        data[8] = 16;
      }
    });
    final outcomes = [
      _reject(_tag(base64.encode(dimension))),
      _reject(_tag(base64.encode(scanlines))),
    ];
    _require(
      outcomes.every((kind) => kind == 'FormatException'),
      'Raster budget was not enforced',
    );
    return {'rejections': outcomes};
  });

  check('external_and_mismatched_images_rejected', () {
    final outcomes = [
      _reject('<img src="https://example.org/image.png">'),
      _reject('<img src="file:///tmp/image.png">'),
      _reject('<img src="data:image/svg+xml;base64,PHN2Zy8+">'),
      _reject(_tag(_transparent, mime: 'jpeg')),
    ];
    _require(
      outcomes.join(',') ==
          'UnsupportedError,UnsupportedError,UnsupportedError,FormatException',
      'An unsupported image source was accepted',
    );
    return {'rejections': outcomes};
  });

  check('placeholder_marker_and_note_count_guards', () {
    final tag = _tag(_transparent);
    final accepted = _read('<p>${List.filled(32, tag).join()}</p>');
    _require(
      _pictures(accepted).length == 32,
      'The documented image count was not accepted',
    );
    final outcomes = [
      _reject('<a href="https://www.zotero.org/?ABC123">$tag</a>'),
      _reject('<p>&#57344;i0&#57345;$tag</p>'),
      _reject('<p>${List.filled(33, tag).join()}</p>'),
    ];
    _require(
      outcomes.join(',') == 'UnsupportedError,FormatException,FormatException',
      'A note image boundary was not enforced',
    );
    return {'accepted_image_count': 32, 'rejections': outcomes};
  });

  final passed = results.where((result) => result['passed'] == true).length;
  print(
    jsonEncode({
      'schema': 1,
      'suite': 'zotero-image-note-portable',
      'behavior_count': results.length,
      'passed': passed,
      'results': results,
    }),
  );
  if (passed != results.length) {
    throw StateError('Portable Zotero image-note smoke failed.');
  }
}

WordZoteroNoteText _read(String html) => WordZoteroNoteText.fromHtml(html);
String _tag(String data, {String mime = 'png', String attributes = ''}) =>
    '<img src="data:image/$mime;base64,$data" $attributes>';
List<WmlRun> _pictures(WordZoteroNoteText note) => [
  for (final paragraph in note.paragraphs)
    for (final run in paragraph.inlines.whereType<WmlRun>())
      if (run.inlineVisual != null) run,
];
int _emu(double points) => (points * 12700).round();
Map<String, Object?> _raster(OfficeVisual visual) => {
  'sha256': crypto.sha256.convert(visual.imageBytes!).toString(),
  'encoded_bytes': visual.imageBytes!.length,
  'width_emu': _emu(visual.width),
  'height_emu': _emu(visual.height),
};
bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String _reject(String html) {
  try {
    _read(html);
  } on FormatException {
    return 'FormatException';
  } on UnsupportedError {
    return 'UnsupportedError';
  }
  throw StateError('Malformed or unsupported image was accepted.');
}

// Rebuild every CRC after a controlled payload mutation. In particular, the
// Adler control must reach zlib validation instead of failing an earlier CRC.
Uint8List _rewritePng(
  Uint8List input,
  void Function(String type, Uint8List data) change,
) {
  final out = BytesBuilder()..add(input.sublist(0, 8));
  var offset = 8;
  while (offset + 12 <= input.length) {
    final length = ByteData.sublistView(input).getUint32(offset);
    final type = ascii.decode(input.sublist(offset + 4, offset + 8));
    final data = Uint8List.fromList(
      input.sublist(offset + 8, offset + 8 + length),
    );
    change(type, data);
    final chunk = Uint8List(data.length + 12);
    final view = ByteData.sublistView(chunk)..setUint32(0, data.length);
    chunk
      ..setRange(4, 8, ascii.encode(type))
      ..setRange(8, 8 + data.length, data);
    view.setUint32(
      chunk.length - 4,
      Crc32.compute(Uint8List.sublistView(chunk, 4, chunk.length - 4)),
    );
    out.add(chunk);
    offset += length + 12;
  }
  return out.toBytes();
}
