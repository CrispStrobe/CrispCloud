// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Small independent grammar: authored fields have instruction/result trees,
/// so expected display text is evaluated without parsing the generated DOC.
/// No fields are evaluated. Results deliberately differ from their instructions.
class GeneratedFieldTreeCase {
  GeneratedFieldTreeCase(int seed, {bool ascii = false}) {
    final random = _StableRandom(seed);
    final root = _GeneratedField(
      'IF',
      [
        _GeneratedText(' "instruction-$seed" '),
        _field(random, 0, ascii),
        _GeneratedText(' = "unused" '),
      ],
      [
        _GeneratedText('cached-$seed:'),
        _field(random, 0, ascii),
        _GeneratedText('|${_text(random, ascii)}|'),
        _field(random, 0, ascii),
      ],
      privateResult: seed % 7 == 0,
    );
    final writer = _GeneratedSource();
    final prefix = ascii ? 'A:' : 'A\u{1f600}:';
    writer.write(_GeneratedText(prefix));
    writer.write(root);
    writer.write(_GeneratedText(':Z\r'));
    source = writer.text.toString();
    expected = '$prefix${root.visible}:Z';
    fields = writer.fields;
    fieldTable = storyPlc([...writer.positions, 0xffffffff], writer.records);
  }

  late final String source;
  late final String expected;
  late final List<GeneratedFieldExpectation> fields;
  late final List<int> fieldTable;

  Uint8List bytes({bool splitPieces = false}) {
    final cuts = splitPieces
        ? <int>{
            0,
            2,
            3,
            source.length ~/ 3,
            source.length * 2 ~/ 3,
            source.length,
          }.toList()
        : [0, source.length];
    cuts.sort();
    final pieces = <WordFixturePiece>[];
    for (var index = 0; index < cuts.length - 1; index++) {
      final text = source.substring(cuts[index], cuts[index + 1]);
      pieces.add(
        WordFixturePiece(
          text,
          // CP order is deliberately opposite physical FC order. Cuts 2/3 split
          // the initial supplementary character across two Unicode pieces.
          offset: 8192 + (cuts.length - 2 - index) * 3072,
          compressed: splitPieces && text.codeUnits.every((c) => c < 128),
        ),
      );
    }
    return StructuredWordFixture(
      pieces: pieces,
      extraTablePairs: {16: fieldTable},
    ).build();
  }
}

class GeneratedFieldExpectation {
  const GeneratedFieldExpectation({
    required this.id,
    required this.start,
    required this.separator,
    required this.end,
    required this.parent,
    required this.instruction,
    required this.result,
    required this.type,
    required this.privateResult,
  });
  final int id, start, separator, end;
  final int? parent;
  final String instruction, result, type;
  final bool privateResult;
}

abstract class _GeneratedNode {
  String get visible;
}

class _GeneratedText extends _GeneratedNode {
  _GeneratedText(this.text);
  final String text;
  @override
  String get visible {
    const normalized = {11: '\n', 30: '\u2011', 31: '\u00ad'};
    return String.fromCharCodes(
      text.codeUnits.where(
        (c) => c >= 32 || const {9, 10, 11, 12, 14, 30, 31}.contains(c),
      ),
    ).split('').map((c) => normalized[c.codeUnitAt(0)] ?? c).join();
  }
}

class _GeneratedField extends _GeneratedNode {
  _GeneratedField(
    this.type,
    this.instruction,
    this.result, {
    this.privateResult = false,
  });
  final String type;
  final List<_GeneratedNode> instruction, result;
  final bool privateResult;
  String get cached => result.map((node) => node.visible).join();
  @override
  String get visible => privateResult ? '' : cached;
}

class _GeneratedSource {
  final text = StringBuffer();
  final positions = <int>[];
  final records = <int>[];
  final fields = <GeneratedFieldExpectation>[];
  var _nextId = 0;

  void marker(int code, int flags) {
    positions.add(text.length);
    records.addAll([code, flags]);
    text.writeCharCode(code);
  }

  void write(_GeneratedNode node, [int? parent]) {
    if (node is _GeneratedText) {
      text.write(node.text);
      return;
    }
    final field = node as _GeneratedField;
    final id = _nextId++, start = text.length;
    marker(19, 0);
    text.write(' ${field.type}');
    for (final child in field.instruction) {
      write(child, id);
    }
    final separator = text.length;
    final instruction = text.toString().substring(start + 1);
    marker(20, 0);
    for (final child in field.result) {
      write(child, id);
    }
    marker(
      21,
      0x80 | (parent == null ? 0 : 0x40) | (field.privateResult ? 0x20 : 0),
    );
    fields.add(
      GeneratedFieldExpectation(
        id: id,
        start: start,
        separator: separator,
        end: text.length,
        parent: parent,
        instruction: instruction,
        result: field.cached,
        type: field.type,
        privateResult: field.privateResult,
      ),
    );
  }
}

_GeneratedField _field(_StableRandom random, int depth, bool ascii) {
  const types = ['QUOTE', 'REF', 'IF', 'DDEAUTO'];
  final type = types[random.next(types.length)];
  final instruction = <_GeneratedNode>[
    _GeneratedText(' "key-${random.next(97)}" '),
  ];
  if (depth < 2 && random.next(3) == 0) {
    instruction.add(_field(random, depth + 1, ascii));
    instruction.add(_GeneratedText(' "tail" '));
  }
  final result = <_GeneratedNode>[_GeneratedText(_text(random, ascii))];
  if (depth < 2 && random.next(2) == 0) {
    result.add(_field(random, depth + 1, ascii));
    result.add(_GeneratedText(_text(random, ascii)));
  }
  return _GeneratedField(
    type,
    instruction,
    result,
    privateResult: random.next(5) == 0,
  );
}

String _text(_StableRandom random, bool ascii) {
  const values = [
    'Latin',
    'عربي',
    'עברית',
    '中日',
    '\u{1f680}',
    'e\u0301',
    '<&>"\'',
    '\t',
    '\n',
    '\v',
    '\f',
    '\x0e',
    '\x1e',
    '\x1f',
    '\x06',
  ];
  const asciiValues = [
    'Latin',
    'Arabic',
    'Hebrew',
    'Cjk',
    'Rocket',
    'Accent',
    '<&>"\'',
    'TAB',
    'NL',
    'VT',
    'FF',
    'COL',
    'NB',
    'SH',
    'CTL',
  ];
  final selected = ascii ? asciiValues : values;
  return List.generate(3, (_) => selected[random.next(selected.length)]).join();
}

class _StableRandom {
  _StableRandom(this._state);
  int _state;
  int next(int bound) {
    _state = (_state * 1664525 + 1013904223) & 0xffffffff;
    return (_state >>> 8) % bound;
  }
}
