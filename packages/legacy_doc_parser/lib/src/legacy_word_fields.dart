// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.8.25 Plcfld, 2.9.88 Fld and 2.9.110 grffldEnd. Fields are
// described, never evaluated. CPs come exclusively from the logical CLX text.
class _FieldFrame {
  _FieldFrame(this.id, this.start, this.parent);
  final int id;
  final int start;
  final int? parent;
  int? separator;
}

extension _WordFields on _StructuredWordParser {
  List<(int, int)> _fieldHiddenMediaRanges(int firstField) {
    final ranges = <(int, int)>[];
    for (var i = firstField; i < fields.length; i++) {
      final field = fields[i];
      final instructionEnd = field.separatorCp ?? field.endCp - 1;
      if (instructionEnd > field.startCp + 1) {
        ranges.add((field.startCp + 1, instructionEnd));
      }
      if (field.privateResult && field.separatorCp != null) {
        ranges.add((field.separatorCp!, field.endCp - 1));
      }
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
        final previous = merged.removeLast();
        merged.add((
          previous.$1,
          previous.$2 > range.$2 ? previous.$2 : range.$2,
        ));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  void _readFieldTables() {
    final parts = <(int, int, int)>[(0, source.bodyLength, 16)];
    const pairs = [18, 17, 19, 48, 57, 59];
    for (var index = 0; index < source.storyLengths.length; index++) {
      parts.add((_storyBase(index), source.storyLengths[index], pairs[index]));
    }
    for (final (base, length, pair) in parts) {
      final plc = _plc(pair, 2, length, allowEqual: false);
      if (plc == null) continue;
      for (var index = 0; index < plc.count; index++) {
        final cp = base + plc.cps[index];
        if (plc.cps[index] >= length) {
          throw const FormatException(
            'Word field lies outside its document part.',
          );
        }
        final marker = plc.data.u8(index * 2) & 0x1f;
        if (!const {19, 20, 21}.contains(marker) || body[cp] != marker) {
          throw const FormatException(
            'Word field table does not match its text.',
          );
        }
        _fieldFlags[cp] = plc.data.u8(index * 2 + 1);
      }
    }
  }

  void _collectFields(int first, int limit, String storyId) {
    final stack = <_FieldFrame>[];
    var nextId = fields.length;
    // A prior range is fully closed, so its field IDs are exactly 0..N-1 even
    // though a nested child is appended before its parent.
    for (var cp = first; cp < limit; cp++) {
      switch (body[cp]) {
        case 19:
          if (stack.length >= 64 || nextId >= 20000) {
            throw const FormatException(
              'Word fields exceed the complexity limit.',
            );
          }
          stack.add(
            _FieldFrame(nextId++, cp, stack.isEmpty ? null : stack.last.id),
          );
        case 20:
          if (stack.isEmpty || stack.last.separator != null) {
            throw const FormatException('Unmatched Word field separator.');
          }
          stack.last.separator = cp;
        case 21:
          if (stack.isEmpty) {
            throw const FormatException('Unmatched Word field end.');
          }
          final frame = stack.removeLast();
          final separator = frame.separator;
          final instructionEnd = separator ?? cp;
          final count = cp - frame.start - 1;
          if (instructionEnd - frame.start > 1024 * 1024 ||
              count > 16 * 1024 * 1024 - fieldTextUnits) {
            throw const FormatException(
              'Word field metadata exceeds the text size limit.',
            );
          }
          fieldTextUnits += count;
          final flags = _fieldFlags[cp] ?? 0;
          if (_fieldFlags.containsKey(cp) &&
              (((flags & 0x80) != 0) != (separator != null) ||
                  ((flags & 0x40) != 0) != (frame.parent != null))) {
            throw const FormatException(
              'Word field flags do not match its structure.',
            );
          }
          final privateResult = (flags & 0x20) != 0;
          if (privateResult && separator != null) {
            _privateFieldSeparators.add(separator);
          }
          final instruction = String.fromCharCodes(
            Uint16List.sublistView(body, frame.start + 1, instructionEnd),
          );
          final type =
              RegExp(
                r'^\s*([A-Za-z][A-Za-z0-9_]*|=)',
              ).firstMatch(instruction)?.group(1)?.toUpperCase() ??
              '';
          fields.add(
            LegacyWordField(
              id: frame.id,
              storyId: storyId,
              startCp: frame.start,
              endCp: cp + 1,
              separatorCp: separator,
              parentId: frame.parent,
              instruction: instruction,
              storedResult: separator == null
                  ? ''
                  : _cachedFieldText(separator + 1, cp),
              type: type,
              locked: (flags & 0x10) != 0,
              dirty: (flags & 0x0c) != 0,
              privateResult: privateResult,
            ),
          );
      }
    }
    if (stack.isNotEmpty) {
      throw const FormatException('Word field crosses a story boundary.');
    }
  }

  String _cachedFieldText(int first, int limit) {
    final modes = <bool>[];
    final output = StringBuffer();
    for (var cp = first; cp < limit; cp++) {
      final unit = body[cp];
      if (unit == 19) {
        modes.add(false);
        continue;
      }
      if (unit == 20) {
        if (modes.isEmpty) {
          throw const FormatException('Invalid cached Word field result.');
        }
        modes[modes.length - 1] = !_privateFieldSeparators.contains(cp);
        continue;
      }
      if (unit == 21) {
        if (modes.isEmpty) {
          throw const FormatException('Invalid cached Word field result.');
        }
        modes.removeLast();
        continue;
      }
      if (modes.contains(false)) continue;
      if (unit == 13 || unit == 11) {
        output.write('\n');
      } else if (unit == 7) {
        output.write('\t');
      } else if (unit == 30) {
        output.writeCharCode(0x2011);
      } else if (unit == 31) {
        output.writeCharCode(0x00ad);
      } else if (unit >= 32 ||
          unit == 9 ||
          unit == 10 ||
          unit == 12 ||
          unit == 14) {
        output.writeCharCode(unit);
      }
    }
    if (modes.isNotEmpty) {
      throw const FormatException('Invalid cached Word field result.');
    }
    return output.toString();
  }
}
