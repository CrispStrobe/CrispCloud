import 'dart:convert';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const info = EbookBookInfo(
    title: 'Fixture',
    authors: ['CrispCloud'],
    toc: [],
    sectionCount: 2,
    sourceFormat: 'epub',
  );

  test('disposing a keyed old host cannot detach the replacement transport',
      () async {
    final controller = CrispEbookController();
    final calls = <String>[];
    Future<dynamic> oldHost(String method, EbookJson args) async {
      calls.add('old:$method');
    }

    Future<dynamic> newHost(String method, EbookJson args) async {
      calls.add('new:$method');
    }

    controller.attach(oldHost);
    controller.updateBookInfo(info);
    controller.updateLocation(const EbookLocation(cfi: 'old', fraction: 0.5));
    controller.attach(newHost);
    expect(controller.isReady, isFalse);
    expect(controller.location, isNull);
    controller.detach(sender: oldHost);
    controller.updateBookInfo(info);
    expect(controller.isReady, isTrue);
    await controller.next();
    expect(calls, ['new:next']);
    controller.detach(sender: newHost);
    expect(controller.isReady, isFalse);
    await expectLater(controller.next(), throwsStateError);
    controller.dispose();
  });

  test('normalized import requires a known schema and encoding', () {
    expect(() => EbookImportPayload.fromJson({'schemaVersion': 2}),
        throwsFormatException);
    final payload = EbookImportPayload.fromJson({
      'schemaVersion': 1,
      'sourceFormat': 'fb2',
      'resources': [
        {
          'href': 'chapters/0001.xhtml',
          'mediaType': 'application/xhtml+xml',
          'encoding': 'base64',
          'data': base64Encode(utf8.encode('café 日本語'))
        },
      ],
    });
    expect(utf8.decode(payload.resourceBytes(payload.resources.single)),
        'café 日本語');
    expect(() => payload.resourceBytes({'encoding': 'remote-url'}),
        throwsFormatException);
  });

  test('platform capabilities do not advertise a bundled Linux renderer', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(EbookReaderCapabilities.supportsEmbeddedReader, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(EbookReaderCapabilities.supportsEmbeddedReader, isTrue);
    expect(EbookReaderCapabilities.supportsDrm, isFalse);
    expect(EbookReaderCapabilities.supportsKfx, isFalse);
  });
}
