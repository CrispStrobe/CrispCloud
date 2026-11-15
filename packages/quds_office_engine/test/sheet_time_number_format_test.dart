import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  const date = 45293.0; // 2024-01-02 in the workbook's 1900 date system.
  const time = (13 * 3600 + 7 * 60 + 9) / 86400;

  test(
    'date formats accept uppercase tokens and preserve escaped literals',
    () {
      expect(applyNumberFormat(date, 'DD.MM.YYYY'), '02.01.2024');
      expect(applyNumberFormat(date, r'dd\.mm\.yyyy'), '02.01.2024');
      expect(applyNumberFormat(date, 'yyyy"-hmm-"mm"-"dd'), '2024-hmm-01-02');
    },
  );

  test('clock formats retain hours, minutes, seconds and AM/PM', () {
    expect(applyNumberFormat(time, 'h:mm'), '13:07');
    expect(applyNumberFormat(time, 'HH:MM:SS'), '13:07:09');
    expect(applyNumberFormat(time, 'h:mm AM/PM'), '1:07 PM');
    expect(applyNumberFormat(0, 'h:mm AM/PM'), '12:00 AM');
    expect(applyNumberFormat(0.5, 'h:mm AM/PM'), '12:00 PM');
  });

  test('minutes before seconds do not use the calendar month', () {
    const serial = date + (8 * 60 + 7) / 86400;
    expect(applyNumberFormat(serial, 'mm:ss'), '08:07');
    expect(applyNumberFormat(serial, 'm:ss'), '8:07');
  });

  test('date tokens reset minute context after a time', () {
    expect(
      applyNumberFormat(date + time, 'hh:mm dd/mm/yyyy'),
      '13:07 02/01/2024',
    );
    expect(
      applyNumberFormat(date + time, 'dd/mm/yyyy mm:ss'),
      '02/01/2024 07:09',
    );
    expect(
      applyNumberFormat(date + time, 'dd/mm/yyyy hh:mm:ss'),
      '02/01/2024 13:07:09',
    );
  });

  test('quoted time tokens cannot change minute or elapsed context', () {
    expect(
      applyNumberFormat(date + time, 'hh:mm "mm:ss [h]" yyyy-mm-dd'),
      '13:07 mm:ss [h] 2024-01-02',
    );
    expect(applyNumberFormat(7, '"[h]" 0'), '[h] 7');
    expect(applyNumberFormat(7, '"[h]"'), '[h]');
  });

  test('elapsed hours, minutes and seconds retain totals beyond one day', () {
    const duration = (30 * 3600 + 7 * 60 + 9) / 86400;
    expect(applyNumberFormat(duration, '[h]:mm:ss'), '30:07:09');
    expect(applyNumberFormat(duration, '[hh]:mm:ss'), '30:07:09');
    expect(applyNumberFormat(duration, '[m]:ss'), '1807:09');
    expect(applyNumberFormat(duration, '[mm]'), '1807');
    expect(applyNumberFormat(duration, '[s]'), '108429');
  });

  test('standalone elapsed tokens support zero and padded uppercase units', () {
    expect(applyNumberFormat(0, '[h]'), '0');
    expect(applyNumberFormat(0, '[m]'), '0');
    expect(applyNumberFormat(0, '[s]'), '0');
    expect(applyNumberFormat(8 / 24, '[HH]'), '08');
    expect(applyNumberFormat(8 / 1440, '[MM]'), '08');
    expect(applyNumberFormat(7 / 86400, '[SS]'), '07');
  });

  test('negative elapsed sections retain the sign and positive remainders', () {
    expect(applyNumberFormat(-0.5 / 24, '[h]:mm:ss'), '-0:30:00');
    expect(applyNumberFormat(-30.5 / 24, '[h]:mm;([h]:mm)'), '(30:30)');
  });
}
