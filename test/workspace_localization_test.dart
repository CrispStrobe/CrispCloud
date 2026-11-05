import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/l10n/workspace_strings.dart';
import 'package:crisp_cloud/l10n/workspace_translations.dart';
import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/sort.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace captions cover every locale and preserve parameters', () {
    final parameters = RegExp(r'\{\d+\}');
    for (final entry in workspaceTranslations.entries) {
      expect(entry.value, hasLength(8), reason: entry.key);
      for (final value in entry.value) {
        expect(value.trim(), isNotEmpty, reason: entry.key);
        expect(
          parameters.allMatches(value).map((m) => m[0]).toSet(),
          parameters.allMatches(entry.key).map((m) => m[0]).toSet(),
          reason: entry.key,
        );
      }
    }
    final calls = RegExp(
      r'\.commanderTr\(\s*("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)',
    );
    for (final file in [
      'workspace_dialog',
      'file_view_editor_dialog',
      'bookmark_actions',
      'file_column_header',
      'file_panel',
      'panel_header',
      'file_breadcrumbs',
    ]) {
      final source = File('lib/widgets/$file.dart').readAsStringSync();
      for (final match in calls.allMatches(source)) {
        final literal = match[1]!;
        final key = literal.startsWith('"')
            ? jsonDecode(literal) as String
            : literal.substring(1, literal.length - 1).replaceAll(r'\n', '\n');
        expect(CommanderStrings.contains(key), isTrue, reason: '$file / $key');
      }
    }
  });

  test('column serialization distinguishes built-in from user labels', () {
    final builtIn = FileColumnDefinition.defaults.first;
    expect(
      FileColumnDefinition.fromJson(builtIn.toJson()).localizeLabel,
      isTrue,
    );
    final old = builtIn.toJson()..remove('localizeLabel');
    expect(FileColumnDefinition.fromJson(old).localizeLabel, isTrue);
    const custom = FileColumnDefinition(
      id: 'size',
      label: 'Size',
      kind: FileColumnKind.size,
    );
    expect(
      FileColumnDefinition.fromJson(custom.toJson()).localizeLabel,
      isFalse,
    );
    expect(
      FileColumnDefinition.fromJson({...old, 'label': 'My size'}).localizeLabel,
      isFalse,
    );
  });

  testWidgets(
    'built-in view labels follow locale while custom titles stay literal',
    (tester) async {
      for (final code in CommanderStrings.supportedLanguageCodes.skip(1)) {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(code),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) {
                const custom = FileColumnDefinition(
                  id: 'custom',
                  label: 'Size {0}',
                  kind: FileColumnKind.size,
                );
                expect(custom.localizedLabel(context), 'Size {0}');
                expect(
                  FileColumnDefinition.defaults.first.localizedLabel(context),
                  CommanderStrings.forLanguage(code, 'Size'),
                );
                for (final view in FileViewDisplay.values) {
                  expect(view.localizedLabel(context), isNotEmpty);
                }
                for (final order in SortOrder.values) {
                  expect(order.localizedLabel(context), isNot(order.name));
                }
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
