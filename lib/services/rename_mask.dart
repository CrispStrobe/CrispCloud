import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';

/// The selected grammar is saved with a preset. Ambiguous date/range tokens
/// therefore keep their meaning when a preset is reopened on another machine.
enum RenameMaskDialect { crispCloud, totalCommander, doubleCommander }

enum RenameDateSource { modified, created, accessed, captured, current }

enum RenameDateZone { original, local, utc }

class RenameMaskContext {
  const RenameMaskContext({
    required this.file,
    required this.name,
    required this.extension,
    required this.sourcePath,
    required this.paths,
    required this.index,
    required this.counterStart,
    required this.counterStep,
    required this.counterWidth,
    required this.referenceTime,
    this.optionsChangedAt,
    this.dialect = RenameMaskDialect.crispCloud,
    this.dateSource = RenameDateSource.modified,
    this.dateZone = RenameDateZone.original,
    this.dateOffsetMinutes = 0,
    this.variables = const {},
  });

  final FileItem file;
  final String name;
  final String extension;
  final String sourcePath;
  final p.Context paths;
  final int index;
  final int counterStart;
  final int counterStep;
  final int counterWidth;
  final DateTime referenceTime;
  final DateTime? optionsChangedAt;
  final RenameMaskDialect dialect;
  final RenameDateSource dateSource;
  final RenameDateZone dateZone;
  final int dateOffsetMinutes;
  final Map<String, String> variables;

  String get parent => paths.basename(paths.dirname(sourcePath));
}

/// Expand a mask without I/O. Date/metadata values must have been captured
/// before preview, and [RenameMaskContext.referenceTime] stays fixed for the
/// whole preview/execution batch (including generated GUIDs).
String expandRenameMask(
  String mask,
  RenameMaskContext context, {
  bool allowUnavailableValues = false,
}) {
  final result = StringBuffer();
  var position = 0;
  var letterCase = '';
  var titleStart = true;
  var dateSource = context.dateSource;
  var currentTime = context.referenceTime;
  var offset = _checkedOffset(context.dateOffsetMinutes);
  void append(String text) {
    if (letterCase == 'F') {
      for (final rune in text.runes) {
        final letter = String.fromCharCode(rune);
        final isLetter = letter.toLowerCase() != letter.toUpperCase();
        result.write(
          isLetter
              ? titleStart
                    ? letter.toUpperCase()
                    : letter.toLowerCase()
              : letter,
        );
        titleStart = !isLetter && !RegExp(r'\d').hasMatch(letter);
      }
      return;
    }
    result.write(switch (letterCase) {
      'U' => text.toUpperCase(),
      'L' => text.toLowerCase(),
      _ => text,
    });
  }

  while (position < mask.length) {
    if (context.dialect != RenameMaskDialect.crispCloud &&
        mask.startsWith('[[]', position)) {
      append('[');
      position += 3;
    } else if (context.dialect != RenameMaskDialect.crispCloud &&
        mask.startsWith('[]]', position)) {
      append(']');
      position += 3;
    } else if (mask.startsWith('[[', position)) {
      append('[');
      position += 2;
    } else if (mask.startsWith(']]', position)) {
      append(']');
      position += 2;
    } else if (mask[position] == '[') {
      final end = mask.indexOf(']', position + 1);
      if (end < 0) {
        throw const FormatException('A mask token is missing its closing ].');
      }
      final token = mask.substring(position + 1, end);
      final time = RegExp(r'^T([1-5])(?:([+-]\d+)([dhms]))?$')
          .firstMatch(token);
      if (context.dialect == RenameMaskDialect.totalCommander &&
          const {'U', 'L', 'F', 'n'}.contains(token)) {
        letterCase = token == 'n' ? '' : token;
        if (token == 'F') titleStart = true;
      } else if (time != null) {
        if (context.dialect == RenameMaskDialect.totalCommander) {
          // TC's switches distinguish dialog-open and options-change time.
          // https://www.ghisler.com/android/help.htm (Multi-Rename Tool)
          dateSource = switch (time[1]) {
            '1' => RenameDateSource.modified,
            '2' || '3' => RenameDateSource.current,
            '4' => RenameDateSource.captured,
            _ => throw FormatException('Unknown mask token [$token].'),
          };
          currentTime = time[1] == '3'
              ? context.optionsChangedAt ?? context.referenceTime
              : context.referenceTime;
        } else {
          dateSource = switch (time[1]) {
            '1' => RenameDateSource.modified,
            '2' => RenameDateSource.created,
            '3' => RenameDateSource.accessed,
            '4' => RenameDateSource.captured,
            _ => RenameDateSource.current,
          };
        }
        final count = int.tryParse(time[2] ?? '0');
        if (count == null) {
          throw const FormatException(
            'The date offset is outside the supported range.',
          );
        }
        offset = _checkedOffset(
          context.dateOffsetMinutes,
          count: count,
          unit: time[3],
        );
      } else {
        try {
          append(_expandToken(token, context, dateSource, offset, currentTime));
        } on _UnavailableRenameValue {
          // A manual target replaces this row's computed name, but the rest
          // of the mask still needs syntax validation. Never suppress an
          // unknown token, malformed range, or other configuration error.
          if (!allowUnavailableValues) rethrow;
        }
      }
      position = end + 1;
    } else {
      append(mask[position]);
      position++;
    }
  }
  return result.toString();
}

