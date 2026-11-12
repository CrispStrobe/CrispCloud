import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:crisp_cloud/l10n/office_preview_strings.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/legacy_powerpoint_document.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();
Uint8List _record(
  int type,
  List<int> bytes, {
  int version = 0,
  int instance = 0,
}) {
  final header = ByteData(8)
    ..setUint16(0, (instance << 4) | version, Endian.little)
    ..setUint16(2, type, Endian.little)
    ..setUint32(4, bytes.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...bytes]);
}

List<int> _text(String text, {bool unicode = true}) {
  final encoded = ByteData(text.length * 2);
  for (var index = 0; index < text.length; index++) {
    encoded.setUint16(index * 2, text.codeUnitAt(index), Endian.little);
  }
  return [
    ..._record(0x0f9f, _u32(0)),
    ..._record(
      unicode ? 0x0fa0 : 0x0fa8,
      unicode ? encoded.buffer.asUint8List() : text.codeUnits,
    ),
  ];
}

Uint8List _slide({
  int? reference,
  String? text,
  int nestedDepth = 0,
  bool deleted = false,
}) {
  var shapes = _record(0xf004, [
    ..._record(0xf00a, [..._u32(100), ..._u32(deleted ? 8 : 0)], version: 2),
    ..._record(
      0xf00d,
      reference != null ? _record(0x0f9e, _u32(reference)) : _text(text ?? ''),
      version: 15,
    ),
    // Another client-data payload is not a textbox and must never be scanned.
    ..._record(0xf011, _text('PRIVATE CLIENT DATA')),
  ], version: 15);
  for (var index = 0; index <= nestedDepth; index++) {
    shapes = _record(0xf003, shapes, version: 15);
  }
  return _record(0x03ee, [
    ..._record(0x03ef, Uint8List(24), version: 2),
    ..._record(0x040c, _record(0xf002, shapes, version: 15), version: 15),
    ..._record(0x03f0, _text('NOTES TEXT'), version: 15),
  ], version: 15);
}

List<int> _slidePersist(int id, int slideId, int count) => _record(0x03f3, [
  ..._u32(id),
  ..._u32(0),
  ..._u32(count),
  ..._u32(slideId),
  ..._u32(0),
]);

