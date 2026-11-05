import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/checksum_error_strings.dart';
import 'package:crisp_cloud/services/checksum_file_failure.dart';
import 'package:crisp_cloud/services/checksum_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'checksum reads, sidecar writes, and verification retain typed failures',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'checksum-errors-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final missing = '${directory.path}/missing';
      for (final read in [
        ChecksumService.md5File,
        ChecksumService.sha256File,
        ChecksumService.verifyChecksumFile,
      ]) {
        await expectLater(
          read(missing),
          throwsA(
            isA<ChecksumFileException>()
                .having(
                  (error) => error.action,
                  'action',
                  ChecksumFileAction.read,
                )
                .having((error) => error.filePath, 'input path', missing),
          ),
        );
      }
      for (final generate in [
        ChecksumService.generateMd5File,
        ChecksumService.generateSha256File,
      ]) {
        await expectLater(
          generate([], missing),
          throwsA(
            isA<ChecksumFileException>().having(
              (error) => error.action,
              'action',
              ChecksumFileAction.write,
            ),
          ),
        );
      }
      final sidecar = File('${directory.path}/checksums.md5');
      await sidecar.writeAsString(
        'd41d8cd98f00b204e9800998ecf8427e  missing\n',
      );
      final results = await ChecksumService.verifyChecksumFile(sidecar.path);
      expect(results.single.ok, isFalse);
      expect(results.single.error, isA<ChecksumFileException>());
    },
  );

  testWidgets(
    'checksum failures translate in nine locales and preserve details',
    (tester) async {
      final reads = <String>{};
      final writes = <String>{};
      const cause = FileSystemException(
        'native message',
        '/raw',
        OSError('denied {path}', 13),
      );
      final read = ChecksumFileException(
        ChecksumFileAction.read,
        '/file-{detail}.bin',
        cause,
      );
      final write = ChecksumFileException(
        ChecksumFileAction.write,
        '/checksums.md5',
        cause,
      );
      expect(read, isA<FileSystemException>());
      expect(read.toString(), cause.toString());
      expect(read.osError, same(cause.osError));
      for (final locale in AppLocalizations.supportedLocales) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        final readText = localizedChecksumError(context, read);
        final writeText = localizedChecksumError(context, write);
        expect(readText, contains('/file-{detail}.bin'));
        expect(readText, contains('denied {path}'));
        expect(writeText, contains('/checksums.md5'));
        expect(
          localizedChecksumError(context, 'external detail'),
          'external detail',
        );
        reads.add(readText);
        writes.add(writeText);
      }
      expect(reads, hasLength(9));
      expect(writes, hasLength(9));
    },
  );
}
