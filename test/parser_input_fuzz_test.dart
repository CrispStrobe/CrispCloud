import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/email_message_service.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<Uint8List> _variants(List<int> seed, int randomSeed) sync* {
  yield Uint8List.fromList(seed);
  final random = Random(randomSeed);
  for (var i = 0; i < 48; i++) {
    final bytes = Uint8List.fromList(
      i % 4 == 0 ? seed.take(random.nextInt(seed.length)).toList() : seed,
    );
    if (bytes.isNotEmpty) {
      final index = random.nextInt(bytes.length);
      bytes[index] ^= 1 << random.nextInt(8);
    }
    yield bytes;
  }
}

void main() {
  test(
    'ZIP preview keeps bounded members and handles malformed metadata',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('sample.txt', utf8.encode('hello')));
      for (final bytes in _variants(ZipEncoder().encode(archive), 193)) {
        try {
          final opened = await openViewerArchive(
            bytes,
            name: 'sample.zip',
            maxMemberBytes: 1024,
          );
          try {
            for (final member in opened.members.where(
              (entry) => entry.isFile,
            )) {
              expect(
                (await opened.readMember(member, maxBytes: 1024)).length,
                lessThanOrEqualTo(1024),
              );
            }
          } finally {
            await opened.close();
          }
        } on ArchiveViewException {
          // The viewer can report a malformed container or member.
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('saved email keeps active HTML out of the preview', () {
    final message = utf8.encode(
      'Subject: Fixture\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n'
      '<p>Fixture</p><script>example</script><iframe src="/test"></iframe>',
    );
    for (final bytes in _variants(message, 297)) {
      try {
        final mail = parseEmailMessage(bytes, 'fixture.eml');
        final html = mail.safeHtml?.toLowerCase() ?? '';
        expect(html, isNot(contains(RegExp(r'<(?:script|iframe)\b'))));
      } on FormatException {
        // Invalid MIME and headers are explicit parse failures.
      }
    }
  }, timeout: const Timeout(Duration(seconds: 10)));
}
