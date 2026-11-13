import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/lrc_parser.dart';
import 'package:crisp_cloud/services/lrc_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSource extends ViewBytesSource {
  _RecordingSource(this.data, {int? reportedSize})
    : super.memory(Uint8List(0)) {
    size = reportedSize ?? data.length;
  }

  final Uint8List data;
  final reads = <(int, int)>[];
  int validations = 0;
  bool shortRead = false;
  Object? readError;
  Future<void> Function(int call)? onValidate;
  void Function(int call)? onRead;

  @override
  Future<void> validateUnchanged() async {
    final call = ++validations;
    await onValidate?.call(call);
  }

  @override
  Uint8List readSync(int offset, int length) {
    reads.add((offset, length));
    if (readError != null) throw readError!;
    onRead?.call(reads.length);
    return Uint8List.sublistView(
      data,
      offset,
      offset + length - (shortRead ? 1 : 0),
    );
  }
}

class _MutatingFileSource extends ViewBytesSource {
  _MutatingFileSource(this.file) : super.file(file.path);

  final File file;

  @override
  Uint8List readSync(int offset, int length) {
    final bytes = super.readSync(offset, length);
    file.writeAsStringSync('[00:03.00]This replacement is longer.');
    return bytes;
  }
}

Uint8List _utf8(String source) => Uint8List.fromList(utf8.encode(source));

Uint8List _utf16(String source, Endian endian) {
  final bytes = Uint8List(2 + source.length * 2);
  final view = ByteData.sublistView(bytes);
  view.setUint16(0, 0xfeff, endian);
  for (var i = 0; i < source.length; i++) {
    view.setUint16(2 + i * 2, source.codeUnitAt(i), endian);
  }
  return bytes;
}

Matcher _throwsCode(LrcSourceError code) => throwsA(
  isA<LrcSourceException>().having((error) => error.code, 'code', code),
);