class _UnavailableRenameValue extends FormatException {
  const _UnavailableRenameValue(String message) : super(message);
}

String _expandToken(
  String token,
  RenameMaskContext context,
  RenameDateSource dateSource,
  Duration offset,
  DateTime currentTime,
) {
  if (token == 'N') return context.name;
  if (token == 'E') return context.extension;
  if (token == 'P') return context.parent;
  if (token == 'A') return context.sourcePath;
  if (token == 'G') {
    final digest = sha256
        .convert(
          utf8.encode(
            '${context.sourcePath}\u0000${context.referenceTime.toIso8601String()}',
          ),
        )
        .toString();
    final value =
        '${digest.substring(0, 12)}5${digest.substring(13, 16)}8'
        '${digest.substring(17, 32)}';
    return '{${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}}';
  }
  if (token.startsWith('V:')) {
    final key = token.substring(2);
    final value = context.variables[key];
    if (value == null) {
      throw FormatException('Enter a value for variable "$key".');
    }
    return value;
  }
  if (token.startsWith('meta:') || token.startsWith('=meta.')) {
    final key = token.substring(token.startsWith('meta:') ? 5 : 6);
    final value = _metadata(context.file, [key]);
    if (value == null) {
      throw _UnavailableRenameValue('Metadata "$key" is unavailable.');
    }
    return value.toString();
  }
  if (token.startsWith('=tc.')) {
    final pieces = token.substring(4).split('.');
    final field = pieces.first.toLowerCase();
    switch (field) {
      case 'name':
        return context.name;
      case 'ext':
      case 'extension':
        return context.extension;
      case 'fullname':
        return context.file.name;
      case 'path':
        return context.paths.dirname(context.sourcePath);
      case 'size':
        if (context.file.size == null) {
          throw const _UnavailableRenameValue('File size is unavailable.');
        }
        return context.file.size.toString();
      case 'writedate':
        dateSource = RenameDateSource.modified;
      case 'creationdate':
        dateSource = RenameDateSource.created;
      case 'accessdate':
        dateSource = RenameDateSource.accessed;
      default:
        throw FormatException(
          'Unsupported content field [$token]. Use [meta:key] for captured metadata.',
        );
    }
    final date = _dateWithOffset(context, dateSource, offset, currentTime);
    return _dateFormat(
      pieces.length == 1 ? 'Y-M-D' : pieces.skip(1).join('.'),
      date,
    );
  }

  final ancestor = RegExp(r'^(P)(-?[1-9]\d*)$|^(B)(\+?\d+)$').firstMatch(token);
  if (ancestor != null) {
    final split = context.paths.split(
      context.paths.dirname(context.sourcePath),
    );
    final root = split.isEmpty ? '' : split.first;
    final folders = split.skip(1).toList();
    if (ancestor[1] != null) {
      final n = int.parse(ancestor[2]!);
      final index = n < 0 ? folders.length + n : n - 1;
      return index < 0 || index >= folders.length ? '' : folders[index];
    }
    final value = ancestor[4]!;
    final n = int.parse(value);
    if (value.startsWith('+')) {
      if (n == 0) return root.replaceAll(RegExp(r'[:/\\]'), '');
      return n > folders.length ? '' : folders[n - 1];
    }
    final index = folders.length - n - 1;
    return index < 0 ? '' : folders[index];
  }

  final counter = RegExp(r'^C(?:(-?\d+)([+-]\d+)?)?(?::(\d+))?$')
      .firstMatch(token);
  if (counter != null) {
    final start = int.tryParse(counter[1] ?? '') ?? context.counterStart;
    final step = int.tryParse(counter[2] ?? '') ?? context.counterStep;
    final width = int.tryParse(counter[3] ?? '') ?? context.counterWidth;
    if (width < 1 || width > 12) {
      throw const FormatException('Counter width must be between 1 and 12.');
    }
    final value = start + context.index * step;
    if (value.abs() > 999999999999 ||
        (value < 0 && context.dialect == RenameMaskDialect.crispCloud)) {
      throw const FormatException(
        'A counter value is outside the supported range.',
      );
    }
    return '${value < 0 ? '-' : ''}${value.abs().toString().padLeft(width, '0')}';
  }

  if (_isDateToken(token, context.dialect)) {
    final date = _dateWithOffset(context, dateSource, offset, currentTime);
    if (context.dialect == RenameMaskDialect.doubleCommander) {
      return _doubleCommanderDate(token, date);
    }
    return _dateFormat(token, date);
  }

  final slice = RegExp(r'^([NEA])(-?[1-9]\d*)(?:([,:-])(-?[1-9]\d*)?)?$')
      .firstMatch(token);
  if (slice != null) {
    final points = (switch (slice[1]) {
      'N' => context.name,
      'E' => context.extension,
      _ => context.sourcePath,
    }).runes.toList();
    final n = int.tryParse(slice[2]!);
    if (n == null) {
      throw const FormatException('The mask position is too large.');
    }
    int offset(int index) => index < 0 ? points.length + index : index - 1;
    final rawStart = offset(n);
    var start = rawStart.clamp(0, points.length);
    var end = start;
    final separator = slice[3];
    if (separator == null) {
      if (rawStart < 0 || rawStart >= points.length) return '';
      end = start + 1;
    } else if (slice[4] == null) {
      end = points.length;
    } else {
      final amount = int.tryParse(slice[4]!);
      if (amount == null) {
        throw const FormatException('The mask position is too large.');
      }
      if (separator == ',') {
        if (amount < 0) {
          throw const FormatException('A slice length must be positive.');
        }
        if (n < 0 && context.dialect == RenameMaskDialect.doubleCommander) {
          end = (rawStart + 1).clamp(0, points.length);
          start = (end - amount).clamp(0, points.length);
        } else {
          end = (rawStart + amount).clamp(0, points.length);
        }
      } else {
        final rawEnd = offset(amount);
        end = (rawEnd + 1).clamp(0, points.length);
        if (end <= start &&
            context.dialect == RenameMaskDialect.doubleCommander) {
          start = rawEnd.clamp(0, points.length);
          end = (rawStart + 1).clamp(0, points.length);
        }
      }
    }
    return end < start ? '' : String.fromCharCodes(points.sublist(start, end));
  }
  throw FormatException('Unknown mask token [$token].');
}

