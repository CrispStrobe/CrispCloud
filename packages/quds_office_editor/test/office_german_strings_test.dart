import 'dart:io';

import 'package:flutter/widgets.dart' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/l10n/office_german.dart';
import 'package:quds_office_editor/src/l10n/office_language.dart';
import 'package:quds_office_editor/src/l10n/office_plural.dart';

/// Files whose labels are authored as `_s(english, arabic)` pairs (or the
/// status bar's local `s(english, arabic)`); German comes from [officeGerman].
const List<String> _sources = <String>[
  'lib/src/embed/word_review_pane.dart',
  'lib/src/embed/word_review_dialog.dart',
  'lib/src/embed/word_notes_pane.dart',
  'lib/src/embed/word_review_status.dart',
];

const String _literal = r"""(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""";
final RegExp _call = RegExp(
  r'(?<![\w.])_?s\(\s*((?:' +
      _literal +
      r'\s*)+),\s*((?:' +
      _literal +
      r'\s*)+),?\s*\)',
);
final RegExp _anyCall = RegExp(r'(?<![\w.])_?s\(');
final RegExp _languageName = RegExp(
  r"'[a-z]{2}': \((" + _literal + r'), (' + _literal + r')\)',
);
final RegExp _part = RegExp(_literal);

String _value(String source) => _part
    .allMatches(source)
    .map((m) => m[0]!.substring(1, m[0]!.length - 1))
    .join()
    .replaceAll(r"\'", "'");

/// Every English label the editor authors next to an Arabic one.
Set<String> _englishLabels() {
  final labels = <String>{};
  for (final path in _sources) {
    final source = File(path).readAsStringSync();
    final calls = _call.allMatches(source).toList();
    // Declarations and the language-name lookup `_s(name.$1, name.$2)` are
    // the only calls without literal arguments.
    final dynamicCalls = _anyCall.allMatches(source).length - calls.length;
    expect(
      dynamicCalls,
      lessThanOrEqualTo(2),
      reason: '$path has an _s(...) call whose English is not a literal',
    );
    for (final match in calls) {
      final english = _value(match[1]!);
      expect(
        english.contains(r'$'),
        isFalse,
        reason:
            '$path: "$english" interpolates values; use '
            'OfficeUiLanguage.phrase with an explicit German phrase',
      );
      labels.add(english);
    }
    for (final match in _languageName.allMatches(source)) {
      labels.add(_value(match[1]!));
    }
  }
  return labels;
}

void main() {
  test('every English review/proofing label has a German entry', () {
    final labels = _englishLabels();
    expect(labels.length, greaterThan(150));
    final missing = labels.difference(officeGerman.keys.toSet());
    expect(missing, isEmpty, reason: 'German entries missing for $missing');
    final unused = officeGerman.keys.toSet().difference(labels);
    expect(unused, isEmpty, reason: 'German entries without a label: $unused');
    for (final entry in officeGerman.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
    }
  });

  test('German is selected by OfficeStrings.german; RTL keeps Arabic', () {
    expect(
      OfficeUiLanguage.of(
        const OfficeSurfaceConfig(strings: OfficeStrings.german),
      ),
      OfficeUiLanguage.german,
    );
    expect(
      OfficeUiLanguage.of(const OfficeSurfaceConfig()),
      OfficeUiLanguage.english,
    );
    expect(
      OfficeUiLanguage.of(
        const OfficeSurfaceConfig(
          strings: OfficeStrings.arabic,
          textDirection: TextDirection.rtl,
        ),
      ),
      OfficeUiLanguage.arabic,
    );
    expect(
      OfficeUiLanguage.german.label('Spelling', 'الإملاء'),
      'Rechtschreibung',
    );
    expect(OfficeUiLanguage.german.label('Not a key', 'x'), 'Not a key');
  });

  test('German counts use one/other', () {
    expect(officeFindings(1, german: true), '1 Hinweis');
    expect(officeFindings(0, german: true), '0 Hinweise');
    expect(officeFindings(5, german: true), '5 Hinweise');
    expect(officeIssues(1, german: true), '1 Hinweis');
    expect(officeIssues(1, german: true, writing: true), '1 Schreibhinweis');
    expect(officeIssues(3, german: true, writing: true), '3 Schreibhinweise');
    expect(officeChanges(1, german: true), '1 Änderung');
    expect(officeChanges(2, german: true), '2 Änderungen');
    expect(officeParagraphs(1, german: true), '1 Absatz');
    expect(officeParagraphs(4, german: true), '4 Absätze');
    // Arabic takes precedence; English stays the default.
    expect(officeFindings(2, arabic: true, german: true), 'نتيجتان');
    expect(officeFindings(2), '2 findings');
  });
}