void main() {
  test(
    'reads the complete source before applying late offset metadata',
    () async {
      final text =
          '[ti:Example]\r\n[00:01.50]Hello\r\n${' ' * (256 * 1024)}'
          '\r\n[offset:250]\r\n';
      final source = _RecordingSource(_utf8(text));
      final result = await readLrcSource(source);
      expect(result.encoding, 'utf8');
      expect(result.document.source, text);
      expect(result.document.offsetMs, 250);
      expect(result.document.timedCues.single.text, 'Hello');
      expect(result.document.timedCues.single.timeMs, 1250);
      expect(source.reads, [
        (0, 256 * 1024),
        (256 * 1024, source.size - 256 * 1024),
      ]);
      expect(source.validations, 2);
    },
  );

  for (final (endian, encoding) in [
    (Endian.little, 'utf16le'),
    (Endian.big, 'utf16be'),
  ]) {
    test('uses the viewer decoder for $encoding with a BOM', () async {
      const text = '[00:01.50]雪😀';
      final source = _RecordingSource(_utf16(text, endian));
      final result = await readLrcSource(source);
      expect(result.encoding, encoding);
      expect(result.document.source, text);
      expect(result.document.cues.single.text, '雪😀');
      expect(result.document.cues.single.timeMs, 1500);
    });
  }

  test('honors the current viewer encoding override', () async {
    final bytes = Uint8List.fromList([...ascii.encode('[00:01]Price '), 0x80]);
    final source = _RecordingSource(bytes);
    final result = await readLrcSource(source, encodingOverride: 'windows1252');
    expect(result.encoding, 'windows1252');
    expect(result.document.cues.single.text, 'Price €');
    final auto = await readLrcSource(source);
    expect(auto.encoding, 'latin1');
    expect(auto.document.cues.single.text, 'Price \u0080');
  });

  test(
    'borrows the source without disposing it or retaining mutable bytes',
    () async {
      final bytes = _utf8('[00:01]Original');
      final source = ViewBytesSource.memory(bytes);
      await source.open();
      addTearDown(source.dispose);
      final result = await readLrcSource(source);
      bytes[8] = 0x58;
      expect(result.document.source, '[00:01]Original');
      expect(source.readSync(8, 1).single, 0x58);
    },
  );

  test('an empty file remains a complete empty document', () async {
    final source = _RecordingSource(Uint8List(0));
    final result = await readLrcSource(source);
    expect(result.document.source, isEmpty);
    expect(result.document.timedCues, isEmpty);
    expect(result.document.cues.single.text, isEmpty);
    expect(result.document.isTruncated, isFalse);
    expect(source.reads, isEmpty);
    expect(source.validations, 2);
  });

  for (final size in [lrcSourceMaxBytes + 1, 5 * 1024 * 1024 * 1024]) {
    test('rejects $size bytes before owner I/O or allocation', () async {
      final source = _RecordingSource(Uint8List(0), reportedSize: size);
      await expectLater(
        readLrcSource(source),
        _throwsCode(LrcSourceError.readLimit),
      );
      expect(source.reads, isEmpty);
      expect(source.validations, 0);
    });
  }

  test('accepts the exact byte limit and reads every bounded window', () async {
    final bytes = Uint8List(lrcSourceMaxBytes);
    final prefix = ascii.encode('[00:01]');
    bytes.setAll(0, prefix);
    for (var i = prefix.length; i < bytes.length; i += 3) {
      bytes[i] = 0xe9;
      bytes[i + 1] = 0x9b;
      bytes[i + 2] = 0xaa;
    }
    final source = _RecordingSource(bytes);
    final result = await readLrcSource(source);
    expect(result.encoding, 'utf8');
    final characters = (lrcSourceMaxBytes - prefix.length) ~/ 3;
    expect(result.document.source.length, prefix.length + characters);
    expect(result.document.cues.single.text.length, characters);
    expect(result.document.cues.single.text, startsWith('雪雪'));
    expect(result.document.isTruncated, isFalse);
    expect(source.reads.length, 16);
    expect(source.reads.first, (0, 256 * 1024));
    expect(source.reads.last, (lrcSourceMaxBytes - 256 * 1024, 256 * 1024));
    expect(source.validations, 2);
  });

  test('retains parser-limit status for the host source fallback', () async {
    final bytes = Uint8List(lrcMaxSourceCodeUnits + 1)
      ..fillRange(0, lrcMaxSourceCodeUnits + 1, 0x20);
    final result = await readLrcSource(_RecordingSource(bytes));
    expect(result.document.isTruncated, isTrue);
    expect(result.document.limitReason, LrcLimitReason.sourceSize);
  });

  test('rejects an obsolete viewer before validating or reading', () async {
    final source = _RecordingSource(_utf8('[00:01]Hello'));
    await expectLater(
      readLrcSource(source, isCurrent: () => false),
      _throwsCode(LrcSourceError.sourceChanged),
    );
    expect(source.reads, isEmpty);
    expect(source.validations, 0);
  });

  test('rejects a viewer change during the first async validation', () async {
    var current = true;
    final entered = Completer<void>(), resume = Completer<void>();
    final source = _RecordingSource(_utf8('[00:01]Hello'));
    source.onValidate = (_) async {
      entered.complete();
      await resume.future;
    };
    final pending = expectLater(
      readLrcSource(source, isCurrent: () => current),
      _throwsCode(LrcSourceError.sourceChanged),
    );
    await entered.future;
    current = false;
    resume.complete();
    await pending;
    expect(source.reads, isEmpty);
  });

  test('rejects a late viewer change before publishing the document', () async {
    var current = true;
    final entered = Completer<void>(), resume = Completer<void>();
    final source = _RecordingSource(_utf8('[00:01]Hello'));
    source.onValidate = (call) async {
      if (call == 2) {
        entered.complete();
        await resume.future;
      }
    };
    final pending = expectLater(
      readLrcSource(source, isCurrent: () => current),
      _throwsCode(LrcSourceError.sourceChanged),
    );
    await entered.future;
    current = false;
    resume.complete();
    await pending;
    expect(source.reads, [(0, source.size)]);
  });

  test('rejects source resizing during validation before any read', () async {
    final source = _RecordingSource(_utf8('[00:01]Hello'));
    source.onValidate = (_) async {
      source.size++;
    };
    await expectLater(
      readLrcSource(source),
      _throwsCode(LrcSourceError.sourceChanged),
    );
    expect(source.reads, isEmpty);
  });

  test('stops a larger read when its owner is no longer current', () async {
    var current = true;
    final source = _RecordingSource(Uint8List(512 * 1024));
    source.onRead = (_) => current = false;
    await expectLater(
      readLrcSource(source, isCurrent: () => current),
      _throwsCode(LrcSourceError.sourceChanged),
    );
    expect(source.reads, [(0, 256 * 1024)]);
  });

  test('short reads fail instead of parsing an incomplete offset', () async {
    final source = _RecordingSource(_utf8('[00:01]Hello\n[offset:500]'))
      ..shortRead = true;
    await expectLater(
      readLrcSource(source),
      _throwsCode(LrcSourceError.readFailed),
    );
  });

  test('read errors have a distinct localized host failure code', () async {
    final source = _RecordingSource(_utf8('[00:01]Hello'))
      ..readError = const FileSystemException('Unavailable');
    await expectLater(
      readLrcSource(source),
      _throwsCode(LrcSourceError.readFailed),
    );
  });

  test('a disposed owner cannot publish lyrics', () async {
    final source = ViewBytesSource.memory(_utf8('[00:01]Hello'));
    await source.open();
    source.dispose();
    await expectLater(
      readLrcSource(source),
      _throwsCode(LrcSourceError.sourceChanged),
    );
  });

  test('detects a real file changed before reading', () async {
    final directory = await Directory.systemTemp.createTemp('lrc-source-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lyrics.lrc');
    await file.writeAsString('[00:01]Original');
    final source = ViewBytesSource.file(file.path);
    await source.open();
    addTearDown(source.dispose);
    await file.writeAsString('[00:02]Changed and longer');
    await expectLater(
      readLrcSource(source),
      _throwsCode(LrcSourceError.sourceChanged),
    );
  });

  test('detects a real file edited after its bytes were read', () async {
    final directory = await Directory.systemTemp.createTemp('lrc-source-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lyrics.lrc');
    await file.writeAsString('[00:01]Original');
    final source = _MutatingFileSource(file);
    await source.open();
    addTearDown(source.dispose);
    await expectLater(
      readLrcSource(source),
      _throwsCode(LrcSourceError.sourceChanged),
    );
  });
}