bool _isDateToken(String token, RenameMaskDialect dialect) =>
    dialect == RenameMaskDialect.doubleCommander
    ? const {
        'Y',
        'YY',
        'YYYY',
        'M',
        'MM',
        'MMM',
        'MMMM',
        'D',
        'DD',
        'DDD',
        'DDDD',
        'h',
        'hh',
        'n',
        'nn',
        's',
        'ss',
      }.contains(token)
    : RegExp(r'^[YMDhmsv]+$').hasMatch(token);

// DateTime supports 100,000,000 days on either side of the Unix epoch.
// Check before constructing/adding Durations: a sufficiently large native
// integer can otherwise overflow and silently become a different offset.
const _maxDateMilliseconds = 8640000000000000;
final _maxDateMicroseconds =
    BigInt.from(_maxDateMilliseconds) *
    BigInt.from(Duration.microsecondsPerMillisecond);

Duration _checkedOffset(int minutes, {int count = 0, String? unit}) {
  final units = switch (unit) {
    'd' => Duration.microsecondsPerDay,
    'h' => Duration.microsecondsPerHour,
    'm' => Duration.microsecondsPerMinute,
    _ => Duration.microsecondsPerSecond,
  };
  final microseconds =
      BigInt.from(minutes) * BigInt.from(Duration.microsecondsPerMinute) +
      BigInt.from(count) * BigInt.from(units);
  if (microseconds.abs() > _maxDateMicroseconds) {
    throw const FormatException(
      'The date offset is outside the supported range.',
    );
  }
  return Duration(microseconds: microseconds.toInt());
}

DateTime _dateWithOffset(
  RenameMaskContext context,
  RenameDateSource source,
  Duration offset,
  DateTime currentTime,
) {
  final date = _date(context, source, currentTime);
  final target =
      BigInt.from(date.microsecondsSinceEpoch) +
      BigInt.from(offset.inMicroseconds);
  if (target.abs() > _maxDateMicroseconds) {
    throw _UnavailableRenameValue(
      'The ${source.name} time with this offset is outside the supported date range.',
    );
  }
  try {
    return date.add(offset);
  } on ArgumentError {
    throw _UnavailableRenameValue(
      'The ${source.name} time with this offset is outside the supported date range.',
    );
  }
}

