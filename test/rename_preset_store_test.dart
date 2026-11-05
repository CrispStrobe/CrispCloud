import 'dart:convert';

import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/rename_preset_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = RenamePresetStore();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'portable presets preserve complete ordered rules and mask dialects',
    () async {
      const options = MultiRenameOptions(
        nameMask: '[V:Project]_[N]',
        dialect: RenameMaskDialect.totalCommander,
        variables: {'Project': 'Trip'},
        dateSource: RenameDateSource.captured,
        dateZone: RenameDateZone.utc,
        collisionPolicy: RenameCollisionPolicy.number,
        additionalSteps: [
          MultiRenameOptions(
            useRegex: true,
            find: r'(\d+)',
            replace: r'[$1]',
            nameCase: RenameCase.upper,
          ),
        ],
      );
      final exported = store.export({'Photo names': options});
      final imported = store.import(exported);
      expect(imported['Photo names']!.toJson(), options.toJson());
      await store.save(imported);
      expect(
        (await RenamePresetStore().load())['Photo names']!.toJson(),
        options.toJson(),
      );
    },
  );

  test('the previous stored settings format remains readable', () async {
    SharedPreferences.setMockInitialValues({
      RenamePresetStore.key: jsonEncode({
        'Older preset': {'nameMask': '[N]_[C]', 'counterWidth': 4},
      }),
    });
    final options = (await store.load())['Older preset']!;
    expect(options.nameMask, '[N]_[C]');
    expect(options.counterWidth, 4);
    expect(options.dialect, RenameMaskDialect.crispCloud);
    expect(options.additionalSteps, isEmpty);
  });

  test(
    'untrusted imports reject unknown formats, excessive size and nested steps',
    () {
      expect(() => store.import('{}'), throwsFormatException);
      expect(
        () => store.import('x' * (2 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
      expect(
        () => store.import(
          jsonEncode({
            'format': 'CrispCloud rename presets',
            'version': 2,
            'presets': {
              'Nested': {
                'additionalSteps': [
                  {
                    'additionalSteps': [{}],
                  },
                ],
              },
            },
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test('a failed import cannot modify saved preset settings', () async {
    await store.save({'Keep': const MultiRenameOptions(nameMask: '[N]_safe')});
    expect(() => store.import('{broken'), throwsFormatException);
    expect((await store.load())['Keep']!.nameMask, '[N]_safe');
  });
}
