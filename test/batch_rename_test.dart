import 'package:flutter_test/flutter_test.dart';

// Test the rename logic directly (extracted from batch_rename_dialog.dart)
// These are pure string transform functions, no widget testing needed.

String applyFindReplace(String name, String find, String replace, {bool useRegex = false}) {
  if (find.isEmpty) return name;
  if (useRegex) {
    return name.replaceAllMapped(RegExp(find), (m) {
      return replace.replaceAllMapped(RegExp(r'\$(\d+)'), (ref) {
        final groupIndex = int.parse(ref.group(1)!);
        return m.group(groupIndex) ?? '';
      });
    });
  }
  return name.replaceAll(find, replace);
}

String applyNumbering(String name, int index, {int start = 1}) {
  final num = (start + index).toString().padLeft(3, '0');
  final dot = name.lastIndexOf('.');
  if (dot > 0) {
    final ext = name.substring(dot);
    final base = name.substring(0, dot);
    return '${base}_$num$ext';
  }
  return '${name}_$num';
}

String applyPrefixSuffix(String name, String prefix, String suffix) {
  final dot = name.lastIndexOf('.');
  if (dot > 0 && suffix.isNotEmpty) {
    final ext = name.substring(dot);
    final base = name.substring(0, dot);
    return '$prefix$base$suffix$ext';
  }
  return '$prefix$name$suffix';
}

String applyExtension(String name, String newExt) {
  if (newExt.isEmpty) return name;
  final dot = name.lastIndexOf('.');
  if (dot > 0) {
    return '${name.substring(0, dot)}.$newExt';
  }
  return '$name.$newExt';
}

void main() {
  group('Find & Replace', () {
    test('simple text replace', () {
      expect(applyFindReplace('photo_001.jpg', 'photo', 'image'), 'image_001.jpg');
    });

    test('replace all occurrences', () {
      expect(applyFindReplace('a-b-c.txt', '-', '_'), 'a_b_c.txt');
    });

    test('empty find returns original', () {
      expect(applyFindReplace('file.txt', '', 'x'), 'file.txt');
    });

    test('regex replace', () {
      expect(applyFindReplace('IMG_20260529_143025.jpg', r'\d+', 'X', useRegex: true), 'IMG_X_X.jpg');
    });

    test('regex capture groups', () {
      expect(applyFindReplace('report-2026.pdf', r'(\d{4})', r'year_$1', useRegex: true), 'report-year_2026.pdf');
    });
  });

  group('Numbering', () {
    test('adds sequential numbers', () {
      expect(applyNumbering('photo.jpg', 0), 'photo_001.jpg');
      expect(applyNumbering('photo.jpg', 1), 'photo_002.jpg');
      expect(applyNumbering('photo.jpg', 9), 'photo_010.jpg');
    });

    test('custom start number', () {
      expect(applyNumbering('doc.pdf', 0, start: 100), 'doc_100.pdf');
    });

    test('no extension', () {
      expect(applyNumbering('README', 0), 'README_001');
    });
  });

  group('Prefix & Suffix', () {
    test('adds prefix', () {
      expect(applyPrefixSuffix('file.txt', 'backup_', ''), 'backup_file.txt');
    });

    test('adds suffix before extension', () {
      expect(applyPrefixSuffix('photo.jpg', '', '_edited'), 'photo_edited.jpg');
    });

    test('adds both', () {
      expect(applyPrefixSuffix('data.csv', '2026_', '_final'), '2026_data_final.csv');
    });

    test('no extension with suffix', () {
      expect(applyPrefixSuffix('Makefile', 'old_', ''), 'old_Makefile');
    });
  });

  group('Extension change', () {
    test('changes extension', () {
      expect(applyExtension('photo.jpg', 'png'), 'photo.png');
    });

    test('adds extension to extensionless file', () {
      expect(applyExtension('README', 'md'), 'README.md');
    });

    test('empty new extension returns original', () {
      expect(applyExtension('file.txt', ''), 'file.txt');
    });

    test('handles multiple dots', () {
      expect(applyExtension('archive.tar.gz', 'zip'), 'archive.tar.zip');
    });
  });
}
