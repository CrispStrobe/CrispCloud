import 'package:crisp_cloud/services/destination_name_mask.dart';
import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/services/file_operation_options.dart';
import 'package:crisp_cloud/services/file_operation_profiles.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final example in [
    ('*.*', 'photo.jpg', 'photo.jpg'),
    ('*.bak', 'photo.jpg', 'photo.bak'),
    ('*.*.bak', 'photo.jpg', 'photo.jpg.bak'),
    ('????.txt', 'abcdef.dat', 'abcd.txt'),
    ('[N]_[C:000].[E]', 'photo.jpg', 'photo_007.jpg'),
    ('*.*', '.gitignore', '.gitignore'),
    ('[N]_[C]', 'README', 'README_7'),
  ]) {
    test('destination mask ${example.$1} transforms ${example.$2}', () {
      expect(
        DestinationNameMask(example.$1).apply(example.$2, index: 7),
        example.$3,
      );
    });
  }
  test('masks reject directory traversal, nulls and unknown tokens', () {
    for (final mask in ['../*', 'sub\\*', '\u0000', '[UNKNOWN]']) {
      expect(() => DestinationNameMask(mask), throwsFormatException);
    }
    expect(() => DestinationNameMask('..').apply('a'), throwsFormatException);
  });
  test('all transfer option semantics survive JSON serialization', () {
    final options = FileOperationOptions(
      kind: FileOperationKind.move,
      fileConflict: FileConflictPolicy.resumeVerified,
      destinationMask: '[N]_[C:000].[E]',
      duplicateNameTemplate: '{name}_copy-{counter:000}{ext}',
      minimumSize: 2,
      maximumSize: 50,
      modifiedAfter: DateTime.utc(2025),
      pattern: FileSelectionPattern(
        r'^a.*',
        mode: FilePatternMode.regex,
        caseSensitive: true,
        matchFullPath: true,
      ),
      searchCriteria: const FileSearchQuery(
        includeFolders: false,
        includeHidden: false,
        extensions: ['txt', 'md'],
        namePattern: '*.txt;*.md',
        minSize: 2,
      ),
      excludedDirectories: FileSelectionPattern('cache;tmp'),
      excludeEmptyDirectories: true,
      preservePermissions: true,
      verifyContents: true,
      copyMethod: FileCopyMethod.stream,
      preallocate: true,
      clientBytesPerSecond: 128 * 1024,
    );
    expect(
      FileOperationOptions.fromJson(options.toJson()).toJson(),
      options.toJson(),
    );
  });
  test(
    'profiles save defaults without previous paths or exact target names',
    () async {
      final profiles = FileOperationProfiles();
      await profiles.save(
        '@default:copy',
        const FileOperationOptions(
          destinationName: 'one.txt',
          relativeBase: '/private/source',
          destinationMask: '*.bak',
          duplicateNameTemplate: '{name}_backup-{counter:000}{ext}',
          fileConflict: FileConflictPolicy.keepBoth,
          clientBytesPerSecond: 512,
        ),
      );
      final stored = (await profiles.load())['@default:copy']!;
      expect(stored.destinationName, isNull);
      expect(stored.relativeBase, isNull);
      expect(stored.destinationMask, '*.bak');
      expect(stored.duplicateNameTemplate, '{name}_backup-{counter:000}{ext}');
      expect(stored.clientBytesPerSecond, 512);
      await profiles.remove('@default:copy');
      expect(await profiles.load(), isEmpty);
    },
  );

  test('old saved options retain the original numbered duplicate names', () {
    final legacy = const FileOperationOptions().toJson()
      ..remove('duplicateNameTemplate')
      ..remove('clientBytesPerSecond');
    expect(FileOperationOptions.fromJson(legacy).clientBytesPerSecond, isNull);
    expect(
      FileOperationOptions.fromJson(legacy).duplicateNameTemplate,
      '{name} ({counter}){ext}',
    );
  });

  test('invalid streaming rates cannot be restored or saved', () async {
    for (final rate in [
      0,
      -1,
      FileOperationOptions.maximumClientBytesPerSecond + 1,
    ]) {
      final invalid = FileOperationOptions(clientBytesPerSecond: rate);
      expect(invalid.validateTransferSettings, throwsFormatException);
      expect(
        () => FileOperationOptions.fromJson(invalid.toJson()),
        throwsFormatException,
      );
      await expectLater(
        FileOperationProfiles().save('invalid', invalid),
        throwsFormatException,
      );
    }
    expect(await FileOperationProfiles().load(), isEmpty);
  });

  test(
    'invalid saved templates cannot enter profiles or restored jobs',
    () async {
      const invalid = FileOperationOptions(
        duplicateNameTemplate: '../{name}-{counter}',
      );
      expect(
        () => FileOperationOptions.fromJson(invalid.toJson()),
        throwsFormatException,
      );
      await expectLater(
        FileOperationProfiles().save('invalid', invalid),
        throwsFormatException,
      );
      expect(await FileOperationProfiles().load(), isEmpty);
    },
  );
}
