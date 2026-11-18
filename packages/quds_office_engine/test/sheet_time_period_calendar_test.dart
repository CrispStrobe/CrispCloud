import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

bool _matches(String period, DateTime clock, DateTime civilDate) {
  final sheet = SmlWorksheet(name: 'Dates', sheetId: 1);
  sheet.cellA1('A1').value = civilDate
      .difference(DateTime.utc(1899, 12, 30))
      .inDays;
  sheet.conditionalFormats.add(
    SmlConditionalRule(
      range: SmlRange.parse('A1'),
      kind: SmlConditionalKind.timePeriod,
      formula: period,
      fillRgb: 'FF0000',
    ),
  );
  return SmlConditionalResolver(
        sheet: sheet,
        now: () => clock,
      ).resolve(SmlCellRef.parse('A1')).fillRgb ==
      'FF0000';
}

void main() {
  // Run this file under UTC, Europe/Berlin and America/Los_Angeles to cover
  // offsets on both sides of UTC. The injected local calendar day is retained,
  // including near-midnight clocks whose UTC instant falls on another day.
  test('last seven days include both civil endpoints near local midnight', () {
    for (final hour in [0, 23]) {
      final clock = DateTime(2026, 11, 17, hour, 30);
      for (final day in [10, 11, 17, 18]) {
        expect(
          _matches('last7Days', clock, DateTime.utc(2026, 11, day)),
          day >= 11 && day <= 17,
          reason: 'hour=$hour day=$day offset=${clock.timeZoneOffset}',
        );
      }
    }
  });

  test('week ranges include Sunday and exclude the following Sunday', () {
    final clock = DateTime(2026, 11, 17, 12);
    for (final (period, firstDay) in [
      ('lastWeek', 8),
      ('thisWeek', 15),
      ('nextWeek', 22),
    ]) {
      for (final offset in [-1, 0, 6, 7]) {
        expect(
          _matches(period, clock, DateTime.utc(2026, 11, firstDay + offset)),
          offset >= 0 && offset < 7,
          reason: '$period offset=$offset timezone=${clock.timeZoneOffset}',
        );
      }
    }
  });

  for (final (month, day, sunday) in [
    (3, 30, 29),
    (10, 26, 25),
    (3, 9, 8),
    (11, 2, 1),
  ]) {
    test('civil day/week arithmetic crosses DST at 2026-$month-$day', () {
      final clock = DateTime(2026, month, day, 0, 30);
      final today = DateTime.utc(2026, month, day);
      final start = DateTime.utc(2026, month, sunday);
      expect(_matches('today', clock, today), isTrue);
      expect(
        _matches('yesterday', clock, today.subtract(const Duration(days: 1))),
        isTrue,
      );
      expect(
        _matches('tomorrow', clock, today.add(const Duration(days: 1))),
        isTrue,
      );
      expect(_matches('last7Days', clock, today), isTrue);
      expect(
        _matches('last7Days', clock, today.subtract(const Duration(days: 6))),
        isTrue,
      );
      expect(
        _matches('last7Days', clock, today.subtract(const Duration(days: 7))),
        isFalse,
      );
      expect(_matches('thisWeek', clock, start), isTrue);
      expect(
        _matches('thisWeek', clock, start.add(const Duration(days: 6))),
        isTrue,
      );
      expect(
        _matches('thisWeek', clock, start.add(const Duration(days: 7))),
        isFalse,
      );
    });
  }

  test('January month periods retain the local year near midnight', () {
    final clock = DateTime(2026, 1, 1, 0, 30);
    expect(_matches('lastMonth', clock, DateTime.utc(2025, 12, 31)), isTrue);
    expect(_matches('lastMonth', clock, DateTime.utc(2025, 11, 30)), isFalse);
    expect(_matches('thisMonth', clock, DateTime.utc(2026, 1, 1)), isTrue);
    expect(_matches('thisMonth', clock, DateTime.utc(2026, 1, 31)), isTrue);
    expect(_matches('nextMonth', clock, DateTime.utc(2026, 2, 1)), isTrue);
    expect(_matches('nextMonth', clock, DateTime.utc(2026, 3, 1)), isFalse);
  });

  test('December next-month period crosses the local calendar year', () {
    final clock = DateTime(2026, 12, 31, 23, 30);
    expect(_matches('thisMonth', clock, DateTime.utc(2026, 12, 31)), isTrue);
    expect(_matches('nextMonth', clock, DateTime.utc(2027, 1, 1)), isTrue);
    expect(_matches('nextMonth', clock, DateTime.utc(2027, 1, 31)), isTrue);
    expect(_matches('nextMonth', clock, DateTime.utc(2027, 2, 1)), isFalse);
  });
}
