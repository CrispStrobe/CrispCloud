import 'package:crisp_cloud/services/command_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all words match independently of their order', () {
    expect(commandSearchScore('size sort', 'Sort by size'), isNotNull);
    expect(commandSearchScore('sort missing', 'Sort by size'), isNull);
  });
  test('exact and prefix matches rank above abbreviations', () {
    final exact = commandSearchScore('copy', 'Copy')!;
    final prefix = commandSearchScore('copy', 'Copy with options')!;
    final abbreviation = commandSearchScore('cpy', 'Copy with options')!;
    expect(exact, greaterThan(prefix));
    expect(prefix, greaterThan(abbreviation));
  });
  test('shortcut and semantic aliases are searchable across locales', () {
    expect(
      commandSearchScore('F9', 'Aktualisieren', keywords: 'refresh F9'),
      isNotNull,
    );
    expect(
      commandSearchScore('refresh', 'Aktualisieren', keywords: 'refresh F9'),
      isNotNull,
    );
    expect(commandSearchScore('akt', 'Aktualisieren'), isNotNull);
  });
  test('empty query is stable and unrelated terms have no result', () {
    expect(commandSearchScore('  ', 'Any command'), 0);
    expect(
      commandSearchScore('___no_such_command___', 'Copy with options'),
      isNull,
    );
  });
}
