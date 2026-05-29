import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/utils/formatters.dart';

void main() {
  group('formatBytes', () {
    test('formats 0 bytes', () {
      expect(formatBytes(0), '0 B');
    });

    test('formats negative as 0 B', () {
      expect(formatBytes(-1), '0 B');
    });

    test('formats bytes', () {
      expect(formatBytes(500), '500 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('formats kilobytes', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(10240), '10.0 KB');
    });

    test('formats megabytes', () {
      expect(formatBytes(1048576), '1.0 MB');
      expect(formatBytes(1572864), '1.5 MB');
      expect(formatBytes(104857600), '100.0 MB');
    });

    test('formats gigabytes', () {
      expect(formatBytes(1073741824), '1.0 GB');
      expect(formatBytes(1610612736), '1.5 GB');
    });

    test('formats terabytes', () {
      expect(formatBytes(1099511627776), '1.0 TB');
    });
  });

  group('formatDate', () {
    test('returns Today for same day', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 5, 29, 10, 0);
      expect(formatDate(date, now: now), 'Today');
    });

    test('returns Yesterday for previous day', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 5, 28, 20, 0);
      expect(formatDate(date, now: now), 'Yesterday');
    });

    test('returns N days ago for recent dates', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 5, 26, 10, 0);
      expect(formatDate(date, now: now), '3 days ago');
    });

    test('returns YYYY-MM-DD for dates over 7 days ago', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 5, 10, 10, 0);
      expect(formatDate(date, now: now), '2026-05-10');
    });

    test('pads month and day with leading zeros', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 1, 5, 10, 0);
      expect(formatDate(date, now: now), '2026-01-05');
    });
  });

  group('formatDateFull', () {
    test('formats today with time', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 5, 29, 9, 5);
      expect(formatDateFull(date, now: now), 'Today at 09:05');
    });

    test('formats yesterday with time', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 5, 28, 22, 45);
      expect(formatDateFull(date, now: now), 'Yesterday at 22:45');
    });

    test('formats older date with time', () {
      final now = DateTime(2026, 5, 29, 14, 30);
      final date = DateTime(2026, 3, 15, 8, 3);
      expect(formatDateFull(date, now: now), '2026-03-15 at 08:03');
    });
  });

  group('formatDuration', () {
    test('formats seconds', () {
      expect(formatDuration(const Duration(seconds: 3)), '3s');
      expect(formatDuration(const Duration(seconds: 0)), '0s');
    });

    test('formats negative as 0s', () {
      expect(formatDuration(const Duration(seconds: -5)), '0s');
    });

    test('formats minutes and seconds', () {
      expect(formatDuration(const Duration(minutes: 2, seconds: 15)), '2m 15s');
    });

    test('formats hours and minutes', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 30)), '1h 30m');
    });

    test('formats days and hours', () {
      expect(formatDuration(const Duration(days: 2, hours: 5)), '2d 5h');
    });
  });

  group('formatSpeed', () {
    test('formats zero speed', () {
      expect(formatSpeed(0), '0 B/s');
    });

    test('formats negative speed', () {
      expect(formatSpeed(-100), '0 B/s');
    });

    test('formats bytes per second', () {
      expect(formatSpeed(500), '500 B/s');
    });

    test('formats KB per second', () {
      expect(formatSpeed(1048576), '1.0 MB/s');
    });

    test('formats MB per second', () {
      expect(formatSpeed(10485760), '10.0 MB/s');
    });
  });
}
