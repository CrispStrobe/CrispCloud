import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/csv_spreadsheet_import.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:flutter_test/flutter_test.dart';

class _ListingBackend extends LocalOperationBackend {
  _ListingBackend(
    super.service, {
    required super.isCurrent,
    required this.listed,
  });
  final Future<void> Function() listed;

  @override
  Future<List<FileItem>> list(String path) async {
    final result = await super.list(path);
    await listed();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File original;
  late DesktopFileService local;
  final bytes = buildSpreadsheetCopy((
    [
      ['id', 'note'],
      ['001', '=literal'],
    ],
    false,
  ));

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('crisp-csv-copy-');
    original = File('${temporary.path}/table.csv');
    await original.writeAsString('id,note\n001,=literal');
    local = DesktopFileService()..currentPath = temporary.path;
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<FileItem> create(LocalOperationBackend backend, String name) =>
      createSpreadsheetCopy(
        backend: backend,
        sourcePath: original.path,
        name: name,
        bytes: bytes,
      );

  test(
    'local file collision preserves both the CSV and existing destination',
    () async {
      final destination = File('${temporary.path}/taken.xlsx');
      await destination.writeAsString('existing spreadsheet');
      await expectLater(
        create(
          LocalOperationBackend(local, isCurrent: () => true),
          'taken.xlsx',
        ),
        throwsStateError,
      );
      expect(await destination.readAsString(), 'existing spreadsheet');
      expect(await original.readAsString(), 'id,note\n001,=literal');
    },
  );

  test('a directory named XLSX is never replaced', () async {
    final destination = Directory('${temporary.path}/taken.xlsx');
    await destination.create();
    await File('${destination.path}/keep').writeAsString('retained');
    await expectLater(
      create(LocalOperationBackend(local, isCurrent: () => true), 'taken.xlsx'),
      throwsStateError,
    );
    expect(await File('${destination.path}/keep').readAsString(), 'retained');
  });

  test(
    'a destination symlink cannot redirect the copy outside its source folder',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'crisp-csv-outside-',
      );
      try {
        final target = File('${outside.path}/protected.xlsx');
        await target.writeAsString('outside data');
        final link = Link('${temporary.path}/linked.xlsx');
        await link.create(target.path);
        await expectLater(
          create(
            LocalOperationBackend(local, isCurrent: () => true),
            'linked.xlsx',
          ),
          throwsStateError,
        );
        expect(await target.readAsString(), 'outside data');
        expect(await FileSystemEntity.isLink(link.path), true);
      } finally {
        await outside.delete(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links needs a separate Windows grant.'
        : false,
  );

  test(
    'source becoming stale during listing blocks local publication',
    () async {
      var current = true;
      final backend = _ListingBackend(
        local,
        isCurrent: () => current,
        listed: () async {
          current = false;
        },
      );
      await expectLater(create(backend, 'new.xlsx'), throwsStateError);
      expect(await File('${temporary.path}/new.xlsx').exists(), false);
      expect(await original.readAsString(), 'id,note\n001,=literal');
    },
  );

  test(
    'competing imports cannot both publish the same local filename',
    () async {
      var listed = 0;
      final bothListed = Completer<void>();
      final backend = _ListingBackend(
        local,
        isCurrent: () => true,
        listed: () async {
          if (++listed == 2) bothListed.complete();
          await bothListed.future.timeout(const Duration(seconds: 10));
        },
      );
      Future<Object> attempt() async {
        try {
          return await create(backend, 'contended.xlsx');
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([attempt(), attempt()]);
      expect(results.whereType<FileItem>(), hasLength(1));
      expect(results.where((result) => result is! FileItem), hasLength(1));
      expect(
        await File('${temporary.path}/contended.xlsx').readAsBytes(),
        bytes,
      );
      expect(
        utf8.decode(await original.readAsBytes()),
        'id,note\n001,=literal',
      );
    },
  );
}
