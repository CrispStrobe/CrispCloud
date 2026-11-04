import 'package:pdf_operations/pdf_operations.dart';
import 'package:test/test.dart';

void main() {
  test('ranges retain requested order and use one-based inclusive notation', () {
    expect(PdfPageRange.parse(' 4-2, 1 ', 4), [3, 2, 1, 0]);
    expect(PdfPageRange.parse('1-3,7', 8), [0, 1, 2, 6]);
    expect(PdfPageRange.parse('ALL', 3), [0, 1, 2]);
  });

  for (final expression in ['', '0', '1-5', '1,1', '1-3,2', '-1', '1,,2',
    '2-', 'all,1', '1.5', '999999999999999999999999999999999']) {
    test('rejects invalid selection $expression', () {
      expect(() => PdfPageRange.parse(expression, 4),
          throwsA(isA<PdfOperationException>().having((e) => e.code, 'code', 'invalidPages')));
    });
  }

  test('explicit duplication opt-in does not change normal workflow policy', () {
    expect(PdfPageRange.parse('2,2', 3, allowDuplicates: true), [1, 1]);
    expect(() => PdfPageRange.parse('2,2', 3), throwsA(isA<PdfOperationException>()));
  });

  test('no zero-page selection and returned indices are immutable', () {
    expect(() => PdfPageRange.parse('all', 0), throwsA(isA<PdfOperationException>()));
    expect(() => PdfPageRange.parse('all', 2).add(2), throwsUnsupportedError);
  });
}
