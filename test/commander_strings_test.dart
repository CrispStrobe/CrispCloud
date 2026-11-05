import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/l10n/commander_translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Commander catalog covers every application language and parameter', () {
    expect(
      CommanderStrings.supportedLanguageCodes.toSet(),
      AppLocalizations.supportedLocales
          .map((locale) => locale.languageCode)
          .toSet(),
    );
    final parameters = RegExp(r'\{\d+\}');
    for (final entry in commanderTranslations.entries) {
      expect(entry.value, hasLength(8), reason: entry.key);
      final expected = parameters
          .allMatches(entry.key)
          .map((m) => m[0])
          .toSet();
      for (var i = 0; i < entry.value.length; i++) {
        final language = CommanderStrings.supportedLanguageCodes[i + 1];
        expect(
          entry.value[i].trim(),
          isNotEmpty,
          reason: '$language / ${entry.key}',
        );
        expect(
          parameters.allMatches(entry.value[i]).map((m) => m[0]).toSet(),
          expected,
          reason: '$language / ${entry.key}',
        );
      }
    }
  });

  test('common controls keep app wording and one shortcut', () {
    for (final language in CommanderStrings.supportedLanguageCodes) {
      final app = lookupAppLocalizations(Locale(language));
      expect(CommanderStrings.forLanguage(language, 'Cancel'), app.cancel);
      expect(CommanderStrings.forLanguage(language, 'Save'), app.save);
      expect(
        CommanderStrings.forLanguage(language, 'Save (Ctrl+S)'),
        '${app.save} (Ctrl+S)',
      );
      expect(
        CommanderStrings.forLanguage(language, 'Filter Files'),
        app.filterFiles,
      );
    }
    expect(
      CommanderStrings.forLanguage('xx', 'Rename {0} items', [2]),
      'Rename 2 items',
    );
  });

  test(
    'formatting preserves literal filenames, placeholders and mask syntax',
    () {
      const path = r'/report/{1}/$1/name.txt';
      expect(
        CommanderStrings.forLanguage('de', 'Save {0}', [path]),
        '$path speichern',
      );
      expect(
        CommanderStrings.forLanguage('ar', 'Current: {0}', [path]),
        'الحالي: $path',
      );
      expect(
        CommanderStrings.forLanguage(
          'ja',
          r'Captures: $1, ${name} · literal dollar: $$',
        ),
        r'キャプチャ: $1、${name} · ドル記号: $$',
      );
      expect(
        CommanderStrings.forLanguage('de', 'Total Commander'),
        'Total Commander',
      );
    },
  );

  test(
    'rename, selection and file-list captions have explicit translations',
    () {
      final calls = RegExp(r'\.commanderTr\(\s*("(?:\\.|[^"\\])*\")');
      for (final name in [
        'batch_rename_dialog',
        'rename_names_dialog',
        'rename_text_dialog',
        'pattern_selection_dialog',
        'file_list_dialog',
      ]) {
        final source = File('lib/widgets/$name.dart').readAsStringSync();
        final matches = calls.allMatches(source).toList();
        expect(matches, isNotEmpty, reason: name);
        for (final match in matches) {
          final english =
              jsonDecode(match[1]!.replaceAll(r'\$', r'$')) as String;
          expect(
            CommanderStrings.contains(english),
            isTrue,
            reason: '$name / $english',
          );
        }
      }
    },
  );
}
