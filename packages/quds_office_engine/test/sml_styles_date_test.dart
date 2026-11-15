import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final date = DateTime.utc(2024, 1, 2, 12, 30);

  test('date codes render authored month and weekday names', () {
    expect(formatExcelDate(date, 'DD.MM.YYYY'), '02.01.2024');
    expect(formatExcelDate(date, 'MMMM D, YYYY'), 'January 2, 2024');
    expect(formatExcelDate(date, 'ddd, dd.mm.yyyy'), 'Tue, 02.01.2024');
    expect(
      formatExcelDate(date, 'DDDD, DD. MMMM YYYY'),
      'Tuesday, 02. January 2024',
    );
  });

  test('time codes distinguish months from minutes', () {
    expect(formatExcelDate(date, 'h:mm'), '12:30');
    expect(formatExcelDate(date, 'hh:mm:ss'), '12:30:00');
    expect(formatExcelDate(date, 'dd.mm.yyyy hh:mm'), '02.01.2024 12:30');
    expect(formatExcelDate(date, 'h:mm AM/PM'), '12:30 PM');
  });
}
