// test/search_command_test.dart
//
// Tests the glob-to-regex conversion in SearchCommand (without network I/O).

import 'package:test/test.dart';

import 'package:crisp/commands/search.dart';

void main() {
  group('SearchCommand glob pattern matching', () {
    RegExp buildRegex(String glob) {
      // Access the private static via a wrapper exposed in tests
      return SearchCommand.buildRegexForTest(glob);
    }

    test('* matches anything', () {
      final re = buildRegex('*.log');
      expect(re.hasMatch('error.log'), isTrue);
      expect(re.hasMatch('app.2024.log'), isTrue);
      expect(re.hasMatch('log'), isFalse);
    });

    test('? matches single character', () {
      final re = buildRegex('file?.txt');
      expect(re.hasMatch('file1.txt'), isTrue);
      expect(re.hasMatch('file22.txt'), isFalse);
    });

    test('exact name matches', () {
      final re = buildRegex('README.md');
      expect(re.hasMatch('README.md'), isTrue);
      expect(re.hasMatch('readme.md'), isTrue); // case-insensitive
      expect(re.hasMatch('README.txt'), isFalse);
    });

    test('* alone matches everything', () {
      final re = buildRegex('*');
      expect(re.hasMatch('anything'), isTrue);
      expect(re.hasMatch(''), isTrue);
    });

    test('dots are treated as literal', () {
      final re = buildRegex('file.txt');
      expect(re.hasMatch('filextxt'), isFalse);
      expect(re.hasMatch('file.txt'), isTrue);
    });

    test('character class [abc]', () {
      final re = buildRegex('[abc]ool');
      expect(re.hasMatch('aool'), isTrue);
      expect(re.hasMatch('bool'), isTrue);
      expect(re.hasMatch('dool'), isFalse);
    });
  });
}