// Two independent save generations, including an unchanged current slide whose
// persist mapping must be inherited. The current document also contains master
// and note lists; their texts are deliberately distinct from current slides.
Uint8List _fixture({
  bool encryptedToken = false,
  bool encryptedEdit = false,
  bool cycle = false,
  bool missingPersist = false,
  bool duplicatePersist = false,
  bool corruptRecordLength = false,
  bool nestedStorageOnly = false,
  bool oldVersion = false,
  int outlineIndex = 0,
  int nestedDepth = 0,
  int textCount = 1,
  bool deletedShape = false,
  bool compressedTitle = false,
  String title = 'CURRENT 世界 😀',
}) {
  final stream = BytesBuilder();
  int add(List<int> data) {
    final offset = stream.length;
    stream.add(data);
    return offset;
  }

  add(_record(0x03ea, []));
  final staleSlide = add(_slide(text: 'STALE FIRST SLIDE'));
  final unchangedSlide = add(_slide(text: 'SECOND CURRENT SLIDE'));
  final deletedSlide = add(_slide(text: 'DELETED SLIDE'));
  final oldDocument = add(
    _record(
      0x03e8,
      _record(0x0ff0, [
        ..._slidePersist(2, 256, 0),
        ..._slidePersist(3, 257, 0),
        ..._slidePersist(4, 258, 0),
      ], version: 15),
      version: 15,
    ),
  );
  final oldDirectory = add(
    _record(0x1772, [
      ..._u32((4 << 20) | 1),
      ..._u32(oldDocument),
      ..._u32(staleSlide),
      ..._u32(unchangedSlide),
      ..._u32(deletedSlide),
    ]),
  );
  Uint8List edit(int previous, int directory, {bool encryption = false}) {
    final payload = ByteData(encryption ? 32 : 28)
      ..setUint8(7, 3)
      ..setUint32(8, previous, Endian.little)
      ..setUint32(12, directory, Endian.little)
      ..setUint32(16, 1, Endian.little)
      ..setUint32(20, 5, Endian.little);
    if (encryption) payload.setUint32(28, 5, Endian.little);
    return _record(0x0ff5, payload.buffer.asUint8List());
  }

  final oldEdit = add(edit(0, oldDirectory));
  final currentSlide = add(
    _slide(
      reference: outlineIndex,
      nestedDepth: nestedDepth,
      deleted: deletedShape,
    ),
  );
  final currentDocument = add(
    _record(0x03e8, [
      ..._record(0x0ff0, [
        ..._slidePersist(missingPersist ? 99 : 2, 256, textCount),
        ..._text(title, unicode: !compressedTitle),
        ..._slidePersist(3, 257, 0),
      ], version: 15),
      ..._record(0x0ff0, _text('MASTER SECRET'), version: 15, instance: 1),
      ..._record(0x0ff0, _text('NOTES SECRET'), version: 15, instance: 2),
    ], version: 15),
  );
  final currentDirectory = add(
    _record(0x1772, [
      ..._u32((2 << 20) | 1),
      ..._u32(currentDocument),
      ..._u32(currentSlide),
      if (duplicatePersist) ...[..._u32((1 << 20) | 2), ..._u32(currentSlide)],
    ]),
  );
  final currentEdit = stream.length;
  add(
    edit(
      cycle ? currentEdit : oldEdit,
      currentDirectory,
      encryption: encryptedEdit,
    ),
  );
  final data = stream.takeBytes();
  if (corruptRecordLength) {
    ByteData.sublistView(data)
        .setUint32(currentSlide + 4, 0xffffffff, Endian.little);
  }
  final currentUser = ByteData(24)
    ..setUint32(0, 20, Endian.little)
    ..setUint32(4, encryptedToken ? 0xf3d1c4df : 0xe391c05f, Endian.little)
    ..setUint32(8, currentEdit, Endian.little)
    ..setUint16(14, oldVersion ? 0x1234 : 0x03f4, Endian.little)
    ..setUint8(16, 3)
    ..setUint32(20, 8, Endian.little);
  final prefix = nestedStorageOnly ? 'Embedded/' : '';
  return (CfbfWriter()
        ..addStream(
          '${prefix}Current User',
          _record(0x0ff6, currentUser.buffer.asUint8List()),
        )
        ..addStream('${prefix}PowerPoint Document', data)
        ..addStream(
          'Unrelated',
          Uint8List.fromList(ascii.encode('UNRELATED SECRET')),
        ))
      .build();
}

Matcher _error(LegacyPowerPointErrorCode code) => throwsA(
  isA<LegacyPowerPointException>().having((error) => error.code, 'code', code),
);

