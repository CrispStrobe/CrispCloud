// Tests for regex replacement expansion used by the editor find panel.

import 'package:crisp_cloud/services/search_replace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expandReplacementTemplate', () {
    test('expands numbered capture groups and the whole match', () {
      final match = RegExp(r'(\w+)=(\d+)').firstMatch('foo=12')!;
      expect(expandReplacementTemplate(r'$1: $2', match), 'foo: 12');
      expect(expandReplacementTemplate(r'[$&]', match), '[foo=12]');
      expect(expandReplacementTemplate(r'$$1', match), r'$1');
      expect(expandReplacementTemplate(r'$0', match), 'foo=12');
    });

    test('expands named capture groups', () {
      final match = RegExp(r'(?<key>\w+)=(?<value>\d+)').firstMatch('foo=12')!;
      expect(expandReplacementTemplate(r'${key}: ${value}', match), 'foo: 12');
    });

    test('keeps unknown groups and dollar text literal', () {
      final match = RegExp(r'\d+').firstMatch('42')!;
      expect(expandReplacementTemplate(r'$9', match), r'$9');
      expect(expandReplacementTemplate(r'cost: $', match), r'cost: $');
      expect(expandReplacementTemplate(r'price 5$', match), r'price 5$');
      // A lone dollar before a non-group is preserved.
      expect(expandReplacementTemplate(r'$x', match), r'$x');
    });

    test('falls back to the longest existing group in multi-digit refs', () {
      final match = RegExp(r'(\w+)=(\d+)').firstMatch('foo=12')!;
      expect(expandReplacementTemplate(r'$12', match), 'foo2');
      expect(expandReplacementTemplate(r'$21', match), '121');
    });
  });

  test('replaceAllWithExpansion replaces every match on LF text', () {
    const source = 'head\nfoo=12\nbar=34\ntail';
    final result = replaceAllWithExpansion(
      source,
      RegExp(r'(\w+)=(\d+)'),
      r'$1: $2',
    );
    expect(result, 'head\nfoo: 12\nbar: 34\ntail');
  });
}
