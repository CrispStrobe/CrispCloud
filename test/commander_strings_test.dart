import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/l10n/commander_translations.dart';
import 'package:crisp_cloud/l10n/commander_completion_translations.dart';
import 'package:crisp_cloud/l10n/transfer_queue_translations.dart';
import 'package:crisp_cloud/models/rename_batch.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_options.dart';
import 'package:crisp_cloud/services/directory_comparison_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'operation and recovery states never expose untranslated enum identifiers',
    () {
      for (final value in <Enum>[
        ...FileOperationKind.values,
        ...FileOperationOutcome.values,
        ...RenameBatchState.values,
        ...DirectoryComparisonStatus.values,
      ]) {
        expect(
          CommanderStrings.contains(CommanderStrings.labelForEnum(value)),
          isTrue,
          reason: value.toString(),
        );
      }
      for (final status in TransferJobStatus.values) {
        expect(
          CommanderStrings.contains(transferStatusLabel(status)),
          isTrue,
          reason: status.name,
        );
      }
    },
  );
  test('Commander catalog covers every application language and parameter', () {
    expect(
      CommanderStrings.supportedLanguageCodes.toSet(),
      AppLocalizations.supportedLocales
          .map((locale) => locale.languageCode)
          .toSet(),
    );
    final parameters = RegExp(r'\{(?:\d+|[A-Za-z][A-Za-z0-9_]*)\}');
    for (final entry in {
      ...commanderTranslations,
      ...commanderCompletionTranslations,
      ...transferQueueTranslations,
    }.entries) {
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

  test('Commander workflow captions have explicit translations', () {
    final calls = RegExp(
      r'''\.commanderTr\(\s*(r?)("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''',
    );
    for (final name in [
      'batch_rename_dialog',
      'rename_names_dialog',
      'rename_text_dialog',
      'pattern_selection_dialog',
      'file_list_dialog',
      'file_operation_dialog',
      'file_operation_conflict_dialog',
      'transfer_history_dialog',
      'operations_panel',
      'transfer_schedule_dialog',
      'rename_history_dialog',
      'trash_history_dialog',
      'file_collections_dialog',
      'archive_workspace_dialog',
      'integrity_dialogs',
      'integrity_recovery_dialog',
      'internal_viewer_dialog',
      'internal_viewer_views',
      'file_attributes_dialog',
      'file_name_dialog',
      'diff_viewer_dialog',
      'directory_comparison_dialog',
      'sync_dialog',
      'sync_plan_dialog',
      'command_palette',
      'file_context_menu',
      'share_link_dialog',
      'version_history_dialog',
      'permissions_dialog',
      '../screens/file_browser_screen',
    ]) {
      final source = File('lib/widgets/$name.dart').readAsStringSync();
      final matches = calls.allMatches(source).toList();
      expect(matches, isNotEmpty, reason: name);
      for (final match in matches) {
        final literal = match[2]!;
        final inner = literal.substring(1, literal.length - 1);
        final english = match[1] == 'r'
            ? inner
            : inner.replaceAllMapped(
                RegExp(
                  r'\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)',
                  dotAll: true,
                ),
                (escape) {
                  final value = escape[1]!;
                  if (value.startsWith('u{')) {
                    return String.fromCharCode(
                      int.parse(
                        value.substring(2, value.length - 1),
                        radix: 16,
                      ),
                    );
                  }
                  if (value.startsWith('u') || value.startsWith('x')) {
                    return String.fromCharCode(
                      int.parse(value.substring(1), radix: 16),
                    );
                  }
                  return const {
                        'n': '\n',
                        'r': '\r',
                        't': '\t',
                        'b': '\b',
                        'f': '\f',
                        'v': '\v',
                      }[value] ??
                      value;
                },
              );
        expect(
          CommanderStrings.contains(english),
          isTrue,
          reason: '$name / $english',
        );
      }
    }
  });
  test('viewer modes and sync choices have explicit translations', () {
    for (final label in [
      'Auto',
      'Text',
      'ASCII',
      'Binary',
      'Hex',
      'Image',
      'Markdown',
      'HTML',
      'XML',
      'PDF',
      'Media',
      'Font',
      'Table',
      'Office',
      'Archive',
      'Unsupported',
      'Slides',
      'Pages',
      'Formatted',
      'Go to offset',
      'Go to line',
      'Go',
      'Wrong password',
      'Password required',
      'Archive password',
      'Incorrect password. Try again',
      'Rename member',
      'Local → Cloud',
      'Cloud → Local',
      'Keep both versions',
      'Skip',
      'Delete local',
      'Delete cloud',
      'Create local folder',
      'Create cloud folder',
      'Unresolved conflict',
      'Read-only',
      'Hidden',
      'System',
      'Archive attribute',
      'Match case',
      'Search text',
      'Left encoding',
      'Right encoding',
      'Auto-detect',
      'Newest Wins',
      'Local Wins',
      'Remote Wins',
      'Keep Both',
      'Ask Me',
    ]) {
      expect(CommanderStrings.contains(label), isTrue, reason: label);
    }
  });
}