DateTime _date(
  RenameMaskContext context,
  RenameDateSource source,
  DateTime currentTime,
) {
  final Object? value = switch (source) {
    RenameDateSource.modified => context.file.updatedAt,
    RenameDateSource.current => currentTime,
    RenameDateSource.created => _metadata(context.file, [
      'createdAt',
      'creationTime',
      'created',
      'birthtime',
    ]),
    RenameDateSource.accessed => _metadata(context.file, [
      'accessedAt',
      'accessTime',
      'lastAccessed',
    ]),
    RenameDateSource.captured => _metadata(context.file, [
      'dateTaken',
      'captureTime',
      'DateTimeOriginal',
      'exif.DateTimeOriginal',
      'recordedAt',
    ]),
  };
  DateTime? date;
  DateTime? originalWallClock;
  if (value is DateTime) date = value;
  if (value is num) {
    if (!value.isFinite ||
        value < -_maxDateMilliseconds ||
        value > _maxDateMilliseconds) {
      throw _UnavailableRenameValue(
        'The ${source.name} time is outside the supported date range.',
      );
    }
    date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    date = DateTime.tryParse(value);
    if (date == null && RegExp(r'^\d{4}:\d{2}:\d{2} ').hasMatch(value)) {
      date = DateTime.tryParse(
        '${value.substring(0, 10).replaceAll(':', '-')}T${value.substring(11)}',
      );
    }
    // DateTime.parse normalizes an explicit offset to UTC. Preserve the
    // captured wall-clock fields when the user selected the original zone.
    final zone = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(value);
    if (date != null && zone != null) {
      final minutes = int.parse(zone[2]!) * 60 + int.parse(zone[3]!);
      originalWallClock = date.add(
        Duration(minutes: zone[1] == '-' ? -minutes : minutes),
      );
    }
  }
  if (date == null) {
    throw _UnavailableRenameValue(
      'This item has no ${source.name} time for the date mask.',
    );
  }
  return switch (context.dateZone) {
    RenameDateZone.original => originalWallClock ?? date,
    RenameDateZone.local => date.toLocal(),
    RenameDateZone.utc => date.toUtc(),
  };
}

Object? _metadata(FileItem file, List<String> keys) {
  for (final key in keys) {
    final direct = file.metadata?[key];
    if (direct != null) return direct;
    Object? value = file.metadata;
    for (final component in key.split('.')) {
      value = value is Map ? value[component] : null;
    }
    if (value != null) return value;
  }
  return null;
}

String _dateFormat(String format, DateTime date) =>
    format.split('').map((part) {
      final number = switch (part) {
        'Y' => date.year,
        'M' => date.month,
        'D' => date.day,
        'h' => date.hour,
        'm' => date.minute,
        's' => date.second,
        'v' => date.millisecond,
        _ => null,
      };
      return number == null
          ? part
          : number.toString().padLeft(
              part == 'Y'
                  ? 4
                  : part == 'v'
                  ? 3
                  : 2,
              '0',
            );
    }).join();

String _doubleCommanderDate(String token, DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return switch (token) {
    'Y' || 'YY' => (date.year % 100).toString().padLeft(2, '0'),
    'YYYY' => date.year.toString().padLeft(4, '0'),
    'M' => date.month.toString(),
    'MM' => date.month.toString().padLeft(2, '0'),
    'MMM' => months[date.month - 1].substring(0, 3),
    'MMMM' => months[date.month - 1],
    'D' => date.day.toString(),
    'DD' => date.day.toString().padLeft(2, '0'),
    'DDD' => days[date.weekday - 1].substring(0, 3),
    'DDDD' => days[date.weekday - 1],
    'h' => date.hour.toString(),
    'hh' => date.hour.toString().padLeft(2, '0'),
    'n' => date.minute.toString(),
    'nn' => date.minute.toString().padLeft(2, '0'),
    's' => date.second.toString(),
    _ => date.second.toString().padLeft(2, '0'),
  };
}

String renameTitleCase(String value) {
  var beginning = true;
  final output = StringBuffer();
  for (final point in value.toLowerCase().runes) {
    final character = String.fromCharCode(point);
    final letter = character.toLowerCase() != character.toUpperCase();
    output.write(letter && beginning ? character.toUpperCase() : character);
    beginning = !letter && !RegExp(r'\d').hasMatch(character);
  }
  return output.toString();
}
