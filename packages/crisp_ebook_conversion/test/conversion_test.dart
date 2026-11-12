@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';
import 'package:crisp_ebook_conversion/src/build_config.dart';
import 'package:test/test.dart';

Matcher errorCode(String code) =>
    isA<EbookConversionException>().having((error) => error.code, 'code', code);

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  late KindlingConverter converter;
  setUp(() => converter = KindlingConverter());

  test('default build bundles the reviewed native engine', () async {
    final capability = await converter.capabilities();
    expect(capability.available, isTrue, reason: capability.reason);
    expect(capability.runtime, EbookConversionRuntime.native);
    expect(capability.engineVersion, '0.46.2');
    expect(capability.cancellationMode, EbookCancellationMode.cooperative);
  });

  for (final format in KindleExportFormat.values) {
    test(
      '${format.extension} converts, rewrites metadata and preserves baseline',
      () async {
        final input = fixture('book.epub');
        final baseline = Uint8List.fromList(input);
        final result = await converter.exportKindle(input, format: format);
        expect(input, baseline);
        expect(ascii.decode(result.bytes.sublist(60, 68)), 'BOOKMOBI');
        expect(result.extension, format.extension);
        expect(result.warnings, isNotEmpty);
        expect(() => result.bytes[0] = 0, throwsUnsupportedError);
        final edited = await converter.rewriteMetadata(
          result.bytes,
          format: format,
          patch: KindleMetadataPatch(
            title: 'Dart café',
            authors: ['Author One'],
          ),
        );
        expect(edited.changes, isNotEmpty);
        expect(
          utf8.decode(edited.bytes, allowMalformed: true),
          contains('Dart café'),
        );
        final unchanged = await converter.rewriteMetadata(
          edited.bytes,
          format: format,
          patch: KindleMetadataPatch(),
        );
        expect(unchanged.noOp, isTrue);
        expect(unchanged.bytes, edited.bytes);
      },
    );
  }

  test('snapshots mutable caller bytes before asynchronous work', () async {
    final input = fixture('book.epub');
    final operation = converter.exportKindle(input);
    input.fillRange(0, input.length, 0);
    final result = await operation;
    expect(ascii.decode(result.bytes.sublist(60, 68)), 'BOOKMOBI');
  });

  test('metadata editing rejects DRM without modifying input', () async {
    final plain = await converter.exportKindle(fixture('book.epub'));
    final encrypted = Uint8List.fromList(plain.bytes);
    final header = ByteData.sublistView(encrypted);
    final firstRecord = header.getUint32(78);
    header.setUint16(firstRecord + 12, 2);
    final baseline = Uint8List.fromList(encrypted);
    await expectLater(
      converter.rewriteMetadata(
        encrypted,
        patch: KindleMetadataPatch(title: 'Blocked'),
      ),
      throwsA(errorCode('drmProtected')),
    );
    expect(encrypted, baseline);
  });

  for (final (name, code) in [
    ('traversal.epub', 'invalidInput'),
    ('external_resource.epub', 'invalidInput'),
    ('protected.epub', 'drmProtected'),
  ]) {
    test('rejects $name before producing output', () async {
      await expectLater(
        converter.exportKindle(fixture(name)),
        throwsA(errorCode(code)),
      );
    });
  }

  test('bounds input size before dispatching a native job', () async {
    final bounded = KindlingConverter(
      limits: const EbookConversionLimits(maxInputBytes: 10),
    );
    await expectLater(
      bounded.exportKindle(fixture('book.epub')),
      throwsA(errorCode('limitExceeded')),
    );
  });

  test('native extraction applies image-pixel limits', () async {
    final bounded = KindlingConverter(
      limits: const EbookConversionLimits(maxImagePixels: 1),
    );
    await expectLater(
      bounded.exportKindle(fixture('book.epub')),
      throwsA(errorCode('limitExceeded')),
    );
  });

  test('rejects overlapping jobs and releases its busy state', () async {
    final first = converter.exportKindle(fixture('book.epub'));
    await expectLater(
      converter.exportKindle(fixture('book.epub')),
      throwsA(errorCode('busy')),
    );
    await first;
    expect(
      (await converter.exportKindle(fixture('book.epub'))).bytes,
      isNotEmpty,
    );
  });

  test('honors an already cancelled token without dispatch', () async {
    final token = EbookCancellationToken()..cancel();
    await expectLater(
      converter.exportKindle(fixture('book.epub'), cancellation: token),
      throwsA(errorCode('cancelled')),
    );
    expect(
      (await converter.exportKindle(fixture('book.epub'))).bytes,
      isNotEmpty,
    );
  });

  test(
    'timeout discards late native output and eventually releases the engine',
    () async {
      final fast = KindlingConverter(timeout: const Duration(microseconds: 1));
      await expectLater(
        fast.exportKindle(fixture('book.epub')),
        throwsA(errorCode('timeout')),
      );
      // A native library call cannot be forcibly interrupted; the worker settles
      // before cleanup. The independent converter must become usable again.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        (await converter.exportKindle(fixture('book.epub'))).bytes,
        isNotEmpty,
      );
    },
  );

  test('missing and unreviewed runtime paths report unavailable', () async {
    final missing = KindlingConverter(
      libraryPath: '/not-installed/crisp_kindling.so',
    );
    expect((await missing.capabilities()).available, isFalse);
    await expectLater(
      missing.exportKindle(fixture('book.epub')),
      throwsA(errorCode('unavailable')),
    );
    expect(
      (await KindlingConverter(
        executablePath: 'relative/helper',
      ).capabilities()).available,
      isFalse,
    );
  });

  test('build mappings distinguish iOS device and simulator', () {
    expect(
      KindlingBuildTarget.forPlatform('ios', 'arm64')!.triple,
      'aarch64-apple-ios',
    );
    expect(
      KindlingBuildTarget.forPlatform(
        'ios',
        'arm64',
        iosSimulator: true,
      )!.triple,
      'aarch64-apple-ios-sim',
    );
    expect(
      KindlingBuildTarget.forPlatform('android', 'arm64')!.triple,
      'aarch64-linux-android',
    );
    expect(
      KindlingBuildTarget.forPlatform('windows', 'x64')!.library,
      'crisp_kindling_bridge.dll',
    );
    expect(KindlingBuildTarget.forPlatform('web', 'wasm'), isNull);
  });

  final helper = File(
    'native/target/release/crisp-kindling${Platform.isWindows ? '.exe' : ''}',
  );
  test(
    'optional real helper exports bytes and offers process cancellation',
    () async {
      final process = KindlingConverter(executablePath: helper.absolute.path);
      expect(
        (await process.capabilities()).cancellationMode,
        EbookCancellationMode.processTermination,
      );
      expect(
        (await process.exportKindle(fixture('book.epub'))).bytes,
        isNotEmpty,
      );
      final token = EbookCancellationToken();
      await process.exportKindle(fixture('book.epub'), cancellation: token);
      token.cancel(); // A late cancellation must not target an exited process.
      final fast = KindlingConverter(
        executablePath: helper.absolute.path,
        timeout: const Duration(microseconds: 1),
      );
      await expectLater(
        fast.exportKindle(fixture('book.epub')),
        throwsA(errorCode('timeout')),
      );
    },
    skip: !helper.existsSync()
        ? 'Build the optional helper with cargo build --release first.'
        : false,
  );
}
