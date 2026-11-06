import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/checksum_error_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/checksum_file_failure.dart';
import 'package:crisp_cloud/services/checksum_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _WriteFailureBackend extends LocalOperationBackend {
  _WriteFailureBackend() : super(LocalFileService(), isCurrent: () => true);

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    throw FileSystemException(
      'Sidecar write denied',
      path,
      const OSError('denied', 13),
    );
  }
}

void main() {
  test(
    'checksum reads, sidecar writes, and verification retain typed failures',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'checksum-errors-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final missing = '${directory.path}/missing.md5';
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
      final input = File('${directory.path}/input.txt');
      await input.writeAsString('checksum input');
      for (final algorithm in [
        ChecksumAlgorithm.md5,
        ChecksumAlgorithm.sha256,
      ]) {
        final outputName = 'failed.${algorithm.extension}';
        await expectLater(
          ChecksumService.createManifest(
            _WriteFailureBackend(),
            [FileItem(name: 'input.txt', path: input.path, isFolder: false)],
            baseDirectory: directory.path,
            outputName: outputName,
            algorithm: algorithm,
          ),
          throwsA(
            isA<ChecksumFileException>()
                .having(
                  (error) => error.action,
                  'action',
                  ChecksumFileAction.write,
                )
                .having(
                  (error) => error.filePath,
                  'output path',
                  p.join(directory.path, outputName),
                )
                .having(
                  (error) => error.osError?.errorCode,
                  'native cause',
                  13,
                ),
          ),
        );
        expect(await File('${directory.path}/$outputName').exists(), isFalse);
      }
      expect(await input.readAsString(), 'checksum input');
      // Empty selections remain invalid input; do not turn validation failures
      // into I/O errors or create manifests containing fake error checksums.
      await expectLater(
        ChecksumService.generateMd5File([], directory.path),
        throwsArgumentError,
      );
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
