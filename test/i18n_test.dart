import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Find the project root by looking for pubspec.yaml.
String _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current.path;
    dir = parent;
  }
}

/// Loads an ARB file and returns a parsed Map.
/// Safe to call at group scope (no expect() calls).
Map<String, dynamic> _loadArb(String locale) {
  final root = _findProjectRoot();
  final file = File('$root/lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    throw StateError('ARB file for locale "$locale" not found at ${file.path}');
  }
  final content = file.readAsStringSync();
  return jsonDecode(content) as Map<String, dynamic>;
}

/// Returns only the user-facing keys (no @-prefixed metadata, no @@locale).
Set<String> _userKeys(Map<String, dynamic> arb) {
  return arb.keys
      .where((k) => !k.startsWith('@'))
      .toSet();
}

/// All supported locales under test.
const List<String> _locales = ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja'];

/// Placeholders that must be preserved verbatim in translated values.
const Map<String, List<String>> _placeholdersByKey = {
  'nSelected': ['{count}'],
  'transferProgress': ['{percent}'],
  'transferSpeed': ['{speed}'],
  'transferEta': ['{time}'],
  'deleteFailed': ['{error}'],
  'renameFailed': ['{error}'],
  'operationFailed': ['{error}'],
  'confirmDeleteMessage': ['{count}'],
};

void main() {
  // ---------------------------------------------------------------------------
  // 1. File existence
  // ---------------------------------------------------------------------------
  group('ARB file existence', () {
    for (final locale in _locales) {
      test('app_$locale.arb exists', () {
        final file = File('lib/l10n/app_$locale.arb');
        expect(file.existsSync(), isTrue,
            reason: 'Missing lib/l10n/app_$locale.arb');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 2. Valid JSON
  // ---------------------------------------------------------------------------
  group('ARB files are valid JSON', () {
    for (final locale in _locales) {
      test('app_$locale.arb parses as valid JSON', () {
        final file = File('lib/l10n/app_$locale.arb');
        if (!file.existsSync()) return; // covered by existence test
        expect(
          () => jsonDecode(file.readAsStringSync()),
          returnsNormally,
          reason: 'app_$locale.arb must be valid JSON',
        );
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 3. @@locale matches filename
  // ---------------------------------------------------------------------------
  group('@@locale matches filename', () {
    for (final locale in _locales) {
      test('app_$locale.arb has @@locale == "$locale"', () {
        final arb = _loadArb(locale);
        expect(arb['@@locale'], equals(locale),
            reason:
                'app_$locale.arb: @@locale should be "$locale" but was "${arb['@@locale']}"');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 4. Key consistency – all locales have the same user-facing keys as English
  // ---------------------------------------------------------------------------
  group('All locales have the same keys as English', () {
    final enArb = _loadArb('en');
    final enKeys = _userKeys(enArb);

    for (final locale in _locales.where((l) => l != 'en')) {
      test('app_$locale.arb has identical keys to app_en.arb', () {
        final arb = _loadArb(locale);
        final keys = _userKeys(arb);

        final missing = enKeys.difference(keys);
        final extra = keys.difference(enKeys);

        expect(missing, isEmpty,
            reason: 'app_$locale.arb is missing keys: $missing');
        expect(extra, isEmpty,
            reason: 'app_$locale.arb has unexpected extra keys: $extra');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 5. No empty string values
  // ---------------------------------------------------------------------------
  group('No empty string values', () {
    for (final locale in _locales) {
      test('app_$locale.arb has no empty string values', () {
        final arb = _loadArb(locale);
        final emptyKeys = arb.entries
            .where((e) => !e.key.startsWith('@') && e.value is String && (e.value as String).isEmpty)
            .map((e) => e.key)
            .toList();
        expect(emptyKeys, isEmpty,
            reason: 'app_$locale.arb has empty values for keys: $emptyKeys');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 6. No duplicate keys (JSON parsers silently accept them)
  // ---------------------------------------------------------------------------
  group('No duplicate keys', () {
    for (final locale in _locales) {
      test('app_$locale.arb has no duplicate keys', () {
        final file = File('lib/l10n/app_$locale.arb');
        if (!file.existsSync()) return;
        final content = file.readAsStringSync();
        // Walk the raw text to count top-level key occurrences.
        final keyPattern = RegExp(r'^\s*"([^"@][^"]*)"\s*:', multiLine: true);
        final allMatches = keyPattern.allMatches(content).map((m) => m.group(1)!).toList();
        final seen = <String>{};
        final duplicates = <String>[];
        for (final k in allMatches) {
          if (!seen.add(k)) duplicates.add(k);
        }
        expect(duplicates, isEmpty,
            reason: 'app_$locale.arb has duplicate keys: $duplicates');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 7. Placeholder patterns preserved in all translations
  // ---------------------------------------------------------------------------
  group('Placeholder patterns preserved', () {
    for (final locale in _locales) {
      for (final entry in _placeholdersByKey.entries) {
        final key = entry.key;
        final placeholders = entry.value;
        test('app_$locale.arb [$key] preserves placeholders $placeholders', () {
          final arb = _loadArb(locale);
          final value = arb[key];
          expect(value, isA<String>(),
              reason: 'app_$locale.arb: key "$key" must be a String');
          for (final ph in placeholders) {
            expect((value as String).contains(ph), isTrue,
                reason:
                    'app_$locale.arb: key "$key" must contain placeholder "$ph" but value was: "$value"');
          }
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 8. CrispCloud brand name unchanged in all locales
  // ---------------------------------------------------------------------------
  group('CrispCloud brand name preserved', () {
    for (final locale in _locales) {
      test('app_$locale.arb appTitle is "CrispCloud"', () {
        final arb = _loadArb(locale);
        expect(arb['appTitle'], equals('CrispCloud'),
            reason:
                'app_$locale.arb: appTitle must remain "CrispCloud", got "${arb['appTitle']}"');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 9. @-metadata keys present for keys that have them in English
  // ---------------------------------------------------------------------------
  group('@-metadata entries preserved', () {
    const metadataKeys = [
      '@appTitle',
      '@nSelected',
      '@transferProgress',
      '@transferSpeed',
      '@transferEta',
      '@deleteFailed',
      '@renameFailed',
      '@operationFailed',
      '@confirmDeleteMessage',
    ];

    // Only the new 5 locales need to carry metadata (German template omits some,
    // but new files follow the English template exactly).
    const newLocales = ['fr', 'es', 'pt', 'zh', 'ja'];

    for (final locale in newLocales) {
      for (final mk in metadataKeys) {
        test('app_$locale.arb contains $mk', () {
          final arb = _loadArb(locale);
          expect(arb.containsKey(mk), isTrue,
              reason: 'app_$locale.arb is missing metadata key "$mk"');
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 10. All string values are actually Strings (not objects / null)
  // ---------------------------------------------------------------------------
  group('All user-facing values are strings', () {
    for (final locale in _locales) {
      test('app_$locale.arb user-facing values are all strings', () {
        final arb = _loadArb(locale);
        final nonStringKeys = arb.entries
            .where((e) => !e.key.startsWith('@') && e.value is! String)
            .map((e) => '${e.key}: ${e.value.runtimeType}')
            .toList();
        expect(nonStringKeys, isEmpty,
            reason:
                'app_$locale.arb has non-string values for: $nonStringKeys');
      });
    }
  });
}
