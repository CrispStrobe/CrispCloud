// SPDX-License-Identifier: MPL-2.0
// The same cases run on the Dart VM and as actual compiled JavaScript.

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import '../test/support/compound_directory_fixture.dart';

Map<String, Object?> verifyCompoundDirectoryWebCases() {
  var rejections = 0;
  void rejects(void Function() read, String label) {
    try {
      read();
    } on CfbfException {
      rejections++;
      return;
    } on FormatException {
      rejections++;
      return;
    }
    throw StateError('Accepted malformed compound directory name: $label');
  }

  for (final mutation in compoundMalformedNames) {
    final bytes = compoundDirectoryNameFixture(mutation);
    final before = Uint8List.fromList(bytes);
    rejects(() => CfbfFile.fromBytes(bytes), 'raw $mutation');
    rejects(() => BoundedCfbReader(bytes), 'bounded $mutation');
    _equal(bytes, before, 'source $mutation');
  }

  var comparisons = 0;
  void valid(Uint8List bytes, Map<String, List<int>> streams) {
    final before = Uint8List.fromList(bytes);
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    for (final stream in streams.entries) {
      _equal(raw.readPath(stream.key)!, stream.value, 'raw ${stream.key}');
      _equal(
        bounded.readPath(stream.key)!,
        stream.value,
        'bounded ${stream.key}',
      );
      comparisons += 2;
    }
    _equal(bytes, before, 'valid source');
  }

  for (final mutation in ['valid', 'unused-padding', 'stale-unused-slot']) {
    valid(compoundDirectoryNameFixture(mutation), {
      'folder/payload': [11, 12, 13],
    });
  }
  final names = ['x' * 31, '\u0005SummaryInformation', '\u{10400}Data'];
  final writer = CfbfWriter();
  for (var index = 0; index < names.length; index++) {
    writer.addStream(names[index], [index + 1]);
  }
  valid(writer.build(), {
    for (var index = 0; index < names.length; index++)
      names[index]: [index + 1],
  });
  return {
    'malformedCases': compoundMalformedNames.length,
    'readerRejections': rejections,
    'validCases': 4,
    'streamComparisons': comparisons,
    'sourceUnchanged': true,
  };
}

void _equal(List<int> actual, List<int> expected, String label) {
  if (actual.length != expected.length) {
    throw StateError('$label length ${actual.length} != ${expected.length}');
  }
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) {
      throw StateError('$label differs at $index');
    }
  }
}
