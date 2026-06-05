// test/locale_formatting_test.dart
//
// Tests for the locale-aware formatting helpers in
// lib/services/formatters.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/formatters.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // LocaleFormats — static accessors
  // ─────────────────────────────────────────────────────────────────────────
  group('LocaleFormats', () {
    group('all 7 supported locales have entries', () {
      const locales = ['en', 'de', 'fr', 'es', 'pt', 'ja', 'zh'];
      for (final locale in locales) {
        test('locale $locale has a decimal separator', () {
          final sep = LocaleFormats.decimalSeparator(locale);
          expect(sep, isNotEmpty);
        });
        test('locale $locale has a thousands separator', () {
          // thousands separator may be empty-ish but must not throw
          expect(() => LocaleFormats.thousandsSeparator(locale), returnsNormally);
        });
        test('locale $locale has a date pattern', () {
          final pat = LocaleFormats.datePattern(locale);
          expect(pat, isNotEmpty);
          // Must contain year, month, and day tokens.
          expect(pat.contains('yyyy') || pat.contains('年'), isTrue);
        });
      }
    });

    test('unknown locale falls back to English decimal separator', () {
      expect(LocaleFormats.decimalSeparator('xx'), '.');
    });

    test('unknown locale falls back to English thousands separator', () {
      expect(LocaleFormats.thousandsSeparator('xx'), ',');
    });

    test('unknown locale falls back to English date pattern', () {
      expect(LocaleFormats.datePattern('xx'), 'MM/dd/yyyy');
    });

    test('full BCP-47 tag en-US falls back to English', () {
      expect(LocaleFormats.decimalSeparator('en-US'), '.');
      expect(LocaleFormats.datePattern('en-US'), 'MM/dd/yyyy');
    });

    test('de decimal separator is comma', () {
      expect(LocaleFormats.decimalSeparator('de'), ',');
    });

    test('de thousands separator is period', () {
      expect(LocaleFormats.thousandsSeparator('de'), '.');
    });

    test('fr thousands separator is narrow no-break space', () {
      expect(LocaleFormats.thousandsSeparator('fr'), '\u202f');
    });

    test('en uses 12-hour time', () {
      expect(LocaleFormats.uses12hTime('en'), isTrue);
    });

    test('de uses 24-hour time', () {
      expect(LocaleFormats.uses12hTime('de'), isFalse);
    });

    test('fr uses 24-hour time', () {
      expect(LocaleFormats.uses12hTime('fr'), isFalse);
    });

    test('ja uses 24-hour time', () {
      expect(LocaleFormats.uses12hTime('ja'), isFalse);
    });

    test('fr unit label converts MB to Mo', () {
      expect(LocaleFormats.unitLabel('fr', 'MB'), 'Mo');
      expect(LocaleFormats.unitLabel('fr', 'GB'), 'Go');
      expect(LocaleFormats.unitLabel('fr', 'KB'), 'Ko');
      expect(LocaleFormats.unitLabel('fr', 'B'), 'o');
      expect(LocaleFormats.unitLabel('fr', 'TB'), 'To');
    });

    test('en unit label is unchanged', () {
      expect(LocaleFormats.unitLabel('en', 'MB'), 'MB');
      expect(LocaleFormats.unitLabel('en', 'GB'), 'GB');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // formatBytesLocale
  // ─────────────────────────────────────────────────────────────────────────
  group('formatBytesLocale', () {
    // en: decimal='.', thousands=','
    test('English — 0 bytes', () {
      expect(formatBytesLocale(0, 'en'), '0 B');
    });

    test('English — negative bytes treated as 0', () {
      expect(formatBytesLocale(-500, 'en'), '0 B');
    });

    test('English — bytes', () {
      expect(formatBytesLocale(512, 'en'), '512 B');
    });

    test('English — kilobytes', () {
      expect(formatBytesLocale(1024, 'en'), '1.0 KB');
    });

    test('English — megabytes', () {
      expect(formatBytesLocale(500 * 1024 * 1024, 'en'), '500.0 MB');
    });

    test('English — terabytes with thousands separator', () {
      // 1234 TB = 1234 * 1024^4 = 1_356_797_348_675_584 bytes
      expect(formatBytesLocale(1356797348675584, 'en'), '1,234.0 TB');
    });

    test('English — gigabytes', () {
      expect(formatBytesLocale(1024 * 1024 * 1024, 'en'), '1.0 GB');
    });

    test('English — terabytes', () {
      expect(formatBytesLocale(1024 * 1024 * 1024 * 1024, 'en'), '1.0 TB');
    });

    // de: decimal=',', thousands='.'
    test('German — 0 bytes', () {
      expect(formatBytesLocale(0, 'de'), '0 B');
    });

    test('German — terabytes with dot thousands and comma decimal', () {
      expect(formatBytesLocale(1356797348675584, 'de'), '1.234,0 TB');
    });

    test('German — megabytes uses comma decimal', () {
      expect(formatBytesLocale(500 * 1024 * 1024, 'de'), '500,0 MB');
    });

    test('German — kilobytes', () {
      expect(formatBytesLocale(1024, 'de'), '1,0 KB');
    });

    // fr: decimal=',', thousands='\u202f', unit suffix differs
    test('French — terabytes uses narrow space and To suffix', () {
      expect(formatBytesLocale(1356797348675584, 'fr'), '1\u202f234,0 To');
    });

    test('French — megabytes uses Mo suffix', () {
      expect(formatBytesLocale(500 * 1024 * 1024, 'fr'), '500,0 Mo');
    });

    test('French — kilobytes uses Ko suffix', () {
      expect(formatBytesLocale(1024, 'fr'), '1,0 Ko');
    });

    // ja: decimal='.', thousands=','
    test('Japanese — terabytes same format as English', () {
      expect(formatBytesLocale(1356797348675584, 'ja'), '1,234.0 TB');
    });

    // zh: decimal='.', thousands=','
    test('Chinese — terabytes same format as English', () {
      expect(formatBytesLocale(1356797348675584, 'zh'), '1,234.0 TB');
    });

    // es: decimal=',', thousands='.'
    test('Spanish — terabytes', () {
      expect(formatBytesLocale(1356797348675584, 'es'), '1.234,0 TB');
    });

    // pt: decimal=',', thousands='.'
    test('Portuguese — terabytes', () {
      expect(formatBytesLocale(1356797348675584, 'pt'), '1.234,0 TB');
    });

    test('unknown locale falls back to English', () {
      expect(formatBytesLocale(1024, 'xx'), '1.0 KB');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // formatDateLocale
  // ─────────────────────────────────────────────────────────────────────────
  group('formatDateLocale', () {
    final date = DateTime(2026, 6, 5, 14, 30);

    test('null date returns empty string', () {
      expect(formatDateLocale(null, 'en'), '');
    });

    test('English — MM/dd/yyyy', () {
      expect(formatDateLocale(date, 'en'), '06/05/2026');
    });

    test('German — dd.MM.yyyy', () {
      expect(formatDateLocale(date, 'de'), '05.06.2026');
    });

    test('French — dd/MM/yyyy', () {
      expect(formatDateLocale(date, 'fr'), '05/06/2026');
    });

    test('Spanish — dd/MM/yyyy', () {
      expect(formatDateLocale(date, 'es'), '05/06/2026');
    });

    test('Portuguese — dd/MM/yyyy', () {
      expect(formatDateLocale(date, 'pt'), '05/06/2026');
    });

    test('Japanese — yyyy/MM/dd', () {
      expect(formatDateLocale(date, 'ja'), '2026/06/05');
    });

    test('Chinese — yyyy年MM月dd日', () {
      expect(formatDateLocale(date, 'zh'), '2026年06月05日');
    });

    test('unknown locale falls back to English', () {
      expect(formatDateLocale(date, 'xx'), '06/05/2026');
    });

    test('pads single-digit month and day', () {
      final d = DateTime(2026, 1, 3);
      expect(formatDateLocale(d, 'en'), '01/03/2026');
      expect(formatDateLocale(d, 'de'), '03.01.2026');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // formatDateFullLocale
  // ─────────────────────────────────────────────────────────────────────────
  group('formatDateFullLocale', () {
    test('null date returns empty string', () {
      expect(formatDateFullLocale(null, 'en'), '');
    });

    test('includes time component', () {
      final date = DateTime(2026, 6, 5, 14, 30);
      final result = formatDateFullLocale(date, 'en');
      expect(result, contains('06/05/2026'));
      expect(result, contains('30')); // minute part
    });

    test('English — 12-hour time with AM', () {
      final date = DateTime(2026, 6, 5, 9, 5);
      expect(formatDateFullLocale(date, 'en'), '06/05/2026 9:05 AM');
    });

    test('English — 12-hour time with PM', () {
      final date = DateTime(2026, 6, 5, 14, 30);
      expect(formatDateFullLocale(date, 'en'), '06/05/2026 2:30 PM');
    });

    test('English — midnight is 12:00 AM', () {
      final date = DateTime(2026, 6, 5, 0, 0);
      expect(formatDateFullLocale(date, 'en'), '06/05/2026 12:00 AM');
    });

    test('English — noon is 12:00 PM', () {
      final date = DateTime(2026, 6, 5, 12, 0);
      expect(formatDateFullLocale(date, 'en'), '06/05/2026 12:00 PM');
    });

    test('German — 24-hour time', () {
      final date = DateTime(2026, 6, 5, 14, 30);
      expect(formatDateFullLocale(date, 'de'), '05.06.2026 14:30');
    });

    test('French — 24-hour time with French date', () {
      final date = DateTime(2026, 6, 5, 9, 5);
      expect(formatDateFullLocale(date, 'fr'), '05/06/2026 09:05');
    });

    test('Japanese — 24-hour time with Japanese date', () {
      final date = DateTime(2026, 6, 5, 14, 30);
      expect(formatDateFullLocale(date, 'ja'), '2026/06/05 14:30');
    });

    test('Chinese — 24-hour time with Chinese date', () {
      final date = DateTime(2026, 6, 5, 14, 30);
      expect(formatDateFullLocale(date, 'zh'), '2026年06月05日 14:30');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // formatNumberLocale
  // ─────────────────────────────────────────────────────────────────────────
  group('formatNumberLocale', () {
    test('English — decimal separator is period', () {
      expect(formatNumberLocale(1234.56, 'en'), '1,234.56');
    });

    test('German — decimal separator is comma, thousands is period', () {
      expect(formatNumberLocale(1234.56, 'de'), '1.234,56');
    });

    test('French — thousands separator is narrow no-break space', () {
      expect(formatNumberLocale(1234.56, 'fr'), '1\u202f234,56');
    });

    test('Spanish — like German', () {
      expect(formatNumberLocale(1234.56, 'es'), '1.234,56');
    });

    test('Portuguese — like German', () {
      expect(formatNumberLocale(1234.56, 'pt'), '1.234,56');
    });

    test('Japanese — like English', () {
      expect(formatNumberLocale(1234.56, 'ja'), '1,234.56');
    });

    test('Chinese — like English', () {
      expect(formatNumberLocale(1234.56, 'zh'), '1,234.56');
    });

    test('zero decimals parameter', () {
      expect(formatNumberLocale(1234.0, 'en', decimals: 0), '1,234');
    });

    test('four decimal places', () {
      expect(formatNumberLocale(3.14159, 'en', decimals: 4), '3.1416');
    });

    test('negative number', () {
      expect(formatNumberLocale(-1234.56, 'en'), '-1,234.56');
    });

    test('small number below thousand — no thousands separator', () {
      expect(formatNumberLocale(99.99, 'en'), '99.99');
    });

    test('very large number', () {
      expect(formatNumberLocale(1234567.0, 'en', decimals: 0), '1,234,567');
    });

    test('unknown locale falls back to English', () {
      expect(formatNumberLocale(1234.56, 'xx'), '1,234.56');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // formatSpeedLocale
  // ─────────────────────────────────────────────────────────────────────────
  group('formatSpeedLocale', () {
    test('English — zero speed', () {
      expect(formatSpeedLocale(0, 'en'), '0 B/s');
    });

    test('English — negative speed treated as zero', () {
      expect(formatSpeedLocale(-100, 'en'), '0 B/s');
    });

    test('English — bytes per second', () {
      expect(formatSpeedLocale(512, 'en'), '512 B/s');
    });

    test('English — megabytes per second', () {
      expect(formatSpeedLocale(1024 * 1024.0, 'en'), '1.0 MB/s');
    });

    test('German — uses comma decimal', () {
      expect(formatSpeedLocale(1024 * 1024.0, 'de'), '1,0 MB/s');
    });

    test('French — uses Mo suffix', () {
      expect(formatSpeedLocale(1024 * 1024.0, 'fr'), '1,0 Mo/s');
    });

    test('Japanese — uses period decimal', () {
      expect(formatSpeedLocale(1024 * 1024.0, 'ja'), '1.0 MB/s');
    });

    test('French — zero speed uses correct unit label', () {
      expect(formatSpeedLocale(0, 'fr'), '0 o/s');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Backwards compatibility — original non-locale functions unchanged
  // ─────────────────────────────────────────────────────────────────────────
  group('backwards compatibility', () {
    test('formatBytes still works', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1048576), '1.0 MB');
      expect(formatBytes(1073741824), '1.0 GB');
      expect(formatBytes(1099511627776), '1.0 TB');
    });

    test('formatDate still works', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      expect(formatDate(DateTime(2026, 5, 29, 10, 0), now: now), 'Today');
      expect(formatDate(DateTime(2026, 5, 28, 20, 0), now: now), 'Yesterday');
      expect(formatDate(DateTime(2026, 5, 26, 10, 0), now: now), '3 days ago');
      expect(formatDate(DateTime(2026, 5, 10, 10, 0), now: now), '2026-05-10');
    });

    test('formatDateFull still works', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      expect(
        formatDateFull(DateTime(2026, 5, 29, 9, 5), now: now),
        'Today at 09:05',
      );
    });

    test('formatDuration still works', () {
      expect(formatDuration(const Duration(seconds: 3)), '3s');
      expect(formatDuration(const Duration(minutes: 2, seconds: 15)), '2m 15s');
      expect(formatDuration(const Duration(hours: 1, minutes: 30)), '1h 30m');
      expect(formatDuration(const Duration(days: 2, hours: 5)), '2d 5h');
    });

    test('formatSpeed still works', () {
      expect(formatSpeed(0), '0 B/s');
      expect(formatSpeed(1048576), '1.0 MB/s');
    });
  });
}