void main() {
  test(
    'reads an authored LibreOffice binary PPT without exposing speaker notes',
    () {
      final bytes = Uint8List.fromList(
        gzip.decode(
          File('test/fixtures/legacy_powerpoint/current-slides.ppt.gz')
              .readAsBytesSync(),
        ),
      );
      final presentation = extractLegacyPowerPoint(bytes);
      expect(presentation.slides.length, 2);
      expect(
        presentation.slides.first.text,
        'Current title 世界\nFirst body paragraph\nSecond body paragraph\nIndependent shape café',
      );
      expect(
        presentation.slides.last.text,
        'Second current slide\nCurrent final body',
      );
      expect(presentation.plainText, isNot(contains('SPEAKER NOTES')));
    },
  );

  test(
    'deleted current shapes and their unreferenced outline text stay hidden',
    () {
      final presentation = extractLegacyPowerPoint(
        _fixture(deletedShape: true),
      );
      expect(presentation.slides.first.text, isEmpty);
      expect(presentation.slides.last.text, 'SECOND CURRENT SLIDE');
    },
  );

  test('TextBytes stores low UTF-16 bytes, not Windows-1252 characters', () {
    final presentation = extractLegacyPowerPoint(
      _fixture(title: 'café \u0080', compressedTitle: true),
    );
    expect(presentation.slides.first.text, 'café \u0080');
    expect(presentation.plainText, isNot(contains('€')));
  });
  test('uses newest persist mapping and inherits unchanged current slides', () {
    final presentation = extractLegacyPowerPoint(_fixture());
    expect(presentation.slides.map((slide) => slide.slideId), [256, 257]);
    expect(presentation.slides.map((slide) => slide.text), [
      'CURRENT 世界 😀',
      'SECOND CURRENT SLIDE',
    ]);
    for (final excluded in [
      'STALE',
      'DELETED',
      'MASTER',
      'NOTES',
      'PRIVATE',
      'UNRELATED',
    ]) {
      expect(presentation.plainText, isNot(contains(excluded)));
    }
  });

  test('follows nested shape groups and keeps current slide order', () {
    expect(
      extractLegacyPowerPoint(_fixture(nestedDepth: 4)).slides.first.text,
      'CURRENT 世界 😀',
    );
  });

  test('rejects both encryption indicators', () {
    expect(
      () => extractLegacyPowerPoint(_fixture(encryptedToken: true)),
      _error(LegacyPowerPointErrorCode.encrypted),
    );
    expect(
      () => extractLegacyPowerPoint(_fixture(encryptedEdit: true)),
      _error(LegacyPowerPointErrorCode.encrypted),
    );
  });

  test('rejects invalid edit cycles, persist maps and record extents', () {
    for (final data in [
      _fixture(cycle: true),
      _fixture(missingPersist: true),
      _fixture(duplicatePersist: true),
      _fixture(corruptRecordLength: true),
      _fixture(outlineIndex: 1),
      _fixture(textCount: 2),
    ]) {
      expect(
        () => extractLegacyPowerPoint(data),
        _error(LegacyPowerPointErrorCode.malformed),
      );
    }
  });

  test('rejects unsupported versions and unrelated nested presentations', () {
    expect(
      () => extractLegacyPowerPoint(_fixture(oldVersion: true)),
      _error(LegacyPowerPointErrorCode.unsupportedVersion),
    );
    expect(
      () => extractLegacyPowerPoint(_fixture(nestedStorageOnly: true)),
      _error(LegacyPowerPointErrorCode.unsupportedVersion),
    );
  });

  test(
    'bounds nesting and validates Unicode text instead of replacing corruption',
    () {
      expect(
        () => extractLegacyPowerPoint(_fixture(nestedDepth: 65)),
        _error(LegacyPowerPointErrorCode.resourceLimit),
      );
      expect(
        () => extractLegacyPowerPoint(_fixture(title: '\ud800x')),
        _error(LegacyPowerPointErrorCode.malformed),
      );
    },
  );

  test(
    'office routing covers PPT PPS POT and localizes generated slide headings',
    () async {
      for (final extension in ['ppt', 'pps', 'pot']) {
        final document = await parseOfficeDocument(
          _fixture(title: 'Slide 1'),
          'deck.$extension',
        );
        expect(document.kind, OfficeDocumentKind.presentation);
        expect(document.notice, OfficePreviewNotice.legacyPowerPointText);
        expect(document.fallback, isNull);
        expect(
          document.plainText,
          'Slide 1\nSlide 1\n\nSlide 2\nSECOND CURRENT SLIDE',
        );
        final strings = OfficePreviewStrings(const Locale('es'));
        expect(
          strings.headings(
            document.plainText,
            document.textHeadings,
            const Locale('es'),
          ),
          'Diapositiva 1\nSlide 1\n\nDiapositiva 2\nSECOND CURRENT SLIDE',
        );
        expect(
          const InternalViewerService().detectMode('deck.$extension'),
          ViewerMode.office,
        );
      }
    },
  );
}
